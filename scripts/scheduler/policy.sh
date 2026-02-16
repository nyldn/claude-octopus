#!/usr/bin/env bash
# Claude Octopus Scheduler - Policy Engine (v8.15.0)
# Pre-dispatch admission checks: budget, security, workspace, workflow allowlist, kill switches

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/store.sh"

# Allowed workflows (must match orchestrate.sh subcommands)
ALLOWED_WORKFLOWS="probe grasp tangle ink embrace squeeze grapple"

# Flags that must never appear in scheduled jobs
DENY_FLAGS="--dangerously-skip-permissions --no-verify --force-delete"

# Check all policies for a job. Returns 0 if allowed, 1 if denied.
# On denial, prints JSON reason to stdout.
policy_check() {
    local job_file="$1"

    if ! jq empty "$job_file" 2>/dev/null; then
        echo '{"allowed":false,"reason":"Invalid job JSON"}'
        return 1
    fi

    policy_check_kill_switches    || return 1
    policy_check_workflow "$job_file" || return 1
    policy_check_workspace "$job_file" || return 1
    policy_check_security "$job_file"  || return 1
    policy_check_budget "$job_file"    || return 1

    echo '{"allowed":true}'
    return 0
}

# Kill switch: KILL_ALL or PAUSE_ALL
policy_check_kill_switches() {
    if [[ -f "${SWITCHES_DIR}/KILL_ALL" ]]; then
        echo '{"allowed":false,"reason":"KILL_ALL switch is active. Remove ~/.claude-octopus/scheduler/switches/KILL_ALL to resume."}'
        return 1
    fi
    if [[ -f "${SWITCHES_DIR}/PAUSE_ALL" ]]; then
        echo '{"allowed":false,"reason":"PAUSE_ALL switch is active. Remove ~/.claude-octopus/scheduler/switches/PAUSE_ALL to resume."}'
        return 1
    fi
    return 0
}

# Workflow allowlist
policy_check_workflow() {
    local job_file="$1"
    local workflow
    workflow=$(jq -r '.task.workflow // ""' "$job_file")

    if [[ -z "$workflow" ]]; then
        echo '{"allowed":false,"reason":"Job has no task.workflow defined"}'
        return 1
    fi

    local allowed=false
    local w
    for w in $ALLOWED_WORKFLOWS; do
        if [[ "$workflow" == "$w" ]]; then
            allowed=true
            break
        fi
    done

    if ! $allowed; then
        echo "{\"allowed\":false,\"reason\":\"Workflow '$workflow' is not in the allowlist: $ALLOWED_WORKFLOWS\"}"
        return 1
    fi

    return 0
}

# Workspace validation: must exist, no traversal, no root
policy_check_workspace() {
    local job_file="$1"
    local workspace
    workspace=$(jq -r '.execution.workspace // ""' "$job_file")

    if [[ -z "$workspace" ]]; then
        echo '{"allowed":false,"reason":"Job has no execution.workspace defined"}'
        return 1
    fi

    # Block path traversal
    if [[ "$workspace" == *".."* ]]; then
        echo '{"allowed":false,"reason":"Workspace path contains .."}'
        return 1
    fi

    # Block root path
    if [[ "$workspace" == "/" ]]; then
        echo '{"allowed":false,"reason":"Workspace cannot be root (/)"}'
        return 1
    fi

    # Must be absolute path
    if [[ "$workspace" != /* ]]; then
        echo '{"allowed":false,"reason":"Workspace must be an absolute path"}'
        return 1
    fi

    # Must exist
    if [[ ! -d "$workspace" ]]; then
        echo "{\"allowed\":false,\"reason\":\"Workspace directory does not exist: $workspace\"}"
        return 1
    fi

    return 0
}

# Security: reject dangerous flags in any field
policy_check_security() {
    local job_file="$1"
    local content
    content=$(cat "$job_file")

    # Check deny_flags from the job definition itself
    local job_deny_flags
    job_deny_flags=$(jq -r '.security.deny_flags[]? // empty' "$job_file" 2>/dev/null)

    # Check the full job content for any denied flag
    local flag
    for flag in $DENY_FLAGS; do
        if echo "$content" | grep -qF -- "$flag"; then
            # It's in deny_flags list itself (which is expected), skip those
            local in_denylist
            in_denylist=$(jq -r --arg f "$flag" '.security.deny_flags[]? | select(. == $f)' "$job_file" 2>/dev/null)
            if [[ -z "$in_denylist" ]]; then
                echo "{\"allowed\":false,\"reason\":\"Job contains denied flag: $flag\"}"
                return 1
            fi
        fi
    done

    # Check the prompt for injection of denied flags
    local prompt
    prompt=$(jq -r '.task.prompt // ""' "$job_file")
    for flag in $DENY_FLAGS; do
        if [[ "$prompt" == *"$flag"* ]]; then
            echo "{\"allowed\":false,\"reason\":\"Job prompt contains denied flag: $flag\"}"
            return 1
        fi
    done

    return 0
}

# Budget admission: check daily spend against per-day limit
policy_check_budget() {
    local job_file="$1"

    local max_per_day
    max_per_day=$(jq -r '.budget.max_cost_usd_per_day // 0' "$job_file")

    # If no budget limit, allow (user's choice)
    if [[ "$max_per_day" == "0" ]] || [[ "$max_per_day" == "null" ]]; then
        return 0
    fi

    local daily_spend
    daily_spend=$(get_daily_spend)

    local over
    over=$(awk -v spent="$daily_spend" -v limit="$max_per_day" '
        BEGIN { print (spent + 0 >= limit + 0) ? "yes" : "no" }
    ')

    if [[ "$over" == "yes" ]]; then
        echo "{\"allowed\":false,\"reason\":\"Daily budget exhausted: \$${daily_spend} spent of \$${max_per_day} limit\"}"
        return 1
    fi

    return 0
}
