#!/bin/bash
#
# Test: Local complete run with raw backups
#
# This test verifies the complete backup workflow using raw mode:
# 1. Create initial test data
# 2. Run initial backup with btrbk (using faketime)
# 3. Restore raw backup and verify it matches source
# 4. Modify test data
# 5. Run incremental backup
# 6. Restore incremental raw backup and verify it matches modified source
#
# Raw backups are stored as .btrfs files (filesystem-independent)
# and must be restored using btrfs receive to verify contents.
#

set -e
set -u

# Set TEST_DIR to tests/ directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

TEST_NAME="11_local_raw"
CONFIG_TEMPLATE="$TEST_DIR/config/local_raw.conf"

log_info "=========================================="
log_info "Test: Local Complete Run (raw mode)"
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
export INCREMENTAL=yes
CONFIG_FILE="$TESTROOT/current.conf"
expand_config "$CONFIG_TEMPLATE" "$CONFIG_FILE" || {
    log_error "Failed to expand config file"
    exit 1
}
CONFIG_FILE_NONINCR="$TESTROOT/current.nonincr.conf"
export INCREMENTAL=no
expand_config "$CONFIG_TEMPLATE" "$CONFIG_FILE_NONINCR" || {
    log_error "Failed to expand config file"
    exit 1
}
export -n INCREMENTAL

log_info "Creating test data subvolume..."
create_subvol "$TESTROOT/data"

log_info "Creating backup directory..."
$SUDO mkdir -p "$TESTROOT/backup"

log_info "Creating snapshots directory..."
$SUDO mkdir -p "$TESTROOT/snapshots"

log_info "Creating temp directory for raw restore..."
# $SUDO mkdir -p "$TESTROOT/temp"

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

# Verify raw backup file was created
RAW_BACKUP1="$TESTROOT/backup/data.20250101T1100.btrfs"
if [ ! -f "$RAW_BACKUP1" ]; then
    log_error "Raw backup file not found: $RAW_BACKUP1"
    exit 1
fi
log_success "Raw backup file created: $(basename "$RAW_BACKUP1")"

# Verify .info file was created
if [ ! -f "$RAW_BACKUP1.info" ]; then
    log_error "Raw backup info file not found: $RAW_BACKUP1.info"
    exit 1
fi
log_success "Raw backup info file created"

# Restore raw backup and verify contents
log_info "Restoring raw backup to verify contents..."
RESTORE1="$TESTROOT/temp/restore1"
$SUDO rm -rf "$RESTORE1"
"$TEST_DIR/support/raw_restore.sh" "$RAW_BACKUP1" "$TESTROOT/temp"

# The restored subvolume will have the same name as the original
RESTORED_SUBVOL1="$TESTROOT/temp/data.20250101T1100"
assert_subvol_exists "$RESTORED_SUBVOL1" "Restored subvolume should exist: $RESTORED_SUBVOL1"

# Verify restored contents match source
log_info "Verifying restored backup contents match source..."
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$RESTORED_SUBVOL1" --verbose

log_success "Phase 1 complete: Initial raw backup successful"

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

# Verify raw backup file was created
RAW_BACKUP2="$TESTROOT/backup/data.20250102T1200.btrfs"
if [ ! -f "$RAW_BACKUP2" ]; then
    log_error "Raw backup file not found: $RAW_BACKUP2"
    exit 1
fi
log_success "Raw backup file created: $(basename "$RAW_BACKUP2")"

# Verify first raw backup still exists
if [ ! -f "$RAW_BACKUP1" ]; then
    log_error "First raw backup should still exist: $RAW_BACKUP1"
    exit 1
fi
log_success "First raw backup still exists"

# Restore raw backup and verify contents
log_info "Restoring incremental raw backup to verify contents..."
$SUDO rm -rf "$TESTROOT/temp/data.20250102T1200"
"$TEST_DIR/support/raw_restore.sh" "$RAW_BACKUP2" "$TESTROOT/temp"

RESTORED_SUBVOL2="$TESTROOT/temp/data.20250102T1200"
assert_subvol_exists "$RESTORED_SUBVOL2" "Restored subvolume should exist: $RESTORED_SUBVOL2"

# Verify restored contents match modified source
log_info "Verifying restored incremental backup contents match source..."
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$RESTORED_SUBVOL2" --verbose

log_success "Phase 2 complete: Incremental raw backup successful"

#
# Phase 3: Third backup with retention policy test
#

log_info "Phase 3: Third Backup with Retention (2025-01-04)"

# Modify test data again
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set2"

# Run third backup (4 days later) - this should trigger retention cleanup
sudo_with_faketime "2025-01-04 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE_NONINCR" -v run

# Verify new snapshot was created
SNAPSHOT3="$TESTROOT/snapshots/data.20250104T1200"
assert_subvol_exists "$SNAPSHOT3" "Third snapshot should exist: $SNAPSHOT3"

# Verify third raw backup was created
RAW_BACKUP3="$TESTROOT/backup/data.20250104T1200.btrfs"
if [ ! -f "$RAW_BACKUP3" ]; then
    log_error "Raw backup file not found: $RAW_BACKUP3"
    exit 1
fi
log_success "Raw backup file created: $(basename "$RAW_BACKUP3")"

# Restore and verify third backup
log_info "Restoring third raw backup to verify contents..."
$SUDO rm -rf "$TESTROOT/temp/data.20250104T1200"
"$TEST_DIR/support/raw_restore.sh" "$RAW_BACKUP3" "$TESTROOT/temp"

RESTORED_SUBVOL3="$TESTROOT/temp/data.20250104T1200"
assert_subvol_exists "$RESTORED_SUBVOL3" "Restored subvolume should exist: $RESTORED_SUBVOL3"

# Verify restored contents match modified source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$RESTORED_SUBVOL3" --verbose

# Check retention policy: with target_preserve 2d 1w, all backups should still exist
if [ ! -f "$RAW_BACKUP1" ]; then
    log_error "First raw backup should still exist: $RAW_BACKUP1"
    exit 1
fi
if [ ! -f "$RAW_BACKUP2" ]; then
    log_error "Second raw backup should still exist: $RAW_BACKUP2"
    exit 1
fi
if [ ! -f "$RAW_BACKUP3" ]; then
    log_error "Third raw backup should still exist: $RAW_BACKUP3"
    exit 1
fi

log_success "Phase 3 complete: Retention policy working correctly"

#
# Phase 4: Additional backups to test snapshot retention
#

log_info "Phase 4: Snapshot Retention Testing (2025-01-07, -10, -13)"

# Create more backups on days 7, 10, and 13
sudo_with_faketime "2025-01-07 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

SNAPSHOT4="$TESTROOT/snapshots/data.20250107T1200"
RAW_BACKUP4="$TESTROOT/backup/data.20250107T1200.btrfs"
assert_subvol_exists "$SNAPSHOT4" "Fourth snapshot should exist: $SNAPSHOT4"
if [ ! -f "$RAW_BACKUP4" ]; then
    log_error "Fourth raw backup file not found: $RAW_BACKUP4"
    exit 1
fi

sudo_with_faketime "2025-01-10 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

SNAPSHOT5="$TESTROOT/snapshots/data.20250110T1200"
RAW_BACKUP5="$TESTROOT/backup/data.20250110T1200.btrfs"
assert_subvol_exists "$SNAPSHOT5" "Fifth snapshot should exist: $SNAPSHOT5"
if [ ! -f "$RAW_BACKUP5" ]; then
    log_error "Fifth raw backup file not found: $RAW_BACKUP5"
    exit 1
fi

sudo_with_faketime "2025-01-13 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v run

SNAPSHOT6="$TESTROOT/snapshots/data.20250113T1200"
RAW_BACKUP6="$TESTROOT/backup/data.20250113T1200.btrfs"
assert_subvol_exists "$SNAPSHOT6" "Sixth snapshot should exist: $SNAPSHOT6"
if [ ! -f "$RAW_BACKUP6" ]; then
    log_error "Sixth raw backup file not found: $RAW_BACKUP6"
    exit 1
fi

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

# Check backup retention: with "2d 1w", should keep day 7 (weekly) and day 13 (daily)
log_info "Verifying raw backup retention (2d 1w) applied correctly..."

# Old backups should be deleted
for raw_backup in "$RAW_BACKUP1" "$RAW_BACKUP2"; do
    if test -f "$raw_backup"; then
        log_error "Old raw backup should have been deleted: $raw_backup"
        exit 1
    else
        log_success "Old raw backup correctly deleted: $(basename $raw_backup)"
    fi
done

# Day 7 and day 13 should be kept
if [ ! -f "$RAW_BACKUP3" ]; then
    log_error "Third raw backup should exist (day 4, full backup): $RAW_BACKUP3"
    exit 1
fi
log_success "Third raw backup exists, the fourth needs it"

if [ ! -f "$RAW_BACKUP4" ]; then
    log_error "Fourth raw backup should exist (day 7, weekly): $RAW_BACKUP4"
    exit 1
fi
log_success "Fourth raw backup exists (day 7, weekly)"

if [ ! -f "$RAW_BACKUP5" ]; then
    log_error "Fifth raw backup should exist, the sixth needs it: $RAW_BACKUP5"
    exit 1
fi
log_success "Sixth raw backup exists (day 13, most recent)"

if [ ! -f "$RAW_BACKUP6" ]; then
    log_error "Sixth raw backup should exist (day 13, most recent): $RAW_BACKUP6"
    exit 1
fi
log_success "Sixth raw backup exists (day 13, most recent)"

# Verify the remaining backups can be restored successfully
log_info "Verifying remaining raw backups can be restored..."

$SUDO rm -rf "$TESTROOT/temp/data.20250107T1200"
"$TEST_DIR/support/raw_restore.sh" "$RAW_BACKUP4" "$TESTROOT/temp"
assert_subvol_exists "$TESTROOT/temp/data.20250107T1200" "Backup 4 restored successfully"

$SUDO rm -rf "$TESTROOT/temp/data.20250113T1200"
"$TEST_DIR/support/raw_restore.sh" "$RAW_BACKUP6" "$TESTROOT/temp"
assert_subvol_exists "$TESTROOT/temp/data.20250113T1200" "Backup 6 restored successfully"

log_success "Phase 4 complete: Snapshot and raw backup retention working correctly"

log_success "PASS $0"
exit 0
