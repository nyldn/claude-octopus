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

test_retired_gemini_timeout_override_absent() {
    test_case "spawn.sh uses the supervised workflow timeout without a Gemini-only override"
    if ! grep -q 'OCTOPUS_GEMINI_TIMEOUT' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q 'octopus_effective_agent_timeout "${TIMEOUT:-0}"' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q '"\$enhanced_prompt" "\$_attempt_timeout" "\$temp_input"' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q 'run_with_timeout "\$timeout_secs"' "$PROJECT_ROOT/scripts/lib/heartbeat.sh"; then
        test_pass
    else test_fail "spawn.sh still exposes retired Gemini timeout behavior"; fi
}


# ── agy/gemini terminal signatures + marker TTL (oco-004 follow-up) ──────────

test_pattern_matches_agy_and_gemini_terminal_errors() {
    test_case "quota pattern matches agy 'Individual quota reached' and gemini IneligibleTierError"
    local errf="$FIXTURE/agy-gemini.err" outf="$FIXTURE/agy-gemini.out"
    : > "$outf"
    printf 'Error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 156h9m1s.\n' > "$errf"
    if ! quota_watcher_has_match "$errf" "$outf"; then
        test_fail "agy 'Individual quota reached' not matched by OCTOPUS_QUOTA_PATTERN"
        return
    fi
    printf 'An unexpected critical error occurred:IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals.\n' > "$errf"
    if ! quota_watcher_has_match "$errf" "$outf"; then
        test_fail "gemini IneligibleTierError not matched by OCTOPUS_QUOTA_PATTERN"
        return
    fi
    test_pass
}

test_quota_dead_mark_expires() {
    test_case "quota-dead mark expires after TTL so a recovered provider is not retired forever"
    local f
    f="$(octo_quota_dead_file)"
    mkdir -p "$(dirname "$f")"
    : > "$f"
    octo_quota_mark_dead "ttl-probe"
    if ! octo_quota_is_dead "ttl-probe"; then
        test_fail "fresh mark should read as dead"
        return
    fi
    # Age the marker well past the default TTL.
    touch -t 202001010000 "$f"
    if octo_quota_is_dead "ttl-probe"; then
        test_fail "stale mark still reads as dead — provider would never recover"
        return
    fi
    # TTL=0 preserves the previous permanent behaviour for operators who want it.
    if ! OCTOPUS_QUOTA_DEAD_TTL=0 octo_quota_is_dead "ttl-probe"; then
        test_fail "OCTOPUS_QUOTA_DEAD_TTL=0 should disable expiry"
        return
    fi
    test_pass
}

test_check_providers_applies_dead_marker_to_every_provider() {
    test_case "shared readiness routes every available provider through the quota-dead downgrade"
    # The downgrade used to be opt-in per renderer. It now belongs to the
    # registry-backed readiness evaluator consumed by check-providers.sh.
    local checker="$PROJECT_ROOT/scripts/helpers/check-providers.sh"
    local readiness="$PROJECT_ROOT/scripts/lib/preflight.sh"
    if grep -Fq 'octo_provider_readiness_legacy' "$checker" &&
       grep -Fq 'octo_quota_is_dead "$provider"' "$readiness" &&
       ! grep -Eq '^(_octo_provider_state|provider_status)\(\)' "$checker"; then
        test_pass
    else
        test_fail "quota-dead policy is not centralized in shared readiness"
    fi
}

# A dead-mark written by a shim running under `env -i` must be visible to the
# reader. agy-exec.sh marks dead from inside the isolated
# environment; if WORKSPACE_DIR is not forwarded they write to the
# $HOME/.claude-octopus fallback while check-providers.sh reads
# $CLAUDE_PLUGIN_DATA, so the provider keeps advertising `available` and is
# reseated every session.
test_provider_env_forwards_workspace_dir() {
    test_case "build_provider_env forwards WORKSPACE_DIR into every isolated env"
    local out missing=""
    for p in agy codex; do
        out="$(WORKSPACE_DIR=/tmp/octo-wsdir-probe bash -c '
            cd "$1" || exit 1
            source scripts/lib/validation.sh 2>/dev/null
            source scripts/lib/provider-routing.sh
            build_provider_env "$2"
            printf "%s\n" "${PROVIDER_ENV_ARRAY[@]}"
        ' _ "$PROJECT_ROOT" "$p" 2>/dev/null)"
        printf '%s\n' "$out" | grep -q '^WORKSPACE_DIR=/tmp/octo-wsdir-probe$' || missing="$missing $p"
    done
    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "WORKSPACE_DIR not forwarded for:$missing"
    fi
}

test_dead_mark_survives_isolated_env() {
    test_case "a dead-mark written under the isolated env is visible to the reader"
    local th pd res
    th="$(mktemp -d)"; pd="$(mktemp -d)"
    res="$(HOME="$th" WORKSPACE_DIR="$pd" bash -c '
        cd "$1" || exit 1
        source scripts/lib/validation.sh 2>/dev/null
        source scripts/lib/provider-routing.sh
        build_provider_env agy
        "${PROVIDER_ENV_ARRAY[@]}" bash -c "cd \"$1\"; source scripts/lib/quota-watcher.sh; octo_quota_mark_dead agy 0" _ "$1"
        source scripts/lib/quota-watcher.sh
        octo_quota_is_dead agy && echo DEAD || echo ALIVE
    ' _ "$PROJECT_ROOT" 2>/dev/null)"
    rm -rf "$th" "$pd"
    if [[ "$res" == "DEAD" ]]; then
        test_pass
    else
        test_fail "mark written under env -i was invisible to the reader (got '$res')"
    fi
}

test_quota_dead_cache_roundtrip
test_quota_dead_cache_dedup
test_provider_env_forwards_workspace_dir
test_dead_mark_survives_isolated_env
test_pattern_matches_terminal_errors
test_watcher_marks_dead_on_match
test_is_agent_available_skips_dead
test_retired_gemini_timeout_override_absent
test_pattern_matches_agy_and_gemini_terminal_errors
test_quota_dead_mark_expires
test_check_providers_applies_dead_marker_to_every_provider

test_summary
