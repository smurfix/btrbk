#!/bin/bash
#
# Restore a raw backup to a btrfs subvolume
#
# Usage: raw_restore.sh <raw_backup_path> <restore_target_dir>
#
# This script:
# 1. Finds all parts of a raw backup (handles split files)
# 2. Decompresses if needed
# 3. Concatenates split parts if needed
# 4. Uses btrfs receive to restore to a subvolume
#
# Raw backup file naming convention:
#   <snapshot-name>.<timestamp>[_N].btrfs[.gz|.bz2|...][.gpg]
#   where [_N] is for split files: _1, _2, _3, etc.
#

set -e
set -u

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <raw_backup_path> <restore_target_dir>" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 /path/to/backup/data.20250101T1200.btrfs /path/to/restore" >&2
    echo "  $0 /path/to/backup/data.20250101T1200.btrfs.gz /path/to/restore" >&2
    exit 1
fi

RAW_BACKUP="$1"
RESTORE_DIR="$2"

# Check if the raw backup file exists
if [ ! -f "$RAW_BACKUP" ]; then
    log_error "Raw backup file not found: $RAW_BACKUP"
    exit 1
fi

log_info "Restoring raw backup: $RAW_BACKUP"
log_info "Restore target: $RESTORE_DIR"

# Determine base name and extension
BASENAME=$(basename "$RAW_BACKUP")
DIRNAME=$(dirname "$RAW_BACKUP")

# Detect compression based on file extension
COMPRESSION=""
DECOMPRESSOR=""

if [[ "$BASENAME" =~ \.gz$ ]]; then
    COMPRESSION="gzip"
    DECOMPRESSOR="gunzip -c"
    BASENAME="${BASENAME%.gz}"
elif [[ "$BASENAME" =~ \.bz2$ ]]; then
    COMPRESSION="bzip2"
    DECOMPRESSOR="bunzip2 -c"
    BASENAME="${BASENAME%.bz2}"
elif [[ "$BASENAME" =~ \.xz$ ]]; then
    COMPRESSION="xz"
    DECOMPRESSOR="unxz -c"
    BASENAME="${BASENAME%.xz}"
elif [[ "$BASENAME" =~ \.lz4$ ]]; then
    COMPRESSION="lz4"
    DECOMPRESSOR="lz4 -dc"
    BASENAME="${BASENAME%.lz4}"
elif [[ "$BASENAME" =~ \.zst$ ]]; then
    COMPRESSION="zstd"
    DECOMPRESSOR="zstd -dc"
    BASENAME="${BASENAME%.zst}"
fi

if [ -n "$COMPRESSION" ]; then
    log_info "Detected compression: $COMPRESSION"
fi

# Check if this is a split backup (look for _1 suffix before .btrfs)
# Pattern: data.20250101T1200_1.btrfs or data.20250101T1200.btrfs
IS_SPLIT=false
if [[ "$BASENAME" =~ _[0-9]+\.btrfs$ ]]; then
    IS_SPLIT=true
    # Extract the base pattern without the _N part
    BASE_PATTERN="${BASENAME%_[0-9]*.btrfs}"
    log_info "Detected split backup with pattern: ${BASE_PATTERN}_N.btrfs"
fi

# Create temporary working directory
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

# Process the backup file(s)
if [ "$IS_SPLIT" = true ]; then
    log_info "Concatenating split backup files..."

    # Find all parts and concatenate them
    PART_NUM=1
    CONCAT_FILE="$TMPDIR/backup.btrfs"

    while true; do
        if [ -n "$COMPRESSION" ]; then
            PART_FILE="$DIRNAME/${BASE_PATTERN}_${PART_NUM}.btrfs.${COMPRESSION}"
        else
            PART_FILE="$DIRNAME/${BASE_PATTERN}_${PART_NUM}.btrfs"
        fi

        if [ ! -f "$PART_FILE" ]; then
            if [ $PART_NUM -eq 1 ]; then
                log_error "Split backup part 1 not found: $PART_FILE"
                exit 1
            fi
            break
        fi

        log_info "Processing part $PART_NUM: $(basename "$PART_FILE")"

        if [ -n "$DECOMPRESSOR" ]; then
            $DECOMPRESSOR "$PART_FILE" >> "$CONCAT_FILE"
        else
            cat "$PART_FILE" >> "$CONCAT_FILE"
        fi

        PART_NUM=$((PART_NUM + 1))
    done

    log_info "Concatenated $((PART_NUM - 1)) parts"
    STREAM_FILE="$CONCAT_FILE"

else
    # Single file backup
    if [ -n "$DECOMPRESSOR" ]; then
        log_info "Decompressing backup..."
        STREAM_FILE="$TMPDIR/backup.btrfs"
        $DECOMPRESSOR "$RAW_BACKUP" > "$STREAM_FILE"
    else
        # No decompression needed, use file directly
        STREAM_FILE="$RAW_BACKUP"
    fi
fi

# Restore using btrfs receive
log_info "Restoring subvolume using btrfs receive..."
$SUDO btrfs receive -f "$STREAM_FILE" "$RESTORE_DIR"

log_success "Raw backup restored successfully to $RESTORE_DIR"
