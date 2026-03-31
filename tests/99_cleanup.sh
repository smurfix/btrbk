#!/bin/bash
#
# Test: Clean up at the end of a test run
#
# This is a no-op test that you can use standalone to clean up the
# artefacts left over by a previous test run.

set -e
set -u

# Set TEST_DIR to tests/ directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

log_info "============="
log_info "Test clean up"
log_info "============="

cleanup_test_env
