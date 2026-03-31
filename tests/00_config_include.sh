#!/bin/bash
#
# Test: "include" directive in btrbk configuration files
#
# Exercises the following behaviour of "include NAME":
#   - Directory: every *.conf file inside the directory is included in
#     sorted order; non-.conf files are ignored.
#   - Glob wildcard: files matching a shell glob pattern are included in
#     sorted order.
#   - Non-matching glob: silently succeeds (no error, no volumes).
#   - Relative path: the pattern is resolved relative to the directory of
#     the including file, not the process working directory.
#   - Circular include: detected and reported as an error (exit non-zero).
#
# No btrfs filesystem is required; all verification is done via
# "btrbk config print", which only parses the configuration.
#

set -e
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_DIR

source "$TEST_DIR/support/common.sh"

log_info "=========================================="
log_info "Test: include directive"
log_info "=========================================="

# Absolute path to the shared config fixtures for this test.
FIXTURES="$TEST_DIR/config/include"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run "btrbk config print" and return its stdout; suppress stderr.
config_print() {
    "$BTRBK_BIN" -c "$1" config print 2>/dev/null
}

# Assert that OUTPUT contains the literal string STR.
assert_contains() {
    local output="$1" str="$2" msg="$3"
    if echo "$output" | grep -qF "$str"; then
        log_success "$msg"
    else
        log_error "$msg -- expected to find: $str"
        log_error "Actual output:"
        echo "$output" >&2
        exit 1
    fi
}

# Assert that OUTPUT does NOT contain the literal string STR.
assert_excludes() {
    local output="$1" str="$2" msg="$3"
    if echo "$output" | grep -qF "$str"; then
        log_error "$msg -- expected NOT to find: $str"
        log_error "Actual output:"
        echo "$output" >&2
        exit 1
    else
        log_success "$msg"
    fi
}

# Assert that STR_A appears on an earlier line than STR_B in OUTPUT.
assert_ordered() {
    local output="$1" str_a="$2" str_b="$3" msg="$4"
    local line_a line_b
    line_a=$(echo "$output" | grep -nF "$str_a"  | head -1 | cut -d: -f1)
    line_b=$(echo "$output" | grep -nF "$str_b"  | head -1 | cut -d: -f1)
    if [ -z "$line_a" ] || [ -z "$line_b" ]; then
        log_error "$msg -- one or both patterns not found in output"
        exit 1
    fi
    if [ "$line_a" -lt "$line_b" ]; then
        log_success "$msg"
    else
        log_error "$msg -- '$str_a' (line $line_a) should precede '$str_b' (line $line_b)"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Test 1: Directory include
#
# "include <dir>" is equivalent to "include <dir>/*.conf".
# Files are processed in sorted (lexicographic) order.
# Files not ending in ".conf" must be ignored.
# ---------------------------------------------------------------------------

log_info "--- Test 1: directory include ---"

# Build a temporary main config that references the fixture directory.
TMP_CONF=$(mktemp --suffix=.conf)
trap 'rm -f "$TMP_CONF"' EXIT

cat > "$TMP_CONF" <<EOF
include $FIXTURES/conf.d
EOF

OUT=$(config_print "$TMP_CONF")

assert_contains "$OUT" "volume /mnt/vol-a" \
    "T1: vol-a included from directory"
assert_contains "$OUT" "volume /mnt/vol-b" \
    "T1: vol-b included from directory"
assert_excludes "$OUT" "MUST_NOT_APPEAR" \
    "T1: non-.conf file in directory is ignored"
assert_ordered "$OUT" "volume /mnt/vol-a" "volume /mnt/vol-b" \
    "T1: files included in sorted (lexicographic) order"

# ---------------------------------------------------------------------------
# Test 2: Glob wildcard pattern
#
# "include <dir>/*.conf" produces the same result as the directory form.
# ---------------------------------------------------------------------------

log_info "--- Test 2: glob wildcard ---"

cat > "$TMP_CONF" <<EOF
include $FIXTURES/conf.d/*.conf
EOF

OUT=$(config_print "$TMP_CONF")

assert_contains "$OUT" "volume /mnt/vol-a" \
    "T2: vol-a matched by glob"
assert_contains "$OUT" "volume /mnt/vol-b" \
    "T2: vol-b matched by glob"
assert_excludes "$OUT" "MUST_NOT_APPEAR" \
    "T2: non-.conf file not matched by *.conf glob"
assert_ordered "$OUT" "volume /mnt/vol-a" "volume /mnt/vol-b" \
    "T2: glob results processed in sorted order"

# ---------------------------------------------------------------------------
# Test 3: Non-matching glob
#
# A pattern that matches no files must not produce an error.
# The resulting config is valid and contains no volumes.
# ---------------------------------------------------------------------------

log_info "--- Test 3: non-matching glob ---"

cat > "$TMP_CONF" <<EOF
include $FIXTURES/conf.d/nonexistent*.conf
EOF

if "$BTRBK_BIN" -c "$TMP_CONF" config print >/dev/null 2>&1; then
    log_success "T3: non-matching glob exits 0"
else
    log_error "T3: non-matching glob must exit 0, got exit code $?"
    exit 1
fi

OUT=$(config_print "$TMP_CONF")
assert_excludes "$OUT" "volume /mnt/" \
    "T3: no volumes emitted for non-matching glob"

# ---------------------------------------------------------------------------
# Test 4: Relative include path
#
# A pattern without a leading '/' is resolved relative to the directory
# of the file that contains the "include" statement, regardless of the
# current working directory when btrbk is invoked.
# ---------------------------------------------------------------------------

log_info "--- Test 4: relative include path ---"

# Write the config into the FIXTURES root so that "sub/extra.conf" is a
# valid relative reference to FIXTURES/sub/extra.conf.
REL_CONF="$FIXTURES/t4_relative.conf"
cat > "$REL_CONF" <<EOF
include sub/extra.conf
EOF
trap 'rm -f "$TMP_CONF" "$REL_CONF"' EXIT

# Invoke btrbk from a different directory to confirm CWD is irrelevant.
OUT=$(cd /tmp && config_print "$REL_CONF")

assert_contains "$OUT" "volume /mnt/vol-extra" \
    "T4: volume from relative include path found (CWD=/tmp)"

rm -f "$REL_CONF"

# ---------------------------------------------------------------------------
# Test 5: Circular include detection
#
# Two files that include each other must be detected as a circular
# dependency.  btrbk must exit non-zero and print an error mentioning
# "circular" (case-insensitive).
# ---------------------------------------------------------------------------

log_info "--- Test 5: circular include detection ---"

CIRC_DIR=$(mktemp -d)
trap 'rm -f "$TMP_CONF"; rm -rf "$CIRC_DIR"' EXIT

cat > "$CIRC_DIR/circ-a.conf" <<EOF
include $CIRC_DIR/circ-b.conf
EOF
cat > "$CIRC_DIR/circ-b.conf" <<EOF
include $CIRC_DIR/circ-a.conf
EOF

CIRC_OUT=$("$BTRBK_BIN" -c "$CIRC_DIR/circ-a.conf" config print 2>&1 || true)

if echo "$CIRC_OUT" | grep -qi "circular"; then
    log_success "T5: circular include detected and reported"
else
    log_error "T5: expected 'circular' in error output"
    log_error "Actual output: $CIRC_OUT"
    exit 1
fi

if "$BTRBK_BIN" -c "$CIRC_DIR/circ-a.conf" config print >/dev/null 2>&1; then
    log_error "T5: circular include must cause a non-zero exit"
    exit 1
else
    log_success "T5: circular include exits non-zero"
fi

rm -rf "$CIRC_DIR"

# ---------------------------------------------------------------------------

log_success "PASS $0"
exit 0
