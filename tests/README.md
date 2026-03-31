# btrbk Test Suite

Comprehensive test suite for btrbk backup functionality.

## Prerequisites

- **btrfs-progs**: For btrfs commands
- **faketime**: For deterministic timestamps in tests
- **TESTROOT**: A writable btrfs subvolume for testing

## Setup

### Option 1: Use Existing Btrfs Filesystem

```bash
export TESTROOT=/mnt/btrfs_volume/test
sudo mkdir -p "$TESTROOT"
```

### Option 2: Create Test Btrfs Filesystem

```bash
# Create a 10GB image file
truncate -s 10G /tmp/btrbk_test.img

# Format as btrfs
mkfs.btrfs /tmp/btrbk_test.img

# Mount it
sudo mkdir -p /mnt/test_btrfs
sudo mount -o loop /tmp/btrbk_test.img /mnt/test_btrfs

# Set TESTROOT
export TESTROOT=/mnt/test_btrfs
```

## Running Tests

The test suite uses `sudo` liberally. You might want to do something like
this, in order to not type your password umpteen times:

```bash
export SUDO_ASKPASS=$XDG_RUNTIME_DIR/sudo_password
cat >$SUDO_ASKPASS <<END
#!/bin/sh
echo $(quote "$(ssh-askpass)")
END
chmod 700 $SUDO_ASKPASS
```

### Run All Tests

```bash
cd tests
./test_all.sh
```

### Run Specific Test

```bash
cd tests
./01_local_complete_run.sh
```

### Run Tests Matching Pattern

```bash
cd tests
./test_all.sh "01_*.sh"  # Run only test 01
./test_all.sh "*local*.sh"  # Run all local tests
```

## Available Tests

### 01\_local\_complete\_run.sh

Tests complete local backup workflow with send-receive:
- Creates initial test data
- Runs initial backup with btrbk (2025-01-01)
- Verifies backup matches source
- Modifies test data (add/delete/modify files)
- Runs incremental backup (2025-01-02)
- Verifies incremental backup matches modified source
- Tests retention policies (snapshot\_preserve 5d, target\_preserve 2d 1w)

### 02\_local\_split.sh

Tests the same workflow as 01, but splits each `btrbk run` into individual steps:
- Step 1: Create snapshots (`btrbk snapshot --preserve`)
- Step 2: Create backups (`btrbk resume --preserve`)
- Step 3: Delete backups (`btrbk prune --preserve-snapshots`)
- Step 4: Delete snapshots (`btrbk prune --preserve-backups`)
- Verifies that each step performs only its designated action

### 11\_local\_raw.sh

Tests complete local backup workflow with raw mode:
- Same workflow as 01\_local\_complete\_run.sh but uses raw backups
- Raw backups are stored as .btrfs files (filesystem-independent)
- Uses raw\_restore.sh helper to restore and verify backups
- Tests both incremental and non-incremental raw backups
- Tests retention policies with incremental backup chain dependencies
- Verifies that parent backups are preserved when children depend on them

## Helper Scripts

### support/data\_create.sh

Creates test data in a subvolume with deterministic content.

```bash
./support/data_create.sh <subvolume_path> <state_id>
```

**State IDs:**
- `initial` or `state1`: Basic directory structure with files
- `state2`: Extended dataset with more files

### support/data\_modify.sh

Modifies existing test data in a subvolume.

```bash
./support/data_modify.sh <subvolume_path> <modification_set>
```

**Modification Sets:**
- `set1`: Basic modifications (add, delete, modify files)
- `set2`: Extended modifications
- `minor`: Small changes only
- `major`: Large-scale changes

### support/data\_verify.sh

Verifies that two subvolumes contain identical data.

```bash
./support/data_verify.sh <source_path> <target_path> [options]
```

**Options:**
- `--expect-differences`: Expect differences (inverse check)
- `--file-list`: Only compare file lists, not contents
- `--verbose`: Show detailed comparison output

### support/raw\_restore.sh

Restores a raw backup to a btrfs subvolume for verification.

```bash
./support/raw_restore.sh <raw_backup_file> <restore_target_dir>
```

**Features:**
- Automatically detects compression (gzip, bzip2, xz, lz4, zstd)
- Handles incremental backups

**Example:**
```bash
./support/raw_restore.sh /path/to/backup/data.20250101T1200.btrfs /mnt/restore
./support/raw_restore.sh /path/to/backup/data.20250101T1200.btrfs.gz /mnt/restore
```

## Writing New Tests

1. Name the test script `NN_test_name.sh`
2. `source "$TEST_DIR/support/common.sh"`
3. Use `setup_test_env` at the beginning
4. Use assertion functions for validation
5. Write a one-liner to stderr and `exit 1` on failure. Do not continue.
6. Do not clean up at the end, that's the job of test `99_cleanup`
7. Return appropriate exit code

Example test template:

```bash
#!/bin/bash
set -e
set -u

# Set TEST_DIR to tests/ directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"
setup_test_env

CONFIG_TEMPLATE="$TEST_DIR/config/my_config.conf"
CONFIG_FILE="$TESTROOT/current.conf"
expand_config "$CONFIG_TEMPLATE" "$CONFIG_FILE"

export TESTROOT

# Test implementation here
# Use assert_* functions for validation
# `exit 1` on failure

exit 0
```

## Configuration Files

Test configurations use environment variable expansion:

```
volume ${TESTROOT}
  subvolume data
    target ${TESTROOT}/backup
```

## Cleanup

The `test_all.sh` wrapper cleans up after testing. Individual tests do not,
so the result can be inspected manually.

To manually clean:

```bash
# Remove test btrfs filesystem
sudo umount /mnt/test_btrfs
rm /tmp/btrbk_test.img

# Or just clean TESTROOT
cd tests
./99_cleanup.sh
```

## Troubleshooting

### "TESTROOT is not on a btrfs filesystem"

Ensure TESTROOT points to a btrfs-mounted directory:
```bash
sudo btrfs subvolume show "$TESTROOT"
```

### "Required command not found: faketime"

Install faketime:
```bash
# Debian/Ubuntu
sudo apt-get install faketime

# Fedora
sudo dnf install libfaketime

# Arch
sudo pacman -S libfaketime
```

## Future Test Cases

- 03\_ssh\_complete\_run.sh - SSH remote backups
- 04\_retention.sh - Additional retention policy testing scenarios
- 05\_resume.sh - Interrupted backup recovery
- 06\_archive.sh - Archive command testing
- 12\_local\_raw\_compressed.sh - Raw backups with compression
