#!/bin/bash
#
# Test: Local complete run with send-receive
#
# This test verifies the complete backup workflow:
# 1. Create initial test data
# 2. Run initial backup with btrbk (using faketime)
# 3. Verify backup matches source
# 4. Modify test data
# 5. Run incremental backup
# 6. Verify incremental backup matches modified source
#

set -e
set -u

# Set TEST_DIR to tests/ directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

TEST_NAME="01_local_complete_run"
CONFIG_TEMPLATE="$TEST_DIR/config/local_simple.conf"

log_info "=========================================="
log_info "Test: Local Complete Run (send-receive)"
log_info "=========================================="

#
# Test setup
#

log_info "Setting up test environment..."
setup_test_env "$TEST_NAME" || {
    log_error "Failed to setup test environment"
    exit 1
}

# Expand config file template
CONFIG_FILE="$TESTROOT/current.conf"
expand_config "$CONFIG_TEMPLATE" "$CONFIG_FILE" || {
    log_error "Failed to expand config file"
    exit 1
}

log_info "Creating test data subvolume..."
create_subvol "$TESTROOT/data"

log_info "Creating backup directory..."
$SUDO mkdir -p "$TESTROOT/backup"

log_info "Creating snapshots directory..."
$SUDO mkdir -p "$TESTROOT/snapshots"

#
# Phase 1: Initial backup
#

log_info ""
log_info "=========================================="
log_info "Phase 1: Initial Backup"
log_info "=========================================="

# Create initial test data
log_info "Creating initial test data..."
"$TEST_DIR/support/data_create.sh" "$TESTROOT/data" "initial"

# Run btrbk with faketime for deterministic timestamp
log_info "Running initial backup with btrbk (date: 2025-01-01)..."
sudo_with_faketime "2025-01-01 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

# Verify snapshot was created
log_info "Verifying snapshot creation..."
SNAPSHOT="$TESTROOT/snapshots/data.20250101T1200"
assert_subvol_exists "$SNAPSHOT" "Snapshot should exist: $SNAPSHOT"

# Verify backup was created
log_info "Verifying backup creation..."
BACKUP1="$TESTROOT/backup/data.20250101T1200"
assert_subvol_exists "$BACKUP1" "Backup should exist: $BACKUP1"

# Verify backup contents match source
log_info "Verifying backup contents match source..."
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP1" --verbose

log_success "Phase 1 complete: Initial backup successful"

#
# Phase 2: Incremental backup after modifications
#

log_info ""
log_info "=========================================="
log_info "Phase 2: Incremental Backup"
log_info "=========================================="

# Modify test data
log_info "Modifying test data..."
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set1"

# Run incremental backup
log_info "Running incremental backup with btrbk (date: 2025-01-02)..."
sudo_with_faketime "2025-01-02 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

# Verify new snapshot was created
log_info "Verifying new snapshot creation..."
SNAPSHOT2="$TESTROOT/snapshots/data.20250102T1200"
assert_subvol_exists "$SNAPSHOT2" "New snapshot should exist: $SNAPSHOT2"

# Verify new backup was created
log_info "Verifying new backup creation..."
BACKUP2="$TESTROOT/backup/data.20250102T1200"
assert_subvol_exists "$BACKUP2" "New backup should exist: $BACKUP2"

# Verify incremental backup contents match modified source
log_info "Verifying incremental backup contents match modified source..."
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP2" --verbose

# Verify first backup still exists and hasn't changed
log_info "Verifying first backup still exists..."
assert_subvol_exists "$BACKUP1" "First backup should still exist: $BACKUP1"

log_success "Phase 2 complete: Incremental backup successful"

#
# Phase 3: Third backup with retention policy test
#

log_info ""
log_info "=========================================="
log_info "Phase 3: Third Backup with Retention"
log_info "=========================================="

# Modify test data again
log_info "Modifying test data again..."
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set2"

# Run third backup (4 days later) - this should trigger retention cleanup
log_info "Running third backup with btrbk (date: 2025-01-04)..."
sudo_with_faketime "2025-01-04 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

# Verify new snapshot was created
log_info "Verifying third snapshot creation..."
SNAPSHOT3="$TESTROOT/snapshots/data.20250104T1200"
assert_subvol_exists "$SNAPSHOT3" "Third snapshot should exist: $SNAPSHOT3"

# Verify third backup was created
log_info "Verifying third backup creation..."
BACKUP3="$TESTROOT/backup/data.20250104T1200"
assert_subvol_exists "$BACKUP3" "Third backup should exist: $BACKUP3"

# Verify third backup contents match modified source
log_info "Verifying third backup contents match modified source..."
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP3" --verbose

# Check retention policy: with target_preserve 2d, first backup should be deleted
log_info "Verifying retention policy applied..."
if $SUDO btrfs subvolume show "$BACKUP1" >/dev/null 2>&1; then
    log_error "First backup should have been deleted by retention policy: $BACKUP1"
    TEST_FAILED=$((TEST_FAILED + 1))
else
    log_success "First backup correctly deleted by retention policy"
    TEST_PASSED=$((TEST_PASSED + 1))
fi

# Second and third backups should still exist (within 2d retention)
assert_subvol_exists "$BACKUP2" "Second backup should still exist: $BACKUP2"
assert_subvol_exists "$BACKUP3" "Third backup should still exist: $BACKUP3"

log_success "Phase 3 complete: Retention policy working correctly"

#
# Phase 4: Verification checks
#

log_info ""
log_info "=========================================="
log_info "Phase 4: Additional Verification"
log_info "=========================================="

# Verify that the two backups are different (since we modified data)
log_info "Verifying backups are different (as expected)..."
if "$TEST_DIR/support/data_verify.sh" "$BACKUP1" "$BACKUP2" --verbose 2>/dev/null; then
    log_error "Backups should be different but are identical!"
    TEST_FAILED=$((TEST_FAILED + 1))
else
    log_success "Backups are correctly different"
    TEST_PASSED=$((TEST_PASSED + 1))
fi

# List all subvolumes created
log_info "Listing all test subvolumes..."
list_subvols "$TESTROOT" | grep -E '(data|backup)' || true

# Check btrbk list output
log_info "Checking btrbk list snapshots..."
$SUDO "$BTRBK_BIN" -c "$CONFIG_FILE" list snapshots

log_info "Checking btrbk list backups..."
$SUDO "$BTRBK_BIN" -c "$CONFIG_FILE" list backups

log_success "Phase 4 complete: All verifications passed"

#
# Test summary
#

log_info ""
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_success "=========================================="
    log_success "Test PASSED: $TEST_NAME"
    log_success "=========================================="
    exit 0
else
    log_error "=========================================="
    log_error "Test FAILED: $TEST_NAME"
    log_error "=========================================="
    exit 1
fi
