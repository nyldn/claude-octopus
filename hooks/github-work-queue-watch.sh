#!/usr/bin/env bash
# github-work-queue-watch.sh - Periodically surface open upstream work.
# UserPromptSubmit hook. Read-only: never comments, pushes, merges, or edits.

set -euo pipefail

_octo_hook_exit() {
    local c=$?
    if [[ $c -ne 0 ]]; then
        echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true
    fi
    return 0
}
trap _octo_hook_exit EXIT

escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

emit_context() {
    local context="$1"
    local escaped
    escaped=$(escape_for_json "$context")
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$escaped"
}

emit_continue() {
    : # pass-through — current hook schema treats silence as continue
}

[[ "${OCTOPUS_GITHUB_WORK_QUEUE:-on}" == "off" ]] && { emit_continue; exit 0; }

input=""
if [[ ! -t 0 ]]; then
    if command -v timeout >/dev/null 2>&1; then
        input=$(timeout 3 cat 2>/dev/null || true)
    else
        input=$(cat 2>/dev/null || true)
    fi
fi

cwd="${PWD:-}"
if [[ -n "$input" ]] && command -v jq >/dev/null 2>&1; then
    hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace // empty' 2>/dev/null || true)
    [[ -n "$hook_cwd" && "$hook_cwd" != "null" ]] && cwd="$hook_cwd"
fi

[[ -n "$cwd" && -d "$cwd" ]] || { emit_continue; exit 0; }

if ! git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    emit_continue
    exit 0
fi

remote_urls=$(git -C "$cwd" remote -v 2>/dev/null || true)
if ! printf '%s\n' "$remote_urls" | grep -qE 'github\.com[:/]nyldn/(claude-octopus|claude-octopus-dev)(\.git)?'; then
    emit_continue
    exit 0
fi

repo="${OCTOPUS_GITHUB_WORK_QUEUE_REPO:-nyldn/claude-octopus}"
watch_issue="${OCTOPUS_GITHUB_WORK_QUEUE_ISSUE:-}"
limit="${OCTOPUS_GITHUB_WORK_QUEUE_LIMIT:-3}"
interval="${OCTOPUS_GITHUB_WORK_QUEUE_INTERVAL_SECONDS:-21600}"
case "$limit" in ''|*[!0-9]*) limit=3 ;; esac
case "$interval" in ''|*[!0-9]*) interval=21600 ;; esac

home_dir="${HOME:-/tmp}"
state_dir="${OCTOPUS_STATE_DIR:-${home_dir}/.claude-octopus}/github-work-queue"
state_file="${state_dir}/$(printf '%s' "$repo" | tr '/:' '--').last"

now=$(date +%s)
if [[ "${OCTOPUS_GITHUB_WORK_QUEUE_FORCE:-0}" != "1" && -f "$state_file" ]]; then
    last=$(cat "$state_file" 2>/dev/null || echo 0)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    if [[ $((now - last)) -lt "$interval" ]]; then
        emit_continue
        exit 0
    fi
fi

command -v gh >/dev/null 2>&1 || { emit_continue; exit 0; }
gh auth status --hostname github.com >/dev/null 2>&1 || { emit_continue; exit 0; }

focus_issue=""
if [[ -n "$watch_issue" ]]; then
    focus_issue=$(gh issue view "$watch_issue" --repo "$repo" \
        --json number,title,state,url \
        --jq 'select(.state == "OPEN") | "#\(.number) \(.title) - \(.url)"' 2>/dev/null || true)
fi

open_issues=$(gh issue list --repo "$repo" --state open --limit "$limit" \
    --json number,title,url \
    --jq '.[] | "#\(.number) \(.title) - \(.url)"' 2>/dev/null || true)
open_prs=$(gh pr list --repo "$repo" --state open --limit "$limit" \
    --json number,title,url \
    --jq '.[] | "#\(.number) \(.title) - \(.url)"' 2>/dev/null || true)

mkdir -p "$state_dir" 2>/dev/null || true
printf '%s\n' "$now" > "$state_file" 2>/dev/null || true

[[ -n "$focus_issue$open_issues$open_prs" ]] || { emit_continue; exit 0; }

message="[Octopus GitHub queue] Open upstream work exists in ${repo}."
if [[ -n "$focus_issue" ]]; then
    message="${message}"$'\n'"Focus issue: ${focus_issue}"
fi
if [[ -n "$open_issues" ]]; then
    message="${message}"$'\n'"Open issues:"$'\n'"${open_issues}"
fi
if [[ -n "$open_prs" ]]; then
    message="${message}"$'\n'"Open PRs:"$'\n'"${open_prs}"
fi
message="${message}"$'\n'"When the current user request is repo maintenance or a relevant fix, kindly pick up the most applicable item: inspect it, make a focused local change, verify it, and only push/comment/merge after the user asks."

emit_context "$message"
