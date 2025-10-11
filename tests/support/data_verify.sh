#!/bin/bash
#
# Verify and compare btrfs subvolume data
#
# Usage: data_verify.sh <source_path> <target_path> [options]
#

set -e
set -u

# Set TEST_DIR to tests/ directory
SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "$SUPPORT_DIR/.." && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

usage() {
    cat <<EOF
Usage: $0 <source_path> <target_path> [options]

Verify that two btrfs subvolumes contain identical data.

Arguments:
    source_path  Path to source subvolume
    target_path  Path to target subvolume (e.g., backup)

Options:
    --expect-differences  Expect differences (inverse check)
    --file-list          Only compare file lists, not contents
    --verbose            Show detailed comparison output

Exit Codes:
    0  - Verification successful (subvolumes match or differences as expected)
    1  - Verification failed

Examples:
    $0 /mnt/test/data /mnt/test/backup/data.20250101
    $0 /mnt/test/data /mnt/test/backup/data.20250102 --verbose
EOF
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

SOURCE="$1"
TARGET="$2"
shift 2

EXPECT_DIFFERENCES=0
FILE_LIST_ONLY=0
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --expect-differences)
            EXPECT_DIFFERENCES=1
            shift
            ;;
        --file-list)
            FILE_LIST_ONLY=1
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate paths
if [ ! -d "$SOURCE" ]; then
    log_error "Source path does not exist: $SOURCE"
    exit 1
fi

if [ ! -d "$TARGET" ]; then
    log_error "Target path does not exist: $TARGET"
    exit 1
fi

log_info "Verifying data: $SOURCE vs $TARGET"

#
# Helper functions
#

verify_file_exists() {
    local path="$1"
    local file="$2"

    if [ ! -e "$path/$file" ]; then
        return 1
    fi
    return 0
}

compare_file_content() {
    local src_file="$1"
    local tgt_file="$2"

    if [ ! -e "$src_file" ] || [ ! -e "$tgt_file" ]; then
        return 1
    fi

    if [ -L "$src_file" ]; then
        # Compare symlinks
        local src_target=$(readlink "$src_file")
        local tgt_target=$(readlink "$tgt_file")
        [ "$src_target" = "$tgt_target" ]
        return $?
    elif [ -f "$src_file" ]; then
        # Compare regular files
        $SUDO cmp -s "$src_file" "$tgt_file"
        return $?
    elif [ -d "$src_file" ]; then
        # Both are directories
        return 0
    fi

    return 1
}

#
# Main verification logic
#

TMP_DIR=$(mktemp -d)
trap "rm -rf '$TMP_DIR'" EXIT

SRC_LIST="$TMP_DIR/source.list"
TGT_LIST="$TMP_DIR/target.list"
DIFF_FILE="$TMP_DIR/diff.txt"

# Generate sorted file lists
log_info "Generating file lists..."
(cd "$SOURCE" && $SUDO find . -print | sort > "$SRC_LIST")
(cd "$TARGET" && $SUDO find . -print | sort > "$TGT_LIST")

SRC_COUNT=$(wc -l < "$SRC_LIST")
TGT_COUNT=$(wc -l < "$TGT_LIST")

log_info "Source: $SRC_COUNT items"
log_info "Target: $TGT_COUNT items"

# Compare file lists
DIFFERENCES_FOUND=0

if ! diff -u "$SRC_LIST" "$TGT_LIST" > "$DIFF_FILE"; then
    DIFFERENCES_FOUND=1
    log_warning "File lists differ"

    if [ $VERBOSE -eq 1 ]; then
        echo "=== File List Differences ===" >&2
        cat "$DIFF_FILE" >&2
        echo "=============================" >&2
    fi

    # Count differences
    ADDED=$(grep -c '^+\.' "$DIFF_FILE" || true)
    REMOVED=$(grep -c '^-\.' "$DIFF_FILE" || true)
    log_info "Files added: $ADDED"
    log_info "Files removed: $REMOVED"
else
    log_success "File lists are identical"
fi

# If only checking file lists, stop here
if [ $FILE_LIST_ONLY -eq 1 ]; then
    if [ $DIFFERENCES_FOUND -eq 1 ]; then
        log_error "File list verification failed"
        exit 1
    else
        log_success "File list verification passed"
        exit 0
    fi
fi

# Compare file contents
if [ $DIFFERENCES_FOUND -eq 0 ]; then
    log_info "Comparing file contents..."

    CONTENT_DIFFS=0
    TOTAL_FILES=0

    while IFS= read -r file; do
        # Skip directories
        [ ! -f "$SOURCE/$file" ] && [ ! -L "$SOURCE/$file" ] && continue

        TOTAL_FILES=$((TOTAL_FILES + 1))

        if ! compare_file_content "$SOURCE/$file" "$TARGET/$file"; then
            CONTENT_DIFFS=$((CONTENT_DIFFS + 1))
            DIFFERENCES_FOUND=1

            if [ $VERBOSE -eq 1 ]; then
                log_warning "Content differs: $file"
            fi
        fi

        # Progress indicator for large datasets
        if [ $VERBOSE -eq 1 ] && [ $((TOTAL_FILES % 100)) -eq 0 ]; then
            log_info "Checked $TOTAL_FILES files..."
        fi
    done < "$SRC_LIST"

    if [ $CONTENT_DIFFS -gt 0 ]; then
        log_warning "Content differences found: $CONTENT_DIFFS files"
    else
        log_success "All file contents are identical ($TOTAL_FILES files checked)"
    fi
fi

#
# Verification result
#

echo "" >&2
echo "======================================" >&2
echo "Verification Summary" >&2
echo "======================================" >&2
echo "Source: $SOURCE" >&2
echo "Target: $TARGET" >&2
echo "--------------------------------------" >&2

if [ $DIFFERENCES_FOUND -eq 1 ]; then
    if [ $EXPECT_DIFFERENCES -eq 1 ]; then
        echo -e "${GREEN}Result: PASS (differences found as expected)${NC}" >&2
        echo "======================================" >&2
        exit 0
    else
        echo -e "${RED}Result: FAIL (unexpected differences found)${NC}" >&2
        echo "======================================" >&2
        exit 1
    fi
else
    if [ $EXPECT_DIFFERENCES -eq 1 ]; then
        echo -e "${RED}Result: FAIL (expected differences, but subvolumes are identical)${NC}" >&2
        echo "======================================" >&2
        exit 1
    else
        echo -e "${GREEN}Result: PASS (subvolumes are identical)${NC}" >&2
        echo "======================================" >&2
        exit 0
    fi
fi
