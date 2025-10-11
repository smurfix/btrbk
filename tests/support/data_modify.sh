#!/bin/bash
#
# Modify existing test data in a btrfs subvolume
#
# Usage: data_modify.sh <subvolume_path> <modification_set>
#

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<EOF
Usage: $0 <subvolume_path> <modification_set>

Modify existing test data in a btrfs subvolume.

Arguments:
    subvolume_path    Path to the subvolume to modify
    modification_set  Type of modifications to apply

Modification Sets:
    set1    - Basic modifications: add, delete, and modify files
    set2    - Extended modifications: more complex changes
    minor   - Small changes only
    major   - Large-scale changes

Examples:
    $0 /mnt/test/data set1
    $0 /mnt/test/data set2
EOF
    exit 1
}

# Parse arguments
if [ $# -ne 2 ]; then
    usage
fi

SUBVOL="$1"
MOD_SET="$2"

if [ ! -d "$SUBVOL" ]; then
    log_error "Subvolume directory does not exist: $SUBVOL"
    exit 1
fi

log_info "Modifying test data in: $SUBVOL (modification set: $MOD_SET)"

#
# Helper functions
#

modify_file() {
    local filepath="$1"
    local new_content="$2"

    if [ ! -e "$filepath" ]; then
        log_warning "File does not exist, cannot modify: $filepath"
        return 1
    fi

    log_info "Modifying file: $filepath"
    sudo bash -c "echo '$new_content' >> '$filepath'"
}

append_to_file() {
    local filepath="$1"
    local content="$2"

    if [ ! -e "$filepath" ]; then
        log_warning "File does not exist, cannot append: $filepath"
        return 1
    fi

    log_info "Appending to file: $filepath"
    sudo bash -c "echo '$content' >> '$filepath'"
}

create_new_file() {
    local filepath="$1"
    local content="$2"
    local mode="${3:-644}"

    log_info "Creating new file: $filepath"
    sudo bash -c "echo '$content' > '$filepath'"
    sudo chmod "$mode" "$filepath"
}

delete_file() {
    local filepath="$1"

    if [ ! -e "$filepath" ]; then
        log_warning "File does not exist, cannot delete: $filepath"
        return 0
    fi

    log_info "Deleting file: $filepath"
    sudo rm -f "$filepath"
}

delete_dir() {
    local dirpath="$1"

    if [ ! -d "$dirpath" ]; then
        log_warning "Directory does not exist, cannot delete: $dirpath"
        return 0
    fi

    log_info "Deleting directory: $dirpath"
    sudo rm -rf "$dirpath"
}

#
# Modification Set 1: Basic changes
#

apply_mod_set1() {
    log_info "Applying modification set 1"

    # Modify existing files
    append_to_file "$SUBVOL/README.txt" \
        "
Updated on 2025-01-02 after initial backup.
Added new information about incremental backups."

    append_to_file "$SUBVOL/documents/work/project1.txt" \
        "
Update: 2025-01-02
Progress: 50% complete
Next steps: Continue testing"

    modify_file "$SUBVOL/documents/personal/notes.txt" \
        "
- Added new task: Test incremental backups
- Completed: Buy groceries"

    # Create new files
    create_new_file "$SUBVOL/documents/work/meeting_notes.txt" \
        "Meeting Notes - 2025-01-02
Attendees: Team
Topics: Backup strategy, incremental backups
Action items: Test and verify" \
        644

    create_new_file "$SUBVOL/documents/personal/journal.txt" \
        "Journal Entry - 2025-01-02
Today I tested btrbk incremental backups.
Everything is working as expected." \
        644

    create_new_file "$SUBVOL/projects/code/config.sh" \
        "#!/bin/bash
# Configuration file
export APP_NAME='btrbk-test'
export VERSION='1.0'" \
        644

    create_new_file "$SUBVOL/pictures/photo3.txt" \
        "Simulated photo file 3 (2025-01-02)" \
        644

    # Delete some files
    delete_file "$SUBVOL/documents/personal/todo.txt"
    delete_file "$SUBVOL/music/song1.txt"
    delete_file "$SUBVOL/pictures/photo2.txt"

    # Delete the empty directory
    delete_dir "$SUBVOL/empty_dir"

    # Modify binary file
    if [ -f "$SUBVOL/pictures/image.bin" ]; then
        log_info "Modifying binary file"
        sudo dd if=/dev/urandom of="$SUBVOL/pictures/image.bin" bs=1 count=512 seek=512 conv=notrunc status=none
    fi

    log_success "Modification set 1 applied"
}

#
# Modification Set 2: Extended changes
#

apply_mod_set2() {
    log_info "Applying modification set 2"

    # First apply set1
    apply_mod_set1

    # Additional modifications
    create_new_file "$SUBVOL/documents/work/project4.txt" \
        "Project 4 Documentation
Status: New
Created: 2025-01-03
Priority: High" \
        644

    create_new_file "$SUBVOL/documents/work/project5.txt" \
        "Project 5 Documentation
Status: New
Created: 2025-01-03
Priority: Low" \
        644

    append_to_file "$SUBVOL/projects/code/main.sh" \
        "
# Updated 2025-01-03
# Added new functionality
source ./config.sh
echo \"Version: \$VERSION\""

    # Create new directory with files
    sudo mkdir -p "$SUBVOL/logs"
    create_new_file "$SUBVOL/logs/app.log" \
        "Application Log
2025-01-03 10:00:00 - Application started
2025-01-03 10:01:00 - Processing data
2025-01-03 10:02:00 - Backup initiated" \
        644

    create_new_file "$SUBVOL/logs/error.log" \
        "Error Log
No errors recorded" \
        644

    # Delete additional files
    delete_file "$SUBVOL/projects/design/layout.txt"
    delete_file "$SUBVOL/videos/video.bin"

    # Rename a file (simulate by copy and delete)
    if [ -f "$SUBVOL/music/audio.bin" ]; then
        log_info "Renaming file: audio.bin -> sound.bin"
        sudo cp "$SUBVOL/music/audio.bin" "$SUBVOL/music/sound.bin"
        sudo rm "$SUBVOL/music/audio.bin"
    fi

    log_success "Modification set 2 applied"
}

#
# Modification Set: Minor changes
#

apply_mod_minor() {
    log_info "Applying minor modifications"

    # Only modify a couple of files
    append_to_file "$SUBVOL/README.txt" \
        "
Minor update on 2025-01-02."

    create_new_file "$SUBVOL/documents/quick_note.txt" \
        "Quick note added" \
        644

    log_success "Minor modifications applied"
}

#
# Modification Set: Major changes
#

apply_mod_major() {
    log_info "Applying major modifications"

    # Apply set2 first
    apply_mod_set2

    # Create large directory structure
    for i in {1..5}; do
        sudo mkdir -p "$SUBVOL/data_$i"
        for j in {1..3}; do
            create_new_file "$SUBVOL/data_$i/file_$j.txt" \
                "Data file $j in directory $i
Created during major modification test" \
                644
        done
    done

    # Delete entire directory
    delete_dir "$SUBVOL/projects/design"

    # Create new large binary file
    log_info "Creating large binary file"
    sudo dd if=/dev/urandom of="$SUBVOL/large_file.bin" bs=1024 count=100 status=none

    log_success "Major modifications applied"
}

#
# Main logic
#

case "$MOD_SET" in
    set1)
        apply_mod_set1
        ;;
    set2)
        apply_mod_set2
        ;;
    minor)
        apply_mod_minor
        ;;
    major)
        apply_mod_major
        ;;
    *)
        log_error "Unknown modification set: $MOD_SET"
        log_error "Valid sets: set1, set2, minor, major"
        exit 1
        ;;
esac

# Report changes
FILE_COUNT=$(sudo find "$SUBVOL" -type f | wc -l)
DIR_COUNT=$(sudo find "$SUBVOL" -type d | wc -l)

log_info "After modifications: $FILE_COUNT files and $DIR_COUNT directories"
log_success "Data modification complete"
