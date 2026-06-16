#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Quota fast-fail + quota-dead cache (oco-2kw/48z/cbb)"

# Isolate the session cache to a tmp workspace.
FIXTURE="$(mktemp -d)"
export WORKSPACE_DIR="$FIXTURE"
trap 'rm -rf "$FIXTURE"' EXIT

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
# stub log so the watcher subshell doesn't error when log is undefined
log() { :; }

test_quota_dead_cache_roundtrip() {
    test_case "octo_quota_mark_dead / octo_quota_is_dead roundtrip"
    if octo_quota_is_dead perplexity; then test_fail "dead before mark"; return; fi
    octo_quota_mark_dead perplexity
    if octo_quota_is_dead perplexity && ! octo_quota_is_dead gemini; then test_pass
    else test_fail "mark/is_dead mismatch"; fi
}

test_quota_dead_cache_dedup() {
    test_case "marking the same provider twice does not duplicate"
    octo_quota_mark_dead codex; octo_quota_mark_dead codex
    local n
    n=$(grep -cxF codex "$(octo_quota_dead_file)" 2>/dev/null | tr -d ' ')
    [[ "$n" == "1" ]] && test_pass || test_fail "expected 1 codex entry, got $n"
}

test_pattern_matches_terminal_errors() {
    test_case "quota pattern matches 401 / insufficient_quota / exhausted"
    local tmp_ok="$FIXTURE/m.txt" tmp_no="$FIXTURE/n.txt"
    printf 'You exceeded your current quota insufficient_quota code 401\n' > "$tmp_ok"
    printf 'all good, normal output\n' > "$tmp_no"
    if quota_watcher_has_match "$tmp_ok" /dev/null && ! quota_watcher_has_match "$tmp_no" /dev/null; then
        test_pass
    else test_fail "pattern match incorrect"; fi
}

test_watcher_marks_dead_on_match() {
    test_case "watcher marks a provider quota-dead when it sees a terminal error"
    local errf="$FIXTURE/w-err.txt" outf="$FIXTURE/w-out.txt"
    : > "$errf"; : > "$outf"
    # Short-lived target we manage ourselves (no orphaned sleep, no self-kill race).
    # Quota line is written AFTER the watcher starts (it truncates temp files on entry).
    _noop_kill() { kill "$1" 2>/dev/null || true; }
    ( sleep 1; echo "exhausted your capacity (insufficient_quota)" >> "$errf"; sleep 4 ) &
    local target=$!
    local wpid
    wpid=$(start_quota_watcher "$target" "$errf" "$outf" _noop_kill "test" "fakeprov")
    # Poll up to ~6s for the watcher to detect + mark.
    local i marked=0
    for i in $(seq 1 12); do
        if octo_quota_is_dead fakeprov; then marked=1; break; fi
        sleep 0.5
    done
    kill "$target" 2>/dev/null || true
    wait "$target" 2>/dev/null || true
    stop_quota_watcher "$wpid"
    [[ "$marked" == "1" ]] && test_pass || test_fail "watcher did not mark fakeprov dead on quota match"
}

test_is_agent_available_skips_dead() {
    test_case "is_agent_available returns false for a quota-dead provider"
    octo_quota_mark_dead perplexity
    # Minimal harness: define the guard exactly as orchestrate.sh uses it.
    _is_avail() {
        if declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead "${1%%-*}"; then
            return 1
        fi
        return 0
    }
    if ! _is_avail perplexity && _is_avail copilot; then test_pass
    else test_fail "quota-dead skip gate wrong"; fi
}

test_gemini_timeout_override_present() {
    test_case "spawn.sh applies OCTOPUS_GEMINI_TIMEOUT to gemini dispatch (oco-2kw)"
    if grep -q 'OCTOPUS_GEMINI_TIMEOUT' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q 'run_with_timeout "\$_eff_timeout"' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
        test_pass
    else test_fail "spawn.sh missing per-provider gemini timeout wiring"; fi
}

test_quota_dead_cache_roundtrip
test_quota_dead_cache_dedup
test_pattern_matches_terminal_errors
test_watcher_marks_dead_on_match
test_is_agent_available_skips_dead
test_gemini_timeout_override_present

test_summary
