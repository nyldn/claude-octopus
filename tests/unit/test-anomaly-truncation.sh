#!/usr/bin/env bash
# Tests for anomaly-preserving output truncation in guard_output()
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "anomaly-preserving output truncation in guard_output()"

SECURE="$PROJECT_ROOT/scripts/lib/secure.sh"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── guard_output function exists in secure.sh ──────────────────────

if grep -q '^guard_output()' "$SECURE" 2>/dev/null; then
    pass "guard_output() defined in secure.sh"
else
    fail "guard_output() defined in secure.sh" "function not found"
fi

# ── anomaly pattern variable is defined ─────────────────────────────

if grep -A30 'guard_output()' "$SECURE" | grep -q 'anomaly_pattern' 2>/dev/null; then
    pass "anomaly_pattern variable defined in guard_output"
else
    fail "anomaly_pattern variable defined in guard_output" "missing anomaly_pattern"
fi

# ── anomaly patterns include required keywords ──────────────────────

for keyword in ERROR FATAL FAIL PANIC Traceback Exception CRITICAL 'error:' 'failed' 'Error:'; do
    if grep -A30 'guard_output()' "$SECURE" | grep 'anomaly_pattern' | grep -qF "$keyword" 2>/dev/null; then
        pass "anomaly pattern includes $keyword"
    else
        fail "anomaly pattern includes $keyword" "keyword not found in pattern"
    fi
done

# ── truncated output includes head section (first 20 lines) ────────

if grep -A50 'guard_output()' "$SECURE" | grep -q 'head -20' 2>/dev/null; then
    pass "truncated output includes head (first 20 lines)"
else
    fail "truncated output includes head (first 20 lines)" "head -20 not found"
fi

# ── truncated output includes tail section (last 10 lines) ─────────

if grep -A50 'guard_output()' "$SECURE" | grep -q 'tail -10' 2>/dev/null; then
    pass "truncated output includes tail (last 10 lines)"
else
    fail "truncated output includes tail (last 10 lines)" "tail -10 not found"
fi

# ── truncated output includes anomaly section markers ───────────────

if grep -A50 'guard_output()' "$SECURE" | grep -q 'lines omitted.*showing anomalies' 2>/dev/null; then
    pass "truncated output includes omitted/anomalies marker"
else
    fail "truncated output includes omitted/anomalies marker" "marker not found"
fi

if grep -A50 'guard_output()' "$SECURE" | grep -q 'end of anomalies' 2>/dev/null; then
    pass "truncated output includes end-of-anomalies marker"
else
    fail "truncated output includes end-of-anomalies marker" "marker not found"
fi

# ── small output passes through unchanged (under threshold) ─────────
# Source the secure.sh module to do a behavioral test

(
    # Subshell to avoid polluting this script's environment
    export OCTOPUS_TMP_DIR="${TMPDIR:-/tmp}"
    # Unset the guard to allow sourcing
    unset _OCTOPUS_SECURE_LOADED
    source "$SECURE"

    small_content="line 1
line 2
line 3"
    result=$(guard_output "$small_content" "test-small")
    if [[ "$result" == "$small_content" ]]; then
        echo "PASS_INNER: small output passes through unchanged"
    else
        echo "FAIL_INNER: small output passes through unchanged"
    fi
) > /tmp/octopus-test-anomaly-$$.out 2>/dev/null

if grep -q 'PASS_INNER' /tmp/octopus-test-anomaly-$$.out; then
    pass "small output passes through unchanged (under threshold)"
else
    fail "small output passes through unchanged (under threshold)" "content was modified"
fi
rm -f /tmp/octopus-test-anomaly-$$.out

# ── head+tail+anomaly structure in truncated output ─────────────────
# Generate content >49KB with an error line buried in the middle

(
    export OCTOPUS_TMP_DIR="${TMPDIR:-/tmp}"
    unset _OCTOPUS_SECURE_LOADED
    source "$SECURE"

    # Build oversized content (~60KB): 2000 lines of padding with one error
    big_content=""
    i=0
    while [[ $i -lt 500 ]]; do
        big_content="${big_content}padding line $i: this is normal output that fills space xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
        i=$((i + 1))
    done
    big_content="${big_content}ERROR: something went terribly wrong here
"
    while [[ $i -lt 1000 ]]; do
        big_content="${big_content}padding line $i: more normal output filling space yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
"
        i=$((i + 1))
    done

    result=$(guard_output "$big_content" "test-anomaly")

    # Check for head+anomaly+tail structure
    has_head=false
    has_anomaly_marker=false
    has_error_line=false
    has_end_marker=false
    has_tail=false
    has_file_ref=false

    echo "$result" | grep -q 'padding line 0' && has_head=true
    echo "$result" | grep -q 'lines omitted.*showing anomalies' && has_anomaly_marker=true
    echo "$result" | grep -q 'ERROR.*something went terribly wrong' && has_error_line=true
    echo "$result" | grep -q 'end of anomalies' && has_end_marker=true
    echo "$result" | grep -q 'padding line 999' && has_tail=true
    echo "$result" | grep -q 'Full output: @file:' && has_file_ref=true

    if $has_head && $has_anomaly_marker && $has_error_line && $has_end_marker && $has_tail && $has_file_ref; then
        echo "PASS_INNER: head+tail+anomaly structure correct"
    else
        echo "FAIL_INNER: head=$has_head anomaly_marker=$has_anomaly_marker error=$has_error_line end=$has_end_marker tail=$has_tail file_ref=$has_file_ref"
    fi
) > /tmp/octopus-test-anomaly-struct-$$.out 2>/dev/null

if grep -q 'PASS_INNER' /tmp/octopus-test-anomaly-struct-$$.out; then
    pass "head+tail+anomaly structure in truncated output"
else
    detail=$(cat /tmp/octopus-test-anomaly-struct-$$.out)
    fail "head+tail+anomaly structure in truncated output" "$detail"
fi
rm -f /tmp/octopus-test-anomaly-struct-$$.out

# ── no-anomaly fallback uses original head-truncation ───────────────

(
    export OCTOPUS_TMP_DIR="${TMPDIR:-/tmp}"
    unset _OCTOPUS_SECURE_LOADED
    source "$SECURE"

    # Build oversized content with NO error patterns
    big_content=""
    i=0
    while [[ $i -lt 1000 ]]; do
        big_content="${big_content}normal line $i: everything is fine here zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
"
        i=$((i + 1))
    done

    result=$(guard_output "$big_content" "test-noerror")

    if echo "$result" | grep -q 'Output exceeded.*bytes' && echo "$result" | grep -q '@file:'; then
        echo "PASS_INNER: fallback to head-truncation when no anomalies"
    else
        echo "FAIL_INNER: expected head-truncation fallback"
    fi
) > /tmp/octopus-test-anomaly-fallback-$$.out 2>/dev/null

if grep -q 'PASS_INNER' /tmp/octopus-test-anomaly-fallback-$$.out; then
    pass "no-anomaly fallback uses original head-truncation"
else
    fail "no-anomaly fallback uses original head-truncation" "fallback behavior incorrect"
fi
rm -f /tmp/octopus-test-anomaly-fallback-$$.out

# ── attribution check — no prohibited references ────────────────────

if grep -riE 'github\.com/[a-z]|@[a-z]+/' "$SECURE" 2>/dev/null | grep -ivE 'file:|REDACTED|CONNECTION-STRING' | grep -qiE 'github\.com|author'; then
    fail "no prohibited source references in secure.sh" "found external attribution"
else
    pass "no prohibited source references in secure.sh"
fi
test_summary
