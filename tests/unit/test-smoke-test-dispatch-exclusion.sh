#!/usr/bin/env bash
# Regression coverage for #840: a provider that fails the current run's
# smoke test must not be selected into probe/discover dispatch a moment later.
#
# Two things had to be true for that to hold, and each half is its own bug:
#   1. provider_smoke_test() (lib/smoke.sh) must record *which* provider
#      failed somewhere a later dispatch decision can see.
#   2. get_dispatch_strategy() (lib/embrace.sh) must actually consult that
#      record, not just `command -v <provider>`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "smoke test failures exclude providers from dispatch"

log() { :; }

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
HOME="$TEST_TMP_DIR/home"
FAKE_BIN_DIR="$TEST_TMP_DIR/bin"
mkdir -p "$WORKSPACE_DIR" "$HOME" "$FAKE_BIN_DIR"

# ─── Part 1: provider_smoke_test's per-result tally marks failures dead ───

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/smoke.sh"

pass_count=0
fail_count=0
skip_count=0

# Simulate a provider that failed an earlier smoke test but has now recovered.
octo_quota_mark_dead "codex" 0
_smoke_tally_result "codex" "PASS"
_smoke_tally_result "gemini" "UNKNOWN:gemini-3.1-pro-preview"
_smoke_tally_result "agy" "SKIP"

test_case "_smoke_tally_result marks a failed provider quota-dead"
if octo_quota_is_dead "gemini"; then
    test_pass
else
    test_fail "gemini failed its smoke test but was not marked quota-dead"
fi

test_case "_smoke_tally_result clears a passing provider's stale dead marker"
if ! octo_quota_is_dead "codex"; then
    test_pass
else
    test_fail "codex passed its smoke test but its stale dead marker remained"
fi

test_case "successful smoke also clears stale per-provider expiry metadata"
if ! grep -q "^codex	" "$(octo_quota_dead_meta_file)" 2>/dev/null; then
    test_pass
else
    test_fail "codex passed its smoke test but stale permanent metadata remained"
fi

test_case "_smoke_tally_result does not mark a skipped provider quota-dead"
if ! octo_quota_is_dead "agy"; then
    test_pass
else
    test_fail "agy was skipped (not tested) but was marked quota-dead anyway"
fi

test_case "_smoke_tally_result tallies pass/fail/skip correctly"
if [[ "$pass_count" -eq 1 && "$fail_count" -eq 1 && "$skip_count" -eq 1 ]]; then
    test_pass
else
    test_fail "expected 1 pass / 1 fail / 1 skip, got ${pass_count}/${fail_count}/${skip_count}"
fi

# ─── Part 2: get_dispatch_strategy honors the quota-dead marker ───

cat > "$FAKE_BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$FAKE_BIN_DIR/gemini" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$FAKE_BIN_DIR/agy" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/codex" "$FAKE_BIN_DIR/gemini" "$FAKE_BIN_DIR/agy"
export PATH="$FAKE_BIN_DIR:$PATH"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/embrace.sh"

# gemini "just failed" this run's smoke test; codex passed.
octo_quota_mark_dead "gemini"

OCTOPUS_DISPATCH_STRATEGY="smart"
result="$(get_dispatch_strategy "research this topic" "research")"

test_case "get_dispatch_strategy excludes a provider marked quota-dead by smoke test"
if [[ "$result" != *"gemini"* ]]; then
    test_pass
else
    test_fail "gemini was marked quota-dead but still appeared in dispatch: $result"
fi

test_case "get_dispatch_strategy still selects a provider that is not quota-dead"
if [[ "$result" == *"codex"* ]]; then
    test_pass
else
    test_fail "codex is healthy and on PATH but was excluded from dispatch: $result"
fi

full_result="$(OCTOPUS_DISPATCH_STRATEGY=full get_dispatch_strategy "unused" "unused")"

test_case "get_dispatch_strategy (full) also excludes a quota-dead provider"
if [[ "$full_result" != *"gemini"* && "$full_result" == *"codex"* ]]; then
    test_pass
else
    test_fail "full strategy did not exclude quota-dead gemini while keeping codex: $full_result"
fi

octo_quota_mark_dead "agy"
minimal_result="$(OCTOPUS_DISPATCH_STRATEGY=minimal get_dispatch_strategy "unused" "unused")"

test_case "get_dispatch_strategy (minimal) falls through dead Google seats to codex"
if [[ "$minimal_result" == *"codex"* && "$minimal_result" != *"gemini"* && "$minimal_result" != *"agy"* ]]; then
    test_pass
else
    test_fail "minimal strategy did not fall through dead gemini/agy seats to codex: $minimal_result"
fi

test_summary
