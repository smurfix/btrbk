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

log_info "Checking prerequisites..."

if ! check_testroot; then
    echo ""
    log_error "TESTROOT validation failed"
    log_error ""
    log_error "Please set TESTROOT to a writable btrfs subvolume:"
    log_error "  export TESTROOT=/mnt/test_btrfs"
    log_error ""
    log_error "To create a test btrfs filesystem:"
    log_error "  truncate -s 10G /tmp/btrbk_test.img"
    log_error "  mkfs.btrfs /tmp/btrbk_test.img"
    log_error "  mkdir -p /mnt/test_btrfs"
    log_error "  sudo mount -o loop /tmp/btrbk_test.img /mnt/test_btrfs"
    log_error "  export TESTROOT=/mnt/test_btrfs"
    echo ""
    exit 1
fi

if ! check_prerequisites; then
    echo ""
    log_error "Prerequisites check failed"
    log_error "Please install missing dependencies:"
    log_error "  - btrfs-progs (for btrfs commands)"
    log_error "  - faketime (for deterministic timestamps)"
    echo ""
    exit 1
fi

echo ""
log_success "Prerequisites check passed"
echo ""

#
# Find and run tests
#

TEST_PATTERN="${1:-[0-9][0-9]_*.sh}"

log_info "Finding tests matching pattern: $TEST_PATTERN"
TESTS=$(find "$TEST_DIR" -maxdepth 1 -name "$TEST_PATTERN" -type f | sort)

if [ -z "$TESTS" ]; then
    log_error "No tests found matching pattern: $TEST_PATTERN"
    exit 1
fi

TEST_COUNT=$(echo "$TESTS" | wc -l)
log_info "Found $TEST_COUNT test(s) to run"
echo ""

# Track overall results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TEST_NAMES=()

# Run each test
for test in $TESTS; do
    TEST_NAME=$(basename "$test")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Create temporary file for test output
    TEST_OUTPUT=$(mktemp)
    trap "rm -f '$TEST_OUTPUT'" EXIT

    echo -n "Running $TEST_NAME... "

    # Run test and capture output
    if "$test" > "$TEST_OUTPUT" 2>&1; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}PASS${NC}"
        rm -f "$TEST_OUTPUT"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_TEST_NAMES+=("$TEST_NAME")
        echo -e "${RED}FAIL${NC}"
        echo ""
        echo "Output from $TEST_NAME:"
        echo "----------------------------------------"
        cat "$TEST_OUTPUT"
        echo "----------------------------------------"
        echo ""
        rm -f "$TEST_OUTPUT"
    fi
done

#
# Print overall summary
#

echo ""
echo -e "${BOLD}=========================================="
echo "Overall Test Suite Summary"
echo -e "==========================================${BOLD_NC}"
echo ""
echo "Total tests run: $TOTAL_TESTS"
echo -e "${GREEN}Passed:         $PASSED_TESTS${NC}"
echo -e "${RED}Failed:         $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed tests:${NC}"
    for failed in "${FAILED_TEST_NAMES[@]}"; do
        echo -e "  ${RED}✗${NC} $failed"
    done
    echo ""
fi

echo "=========================================="
echo ""

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    log_success "All tests passed!"
    exit 0
else
    log_error "Some tests failed"
    exit 1
fi
