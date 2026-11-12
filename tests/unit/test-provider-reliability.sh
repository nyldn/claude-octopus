#!/usr/bin/env bash
# Tests for Provider Reliability Layer (v9.8.0)
# Validates: error classification, circuit breaker, backoff, provider filtering
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider Reliability Layer (v9.8.0)"

ROUTER="$PROJECT_ROOT/scripts/provider-router.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

source "$ROUTER"
_PROVIDER_STATE_DIR="$TEST_TMP_DIR/provider-state"
OCTO_CB_FAILURE_THRESHOLD=1
log() { :; }

mkdir -p "$_PROVIDER_STATE_DIR"
test_case "failure classification does not hold the shared breaker lock"
if (
    classify_provider_error() {
        [[ ! -d "$_PROVIDER_STATE_DIR/codex.breaker.lock" ]] || return 1
        printf 'transient\n'
    }
    [[ "$(record_provider_failure codex 75 'temporary limit')" == transient ]]
); then test_pass; else test_fail "classification held the breaker transaction lock"; fi
rm -f "$_PROVIDER_STATE_DIR/codex.failures" "$_PROVIDER_STATE_DIR/codex.cooldown"
for timestamp in '' invalid '1+1' 999999999999999999999999; do
    printf '%s\n' "$timestamp" > "$_PROVIDER_STATE_DIR/codex.cooldown"
    if (is_provider_available codex) 2>/dev/null; then
        pass "invalid cooldown '$timestamp' uses the available-provider fallback"
    else
        fail "invalid cooldown '$timestamp' uses the available-provider fallback"
    fi
done
for timestamp in "$(( $(date +%s) + 60 ))" 999999999999999999; do
    test_case "future cooldown '$timestamp' is half-open in doctor status"
    printf '%s\n' "$timestamp" > "$_PROVIDER_STATE_DIR/codex.cooldown"
    if [[ "$(get_circuit_breaker_status)" == *'codex: half-open (cooldown expired, probing)'* ]]; then
        test_pass
    else
        test_fail "doctor reported an unbounded future cooldown"
    fi
    for lock_status in 0 75; do
        test_case "future cooldown '$timestamp' permits a probe with lock status $lock_status"
        if (
            _octo_event_lock() { return "$lock_status"; }
            _octo_event_unlock() { :; }
            printf '%s\n' "$timestamp" > "$_PROVIDER_STATE_DIR/codex.cooldown"
            is_provider_available codex &&
                { [[ "$lock_status" -eq 0 && ! -e "$_PROVIDER_STATE_DIR/codex.cooldown" ]] ||
                  [[ "$lock_status" -eq 75 && "$(cat "$_PROVIDER_STATE_DIR/codex.cooldown")" == "$timestamp" ]]; }
        ); then test_pass; else test_fail "future cooldown blocked a probe or mutated unowned state"; fi
    done
done
printf '08\n' > "$_PROVIDER_STATE_DIR/codex.cooldown"
if (is_provider_available codex) 2>/dev/null; then
    pass "numeric cooldown timestamps use decimal arithmetic"
else
    fail "numeric cooldown timestamps use decimal arithmetic"
fi

printf '1\n' > "$_PROVIDER_STATE_DIR/codex.cooldown"
mv() {
    if [[ "$2" == "$_PROVIDER_STATE_DIR/codex.cooldown" ]]; then
        [[ "$(cat "$2")" == 1 && "$(cat "$1")" =~ ^[0-9]+$ ]] || return 1
        touch "$TEST_TMP_DIR/atomic-cooldown"
    fi
    command mv "$@"
}
record_provider_failure codex 75 'temporary usage limit' >/dev/null
unset -f mv
if [[ -e "$TEST_TMP_DIR/atomic-cooldown" ]]; then
    pass "cooldown publication replaces a complete timestamp atomically"
else
    fail "cooldown publication replaces a complete timestamp atomically"
fi
if ! is_provider_available codex && [[ -s "$_PROVIDER_STATE_DIR/codex.cooldown" ]]; then
    pass "persisted cooldown blocks another request before its deadline"
else
    fail "persisted cooldown blocks another request before its deadline"
fi

printf '%s\n' 1 > "$_PROVIDER_STATE_DIR/codex.cooldown"
if is_provider_available codex && [[ ! -e "$_PROVIDER_STATE_DIR/codex.cooldown" ]]; then
    pass "expired cooldown permits a half-open request"
else
    fail "expired cooldown permits a half-open request"
fi

# ── File existence and syntax ─────────────────────────────────────────────────

for lock_status in 1 75; do
    test_case "lock failure $lock_status permits an expired probe without changing shared state"
    if (
        _octo_event_lock() { return "$lock_status"; }
        _octo_event_unlock() { touch "$TEST_TMP_DIR/unowned-unlock"; }
        printf '1\n' > "$_PROVIDER_STATE_DIR/codex.cooldown"
        [[ "$(filter_available_providers codex)" == codex ]] &&
            [[ "$(cat "$_PROVIDER_STATE_DIR/codex.cooldown")" == 1 ]] &&
            [[ ! -e "$TEST_TMP_DIR/unowned-unlock" ]]
    ); then test_pass; else test_fail "lock failure was treated as an open circuit"; fi

    test_case "lock failure $lock_status preserves an active cooldown"
    if (
        _octo_event_lock() { return "$lock_status"; }
        date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown"
        [[ -z "$(filter_available_providers codex)" ]] &&
            [[ -s "$_PROVIDER_STATE_DIR/codex.cooldown" ]]
    ); then test_pass; else test_fail "lock fallback bypassed an active cooldown"; fi
done

test_case "an active cooldown is reported without taking the breaker lock"
if (
    _octo_event_lock() { touch "$TEST_TMP_DIR/active-cooldown-lock"; return 1; }
    date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown"
    ! is_provider_available codex &&
        [[ ! -e "$TEST_TMP_DIR/active-cooldown-lock" ]]
); then test_pass; else test_fail "an active cooldown contended for the breaker lock"; fi

test_case "a cooldown replaced while acquiring the lock is checked again"
if (
    eval "$(declare -f _octo_event_lock | sed '1s/_octo_event_lock/real_event_lock/')"
    _octo_event_lock() {
        real_event_lock "$@" || return $?
        date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown"
    }
    printf '1\n' > "$_PROVIDER_STATE_DIR/codex.cooldown"
    ! is_provider_available codex && [[ -s "$_PROVIDER_STATE_DIR/codex.cooldown" ]]
); then test_pass; else test_fail "a renewed cooldown was removed"; fi

test_case "failure-log trimming does not follow a predictable temporary symlink"
if (
    _PROVIDER_STATE_DIR="$TEST_TMP_DIR/symlink-state"
    mkdir -p "$_PROVIDER_STATE_DIR"
    printf 'preserve me\n' > "$TEST_TMP_DIR/symlink-target"
    ln -s "$TEST_TMP_DIR/symlink-target" "$_PROVIDER_STATE_DIR/codex.failures.tmp"
    record_provider_failure codex 75 'temporary limit' >/dev/null &&
        [[ "$(cat "$TEST_TMP_DIR/symlink-target")" == 'preserve me' ]] &&
        [[ "$(wc -l < "$_PROVIDER_STATE_DIR/codex.failures")" -eq 1 ]]
); then test_pass; else test_fail "failure-log trim overwrote a symlink target"; fi

for failed_command in tail mv; do
    test_case "failure-log $failed_command failure cleans up its temporary file and lock"
    if (
        _PROVIDER_STATE_DIR="$TEST_TMP_DIR/failed-$failed_command-state"
        mkdir -p "$_PROVIDER_STATE_DIR"
        if [[ "$failed_command" == tail ]]; then tail() { return 1; }
        else mv() { return 1; }; fi
        if record_provider_failure codex 75 'temporary limit' >/dev/null; then exit 1; fi
        shopt -s nullglob
        leftovers=("$_PROVIDER_STATE_DIR"/codex.failures.*)
        [[ "${#leftovers[@]}" -eq 0 && ! -d "$_PROVIDER_STATE_DIR/codex.breaker.lock" ]]
    ); then test_pass; else test_fail "failure left temporary state or returned success"; fi
done

test_case "concurrent failures serialize the complete circuit-breaker transaction"
if (
    _PROVIDER_STATE_DIR="$TEST_TMP_DIR/concurrent-state"
    OCTO_CB_FAILURE_THRESHOLD=2
    mkdir -p "$_PROVIDER_STATE_DIR"
    tail() {
        command tail "$@"
        touch "$TEST_TMP_DIR/failure-snapshot"
        for attempt in {1..250}; do
            [[ ! -e "$TEST_TMP_DIR/release-snapshot" ]] || return 0
            sleep 0.02
        done
        return 1
    }
    record_provider_failure codex 75 'temporary limit' > "$TEST_TMP_DIR/first-failure" &
    first=$!
    for attempt in {1..250}; do
        [[ ! -e "$TEST_TMP_DIR/failure-snapshot" ]] || break
        sleep 0.02
    done
    (
        unset -f tail
        sleep() {
            touch "$TEST_TMP_DIR/second-failure-contended"
            command sleep "$@"
        }
        record_provider_failure codex 75 'temporary limit'
    ) > "$TEST_TMP_DIR/second-failure" &
    second=$!
    for attempt in {1..250}; do
        [[ ! -e "$TEST_TMP_DIR/second-failure-contended" ]] || break
        sleep 0.02
    done
    before=$(wc -l < "$_PROVIDER_STATE_DIR/codex.failures")
    touch "$TEST_TMP_DIR/release-snapshot"
    first_rc=0 second_rc=0
    wait "$first" || first_rc=$?
    wait "$second" || second_rc=$?
    if [[ -e "$TEST_TMP_DIR/second-failure-contended" &&
          "$before" -eq 1 && "$first_rc" -eq 0 && "$second_rc" -eq 0 ]] &&
       [[ "$(wc -l < "$_PROVIDER_STATE_DIR/codex.failures")" -eq 2 ]] &&
       ! is_provider_available codex; then
        exit 0
    else
        exit 1
    fi
); then
    test_pass
else
    test_fail "concurrent writers lost history or skipped the cooldown"
fi

test_case "success without breaker state does not contend for the lock"
if (
    _PROVIDER_STATE_DIR="$TEST_TMP_DIR/success-fast-path-state"
    _octo_event_lock() { touch "$TEST_TMP_DIR/success-fast-path-locked"; return 75; }
    record_provider_success codex &&
        [[ ! -e "$TEST_TMP_DIR/success-fast-path-locked" ]]
); then test_pass; else test_fail "a success with nothing to clear waited for the breaker lock"; fi

for state in failures cooldown; do
    test_case "success with a $state file clears it only under the breaker lock"
    if (
        _PROVIDER_STATE_DIR="$TEST_TMP_DIR/success-$state-state"
        mkdir -p "$_PROVIDER_STATE_DIR"
        printf '1\n' > "$_PROVIDER_STATE_DIR/codex.$state"
        (
            _octo_event_lock() { return 75; }
            ! record_provider_success codex
        ) && [[ -e "$_PROVIDER_STATE_DIR/codex.$state" ]] &&
            record_provider_success codex &&
            [[ ! -e "$_PROVIDER_STATE_DIR/codex.$state" && ! -d "$_PROVIDER_STATE_DIR/codex.breaker.lock" ]]
    ); then test_pass; else test_fail "success cleared $state state without holding the breaker lock"; fi
done

if [[ -f "$ROUTER" ]]; then
    pass "provider-router.sh exists"
else
    fail "provider-router.sh exists" "not found"
fi

if bash -n "$ROUTER" 2>/dev/null; then
    pass "provider-router.sh has valid bash syntax"
else
    fail "provider-router.sh has valid bash syntax" "syntax error"
fi

# ── Error classification function exists ──────────────────────────────────────

if grep -q 'classify_provider_error()' "$ROUTER" 2>/dev/null; then
    pass "classify_provider_error() function exists"
else
    fail "classify_provider_error() function exists" "function not found"
fi

# ── Classifies transient errors ───────────────────────────────────────────────

if grep -q '429.*transient\|rate.limit' "$ROUTER" 2>/dev/null; then
    pass "Classifies 429/rate-limit as transient"
else
    fail "Classifies 429/rate-limit as transient" "missing 429 classification"
fi

if grep -q '500\|503\|internal server\|service unavailable' "$ROUTER" 2>/dev/null; then
    pass "Classifies 5xx server errors as transient"
else
    fail "Classifies 5xx server errors as transient" "missing 5xx classification"
fi

if grep -q 'timeout\|timed out\|ECONNRESET\|ETIMEDOUT' "$ROUTER" 2>/dev/null; then
    pass "Classifies network errors as transient"
else
    fail "Classifies network errors as transient" "missing network error classification"
fi

# ── Classifies permanent errors ───────────────────────────────────────────────

if grep -q '401\|403\|unauthorized\|forbidden\|invalid.api.key' "$ROUTER" 2>/dev/null; then
    pass "Classifies auth errors as permanent"
else
    fail "Classifies auth errors as permanent" "missing auth error classification"
fi

if grep -q 'billing\|payment\|quota' "$ROUTER" 2>/dev/null; then
    pass "Classifies billing errors as permanent"
else
    fail "Classifies billing errors as permanent" "missing billing classification"
fi

# ── Circuit breaker functions ─────────────────────────────────────────────────

if grep -q 'record_provider_failure()' "$ROUTER" 2>/dev/null; then
    pass "record_provider_failure() function exists"
else
    fail "record_provider_failure() function exists" "function not found"
fi

if grep -q 'record_provider_success()' "$ROUTER" 2>/dev/null; then
    pass "record_provider_success() function exists"
else
    fail "record_provider_success() function exists" "function not found"
fi

if grep -q 'is_provider_available()' "$ROUTER" 2>/dev/null; then
    pass "is_provider_available() function exists"
else
    fail "is_provider_available() function exists" "function not found"
fi

# ── Circuit breaker has configurable thresholds ───────────────────────────────

if grep -q 'OCTO_CB_FAILURE_THRESHOLD' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker failure threshold is configurable"
else
    fail "Circuit breaker failure threshold is configurable" "missing OCTO_CB_FAILURE_THRESHOLD"
fi

if grep -q 'OCTO_CB_COOLDOWN_SECS' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker cooldown is configurable"
else
    fail "Circuit breaker cooldown is configurable" "missing OCTO_CB_COOLDOWN_SECS"
fi

# ── Circuit breaker state persistence ─────────────────────────────────────────

if grep -q 'provider-state' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker uses provider-state directory"
else
    fail "Circuit breaker uses provider-state directory" "missing state directory"
fi

if grep -q '\.cooldown' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker uses cooldown files"
else
    fail "Circuit breaker uses cooldown files" "missing cooldown mechanism"
fi

if grep -q '\.failures' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker uses failure tracking files"
else
    fail "Circuit breaker uses failure tracking files" "missing failure files"
fi

# ── Backoff calculation ───────────────────────────────────────────────────────

if grep -q 'calculate_backoff()' "$ROUTER" 2>/dev/null; then
    pass "calculate_backoff() function exists"
else
    fail "calculate_backoff() function exists" "function not found"
fi

if grep -q 'jitter\|RANDOM' "$ROUTER" 2>/dev/null; then
    pass "Backoff includes jitter"
else
    fail "Backoff includes jitter" "no jitter in backoff calculation"
fi

# ── Provider filtering ────────────────────────────────────────────────────────

if grep -q 'filter_available_providers()' "$ROUTER" 2>/dev/null; then
    pass "filter_available_providers() function exists"
else
    fail "filter_available_providers() function exists" "function not found"
fi

# ── Retry-After header extraction ─────────────────────────────────────────────

if grep -q 'extract_retry_after\|retry.after' "$ROUTER" 2>/dev/null; then
    pass "Extract Retry-After header support"
else
    fail "Extract Retry-After header support" "missing Retry-After extraction"
fi

# ── Doctor integration ────────────────────────────────────────────────────────

if grep -q 'get_circuit_breaker_status()' "$ROUTER" 2>/dev/null; then
    pass "get_circuit_breaker_status() for doctor integration"
else
    fail "get_circuit_breaker_status() for doctor integration" "function not found"
fi

DOCTOR="$(resolve_claude_skill_path "skill-doctor")"
if grep -q 'circuit breaker' "$DOCTOR" 2>/dev/null; then
    pass "Doctor skill mentions circuit breaker"
else
    fail "Doctor skill mentions circuit breaker" "missing from doctor"
fi

# ── Scored routing mode ───────────────────────────────────────────────────────

if grep -q 'scored)' "$ROUTER" 2>/dev/null; then
    pass "Scored routing mode exists"
else
    fail "Scored routing mode exists" "missing scored routing"
fi

# ── Half-open state support ───────────────────────────────────────────────────

if grep -qi 'half.open' "$ROUTER" 2>/dev/null; then
    pass "Supports half-open circuit breaker state"
else
    fail "Supports half-open circuit breaker state" "missing half-open"
fi

# ── No attribution references ─────────────────────────────────────────────────

if grep -qi 'gsd-2\|strategic-audit\|Rust agent runtime' "$ROUTER" 2>/dev/null; then
    fail "No attribution references" "found prohibited reference"
else
    pass "No attribution references"
fi

# ── v9.13: Persistent state + spawn integration ──────────────────────────────

ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

# Persistent state dir (not /tmp/)
if grep -q 'CLAUDE_PLUGIN_DATA\|WORKSPACE_DIR\|\.claude-octopus' "$PROJECT_ROOT/scripts/provider-router.sh" 2>/dev/null; then
    pass "Circuit breaker state persists across sessions"
else
    fail "Circuit breaker state persists" "still using /tmp/"
fi

# Spawn integration: circuit check before dispatch
if grep -q 'is_provider_available' "$PROJECT_ROOT/scripts/lib/spawn.sh" 2>/dev/null; then
    pass "spawn_agent checks circuit breaker before dispatch"
else
    fail "spawn integration" "is_provider_available not in spawn.sh"
fi

# Spawn integration: records failure with classification
if grep -q 'classify_error' "$PROJECT_ROOT/scripts/lib/spawn.sh" 2>/dev/null; then
    pass "spawn_agent classifies errors for circuit breaker"
else
    fail "spawn error classification" "classify_error not in spawn.sh"
fi

# Bash 3.2 compat: no ${var,,} in provider-router.sh
if grep -q '${.*,,}' "$PROJECT_ROOT/scripts/provider-router.sh" 2>/dev/null; then
    fail "Bash 3.2 compat in provider-router.sh" "found \${var,,}"
else
    pass "Bash 3.2 compat in provider-router.sh"
fi

# Doctor shows open circuits
if grep -q 'circuit-breaker' "$PROJECT_ROOT/scripts/lib/doctor.sh" 2>/dev/null; then
    pass "Doctor checks circuit breaker state"
else
    fail "Doctor circuit check" "not found in doctor.sh"
fi

rm -f "$ALL_SRC"
test_summary
