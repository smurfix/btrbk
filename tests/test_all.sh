#!/bin/bash
#
# btrbk test suite runner
#
# This script runs all btrbk tests and reports results.
#
# Usage: TESTROOT=/path/to/btrfs/subvolume ./test_all.sh [test_pattern]
#

set -e
set -u

# Set TEST_DIR to tests/ directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

# Color output (only if output is to a terminal)
if [ -t 1 ]; then
    BOLD='\033[1m'
    BOLD_NC='\033[0m'
else
    BOLD=''
    BOLD_NC=''
fi

echo -e "${BOLD}=========================================="
echo "btrbk Test Suite"
echo -e "==========================================${BOLD_NC}"
echo ""

#
# Check prerequisites
#

if ! check_testroot; then
    echo ""
    log_error "TESTROOT validation failed"
    log_error ""
    log_error "Set TESTROOT to an empty, writable btrfs subvolume:"
    log_error "  export TESTROOT=/mnt/test_btrfs"
    log_error ""
    log_error "To create a test btrfs filesystem:"
    log_error "  truncate -s 1G /var/tmp/btrbk_test.img"
    log_error "  mkfs.btrfs /var/tmp/btrbk_test.img"
    log_error "  mkdir -p /mnt/test_btrfs"
    log_error "  sudo mount -o loop /var/tmp/btrbk_test.img /mnt/test_btrfs"
    log_error "  export TESTROOT=/mnt/test_btrfs"
    echo ""
    exit 1
fi

if ! check_prerequisites; then
    echo ""
    log_error "Prerequisites check failed"
    log_error "Please install missing dependencies:"
    log_error "  - btrfs-progs (btrfs commands)"
    log_error "  - faketime (deterministic timestamps)"
    echo ""
    exit 1
fi

#
# Find tests
#

TEST_PATTERN="${1:-[0-9][0-9]_*.sh}"

TESTS=$(find "$TEST_DIR" -maxdepth 1 -name "$TEST_PATTERN" -type f | sort)

if [ -z "$TESTS" ]; then
    log_error "No tests found matching '$TEST_PATTERN'"
    exit 1
fi

TEST_COUNT=$(echo "$TESTS" | wc -l)
log_info "Found $TEST_COUNT test(s) to run"
echo ""

# Run each test
for test in $TESTS; do
    TEST_NAME=$(basename "$test")

    # Create temporary file for test output
    TEST_OUTPUT=$(mktemp)
    trap "rm -f '$TEST_OUTPUT'" EXIT

    echo -n "Running $TEST_NAME... "

    # Run test and capture output
    if "$test" > "$TEST_OUTPUT" 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        rm -f "$TEST_OUTPUT"
    else
        echo ""
        echo -e "${RED}FAIL${NC}"
        echo ""
        echo "Output from $TEST_NAME:"
        echo "----------------------------------------"
        cat "$TEST_OUTPUT"
        echo "----------------------------------------"
        rm -f "$TEST_OUTPUT"
        exit 1
    fi
done

cleanup_test_env

log_success "All tests passed."
exit 0
