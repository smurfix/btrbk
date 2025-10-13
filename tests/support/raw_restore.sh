#!/bin/bash
#
# Restore a raw backup to a btrfs subvolume
#
# Usage: raw_restore.sh <raw_backup_path> <restore_target_dir>
#
# This script:
# 1. Reads the .info file to determine if backup is incremental
# 2. If incremental (has RECEIVED_PARENT_UUID), recursively restores parent first
# 3. Decompresses if needed
# 4. Uses btrfs receive to restore to a subvolume
#
# Raw backup file naming convention:
#   <snapshot-name>.<timestamp>.btrfs[.gz|.bz2|...][.gpg]
#   <snapshot-name>.<timestamp>.btrfs[.gz|.bz2|...][.gpg].info
#
# The _N suffix (e.g., data.20250101T1200_1.btrfs) is for disambiguation when
# multiple backups have the same timestamp, not for file splitting.
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

# Track restored backups to avoid loops
declare -A RESTORED_BACKUPS

# Check if an .info file is valid (returns 0 if valid, 1 if invalid)
is_valid_info_file() {
    local info_file="$1"

    [ -f "$info_file" ] || return 1

    # Check syntactic correctness: all lines should be empty, comments, or VAR=VALUE
    grep -qv '^\s*\([A-Z_][A-Z0-9_]*=.*\|#.*\|$\)' "$info_file" && return 1

    return 0
}

# Load and validate a .info file
load_info_file() {
    local info_file="$1"

    if [ ! -f "$info_file" ]; then
        log_error "Info file not found: $info_file"
        exit 1
    fi

    if ! is_valid_info_file "$info_file"; then
        log_error "Invalid syntax in info file: $info_file"
        exit 1
    fi

    # Source the file to load variables
    source "$info_file"
}

# Recursive function to restore a backup and its parents
restore_backup_recursive() {
    local backup_file="$1"
    local restore_dir="$2"

    # Check if already restored
    if [ -n "${RESTORED_BACKUPS[$backup_file]:-}" ]; then
        return 0
    fi

    # Load info file for this backup
    local info_file="${backup_file}.info"
    unset TYPE RECEIVED_UUID RECEIVED_PARENT_UUID INCOMPLETE
    echo LOAD "$info_file"
    load_info_file "$info_file"

    # Validate info file
    if [ "${TYPE:-}" != "raw" ]; then
        log_error "Not a raw backup: TYPE=${TYPE:-} in $info_file"
        exit 1
    fi

    if [ "${INCOMPLETE:-0}" = "1" ]; then
        log_error "Incomplete backup: $backup_file"
        exit 1
    fi

    if [ -z "${RECEIVED_UUID:-}" ]; then
        log_error "Missing RECEIVED_UUID in $info_file"
        exit 1
    fi
    parent="${RECEIVED_PARENT_UUID:-}"

    # If this backup has a parent, restore the parent first
    if [ -n "${parent:-}" ] && [ "$parent" != "-" ]; then
        log_info "Backup requires parent UUID: $parent"

        # Find the parent backup file by searching for matching RECEIVED_UUID
        local backup_dir=$(dirname "$backup_file")
        local parent_file=""

        for info in "$backup_dir"/*.info; do
            # Skip invalid info files
            is_valid_info_file "$info" || continue

            # Load parent info
            unset RECEIVED_UUID INCOMPLETE
            load_info_file "$info"

            # Skip incomplete backups
            [ "${INCOMPLETE:-0}" = "1" ] && continue

            if [ "${RECEIVED_UUID:-}" = "$parent" ]; then
                # Found parent, remove .info suffix to get data file
                parent_file="${info%.info}"
                log_info "Found parent backup: $(basename "$parent_file")"
                break
            fi
        done

        if [ -z "$parent_file" ]; then
            log_error "Parent backup not found for UUID: $parent"
            exit 1
        fi

        # Recursively restore parent first
        restore_backup_recursive "$parent_file" "$restore_dir"
    fi

    # Now restore this backup
    log_info "Restoring: $(basename "$backup_file")"

    # Determine if compressed and decompressor
    local decompressor=""
    if [[ "$backup_file" =~ \.gz$ ]]; then
        decompressor="gunzip -c"
    elif [[ "$backup_file" =~ \.bz2$ ]]; then
        decompressor="bunzip2 -c"
    elif [[ "$backup_file" =~ \.xz$ ]]; then
        decompressor="unxz -c"
    elif [[ "$backup_file" =~ \.lz4$ ]]; then
        decompressor="lz4 -dc"
    elif [[ "$backup_file" =~ \.zst$ ]]; then
        decompressor="zstd -dc"
    fi

    # Ensure restore directory exists and is on btrfs
    $SUDO mkdir -p "$restore_dir"

    # Restore using btrfs receive
    if [ -n "$decompressor" ]; then
        $decompressor "$backup_file" | $SUDO btrfs receive "$restore_dir"
    else
        $SUDO btrfs receive -f "$backup_file" "$restore_dir"
    fi

    # Mark as restored
    RESTORED_BACKUPS[$backup_file]=1
    log_success "Restored: $(basename "$backup_file")"
}

# Start recursive restore
log_info "Restoring raw backup: $(basename "$RAW_BACKUP")"
log_info "Restore target: $RESTORE_DIR"

drop_subvols "$RESTORE_DIR"
restore_backup_recursive "$RAW_BACKUP" "$RESTORE_DIR"

log_success "Raw backup restored successfully to $RESTORE_DIR"
