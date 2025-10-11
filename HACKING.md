# HACKING.md

This file provides guidance to AI helpers when working with code in this repository,
though humans are free to use it too. ;-)


## Project Overview

Btrbk is a backup tool for btrfs subvolumes. It creates atomic snapshots and transfers them incrementally to backup locations, with features like flexible retention policies, SSH transfers, encryption support, and transaction logging.

## Core Architecture

### Main Components

- **btrbk** (Perl script): Single executable containing all core logic (~272KB)
- **lsbtr** (symlink to btrbk): Alternative command for listing subvolumes
- **ssh_filter_btrbk.sh**: SSH command filter for secure remote operations
- **Configuration**: `/etc/btrbk/btrbk.conf` or `/etc/btrbk.conf`

### Key Concepts

- **Volume**: Base path within btrfs filesystem (usually subvolid=5)
- **Subvolume**: Source subvolume to be backed up (relative to volume)
- **Snapshot**: Read-only snapshot created in `snapshot_dir`
- **Target**: Destination for backups (local path or ssh://host/path)
- **Retention Policy**: Defined by `snapshot_preserve*` and `target_preserve*` options

### Btrfs Relationships

btrbk relies on btrfs UUID relationships:
- **received_uuid**: Links identical read-only subvolumes across filesystems (required for incremental backups)
- **parent_uuid**: "is-snapshot-of" relationship between snapshots

## Development Commands

### Building

```bash
# Build man pages (requires asciidoctor or a2x)
make man

# Build everything
make all

# Clean build artifacts
make clean
```

### Installation

```bash
# Install all components
make install

# Individual components
make install-bin          # Install btrbk binary
make install-bin-links    # Install lsbtr symlink
make install-etc          # Install example configs
make install-man          # Install man pages
make install-systemd      # Install systemd units
make install-share        # Install auxiliary scripts
```

## Test Suite

### Overview

The test suite (`tests/`) provides comprehensive automated testing for btrbk functionality. Tests are written in Bash and use reusable helper scripts for data creation, modification, and verification.

### Running Tests

```bash
# Run all tests
export TESTROOT=/mnt/test_btrfs
export SUDO_ASKPASS=/path/to/askpass
make test

# Or directly
cd tests && ./test_all.sh

# Run specific test
cd tests && ./01_local_complete_run.sh
```

### Test Structure

```
tests/
├── test_all.sh                    # Main runner (auto-discovers tests)
├── 01_local_complete_run.sh       # Local send-receive test
├── support/                       # Reusable utilities
│   ├── common.sh                  # Test framework, assertions, btrfs ops
│   ├── data_create.sh             # Generate test data (initial, state1, state2)
│   ├── data_modify.sh             # Modify data (set1, set2, minor, major)
│   ├── data_verify.sh             # Deep subvolume comparison
│   └── expand_vars.py             # Config variable expansion
└── config/                        # Test configuration templates
    └── local_simple.conf          # Basic local config
```

### Environment Variables

- **TESTROOT** (required): Path to btrfs subvolume for testing
- **SUDO**: Sudo command with arguments (default: `sudo -A --preserve-env=TESTROOT`)
- **SUDO_ASKPASS**: Path to askpass helper for non-interactive sudo
- **TEST_DIR**: Always points to `tests/` directory (set automatically)
- **BTRBK_BIN**: Path to btrbk binary (default: `../btrbk`)

### Test Utilities (tests/support/common.sh)

Key functions:
- `setup_test_env()` / `cleanup_test_env()`: Test lifecycle management
- `expand_config(template, output)`: Expand environment variables in config files
- `create_subvol()` / `delete_subvol()`: Btrfs subvolume operations
- `assert_subvol_exists()`, `assert_file_exists()`: Assertions
- `sudo_with_faketime()`: Run commands with deterministic timestamps
- `compare_subvols()`: Deep comparison of two subvolumes

### Config File Expansion

Test configs use environment variable syntax (`${TESTROOT}`). The `expand_config()` function substitutes them before passing the config to btrbk.

Example:
```bash
CONFIG_FILE="$TESTROOT/current.conf"
expand_config "$CONFIG_TEMPLATE" "$CONFIG_FILE"
```

### Writing New Tests

1. Create `NN_testname.sh` in `tests/`
2. Set up TEST_DIR and source common.sh:
   ```bash
   TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   export TEST_DIR
   source "$TEST_DIR/support/common.sh"
   ```
3. Use `setup_test_env()` at start. Do not call `cleanup_test_env()` at end
   of individual tests.
4. Expand config file with `expand_config()`
5. Use `sudo_with_faketime()` for btrbk operations with deterministic timestamps
6. Use assertion functions for validation
7. Return 0 for success, non-zero for failure

Test discovery is automatic - `test_all.sh` finds all `[0-9][0-9]_*.sh` files.

### Test Output

- Successful tests print single line: `Running 01_local_complete_run.sh... PASS`
- Failed tests show full output for debugging

### Important Notes

- Tests require sudo, btrfs-progs and faketime
- Tests use `$SUDO` variable for all privileged operations
- Use `sudo_with_faketime()` not `faketime sudo` (faketime must wrap sudo, not vice versa)
- Snapshot names include time: `data.20250101T1200` (not `data.20250101`)
- TEST_DIR is consistent across all test scripts (always points to `tests/`)
- Config templates must be expanded before use (btrbk doesn't support variable expansion)

## Configuration

Configuration uses hierarchical sections with inheritance:
- Global options apply to all volumes/subvolumes/targets
- Options can be overridden at volume/subvolume/target level
- Parser doesn't care about indentation (only for readability)

Example structure:
```
volume <path>
  subvolume <name>
    target <path>
```

## Important Development Notes

### Main Script Structure

The `btrbk` script is self-contained Perl with no external library dependencies beyond Perl core modules. Key requirements:
- Perl with core modules (Getopt::Long, Time::Local, IPC::Open3, etc.)
- btrfs-progs >= 4.12
- Optional: mbuffer (for stream buffering), OpenSSH (for remote operations)

### Backend Support

btrbk supports different backends for local/remote btrfs operations:
- `btrfs-progs`: Standard btrfs tools (requires root)
- `btrfs-progs-sudo`: Use sudo for individual btrfs commands
- `btrfs-progs-btrbk`: Split btrfs commands with capabilities/setuid

### Security Considerations

- SSH keys are typically stored in `/etc/btrbk/ssh/`
- `ssh_filter_btrbk.sh` restricts remote commands to safe btrfs operations
- Never use `btrfs property set` to make snapshots read-write (breaks received_uuid)

## Documentation

Man pages are generated from AsciiDoc sources in `doc/`:
- `btrbk.1.asciidoc` → btrbk(1) man page
- `btrbk.conf.5.asciidoc` → btrbk.conf(5) man page
- `lsbtr.1.asciidoc` → lsbtr(1) man page
- `ssh_filter_btrbk.1.asciidoc` → ssh_filter_btrbk(1) man page

View documentation:
- README.md for examples and setup
- doc/FAQ.md for common questions
- doc/install.md for installation details

## Testing Workflows

Always test configuration changes:
```bash
btrbk -c /path/to/config -v -n run
```

Never skip `-n` (dry-run) when testing to avoid unintended snapshot/backup operations.

## Common Operations

```bash
# List snapshots
btrbk list snapshots

# List all subvolumes
btrbk ls /
btrbk ls -L /  # with relationships

# Create snapshot manually
btrbk snapshot <subvolume>

# Run backup
btrbk run

# Resume interrupted backups
btrbk resume

# Archive to offline storage
btrbk archive <target>
```

## Project Structure

```
btrbk                           # Main Perl script
lsbtr -> btrbk                  # Symlink
ssh_filter_btrbk.sh             # SSH filter script
btrbk.conf.example              # Example configuration
doc/                            # Man page sources (AsciiDoc)
contrib/
  bash/                         # Bash completion
  cron/                         # Cron job helpers (btrbk-mail, btrbk-verify)
  systemd/                      # Systemd unit templates
  crypt/                        # Encryption utilities
  migration/                    # Migration scripts
  tools/                        # Additional tools
```
