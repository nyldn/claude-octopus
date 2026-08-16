#!/usr/bin/env bash
# Tests that a completed /octo:setup opts the user into suggest-mode routing.
#
# Contract (oco-9yj): Octopus stays dormant on install (#898). Completing
# /octo:setup is an explicit act that implies consent to SUGGESTIONS only.
# Execution (invoke) is never enabled automatically, and an explicit user
# preference is never overwritten.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Setup opts into suggest-mode routing"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }
check() {
    local name="$1" expected="$2" actual="$3"
    test_case "$name"
    if [[ "$expected" == "$actual" ]]; then
        test_pass
    else
        test_fail "Expected: $expected | Actual: $actual"
    fi
}

LIB="$PROJECT_ROOT/scripts/lib/user-config.sh"
SESSION_HOOK="$PROJECT_ROOT/hooks/auto-router-inject.sh"
SETUP_CMD="$PROJECT_ROOT/commands/setup.md"

# Effective router mode the session hook resolves for a given HOME.
resolved_mode() {
    local home_dir="$1" out
    out=$(env -u OCTOPUS_AUTO_ROUTER_MODE -u OCTOPUS_AUTO_INVOKE \
        "HOME=$home_dir" "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" \
        "$SESSION_HOOK" 2>/dev/null) || true
    [[ -n "$out" ]] || { echo "off"; return 0; }
    printf '%s' "$out" | python3 -c '
import re,sys
raw=sys.stdin.read()
m=re.search(r"mode=\\?\"([a-z]+)\\?\"", raw)
print(m.group(1) if m else "off")
'
}

pref_key() {
    python3 -c '
import json,sys
try:
    with open(sys.argv[1]) as f: d=json.load(f)
except Exception: sys.exit(0)
v=d.get(sys.argv[2])
if v is not None: print(v)
' "$1/.claude-octopus/preferences.json" "$2" 2>/dev/null
}

write_default() {
    local home_dir="$1"
    ( HOME="$home_dir"; . "$LIB"; octo_pref_write_default "auto_router_mode" '"suggest"' ) \
        >/dev/null 2>&1 || true
}

# --- 1. helper exists -------------------------------------------------------
if grep -q 'octo_pref_write_default()' "$LIB" 2>/dev/null; then
    pass "user-config.sh exposes octo_pref_write_default"
else
    fail "user-config.sh exposes octo_pref_write_default" "helper missing"
fi

# --- 2. writes suggest on a fresh profile -----------------------------------
H1="$TEST_TMP_DIR/home-fresh"; mkdir -p "$H1/.claude-octopus"
write_default "$H1"
check "setup completion writes auto_router_mode=suggest" "suggest" "$(pref_key "$H1" auto_router_mode)"

# --- 3. never clobbers an explicit user preference --------------------------
H2="$TEST_TMP_DIR/home-optout"; mkdir -p "$H2/.claude-octopus"
printf '{"auto_router_mode":"off"}\n' > "$H2/.claude-octopus/preferences.json"
write_default "$H2"
check "an explicit opt-out is never overwritten" "off" "$(pref_key "$H2" auto_router_mode)"

# --- 4. preserves unrelated keys --------------------------------------------
H3="$TEST_TMP_DIR/home-merge"; mkdir -p "$H3/.claude-octopus"
printf '{"OCTO_PROACTIVE_SUGGESTIONS":"off"}\n' > "$H3/.claude-octopus/preferences.json"
write_default "$H3"
check "unrelated preference keys survive the write" "off" "$(pref_key "$H3" OCTO_PROACTIVE_SUGGESTIONS)"
check "new key is added alongside existing ones" "suggest" "$(pref_key "$H3" auto_router_mode)"

# --- 5. file is owner-only --------------------------------------------------
# GNU stat -f means "filesystem status" and prints a report to stdout, so trying
# the BSD format flag first pollutes the captured value on Linux. Probe GNU -c
# first, and accept a result only when it looks like a mode.
file_mode() {
    local f="$1" m
    m=$(stat -c '%a' "$f" 2>/dev/null) || m=""
    if [[ ! "$m" =~ ^[0-7]{3,4}$ ]]; then
        m=$(stat -f '%Lp' "$f" 2>/dev/null) || m=""
    fi
    [[ "$m" =~ ^[0-7]{3,4}$ ]] || m="?"
    printf '%s' "$m"
}
check "preferences.json is written owner-only" "600" "$(file_mode "$H1/.claude-octopus/preferences.json")"

# --- 6. a profile that never ran setup stays dormant ------------------------
H4="$TEST_TMP_DIR/home-never-setup"; mkdir -p "$H4/.claude-octopus"
check "no setup, no preferences file: router stays off" "off" "$(resolved_mode "$H4")"

# --- 7. the written preference actually reaches the hook --------------------
check "hook resolves suggest from the written preference" "suggest" "$(resolved_mode "$H1")"

# --- 8. an explicit opt-out still reaches the hook as off -------------------
check "hook honors the preserved opt-out" "off" "$(resolved_mode "$H2")"

# --- 9. a corrupt preferences file is left untouched ------------------------
H5="$TEST_TMP_DIR/home-corrupt"; mkdir -p "$H5/.claude-octopus"
CORRUPT='{"auto_router_mode": "off"'   # truncated: not valid JSON
printf '%s' "$CORRUPT" > "$H5/.claude-octopus/preferences.json"
write_default "$H5"
check "a corrupt preferences file is not replaced" \
    "$CORRUPT" "$(cat "$H5/.claude-octopus/preferences.json")"
check "a corrupt preferences file leaves routing dormant" "off" "$(resolved_mode "$H5")"

# --- 10. a held lock skips the write rather than clobbering -----------------
H6="$TEST_TMP_DIR/home-locked"; mkdir -p "$H6/.claude-octopus"
mkdir -p "$H6/.claude-octopus/preferences.json.lock"   # simulate a live holder
write_default "$H6"
check "a contended write is skipped, not forced" "" "$(pref_key "$H6" auto_router_mode)"
rmdir "$H6/.claude-octopus/preferences.json.lock" 2>/dev/null || true
write_default "$H6"
check "the write succeeds once the lock clears" "suggest" "$(pref_key "$H6" auto_router_mode)"

# --- 11. the lock is released after a normal write --------------------------
if [[ -d "$H1/.claude-octopus/preferences.json.lock" ]]; then
    fail "lock is released after a successful write" "lock directory left behind"
else
    pass "lock is released after a successful write"
fi

# --- 12. invoke is never written automatically ------------------------------
if grep -nE 'octo_pref_write_default[[:space:]]+"auto_router_mode"[[:space:]]+.?"invoke"' "$SETUP_CMD" >/dev/null 2>&1; then
    fail "setup never auto-enables invoke" "setup writes invoke"
else
    pass "setup never auto-enables invoke"
fi

# --- 13. setup persists the preference at its completion point --------------
if grep -q 'octo_pref_write_default "auto_router_mode"' "$SETUP_CMD" 2>/dev/null; then
    pass "setup.md persists auto_router_mode on completion"
else
    fail "setup.md persists auto_router_mode on completion" "setup.md does not call the helper"
fi

# --- 14. setup states the consent boundary to the user ----------------------
if grep -qi 'suggest' "$SETUP_CMD" 2>/dev/null; then
    pass "setup.md tells the user suggestions were enabled"
else
    fail "setup.md tells the user suggestions were enabled" "no user-facing mention of suggest mode"
fi

test_summary
