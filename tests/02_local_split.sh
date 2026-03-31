#!/bin/bash
#
# Test: Local split run with send-receive (step-by-step execution)
#
# This test verifies the same workflow as 01_local_complete_run.sh, but splits
# each "btrbk run" into individual steps as documented in the manpage:
#   Step 1: Create Snapshots      (btrbk snapshot --preserve)
#   Step 2: Create Backups        (btrbk resume --preserve)
#   Step 3: Delete Backups        (btrbk prune --preserve-snapshots)
#   Step 4: Delete Snapshots      (btrbk prune --preserve-backups)
#
# This test verifies that each step performs only its designated action.
#

set -e
set -u

# Set TEST_DIR to tests/ directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

CONFIG_TEMPLATE="$TEST_DIR/config/local_simple.conf"

log_info "=========================================="
log_info "Test: Local Split Run (step-by-step)"
log_info "=========================================="

#
# Test setup
#

setup_test_env
CONFIG_FILE="$TESTROOT/current.conf"
expand_config "$CONFIG_TEMPLATE" "$CONFIG_FILE"

#
# Phase 1: Initial backup (split into steps)
#

log_info "Phase 1: Initial Backup (2025-01-01) - Split Steps"

# Create initial test data
log_info "Creating initial test data..."
"$TEST_DIR/support/data_create.sh" "$TESTROOT/data" "initial"

# Step 1: Create snapshot only
log_info "Step 1: Creating snapshot..."
sudo_with_faketime "2025-01-01 11:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v snapshot --preserve

SNAPSHOT="$TESTROOT/snapshots/data.20250101T1100"
BACKUP1="$TESTROOT/backup/data.20250101T1100"

# Verify snapshot was created
assert_subvol_exists "$SNAPSHOT" "Snapshot should exist after step 1: $SNAPSHOT"

# Verify backup does NOT exist yet
if $SUDO btrfs subvolume show "$BACKUP1" >/dev/null 2>&1; then
    log_error "Backup should NOT exist after step 1 (snapshot only): $BACKUP1"
    exit 1
fi
log_success "Step 1 verified: Snapshot created, backup not yet created"

# Step 2: Create backup only
log_info "Step 2: Creating backup..."
sudo_with_faketime "2025-01-01 11:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v resume --preserve

# Verify backup was created
assert_subvol_exists "$BACKUP1" "Backup should exist after step 2: $BACKUP1"
log_success "Step 2 verified: Backup created"

# Verify backup contents match source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP1" --verbose

# Steps 3 & 4: No deletions expected (first backup)
log_info "Steps 3 & 4: No deletions expected for initial backup"

#
# Phase 2: Incremental backup (split into steps)
#

log_info "Phase 2: Incremental Backup (2025-01-02) - Split Steps"

# Modify test data
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set1"

# Step 1: Create snapshot only
log_info "Step 1: Creating snapshot..."
sudo_with_faketime "2025-01-02 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v snapshot --preserve

SNAPSHOT2="$TESTROOT/snapshots/data.20250102T1200"
BACKUP2="$TESTROOT/backup/data.20250102T1200"

# Verify new snapshot was created
assert_subvol_exists "$SNAPSHOT2" "New snapshot should exist after step 1: $SNAPSHOT2"

# Verify backup does NOT exist yet
if $SUDO btrfs subvolume show "$BACKUP2" >/dev/null 2>&1; then
    log_error "Backup should NOT exist after step 1 (snapshot only): $BACKUP2"
    exit 1
fi
log_success "Step 1 verified: New snapshot created, backup not yet created"

# Step 2: Create backup only
log_info "Step 2: Creating backup..."
sudo_with_faketime "2025-01-02 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v resume --preserve

# Verify new backup was created
assert_subvol_exists "$BACKUP2" "New backup should exist after step 2: $BACKUP2"
log_success "Step 2 verified: Backup created"

# Verify incremental backup contents match modified source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP2" --verbose

# Verify first backup still exists
assert_subvol_exists "$BACKUP1" "First backup should still exist: $BACKUP1"

# Steps 3 & 4: No deletions expected yet (all within retention)
log_info "Steps 3 & 4: No deletions expected (within retention)"

#
# Phase 3: Third backup with retention policy test (split into steps)
#

log_info "Phase 3: Third Backup with Retention (2025-01-04) - Split Steps"

# Modify test data again
"$TEST_DIR/support/data_modify.sh" "$TESTROOT/data" "set2"

# Step 1: Create snapshot only
log_info "Step 1: Creating snapshot..."
sudo_with_faketime "2025-01-04 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v snapshot --preserve

SNAPSHOT3="$TESTROOT/snapshots/data.20250104T1200"
BACKUP3="$TESTROOT/backup/data.20250104T1200"

# Verify new snapshot was created
assert_subvol_exists "$SNAPSHOT3" "Third snapshot should exist after step 1: $SNAPSHOT3"

# Verify backup does NOT exist yet
if $SUDO btrfs subvolume show "$BACKUP3" >/dev/null 2>&1; then
    log_error "Backup should NOT exist after step 1 (snapshot only): $BACKUP3"
    exit 1
fi
log_success "Step 1 verified: Third snapshot created, backup not yet created"

# Step 2: Create backup only
log_info "Step 2: Creating backup..."
sudo_with_faketime "2025-01-04 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v resume --preserve

# Verify new backup was created
assert_subvol_exists "$BACKUP3" "Third backup should exist after step 2: $BACKUP3"
log_success "Step 2 verified: Backup created"

# Verify third backup contents match modified source
"$TEST_DIR/support/data_verify.sh" "$TESTROOT/data" "$BACKUP3" --verbose

# All backups should still exist before deletion step
assert_subvol_exists "$BACKUP1" "First backup should exist before step 3: $BACKUP1"
assert_subvol_exists "$BACKUP2" "Second backup should exist before step 3: $BACKUP2"
assert_subvol_exists "$BACKUP3" "Third backup should exist before step 3: $BACKUP3"

# Steps 3 & 4: Still no deletions (all within retention)
log_info "Steps 3 & 4: No deletions expected (within retention)"

#
# Phase 4: Additional backups to test snapshot retention (split into steps)
#

log_info "Phase 4: Snapshot Retention Testing - Split Steps"

# Backup 4 (day 7)
log_info "Creating backup 4 (2025-01-07)..."
sudo_with_faketime "2025-01-07 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v snapshot --preserve

SNAPSHOT4="$TESTROOT/snapshots/data.20250107T1200"
BACKUP4="$TESTROOT/backup/data.20250107T1200"
assert_subvol_exists "$SNAPSHOT4" "Fourth snapshot should exist: $SNAPSHOT4"

sudo_with_faketime "2025-01-07 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v resume --preserve

assert_subvol_exists "$BACKUP4" "Fourth backup should exist: $BACKUP4"

# Backup 5 (day 10)
log_info "Creating backup 5 (2025-01-10)..."
sudo_with_faketime "2025-01-10 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v snapshot --preserve

SNAPSHOT5="$TESTROOT/snapshots/data.20250110T1200"
BACKUP5="$TESTROOT/backup/data.20250110T1200"
assert_subvol_exists "$SNAPSHOT5" "Fifth snapshot should exist: $SNAPSHOT5"

sudo_with_faketime "2025-01-10 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v resume --preserve

assert_subvol_exists "$BACKUP5" "Fifth backup should exist: $BACKUP5"

# Backup 6 (day 13) - this will trigger retention cleanup
log_info "Creating backup 6 (2025-01-13) with retention cleanup..."

# Step 1: Create snapshot
log_info "Step 1: Creating snapshot..."
sudo_with_faketime "2025-01-13 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v snapshot --preserve

SNAPSHOT6="$TESTROOT/snapshots/data.20250113T1200"
BACKUP6="$TESTROOT/backup/data.20250113T1200"
assert_subvol_exists "$SNAPSHOT6" "Sixth snapshot should exist: $SNAPSHOT6"

# Step 2: Create backup
log_info "Step 2: Creating backup..."
sudo_with_faketime "2025-01-13 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v resume --preserve

assert_subvol_exists "$BACKUP6" "Sixth backup should exist: $BACKUP6"

# Verify all backups still exist before deletion
log_info "Verifying all backups exist before deletion steps..."
for backup in "$BACKUP1" "$BACKUP2" "$BACKUP3" "$BACKUP4" "$BACKUP5" "$BACKUP6"; do
    assert_subvol_exists "$backup" "Backup should exist before deletion: $backup"
done

# Verify all snapshots still exist before deletion
log_info "Verifying all snapshots exist before deletion steps..."
for snapshot in "$SNAPSHOT" "$SNAPSHOT2" "$SNAPSHOT3" "$SNAPSHOT4" "$SNAPSHOT5" "$SNAPSHOT6"; do
    assert_subvol_exists "$snapshot" "Snapshot should exist before deletion: $snapshot"
done
log_success "All backups and snapshots preserved before deletion steps"

# Step 3: Delete backups according to retention policy
log_info "Step 3: Deleting old backups..."
sudo_with_faketime "2025-01-13 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v prune --preserve-snapshots

# With "2d 1w" policy on day 13:
# - Keep day 7 (weekly) and day 13 (most recent daily)
# - Delete days 1, 2, 4, 10

log_info "Verifying backup retention (2d 1w)..."
for backup in "$BACKUP1" "$BACKUP2" "$BACKUP3" "$BACKUP5"; do
    if test -d "$backup"; then
        log_error "Old backup should have been deleted in step 3: $backup"
        exit 1
    else
        log_success "Old backup correctly deleted: $(basename $backup)"
    fi
done

# Verify snapshots were NOT deleted in step 3
log_info "Verifying snapshots NOT deleted in step 3..."
for snapshot in "$SNAPSHOT" "$SNAPSHOT2" "$SNAPSHOT3" "$SNAPSHOT4" "$SNAPSHOT5" "$SNAPSHOT6"; do
    assert_subvol_exists "$snapshot" "Snapshot should NOT be deleted in step 3: $snapshot"
done
log_success "Step 3 verified: Only backups deleted, snapshots preserved"

# Verify kept backups still exist
assert_subvol_exists "$BACKUP4" "Fourth backup should exist (day 7, weekly): $BACKUP4"
assert_subvol_exists "$BACKUP6" "Sixth backup should exist (day 13, most recent): $BACKUP6"

# Step 4: Delete snapshots according to retention policy
log_info "Step 4: Deleting old snapshots..."
sudo_with_faketime "2025-01-13 12:00:00" \
    "$BTRBK_BIN" -c "$CONFIG_FILE" -v prune --preserve-backups

# With snapshot_preserve 5d: keep only day 10 and day 13
# Delete days 1, 2, 4, 7

log_info "Verifying snapshot retention (5d)..."
for snapshot in "$SNAPSHOT" "$SNAPSHOT2" "$SNAPSHOT3" "$SNAPSHOT4"; do
    if test -d "$snapshot"; then
        log_error "Old snapshot should have been deleted in step 4: $snapshot"
        exit 1
    else
        log_success "Old snapshot correctly deleted: $(basename $snapshot)"
    fi
done

# Verify recent snapshots still exist
assert_subvol_exists "$SNAPSHOT5" "Fifth snapshot should exist (day 10): $SNAPSHOT5"
assert_subvol_exists "$SNAPSHOT6" "Sixth snapshot should exist (day 13): $SNAPSHOT6"

# Verify backups were NOT deleted in step 4
log_info "Verifying backups NOT deleted in step 4..."
assert_subvol_exists "$BACKUP4" "Backup should NOT be deleted in step 4: $BACKUP4"
assert_subvol_exists "$BACKUP6" "Backup should NOT be deleted in step 4: $BACKUP6"
log_success "Step 4 verified: Only snapshots deleted, backups preserved"

log_success "PASS $0"
exit 0
