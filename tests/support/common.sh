#!/bin/bash
#
# Common utilities for btrbk tests
#

set -e
set -u

# Color output for test results
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0

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

    TEST_COUNT=$((TEST_COUNT + 1))
    if eval "$condition"; then
        TEST_PASSED=$((TEST_PASSED + 1))
        log_success "$message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        log_error "$message"
        return 1
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
        TEST_PASSED=$((TEST_PASSED + 1))
        log_success "$message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        log_error "$message"
        return 1
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

    if ! $SUDO test -w "$TESTROOT"; then
        log_error "TESTROOT is not writable: $TESTROOT"
        return 1
    fi

    # Check if TESTROOT is on a btrfs filesystem
    if ! $SUDO btrfs subvolume show "$TESTROOT" >/dev/null 2>&1; then
        log_error "TESTROOT is not on a btrfs filesystem: $TESTROOT"
        return 1
    fi

    log_info "TESTROOT validated: $TESTROOT"
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

    log_info "All prerequisites met"
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
}

delete_subvol() {
    local path="$1"

    if ! $SUDO btrfs subvolume show "$path" >/dev/null 2>&1; then
        log_info "Subvolume does not exist (already deleted?): $path"
        return 0
    fi

    log_info "Deleting subvolume: $path"
    $SUDO btrfs subvolume delete "$path"
}

list_subvols() {
    local path="$1"
    $SUDO btrfs subvolume list "$path"
}

#
# Test environment setup/cleanup
#

setup_test_env() {
    local test_name="${1:-test}"

    log_info "Setting up test environment: $test_name"

    check_testroot || return 1
    check_prerequisites || return 1

    # Clean up any existing test data
    cleanup_test_env

    # Create base directories
    $SUDO mkdir -p "$TESTROOT"

    log_success "Test environment ready"
    return 0
}

cleanup_test_env() {
    log_info "Cleaning up test environment"

    if [ -z "${TESTROOT:-}" ]; then
        log_warning "TESTROOT not set, skipping cleanup"
        return 0
    fi

    # Delete all subvolumes in TESTROOT
    # List in reverse order to delete children before parents
    local subvols
    subvols=$($SUDO btrfs subvolume list -o "$TESTROOT" 2>/dev/null | awk '{print $NF}' | tac || true)

    for subvol in $subvols; do
        local full_path="$TESTROOT/$subvol"
        if [ -e "$full_path" ]; then
            delete_subvol "$full_path" || true
        fi
    done

    # Clean up regular directories and files
    for item in "$TESTROOT"/{data,backup,snapshots}; do
        if [ -e "$item" ]; then
            if $SUDO btrfs subvolume show "$item" >/dev/null 2>&1; then
                delete_subvol "$item" || true
            else
                log_info "Removing directory: $item"
                $SUDO rm -rf "$item" || true
            fi
        fi
    done

    log_info "Cleanup complete"
}

#
# Faketime utilities
#

run_with_faketime() {
    local datetime="$1"
    shift

    log_info "Running with faketime: $datetime"
    faketime "$datetime" "$@"
}

#
# Data comparison
#

compare_subvols() {
    local src="$1"
    local dst="$2"
    local exclude_pattern="${3:-}"

    log_info "Comparing subvolumes: $src vs $dst"

    local tmp_src=$(mktemp)
    local tmp_dst=$(mktemp)

    trap "rm -f '$tmp_src' '$tmp_dst'" EXIT

    # Generate file lists with relative paths
    (cd "$src" && $SUDO find . -type f -o -type l | sort > "$tmp_src")
    (cd "$dst" && $SUDO find . -type f -o -type l | sort > "$tmp_dst")

    if [ -n "$exclude_pattern" ]; then
        grep -v "$exclude_pattern" "$tmp_src" > "$tmp_src.filtered" || true
        grep -v "$exclude_pattern" "$tmp_dst" > "$tmp_dst.filtered" || true
        mv "$tmp_src.filtered" "$tmp_src"
        mv "$tmp_dst.filtered" "$tmp_dst"
    fi

    # Compare file lists
    if ! diff -u "$tmp_src" "$tmp_dst"; then
        log_error "File lists differ between $src and $dst"
        rm -f "$tmp_src" "$tmp_dst"
        return 1
    fi

    # Compare file contents
    local failed=0
    while IFS= read -r file; do
        if [ ! -e "$src/$file" ] || [ ! -e "$dst/$file" ]; then
            continue
        fi

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
            if ! $SUDO cmp -s "$src/$file" "$dst/$file"; then
                log_error "File contents differ: $file"
                failed=1
            fi
        fi
    done < "$tmp_src"

    rm -f "$tmp_src" "$tmp_dst"

    if [ $failed -eq 0 ]; then
        log_success "Subvolumes are identical"
        return 0
    else
        log_error "Subvolumes differ"
        return 1
    fi
}

#
# Test summary
#

print_test_summary() {
    echo ""
    echo "======================================"
    echo "Test Summary"
    echo "======================================"
    echo "Total:  $TEST_COUNT"
    echo -e "Passed: ${GREEN}$TEST_PASSED${NC}"
    echo -e "Failed: ${RED}$TEST_FAILED${NC}"
    echo "======================================"

    if [ $TEST_FAILED -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

#
# Export functions
#

export -f log_info log_error log_success log_warning
export -f assert_true assert_file_exists assert_dir_exists assert_subvol_exists assert_equal
export -f check_testroot check_prerequisites
export -f create_subvol delete_subvol list_subvols
export -f setup_test_env cleanup_test_env
export -f run_with_faketime compare_subvols
export -f print_test_summary

# Set btrbk binary path relative to test directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BTRBK_BIN="${BTRBK_BIN:-$SCRIPT_DIR/../../btrbk}"
export BTRBK_BIN

# Set sudo command (can be overridden with environment variable)
SUDO="${SUDO:-sudo -A}"
export SUDO
