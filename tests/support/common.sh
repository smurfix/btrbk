#!/bin/bash
#
# Common utilities for btrbk tests
#

set -e
set -u

# Color output for test results (only if output is to a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

#
# Logging functions
#

log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

#
# Assertion functions
#

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if eval "$condition"; then
        log_success "$message"
        return 0
    else
        log_error "$message"
        exit 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"
    assert_true "[ -e '$file' ]" "$message"
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist: $dir}"
    assert_true "[ -d '$dir' ]" "$message"
}

assert_subvol_exists() {
    local path="$1"
    local message="${2:-Subvolume should exist: $path}"
    assert_true "$SUDO btrfs subvolume show '$path' >/dev/null 2>&1" "$message"
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Expected '$expected', got '$actual'}"

    TEST_COUNT=$((TEST_COUNT + 1))
    if [ "$actual" = "$expected" ]; then
        log_success "$message"
        return 0
    else
        log_error "$message"
        exit 1
    fi
}

#
# Environment validation
#

check_testroot() {
    if [ -z "${TESTROOT:-}" ]; then
        log_error "TESTROOT environment variable is not set"
        log_error "Please set TESTROOT to a writable btrfs subvolume"
        log_error "Example: export TESTROOT=/mnt/test_btrfs"
        return 1
    fi

    if [ ! -d "$TESTROOT" ]; then
        log_error "TESTROOT directory does not exist: $TESTROOT"
        return 1
    fi

    # Check if TESTROOT is on a btrfs filesystem
    if ! $SUDO btrfs subvolume show "$TESTROOT" >/dev/null 2>&1; then
        log_error "TESTROOT is not on a btrfs filesystem: $TESTROOT"
        return 1
    fi

    return 0
}

check_prerequisites() {
    local missing=0

    # Check for required commands
    for cmd in btrfs faketime; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    # Check for btrbk script
    if [ ! -x "$BTRBK_BIN" ]; then
        log_error "btrbk binary not found or not executable: $BTRBK_BIN"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        return 1
    fi

    return 0
}

#
# Btrfs operations
#

create_subvol() {
    local path="$1"

    if $SUDO btrfs subvolume show "$path" >/dev/null 2>&1; then
        log_warning "Subvolume already exists: $path"
        return 0
    fi

    log_info "Creating subvolume: $path"
    $SUDO btrfs subvolume create "$path"
    $SUDO chmod 755 "$path"
}

delete_subvol() {
    local path="$1"

    if ! $SUDO btrfs subvolume show "$path" >/dev/null 2>&1; then
        log_info "Subvolume does not exist (already deleted?): $path"
        return 0
    fi

    $SUDO btrfs subvolume delete "$path"
}

list_subvols() {
    local path="$1"
    $SUDO btrfs subvolume list "$path"
}

#
# Config file expansion
#

expand_config() {
    local template="$1"
    local output="${2:-$TESTROOT/current.conf}"

    if [ ! -f "$template" ]; then
        log_error "Template config file does not exist: $template"
        return 1
    fi

    # Use Python script for variable expansion
    local tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" RETURN

    if ! python3 "$TEST_DIR/support/expand_vars.py" "$template" "$tmpfile"; then
        log_error "Failed to expand config template"
        return 1
    fi

    $SUDO mv "$tmpfile" "$output"
    $SUDO chmod 644 "$output"

    return 0
}

#
# Test environment setup/cleanup
#

setup_test_env() {
    local test_name="${1:-test}"

    check_testroot || return 1
    check_prerequisites || return 1

    # Clean up any existing test data
    cleanup_test_env

    # Create base directories
    $SUDO mkdir -p "$TESTROOT"
    create_subvol "$TESTROOT/data"
    $SUDO chown $UID "$TESTROOT/data"

    # snapshots
    $SUDO btrfs subvolume create "$TESTROOT/snapshots"

    # backups
    $SUDO btrfs subvolume create "$TESTROOT/backup"

    # temp (raw restore tests et al.)
    $SUDO btrfs subvolume create "$TESTROOT/temp"

    return 0
}

drop_subvols() {
    # Delete all subvolumes under $1
    # First we need to find the prefix: the root might be some directory
    # under some subvolume mountpoint; "btrfs subvolume list" shows
    # the path from its "real" root *IF* the subvol is not a subdirectory 
    # of the given path.
    local root="$1"

    # we need to find the "real" prefix for this root. The safe way is
    # to create a new subvolume and list with its path to ensure that all
    # results use absolute paths. Then strip the 
    RR="$root/R-$$-R"
    $SUDO btrfs subv cre "$RR"
    PREFIX="$($SUDO btrfs subv lis "$RR" | sed -ne "s#.* path \(.*/\)R-$$-R\$#\1#p")"
    if [ -z "$PREFIX" ] ; then
        echo "Could not determine subvolume prefix for '$root'"
        exit 1
    fi

    $SUDO btrfs subvolume list "$RR" 2>/dev/null | python3 "$SUPPORT_DIR/subvol-prefix.py" "$PREFIX" | tac |
    while read subvol; do
        local full_path="$root/$subvol"
        $SUDO btrfs subvolume delete --recursive "$full_path"
    done
    if [ -d "$RR" ] ; then
        echo "Oops, test subvol '$RR' didn't get deleted ?!?" >&2
    fi
}

cleanup_test_env() {
    if [ -z "${TESTROOT:-}" ]; then
        log_warning "TESTROOT not set, skipping cleanup"
        return 0
    fi

    drop_subvols "$TESTROOT"
}

#
# Faketime utilities
#

run_with_faketime() {
    local datetime="$1"
    shift

    faketime "$datetime" "$@"
}

sudo_with_faketime() {
    local datetime="$1"
    shift

    $SUDO faketime "$datetime" "$@"
}

#
# Data comparison
#

compare_subvols() {
    local src="$1"
    local dst="$2"

    log_info "Comparing subvolumes: $src vs $dst"

    local tmp_src=$(mktemp)
    local tmp_dst=$(mktemp)

    trap "rm -f '$tmp_src' '$tmp_dst'" EXIT

    # Generate file lists with relative paths
    (cd "$src" && find . -type f -o -type l | sort > "$tmp_src")
    (cd "$dst" && find . -type f -o -type l | sort > "$tmp_dst")

    # Compare file lists
    if ! diff -u "$tmp_src" "$tmp_dst"; then
        log_error "File lists differ between $src and $dst"
        rm -f "$tmp_src" "$tmp_dst"
        return 1
    fi

    # Compare file contents
    local failed=0
    while IFS= read -r file; do
        if [ -L "$src/$file" ]; then
            # Compare symlinks
            local src_target=$(readlink "$src/$file")
            local dst_target=$(readlink "$dst/$file")
            if [ "$src_target" != "$dst_target" ]; then
                log_error "Symlink targets differ: $file"
                failed=1
            fi
        elif [ -f "$src/$file" ]; then
            # Compare regular files
            if ! cmp -s "$src/$file" "$dst/$file"; then
                log_error "File contents differ: $file"
                failed=1
            fi
        fi
    done < "$tmp_src"

    rm -f "$tmp_src" "$tmp_dst"

    if [ $failed -eq 0 ]; then
        return 0
    else
        log_error "Subvolumes '$src' and '$dst' differ"
        return 1
    fi
}

export -f log_info log_error log_success log_warning
export -f assert_true assert_file_exists assert_dir_exists assert_subvol_exists assert_equal
export -f check_testroot check_prerequisites
export -f create_subvol delete_subvol list_subvols
export -f expand_config
export -f setup_test_env cleanup_test_env
export -f run_with_faketime sudo_with_faketime compare_subvols

# Set test directory (always points to tests/)
SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${TEST_DIR:-}" ]; then
    TEST_DIR="$(cd "$SUPPORT_DIR/.." && pwd)"
fi
export TEST_DIR

# Set btrbk binary path relative to test directory
BTRBK_BIN="${BTRBK_BIN:-$TEST_DIR/../btrbk}"
export BTRBK_BIN

# Set sudo command (can be overridden with environment variable)
SUDO="${SUDO:-sudo -A --preserve-env=TESTROOT}"
export SUDO
