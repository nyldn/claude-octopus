#!/usr/bin/env bash
# Unit tests for round-aware PR review state helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_LIB="$PROJECT_ROOT/scripts/lib/pr-review-state.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "PR review state"

if [[ -f "$STATE_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_LIB"
fi

assert_function_exists() {
    local fn="$1"
    test_case "function exists: $fn"
    if declare -F "$fn" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "missing function: $fn"
    fi
}

test_case "pr-review-state.sh has valid bash syntax"
if [[ -f "$STATE_LIB" ]] && bash -n "$STATE_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "missing or invalid $STATE_LIB"
fi

for fn in \
    pr_review_state_enabled \
    pr_review_state_path \
    pr_review_state_validate \
    pr_review_state_append_round \
    pr_review_state_next_round \
    pr_review_state_previous_round \
    pr_review_state_classify_findings \
    pr_review_state_diff_since \
    pr_review_state_context_for_prompt \
    pr_review_state_render_timeline
do
    assert_function_exists "$fn"
done

test_case "state path includes host owner repo and PR number"
if declare -F pr_review_state_path >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    path=$(pr_review_state_path "github.com" "nyldn/claude-octopus" "322")
    expected="$tmp_home/.claude-octopus/pr-state/github.com/nyldn/claude-octopus/322.json"
    rm -rf "$tmp_home"
    if [[ "$path" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected $expected, got $path"
    fi
else
    test_fail "pr_review_state_path is not defined"
fi

test_case "OCTOPUS_PR_HISTORY=0 disables state"
if declare -F pr_review_state_enabled >/dev/null 2>&1; then
    if OCTOPUS_PR_HISTORY=0 pr_review_state_enabled; then
        test_fail "expected disabled when OCTOPUS_PR_HISTORY=0"
    else
        test_pass
    fi
else
    test_fail "pr_review_state_enabled is not defined"
fi

test_case "append round creates versioned schema and next round increments"
if declare -F pr_review_state_append_round >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    state_file=$(pr_review_state_path "github.com" "nyldn/claude-octopus" "322")
    findings='[{"id":"f-001","providers":["codex"],"severity":"normal","file":"scripts/foo.sh","line":42,"category":"logic","title":"Missing null check","detail":"detail","confidence":0.92,"status":"open"}]'
    classification='{"addressed":0,"persistent":0,"new":1,"regressed":0}'
    pr_review_state_append_round "$state_file" "github.com" "nyldn/claude-octopus" "322" "abc123" '["codex","gemini"]' "$findings" "$classification"
    if jq -e '.schema == 1 and .pr.host == "github.com" and .pr.repo == "nyldn/claude-octopus" and .pr.number == 322 and (.rounds | length) == 1 and .rounds[0].n == 1' "$state_file" >/dev/null \
       && [[ "$(pr_review_state_next_round "$state_file")" == "2" ]]; then
        test_pass
    else
        test_fail "state schema or next round value was incorrect"
    fi
    rm -rf "$tmp_home"
else
    test_fail "pr_review_state_append_round is not defined"
fi

test_case "previous round returns latest round object"
if declare -F pr_review_state_previous_round >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    state_file=$(pr_review_state_path "github.com" "nyldn/claude-octopus" "322")
    pr_review_state_append_round "$state_file" "github.com" "nyldn/claude-octopus" "322" "sha1" '["codex"]' '[]' '{"addressed":0,"persistent":0,"new":0,"regressed":0}'
    pr_review_state_append_round "$state_file" "github.com" "nyldn/claude-octopus" "322" "sha2" '["gemini"]' '[]' '{"addressed":0,"persistent":0,"new":0,"regressed":0}'
    if [[ "$(pr_review_state_previous_round "$state_file" | jq -r '.n')" == "2" ]]; then
        test_pass
    else
        test_fail "did not return the latest round"
    fi
    rm -rf "$tmp_home"
else
    test_fail "pr_review_state_previous_round is not defined"
fi

test_case "finding classifier reports addressed persistent new and regressed"
if declare -F pr_review_state_classify_findings >/dev/null 2>&1; then
    previous='[
      {"id":"a","file":"a.sh","line":1,"title":"A","status":"open"},
      {"id":"b","file":"b.sh","line":2,"title":"B","status":"open"},
      {"id":"c","file":"c.sh","line":3,"title":"C","status":"addressed"}
    ]'
    current='[
      {"file":"a.sh","line":1,"title":"A"},
      {"file":"c.sh","line":3,"title":"C"},
      {"file":"d.sh","line":4,"title":"D"}
    ]'
    result=$(pr_review_state_classify_findings "$previous" "$current")
    if jq -e '.addressed == 1 and .persistent == 1 and .new == 1 and .regressed == 1' <<< "$result" >/dev/null; then
        test_pass
    else
        test_fail "unexpected classification: $result"
    fi
else
    test_fail "pr_review_state_classify_findings is not defined"
fi

test_case "diff since previous SHA degrades when SHA is unavailable"
if declare -F pr_review_state_diff_since >/dev/null 2>&1; then
    tmp_repo=$(mktemp -d)
    (
        cd "$tmp_repo"
        git init -q
        git -c user.name=Octo -c user.email=octo@example.com commit --allow-empty -m init >/dev/null
        if pr_review_state_diff_since "missing-sha" "HEAD" >/dev/null 2>&1; then
            exit 1
        fi
    )
    status=$?
    rm -rf "$tmp_repo"
    if [[ "$status" -eq 0 ]]; then
        test_pass
    else
        test_fail "expected missing SHA to return non-zero"
    fi
else
    test_fail "pr_review_state_diff_since is not defined"
fi

test_case "context prompt includes prior findings and since-last-round diff"
if declare -F pr_review_state_context_for_prompt >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    tmp_repo=$(mktemp -d)
    HOME="$tmp_home"
    state_file=$(pr_review_state_path "github.com" "nyldn/claude-octopus" "322")
    pr_review_state_append_round "$state_file" "github.com" "nyldn/claude-octopus" "322" "sha1" '["codex"]' '[{"file":"a.sh","line":1,"title":"A","severity":"normal","status":"open"}]' '{"addressed":0,"persistent":0,"new":1,"regressed":0}'
    context=$(pr_review_state_context_for_prompt "$state_file" "diff --git a/a.sh b/a.sh" 2000)
    rm -rf "$tmp_home" "$tmp_repo"
    if grep -q "Prior round-aware review context" <<< "$context" \
       && grep -q '"title":"A"' <<< "$context" \
       && grep -q "diff --git" <<< "$context"; then
        test_pass
    else
        test_fail "context did not include prior findings and diff"
    fi
else
    test_fail "pr_review_state_context_for_prompt is not defined"
fi

test_case "timeline renders carry-over counts"
if declare -F pr_review_state_render_timeline >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    state_file=$(pr_review_state_path "github.com" "nyldn/claude-octopus" "322")
    pr_review_state_append_round "$state_file" "github.com" "nyldn/claude-octopus" "322" "abc123" '["codex"]' '[]' '{"addressed":2,"persistent":1,"new":3,"regressed":0}'
    timeline=$(pr_review_state_render_timeline "$state_file" "def456")
    rm -rf "$tmp_home"
    if grep -q "Round 2" <<< "$timeline" \
       && grep -q "Addressed: 2" <<< "$timeline" \
       && grep -q "Persistent: 1" <<< "$timeline" \
       && grep -q "New: 3" <<< "$timeline"; then
        test_pass
    else
        test_fail "timeline output was unexpected: $timeline"
    fi
else
    test_fail "pr_review_state_render_timeline is not defined"
fi

test_summary
