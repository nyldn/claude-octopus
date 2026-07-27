#!/usr/bin/env bash
# Helpers for release CI polling.

octo_pr_check_state() {
    local checks_json="$1"
    local check_name="$2"

    python3 - "$check_name" "$checks_json" <<'PY'
import json
import sys

check_name = sys.argv[1]
raw = sys.argv[2]

try:
    checks = json.loads(raw)
except Exception:
    print("pending")
    raise SystemExit(0)

state_map = {
    "SUCCESS": "pass",
    "FAILURE": "fail",
    "ERROR": "fail",
    "CANCELLED": "fail",
    "TIMED_OUT": "fail",
    "ACTION_REQUIRED": "fail",
    "SKIPPED": "skip",
    "NEUTRAL": "skip",
    "PENDING": "pending",
    "QUEUED": "pending",
    "IN_PROGRESS": "pending",
    "REQUESTED": "pending",
    "WAITING": "pending",
}

for check in checks:
    if check.get("name") == check_name:
        state = str(check.get("state") or "PENDING").upper()
        print(state_map.get(state, state.lower()))
        break
else:
    print("pending")
PY
}

octo_release_review_gate() {
    local review_decision="$1"
    local unresolved_threads="$2"

    [[ "$review_decision" == "APPROVED" ]] || return 1
    [[ "$unresolved_threads" =~ ^[0-9]+$ ]] || return 1
    [[ "$unresolved_threads" == "0" ]]
}

octo_release_unresolved_review_threads() {
    local repo_owner="$1"
    local repo_name="$2"
    local pr_number="$3"
    local query response page_unresolved has_next cursor=""
    local unresolved_total=0

    query='query($owner:String!, $name:String!, $number:Int!, $cursor:String) {
      repository(owner:$owner, name:$name) {
        pullRequest(number:$number) {
          reviewThreads(first:100, after:$cursor) {
            nodes { isResolved }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }'

    while :; do
        if [[ -z "$cursor" ]]; then
            response=$(gh api graphql \
                -f query="$query" \
                -f owner="$repo_owner" \
                -f name="$repo_name" \
                -F number="$pr_number" \
                -F cursor=null) || return 1
        else
            response=$(gh api graphql \
                -f query="$query" \
                -f owner="$repo_owner" \
                -f name="$repo_name" \
                -F number="$pr_number" \
                -f cursor="$cursor") || return 1
        fi

        page_unresolved=$(jq -er \
            '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' \
            <<< "$response") || return 1
        [[ "$page_unresolved" =~ ^[0-9]+$ ]] || return 1
        unresolved_total=$((unresolved_total + page_unresolved))

        has_next=$(jq -r \
            '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage |
             if type == "boolean" then . else error("invalid hasNextPage") end' \
            <<< "$response") || return 1
        [[ "$has_next" == "true" || "$has_next" == "false" ]] || return 1
        [[ "$has_next" == "true" ]] || break

        cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // empty' <<< "$response")
        [[ -n "$cursor" ]] || return 1
    done

    printf '%s\n' "$unresolved_total"
}

octo_release_run_with_timeout() {
    local timeout_seconds="$1"
    shift

    python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
command = sys.argv[2:]
process = subprocess.Popen(command)
try:
    return_code = process.wait(timeout=timeout)
except subprocess.TimeoutExpired:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    raise SystemExit(124)
raise SystemExit(return_code)
PY
}
