#!/usr/bin/env bash
# Unit tests for provider-health-aware fleet building and per-signature
# quota-dead expiry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider health and fleet"

QUOTA_LIB="$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
BUILD_FLEET="$PROJECT_ROOT/scripts/helpers/build-fleet.sh"

export WORKSPACE_DIR="$TEST_TMP_DIR/health-workspace"
mkdir -p "$WORKSPACE_DIR/state"
DEAD_FILE="$WORKSPACE_DIR/state/.provider-quota-dead"

reset_markers() { rm -f "$DEAD_FILE" "$DEAD_FILE.meta"; }

# Mock CLIs so fleet composition does not depend on what the developer has installed.
mock_bin="$TEST_TMP_DIR/health-bin"
mock_home="$TEST_TMP_DIR/health-home"
mkdir -p "$mock_bin" "$mock_home/.codex"
printf '{}\n' > "$mock_home/.codex/auth.json"
for cmd in codex agy; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$mock_bin/$cmd"
    chmod +x "$mock_bin/$cmd"
done

test_case "quota-watcher has valid bash syntax"
if bash -n "$QUOTA_LIB"; then test_pass; else test_fail "quota-watcher.sh syntax error"; fi

# ── Per-signature expiry ─────────────────────────────────────────────────────

# Some terminal auth failures are permanent until the user reconfigures a seat.
test_case "ttl 0 marks a seat dead permanently"
reset_markers
out=$(WORKSPACE_DIR="$WORKSPACE_DIR" OCTOPUS_QUOTA_DEAD_TTL=1 bash -c "
    source '$QUOTA_LIB'
    octo_quota_mark_dead perplexity 0
    # Backdate far beyond any plausible default TTL.
    touch -t 202001010000 '$DEAD_FILE'
    octo_quota_is_dead perplexity && echo DEAD || echo ALIVE
")
if [[ "$out" == "DEAD" ]]; then
    test_pass
else
    test_fail "a permanent mark must survive an elapsed default TTL, got '$out'"
fi

test_case "a recorded window still in force keeps the seat dead"
reset_markers
out=$(WORKSPACE_DIR="$WORKSPACE_DIR" OCTOPUS_QUOTA_DEAD_TTL=1 bash -c "
    source '$QUOTA_LIB'
    octo_quota_mark_dead agy 100000
    touch -t 202001010000 '$DEAD_FILE'
    octo_quota_is_dead agy && echo DEAD || echo ALIVE
")
if [[ "$out" == "DEAD" ]]; then
    test_pass
else
    test_fail "a ~28h window must outlast a 1s default TTL, got '$out'"
fi

test_case "a recorded window that has elapsed revives the seat"
reset_markers
out=$(WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$QUOTA_LIB'
    octo_quota_mark_dead agy 1
    # Rewrite the metadata timestamp to two hours ago.
    meta=\"\$(octo_quota_dead_meta_file)\"
    now=\$(date +%s)
    printf 'agy\t%s\t1\n' \"\$((now - 7200))\" > \"\$meta\"
    octo_quota_is_dead agy && echo DEAD || echo ALIVE
")
if [[ "$out" == "ALIVE" ]]; then
    test_pass
else
    test_fail "an elapsed window must revive the seat, got '$out'"
fi

test_case "per-provider windows are independent"
reset_markers
out=$(WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$QUOTA_LIB'
    octo_quota_mark_dead qwen 0
    octo_quota_mark_dead agy 1
    meta=\"\$(octo_quota_dead_meta_file)\"
    now=\$(date +%s)
    printf 'qwen\t%s\t0\nagy\t%s\t1\n' \"\$now\" \"\$((now - 7200))\" > \"\$meta\"
    octo_quota_is_dead qwen && echo QWEN_DEAD
    octo_quota_is_dead agy || echo AGY_ALIVE
")
if grep -qx "QWEN_DEAD" <<<"$out" && grep -qx "AGY_ALIVE" <<<"$out"; then
    test_pass
else
    test_fail "expiry must be per provider, got '$out'"
fi

# Markers written by an older version have no sidecar entry and must keep working.
test_case "a marker with no metadata falls back to the default TTL"
reset_markers
printf 'perplexity\n' > "$DEAD_FILE"
in_force=$(WORKSPACE_DIR="$WORKSPACE_DIR" OCTOPUS_QUOTA_DEAD_TTL=3600 bash -c "
    source '$QUOTA_LIB'; octo_quota_is_dead perplexity && echo DEAD || echo ALIVE")
touch -t 202001010000 "$DEAD_FILE"
expired=$(WORKSPACE_DIR="$WORKSPACE_DIR" OCTOPUS_QUOTA_DEAD_TTL=3600 bash -c "
    source '$QUOTA_LIB'; octo_quota_is_dead perplexity && echo DEAD || echo ALIVE")
if [[ "$in_force" == "DEAD" && "$expired" == "ALIVE" ]]; then
    test_pass
else
    test_fail "legacy fallback broken: fresh='$in_force' stale='$expired'"
fi

test_case "the marker file keeps its bare-provider-name format"
reset_markers
WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "source '$QUOTA_LIB'; octo_quota_mark_dead agy 500"
if [[ "$(cat "$DEAD_FILE")" == "agy" ]]; then
    test_pass
else
    test_fail "main marker file must stay a plain name list, got '$(cat "$DEAD_FILE")'"
fi

# ── agy reset-window parsing ─────────────────────────────────────────────────

test_case "agy 'Resets in 156h13m' parses to seconds"
got=$(bash -c '
    stderr_file=$(mktemp); stdout_file=$(mktemp)
    echo "Individual quota reached. Resets in 156h13m" > "$stderr_file"
    _agy_quota_reset_window() { LC_ALL=C grep -hoiE "resets in [0-9]+h[0-9]+m([0-9]+s)?" "$stderr_file" "$stdout_file" 2>/dev/null | head -1; }
    '"$(sed -n '/^_agy_reset_window_seconds() {/,/^}/p' "$PROJECT_ROOT/scripts/helpers/agy-exec.sh")"'
    _agy_reset_window_seconds
    rm -f "$stderr_file" "$stdout_file"
')
if [[ "$got" == "562380" ]]; then
    test_pass
else
    test_fail "expected 562380 (156h13m), got '$got'"
fi

test_case "an unparseable reset window yields an empty ttl"
got=$(bash -c '
    stderr_file=$(mktemp); stdout_file=$(mktemp)
    echo "Individual quota reached." > "$stderr_file"
    _agy_quota_reset_window() { LC_ALL=C grep -hoiE "resets in [0-9]+h[0-9]+m([0-9]+s)?" "$stderr_file" "$stdout_file" 2>/dev/null | head -1; }
    '"$(sed -n '/^_agy_reset_window_seconds() {/,/^}/p' "$PROJECT_ROOT/scripts/helpers/agy-exec.sh")"'
    _agy_reset_window_seconds
    rm -f "$stderr_file" "$stdout_file"
')
if [[ -z "$got" ]]; then
    test_pass
else
    test_fail "no window should mean no ttl (caller falls back), got '$got'"
fi

# ── Fleet excludes dead seats ────────────────────────────────────────────────

test_case "a healthy Antigravity seat is assigned a fleet role"
reset_markers
fleet=$(HOME="$mock_home" PATH="$mock_bin:/usr/bin:/bin" WORKSPACE_DIR="$WORKSPACE_DIR" \
    OCTO_ALLOWED_PROVIDERS="codex agy" "$BUILD_FLEET" review standard "x" 2>/dev/null)
if grep -q "^agy|" <<<"$fleet"; then
    test_pass
else
    test_fail "Antigravity should be in the fleet when healthy: $fleet"
fi

# A dead seat must not be retried repeatedly by every workflow.
test_case "a quota-dead Antigravity seat is excluded from the fleet"
reset_markers
WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "source '$QUOTA_LIB'; octo_quota_mark_dead agy 0"
fleet=$(HOME="$mock_home" PATH="$mock_bin:/usr/bin:/bin" WORKSPACE_DIR="$WORKSPACE_DIR" \
    OCTO_ALLOWED_PROVIDERS="codex agy" "$BUILD_FLEET" review standard "x" 2>/dev/null)
if ! grep -q "^agy|" <<<"$fleet"; then
    test_pass
else
    test_fail "a dead seat must not be dispatched: $fleet"
fi

test_case "excluding a dead seat leaves the rest of the fleet intact"
if grep -q "^codex|" <<<"$fleet"; then
    test_pass
else
    test_fail "codex should still be assigned: $fleet"
fi

test_case "fleet building survives every CLI seat being dead"
reset_markers
WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$QUOTA_LIB'
    octo_quota_mark_dead agy 0
    octo_quota_mark_dead codex 0"
if fleet=$(HOME="$mock_home" PATH="$mock_bin:/usr/bin:/bin" WORKSPACE_DIR="$WORKSPACE_DIR" \
    OCTO_ALLOWED_PROVIDERS="codex agy" "$BUILD_FLEET" review standard "x" 2>/dev/null); then
    if ! grep -qE "^(agy|codex)\|" <<<"$fleet"; then
        test_pass
    else
        test_fail "dead seats leaked into an all-dead fleet: $fleet"
    fi
else
    test_fail "build-fleet must not crash when all CLI seats are dead"
fi

test_summary
