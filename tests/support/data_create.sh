#!/bin/bash
#
# Create test data in a btrfs subvolume
#
# Usage: data_create.sh <subvolume_path> <state_id>
#

set -e
set -u

# Set TEST_DIR to tests/ directory
SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "$SUPPORT_DIR/.." && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

usage() {
    cat <<EOF
Usage: $0 <subvolume_path> <state_id>

Create test data in a btrfs subvolume with deterministic content.

Arguments:
    subvolume_path  Path to the subvolume where data will be created
    state_id        State identifier (e.g., "initial", "state1", "state2")

State IDs:
    initial  - Create basic directory structure with files
    state1   - Same as initial (for compatibility)
    state2   - Extended dataset with more files

Examples:
    $0 /mnt/test/data initial
    $0 /mnt/test/data state1
EOF
    exit 1
}

# Parse arguments
if [ $# -ne 2 ]; then
    usage
fi

SUBVOL="$1"
STATE="$2"

if [ ! -d "$SUBVOL" ]; then
    log_error "Subvolume directory does not exist: $SUBVOL"
    exit 1
fi

log_info "Creating test data in: $SUBVOL (state: $STATE)"

#
# Helper functions
#

create_file() {
    local filepath="$1"
    local content="$2"
    local mode="${3:-644}"

    echo "$content" > "$filepath"
    chmod "$mode" "$filepath"
}

create_binary_file() {
    local filepath="$1"
    local size="$2"  # in bytes

    dd if=/dev/urandom of="$filepath" bs=1 count="$size" status=none
    chmod 644 "$filepath"
}

create_dir() {
    local dirpath="$1"
    local mode="${2:-755}"

    mkdir -p "$dirpath"
    chmod "$mode" "$dirpath"
}

#
# State: initial / state1
#

create_initial_state() {
    log_info "Creating initial state"

    # Create directory structure
    create_dir "$SUBVOL/documents"
    create_dir "$SUBVOL/documents/work"
    create_dir "$SUBVOL/documents/personal"
    create_dir "$SUBVOL/pictures"
    create_dir "$SUBVOL/music"
    create_dir "$SUBVOL/videos"
    create_dir "$SUBVOL/projects"
    create_dir "$SUBVOL/projects/code"
    create_dir "$SUBVOL/projects/design"

    # Create text files
    create_file "$SUBVOL/README.txt" \
        "This is a test dataset for btrbk testing.
Created on 2025-01-01 for automated backup testing.
This file contains important information." \
        644

    create_file "$SUBVOL/documents/work/project1.txt" \
        "Project 1 Documentation
Status: In Progress
Last Updated: 2025-01-01

This is the main project file." \
        644

    create_file "$SUBVOL/documents/work/project2.txt" \
        "Project 2 Documentation
Status: Planning
Last Updated: 2025-01-01" \
        644

    create_file "$SUBVOL/documents/personal/notes.txt" \
        "Personal Notes
- Buy groceries
- Call dentist
- Finish backup testing" \
        644

    create_file "$SUBVOL/documents/personal/todo.txt" \
        "TODO List:
1. Test btrbk backups
2. Verify incremental backups work
3. Test restore procedures" \
        644

    # Create files in other directories
    create_file "$SUBVOL/pictures/photo1.txt" \
        "Simulated photo file 1 (2025-01-01)" \
        644

    create_file "$SUBVOL/pictures/photo2.txt" \
        "Simulated photo file 2 (2025-01-01)" \
        644

    create_file "$SUBVOL/music/song1.txt" \
        "Simulated music file 1" \
        644

    create_file "$SUBVOL/projects/code/main.sh" \
        "#!/bin/bash
# Main script
echo 'Hello, World!'
exit 0" \
        755

    create_file "$SUBVOL/projects/code/utils.sh" \
        "#!/bin/bash
# Utility functions
function print_message() {
    echo \"\$1\"
}" \
        644

    create_file "$SUBVOL/projects/design/layout.txt" \
        "Design Layout
Header: Logo and Navigation
Body: Main Content
Footer: Copyright" \
        644

    # Create some binary files
    create_binary_file "$SUBVOL/pictures/image.bin" 1024
    create_binary_file "$SUBVOL/music/audio.bin" 2048
    create_binary_file "$SUBVOL/videos/video.bin" 4096

    # Create a symlink
    ln -sf "../pictures/photo1.txt" "$SUBVOL/documents/photo_link.txt"

    # Create an empty directory
    create_dir "$SUBVOL/empty_dir"

    log_success "Initial state created successfully"
}

#
# State: state2 (extended dataset)
#

create_state2() {
    log_info "Creating state2 (extended dataset)"

    # First create initial state
    create_initial_state

    # Add additional files
    create_dir "$SUBVOL/backup"
    create_dir "$SUBVOL/temp"
    create_dir "$SUBVOL/archive"

    create_file "$SUBVOL/backup/backup_log.txt" \
        "Backup Log
2025-01-01: Initial backup created
2025-01-02: Incremental backup" \
        644

    create_file "$SUBVOL/temp/temp1.txt" \
        "Temporary file 1" \
        644

    create_file "$SUBVOL/temp/temp2.txt" \
        "Temporary file 2" \
        644

    create_file "$SUBVOL/archive/old_data.txt" \
        "Old archived data from previous years" \
        644

    # Add more files to existing directories
    create_file "$SUBVOL/documents/work/project3.txt" \
        "Project 3 Documentation
Status: New
Last Updated: 2025-01-02" \
        644

    create_file "$SUBVOL/pictures/photo3.txt" \
        "Simulated photo file 3 (2025-01-02)" \
        644

    create_binary_file "$SUBVOL/backup/backup.bin" 8192

    log_success "State2 created successfully"
}

#
# Main logic
#

case "$STATE" in
    initial|state1)
        create_initial_state
        ;;
    state2)
        create_state2
        ;;
    *)
        log_error "Unknown state: $STATE"
        log_error "Valid states: initial, state1, state2"
        exit 1
        ;;
esac

# Verify data was created
FILE_COUNT=$(find "$SUBVOL" -type f | wc -l)
DIR_COUNT=$(find "$SUBVOL" -type d | wc -l)

log_info "Created $FILE_COUNT files and $DIR_COUNT directories"
log_success "Test data creation complete"
