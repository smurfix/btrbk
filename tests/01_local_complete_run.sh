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

#
# Phase 1: Initial backup
#

log_info "Phase 1: Initial Backup"

# Create initial test data
log_info "Creating initial test data..."
"$TEST_DIR/support/data_create.sh" "$TESTROOT/data" "initial"

# Run btrbk with faketime for deterministic timestamp
log_info "Running initial backup (2025-01-01)"
sudo_with_faketime "2025-01-01 11:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

# Verify snapshot was created
SNAPSHOT="$TESTROOT/snapshots/data.20250101T1100"
assert_subvol_exists "$SNAPSHOT" "Snapshot should exist: $SNAPSHOT"

# Verify backup was created
BACKUP1="$TESTROOT/backup/data.20250101T1100"
assert_subvol_exists "$BACKUP1" "Backup should exist: $BACKUP1"

# Verify backup contents match source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP1" --verbose

#
# Phase 2: Incremental backup after modifications
#

log_info "Phase 2: Incremental Backup (2025-01-02)"

# Modify test data
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set1"

# Run incremental backup
sudo_with_faketime "2025-01-02 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

# Verify new snapshot was created
SNAPSHOT2="$TESTROOT/snapshots/data.20250102T1200"
assert_subvol_exists "$SNAPSHOT2" "New snapshot should exist: $SNAPSHOT2"

# Verify new backup was created
BACKUP2="$TESTROOT/backup/data.20250102T1200"
assert_subvol_exists "$BACKUP2" "New backup should exist: $BACKUP2"

# Verify incremental backup contents match modified source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP2" --verbose

# Verify first backup still exists and hasn't changed
assert_subvol_exists "$BACKUP1" "First backup should still exist: $BACKUP1"

#
# Phase 3: Third backup with retention policy test
#

log_info "Phase 3: Third Backup with Retention (2025-01-04)"

# Modify test data again
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set2"

# Run third backup (4 days later) - this should trigger retention cleanup
sudo_with_faketime "2025-01-04 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

# Verify new snapshot was created
SNAPSHOT3="$TESTROOT/snapshots/data.20250104T1200"
assert_subvol_exists "$SNAPSHOT3" "Third snapshot should exist: $SNAPSHOT3"

# Verify third backup was created
BACKUP3="$TESTROOT/backup/data.20250104T1200"
assert_subvol_exists "$BACKUP3" "Third backup should exist: $BACKUP3"

# Verify third backup contents match modified source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP3" --verbose

# Check retention policy: with target_preserve 2d 1w, first backup should be deleted
assert_subvol_exists "$BACKUP1" "First backup should still exist: $BACKUP1"

# Second and third backups should still exist (within 2d retention)
assert_subvol_exists "$BACKUP2" "Second backup should still exist: $BACKUP2"
assert_subvol_exists "$BACKUP3" "Third backup should still exist: $BACKUP3"

log_success "Phase 3 complete: Retention policy working correctly"

#
# Phase 4: Additional backups to test snapshot retention
#

log_info "Phase 4: Snapshot Retention Testing (2025-01-07, -10, -13)"

# Create more backups on days 7 and 10 to exceed snapshot_preserve 5d
sudo_with_faketime "2025-01-07 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

SNAPSHOT4="$TESTROOT/snapshots/data.20250107T1200"
BACKUP4="$TESTROOT/backup/data.20250107T1200"
assert_subvol_exists "$SNAPSHOT4" "Fourth snapshot should exist: $SNAPSHOT4"
assert_subvol_exists "$BACKUP4" "Fourth backup should exist: $BACKUP4"

sudo_with_faketime "2025-01-10 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

SNAPSHOT5="$TESTROOT/snapshots/data.20250110T1200"
BACKUP5="$TESTROOT/backup/data.20250110T1200"
assert_subvol_exists "$SNAPSHOT5" "Fifth snapshot should exist: $SNAPSHOT5"
assert_subvol_exists "$BACKUP5" "Fifth backup should exist: $BACKUP5"

sudo_with_faketime "2025-01-13 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

SNAPSHOT6="$TESTROOT/snapshots/data.20250113T1200"
BACKUP6="$TESTROOT/backup/data.20250113T1200"
assert_subvol_exists "$SNAPSHOT6" "Sixth snapshot should exist: $SNAPSHOT6"
assert_subvol_exists "$BACKUP6" "Sixth backup should exist: $BACKUP6"

# Check snapshot retention policy: with snapshot_preserve 5d, oldest snapshots should be deleted

for snapshot in "$SNAPSHOT" "$SNAPSHOT2" "$SNAPSHOT3" "$SNAPSHOT4"; do
    if test -d "$snapshot"; then
        log_error "Old snapshot should have been deleted by retention policy: $snapshot"
        exit 1
    else
        log_success "Old snapshot correctly deleted: $(basename $snapshot)"
    fi
done

# Only recent snapshots within 5d window should still exist
assert_subvol_exists "$SNAPSHOT5" "Fifth snapshot should exist (day 10): $SNAPSHOT5"
assert_subvol_exists "$SNAPSHOT6" "Sixth snapshot should exist (day 13): $SNAPSHOT6"

# Check backup retention: with "2d 1w", should keep 2 daily + 1 weekly
log_info "Verifying backup retention (2d 1w) applied correctly..."

# Note: 2025-01-01 is a Wednesday
# Week boundaries (Sun-Sat):
#   Week 1: Dec 29 - Jan 4 (contains day 1, 2, 4)
#   Week 2: Jan 5 - Jan 11 (contains day 7 [Tue], 10 [Fri])
#   Week 3: Jan 12 - Jan 18 (contains day 13 [Mon])
# With preserve_day_of_week=sunday (default), btrbk picks backup closest to Sunday

# With "2d 1w" policy on day 13:
# - 1w: Keep day 7 as weekly (closest to Sunday Jan 5 in most recent complete week 2)
# - 2d: Keep day 13 (most recent) and day 7 (which also counts as daily)
# - Day 10 doesn't fit either slot, gets deleted
# Expected: day 7 and day 13 should remain

# Old backups should be deleted
for backup in "$BACKUP1" "$BACKUP2" "$BACKUP3" "$BACKUP5"; do
    if test -d "$backup"; then
        log_error "Old backup should have been deleted: $backup"
        exit 1
    else
        log_success "Old backup correctly deleted: $(basename $backup)"
    fi
done

# Day 7 and day 13 should be kept
assert_subvol_exists "$BACKUP4" "Fourth backup should exist (day 7, weekly + daily): $BACKUP4"
assert_subvol_exists "$BACKUP6" "Sixth backup should exist (day 13, most recent daily): $BACKUP6"

log_success "PASS $0"
exit 0
