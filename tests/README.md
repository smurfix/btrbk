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

## Test Structure

```
tests/
├── test_all.sh              # Main test runner
├── 01_local_complete_run.sh # First test: local send-receive
├── support/                 # Reusable helper scripts
│   ├── common.sh           # Test utilities and setup functions
│   ├── data_create.sh      # Create test data
│   ├── data_modify.sh      # Modify test data
│   └── data_verify.sh      # Verify/compare data
└── config/                  # Test configuration files
    └── local_simple.conf   # Basic local test config
```

## Available Tests

### 01_local_complete_run.sh

Tests complete local backup workflow with send-receive:
- Creates initial test data
- Runs initial backup with btrbk (2025-01-01)
- Verifies backup matches source
- Modifies test data (add/delete/modify files)
- Runs incremental backup (2025-01-02)
- Verifies incremental backup matches modified source

## Helper Scripts

### support/data_create.sh

Creates test data in a subvolume with deterministic content.

```bash
./support/data_create.sh <subvolume_path> <state_id>
```

**State IDs:**
- `initial` or `state1`: Basic directory structure with files
- `state2`: Extended dataset with more files

### support/data_modify.sh

Modifies existing test data in a subvolume.

```bash
./support/data_modify.sh <subvolume_path> <modification_set>
```

**Modification Sets:**
- `set1`: Basic modifications (add, delete, modify files)
- `set2`: Extended modifications
- `minor`: Small changes only
- `major`: Large-scale changes

### support/data_verify.sh

Verifies that two subvolumes contain identical data.

```bash
./support/data_verify.sh <source_path> <target_path> [options]
```

**Options:**
- `--expect-differences`: Expect differences (inverse check)
- `--file-list`: Only compare file lists, not contents
- `--verbose`: Show detailed comparison output

## Writing New Tests

1. Create a new test script: `NN_test_name.sh`
2. Source common.sh: `source "$SCRIPT_DIR/support/common.sh"`
3. Use setup_test_env() at the beginning
4. Use assertion functions for validation
5. Use cleanup_test_env() at the end
6. Return appropriate exit code

Example test template:

```bash
#!/bin/bash
set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/support/common.sh"

TEST_NAME="02_my_test"
CONFIG_FILE="$SCRIPT_DIR/config/my_config.conf"

log_info "Running test: $TEST_NAME"

setup_test_env "$TEST_NAME"
export TESTROOT

# Test implementation here
# Use assert_* functions for validation

cleanup_test_env
print_test_summary

[ $TEST_FAILED -eq 0 ] && exit 0 || exit 1
```

## Configuration Files

Test configurations use environment variable expansion:

```
volume ${TESTROOT}
  subvolume data
    target ${TESTROOT}/backup
```

## Cleanup

Tests automatically clean up after themselves. To manually clean:

```bash
# Remove test btrfs filesystem
sudo umount /mnt/test_btrfs
rm /tmp/btrbk_test.img

# Or just clean TESTROOT
sudo btrfs subvolume delete "$TESTROOT"/* 2>/dev/null || true
sudo rm -rf "$TESTROOT"/*
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

### Permission Errors

Tests require sudo for btrfs operations. Ensure your user can run sudo.

## Future Test Cases

- 02_local_raw.sh - Raw target backups
- 03_ssh_complete_run.sh - SSH remote backups
- 04_retention.sh - Retention policy testing
- 05_resume.sh - Interrupted backup recovery
- 06_archive.sh - Archive command testing
- 07_prune.sh - Snapshot/backup deletion
- 08_incremental.sh - Various incremental scenarios
