#!/usr/bin/env bash
# Regression coverage for `orchestrate.sh --dry-run code-review`. spawn_agent's
# dry-run branch prints a command preview and never a provider PID, so Round 1
# logged a PID error for every reviewer, reported that every provider failed,
# and wrote a failed proof packet and provider fallback records.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "code-review dry-run"

# An isolated HOME keeps a developer's workspace and proof packets out of the
# run. The workspace and proof overrides are cleared too, because they take
# precedence over HOME.
review_home="$TEST_TMP_DIR/review-dry-run-home"
review_project="$TEST_TMP_DIR/review-dry-run-project"
workspace="$review_home/.claude-octopus"
mkdir -p "$review_home"
git init -q "$review_project"
printf 'changed\n' > "$review_project/change.txt"
git -C "$review_project" add change.txt

out="$(cd "$review_project" && env -u CLAUDE_PLUGIN_DATA -u CLAUDE_OCTOPUS_WORKSPACE \
    -u OCTOPUS_WORKFLOW_STATE_DIR -u OCTOPUS_STATE_PROJECT_ROOT \
    -u OCTOPUS_PROOF_PACKET -u OCTOPUS_PROOF_ROOT "HOME=$review_home" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" -n code-review '{"target":"staged"}' </dev/null 2>&1)" \
    && rc=0 || rc=$?
previews="$(grep -c '\[DRY-RUN\] Would execute:' <<< "$out" || true)"
dispatch_counts="$(sed -n 's/.*\[DRY-RUN\] Would dispatch \([0-9][0-9]*\) of \([0-9][0-9]*\) Round 1 reviewers.*/\1 \2/p' <<< "$out")"
read -r would_dispatch fleet_size <<< "${dispatch_counts:-0 0}"

test_case "dry-run code-review exits cleanly"
if [[ "$rc" -eq 0 ]]; then
    test_pass
else
    test_fail "expected exit 0; got exit=$rc, output: $out"
fi

test_case "dry-run code-review previews every Round 1 reviewer"
if [[ "$fleet_size" -ge 1 && "$would_dispatch" -eq "$fleet_size" && "$previews" -eq "$fleet_size" ]]; then
    test_pass
else
    test_fail "expected one preview per reviewer; summary=${dispatch_counts:-none}, previews=$previews, output: $out"
fi

test_case "dry-run code-review reports no failed spawn or failed fleet"
if [[ "$out" != *"produced no provider PID"* && "$out" != *"spawn_agent_capture_pid failed"* \
    && "$out" != *"ALL Round 1 providers failed"* ]]; then
    test_pass
else
    test_fail "dry-run reported provider failures: $out"
fi

test_case "dry-run code-review leaves no proof packet, findings or fallback record"
records="$(find "$workspace" \( -path '*/runs/*' -o -name 'review-*findings-*.json' -o -name 'provider-fallbacks.log' \) \
    -type f 2>/dev/null | tr '\n' ' ' || true)"
if [[ -z "$records" ]]; then
    test_pass
else
    test_fail "dry-run wrote run records: $records"
fi

# A fresh bash process mirrors orchestrate.sh's `set -eo pipefail`; a call
# inside this suite's `&& ... || ...` capture would silently ignore errexit.
# The spawn_agent stub drains stdin, which is the fleet list in production.
harness="$TEST_TMP_DIR/review-dry-run-harness.sh"
cat > "$harness" <<'HARNESS'
set -eo pipefail
calls_log="$2"
failing_agents=" $3 "
DRY_RUN=true
source "$1"
log() { printf '%s: %s\n' "$1" "$2"; }
check_codex_auth_freshness() { return 0; }
parse_review_md() { REVIEW_ALWAYS_CHECK=""; REVIEW_STYLE_RULES=""; REVIEW_SKIP_PATTERNS=""; }
review_collect_diff() { printf '%s\n' "diff --git a/a b/a" "+changed"; }
build_review_fleet() { printf '%s\n' "codex:reviewer1:logic" "claude-sonnet:reviewer2:architecture"; }
review_agent_for_seat() { printf '%s\n' "$1"; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
octo_proof_enabled() { return 0; }
octo_proof_init() { printf 'proof\n' >> "$calls_log"; }
spawn_agent() {
    cat > /dev/null
    printf 'preview:%s:%s\n' "$1" "$4" >> "$calls_log"
    [[ "$failing_agents" != *" $1 "* ]]
}
spawn_agent_capture_pid() { printf 'capture:%s\n' "$1" >> "$calls_log"; return 1; }
review_run '{"target":"staged"}'
echo "review_run returned"
HARNESS

run_harness() {
    local name="$1" failing_agents="${2:-}"
    local home="$TEST_TMP_DIR/$name-home" tmp="$TEST_TMP_DIR/$name-tmp"
    local calls_log="$TEST_TMP_DIR/$name-calls"
    mkdir -p "$home" "$tmp"
    : > "$calls_log"
    harness_out="$(cd "$tmp" && env -u RESULTS_DIR -u OCTOPUS_REVIEW_SINGLE_PROVIDER \
        "HOME=$home" "TMPDIR=$tmp" \
        bash "$harness" "$PROJECT_ROOT/scripts/lib/review.sh" "$calls_log" "$failing_agents" </dev/null 2>&1)" \
        && harness_rc=0 || harness_rc=$?
    harness_calls="$(<"$calls_log")"
    harness_files="$(find "$home" "$tmp" -type f | tr '\n' ' ')"
}

test_case "dry-run code-review previews every reviewer without draining the fleet list or capturing a PID"
run_harness stream
if [[ "$harness_rc" -eq 0 && "$harness_out" == *"review_run returned"* \
    && "$harness_out" == *"[DRY-RUN] Would dispatch 2 of 2 Round 1 reviewers"* \
    && "$harness_calls" == $'preview:codex:reviewer1\npreview:claude-sonnet:reviewer2' \
    && -z "$harness_files" ]]; then
    test_pass
else
    test_fail "expected two previews and no proof, capture or files; got exit=$harness_rc, calls: $harness_calls, files: $harness_files, output: $harness_out"
fi

test_case "dry-run code-review warns on a failed preview and still previews the remaining reviewers"
run_harness partial codex
if [[ "$harness_rc" -eq 0 \
    && "$harness_out" == *"WARN: review_run: could not render a command preview for codex/reviewer1; continuing with remaining fleet"* \
    && "$harness_out" == *"[DRY-RUN] Would dispatch 1 of 2 Round 1 reviewers"* \
    && "$harness_calls" == $'preview:codex:reviewer1\npreview:claude-sonnet:reviewer2' ]]; then
    test_pass
else
    test_fail "expected a warning and both previews; got exit=$harness_rc, calls: $harness_calls, output: $harness_out"
fi

test_case "dry-run code-review fails when no reviewer command renders"
run_harness none "codex claude-sonnet"
if [[ "$harness_rc" -eq 1 && "$harness_out" != *"review_run returned"* \
    && "$harness_out" == *"[DRY-RUN] Would dispatch 0 of 2 Round 1 reviewers"* \
    && "$harness_calls" == $'preview:codex:reviewer1\npreview:claude-sonnet:reviewer2' \
    && -z "$harness_files" ]]; then
    test_pass
else
    test_fail "expected exit 1 after two failed previews; got exit=$harness_rc, calls: $harness_calls, files: $harness_files, output: $harness_out"
fi

test_summary
