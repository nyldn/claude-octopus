#!/usr/bin/env bash
# Claude Octopus Agent Registry (v8.45.0)
# Persistent lifecycle tracking for spawned coding agents.
# Tracks: agent ID, branch, worktree, status, PR number, CI status.
#
# Usage:
#   agent-registry.sh register   <id> <branch> [worktree_path]
#   agent-registry.sh update     <id> --status <status> [--pr <num>] [--ci <pass|fail|pending>]
#   agent-registry.sh get        <id>
#   agent-registry.sh list       [--status <status>] [--json]
#   agent-registry.sh health     [--auto-update] [--react]
#   agent-registry.sh cleanup    [--max-age <days>]
#
# Statuses (v8.45.0 — expanded PR lifecycle):
#   running, retrying, pr_open, ci_pending, ci_failed, review_pending,
#   changes_requested, approved, mergeable, merged, done, failed, stuck

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_DIR="${HOME}/.claude-octopus/agents"
REGISTRY_FILE="${REGISTRY_DIR}/registry.json"
ARCHIVE_DIR="${REGISTRY_DIR}/archive"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Initialize registry
_init() {
    mkdir -p "$REGISTRY_DIR" "$ARCHIVE_DIR"
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo '{"agents":[],"version":"1.0.0"}' > "$REGISTRY_FILE"
    fi
}

# Atomic JSON write (same pattern as scheduler/store.sh)
_atomic_write() {
    local target="$1"
    local content="$2"
    local temp_file="${target}.tmp.$$"

    echo "$content" > "$temp_file"

    if ! jq empty "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        echo "ERROR: invalid JSON, write aborted" >&2
        return 1
    fi

    if [[ -f "$target" ]]; then
        cp "$target" "${target}.bak"
    fi

    mv "$temp_file" "$target"
}

# Register a new agent
cmd_register() {
    local id="$1"
    local branch="$2"
    local worktree="${3:-}"

    if [[ -z "$id" || -z "$branch" ]]; then
        echo "Usage: agent-registry.sh register <id> <branch> [worktree_path]" >&2
        return 1
    fi

    _init

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "unknown")

    local new_agent
    new_agent=$(jq -n \
        --arg id "$id" \
        --arg branch "$branch" \
        --arg worktree "$worktree" \
        --arg status "running" \
        --arg started "$now" \
        --arg project "$project_root" \
        --arg session "${CLAUDE_SESSION_ID:-unknown}" \
        '{
            id: $id,
            branch: $branch,
            worktree: (if $worktree == "" then null else $worktree end),
            status: $status,
            pr: null,
            ci: null,
            started_at: $started,
            updated_at: $started,
            completed_at: null,
            project: $project,
            session: $session,
            retries: 0,
            error: null
        }')

    local updated
    updated=$(jq --argjson agent "$new_agent" '
        .agents = [.agents[] | select(.id != $agent.id)] + [$agent]
    ' "$REGISTRY_FILE")

    _atomic_write "$REGISTRY_FILE" "$updated"
    echo "Registered agent: $id (branch: $branch)"
}

# Update an agent's status
cmd_update() {
    local id="$1"
    shift

    if [[ -z "$id" ]]; then
        echo "Usage: agent-registry.sh update <id> --status <status> [--pr <num>] [--ci <status>]" >&2
        return 1
    fi

    _init

    local status="" pr="" ci="" error=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) status="$2"; shift 2 ;;
            --pr) pr="$2"; shift 2 ;;
            --ci) ci="$2"; shift 2 ;;
            --error) error="$2"; shift 2 ;;
            --retry)
                local updated
                updated=$(jq --arg id "$id" '
                    .agents = [.agents[] | if .id == $id then .retries += 1 | .status = "retrying" else . end]
                ' "$REGISTRY_FILE")
                _atomic_write "$REGISTRY_FILE" "$updated"
                echo "Agent $id: retry count incremented"
                return 0
                ;;
            *) shift ;;
        esac
    done

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local updated
    updated=$(jq --arg id "$id" \
        --arg status "$status" \
        --arg pr "$pr" \
        --arg ci "$ci" \
        --arg error "$error" \
        --arg now "$now" '
        .agents = [.agents[] | if .id == $id then
            (if $status != "" then .status = $status else . end) |
            (if $pr != "" then .pr = ($pr | tonumber) else . end) |
            (if $ci != "" then .ci = $ci else . end) |
            (if $error != "" then .error = $error else . end) |
            .updated_at = $now |
            (if ($status == "done" or $status == "failed" or $status == "merged") then .completed_at = $now else . end)
        else . end]
    ' "$REGISTRY_FILE")

    _atomic_write "$REGISTRY_FILE" "$updated"
    echo "Updated agent: $id"
}

# Get a single agent
cmd_get() {
    local id="$1"
    _init

    jq --arg id "$id" '.agents[] | select(.id == $id)' "$REGISTRY_FILE"
}

# List agents with optional filters
cmd_list() {
    _init

    local filter_status="" json_mode=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) filter_status="$2"; shift 2 ;;
            --json) json_mode=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$json_mode" == true ]]; then
        if [[ -n "$filter_status" ]]; then
            jq --arg s "$filter_status" '[.agents[] | select(.status == $s)]' "$REGISTRY_FILE"
        else
            jq '.agents' "$REGISTRY_FILE"
        fi
        return
    fi

    # Human-readable output
    local count
    if [[ -n "$filter_status" ]]; then
        count=$(jq --arg s "$filter_status" '[.agents[] | select(.status == $s)] | length' "$REGISTRY_FILE")
    else
        count=$(jq '.agents | length' "$REGISTRY_FILE")
    fi

    if [[ "$count" -eq 0 ]]; then
        echo "No agents found."
        return
    fi

    printf "${CYAN}%-20s %-20s %-10s %-8s %-8s %-20s${NC}\n" "ID" "BRANCH" "STATUS" "PR" "CI" "STARTED"
    printf "%-20s %-20s %-10s %-8s %-8s %-20s\n" "----" "------" "------" "--" "--" "-------"

    local query='.agents[]'
    if [[ -n "$filter_status" ]]; then
        query=".agents[] | select(.status == \"$filter_status\")"
    fi

    jq -r "$query | [.id, .branch, .status, (.pr // \"-\"|tostring), (.ci // \"-\"), .started_at] | @tsv" "$REGISTRY_FILE" | \
    while IFS=$'\t' read -r id branch status pr ci started; do
        local status_color="$NC"
        case "$status" in
            running|retrying|ci_pending) status_color="$YELLOW" ;;
            pr_open|review_pending) status_color="$CYAN" ;;
            approved|mergeable) status_color="$GREEN" ;;
            changes_requested|ci_failed|stuck) status_color="$RED" ;;
            merged|done) status_color="$GREEN" ;;
            failed) status_color="$RED" ;;
        esac

        local ci_color="$NC"
        case "$ci" in
            pass) ci_color="$GREEN" ;;
            fail) ci_color="$RED" ;;
            pending) ci_color="$YELLOW" ;;
        esac

        printf "%-20s %-20s ${status_color}%-10s${NC} %-8s ${ci_color}%-8s${NC} %-20s\n" \
            "$id" "$branch" "$status" "$pr" "$ci" "${started:0:16}"
    done
}

# Health check: verify agent status against GitHub
# v8.45.0: --react flag fires reaction engine after detecting state changes
cmd_health() {
    _init

    local auto_update=false
    local react_mode=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto-update) auto_update=true; shift ;;
            --react) react_mode=true; auto_update=true; shift ;;
            *) shift ;;
        esac
    done

    # v8.45.0: Check all active agents, not just running/retrying
    local active_statuses='"running","retrying","pr_open","ci_pending","ci_failed","review_pending","changes_requested","approved","mergeable"'
    local active_agents
    active_agents=$(jq "[.agents[] | select(.status as \$s | [${active_statuses}] | index(\$s) != null)]" "$REGISTRY_FILE")
    local count
    count=$(echo "$active_agents" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "No active agents to check."
        return
    fi

    echo -e "${BLUE}Checking health of $count active agent(s)...${NC}"
    echo ""

    local REACTIONS="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}/reactions.sh"

    echo "$active_agents" | jq -r '.[].id' | while read -r id; do
        local branch current_status
        branch=$(echo "$active_agents" | jq -r --arg id "$id" '.[] | select(.id == $id) | .branch')
        current_status=$(echo "$active_agents" | jq -r --arg id "$id" '.[] | select(.id == $id) | .status')

        echo -n "  $id ($branch) [$current_status]: "

        # Check for open PR on this branch
        local pr_num=""
        if command -v gh &>/dev/null; then
            pr_num=$(gh pr list --head "$branch" --json number --jq '.[0].number' 2>/dev/null || echo "")
        fi

        if [[ -n "$pr_num" ]]; then
            echo -n "PR #$pr_num"

            # Check if PR is merged
            local pr_state
            pr_state=$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null || echo "")

            if [[ "$pr_state" == "MERGED" ]]; then
                echo " — merged"
                if [[ "$auto_update" == true ]]; then
                    cmd_update "$id" --status "merged" --pr "$pr_num"
                fi
                if [[ "$react_mode" == true && -x "$REACTIONS" ]]; then
                    "$REACTIONS" react "$id" "merged" 2>/dev/null || true
                fi
                continue
            fi

            # Check CI status
            local ci_status="pending"
            local checks_output
            checks_output=$(gh pr checks "$pr_num" 2>&1 || true)
            if echo "$checks_output" | grep -c "fail" >/dev/null 2>&1; then
                ci_status="fail"
            elif echo "$checks_output" | grep -c "pass" >/dev/null 2>&1 && ! echo "$checks_output" | grep -c "pending" >/dev/null 2>&1; then
                ci_status="pass"
            fi

            # Check review state
            local review_state=""
            review_state=$(gh pr view "$pr_num" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "")

            echo -n ", CI: $ci_status"
            [[ -n "$review_state" ]] && echo -n ", review: $review_state"
            echo ""

            if [[ "$auto_update" == true ]]; then
                cmd_update "$id" --pr "$pr_num" --ci "$ci_status"

                # v8.45.0: Set granular status based on PR lifecycle
                local new_status="$current_status"
                if [[ "$ci_status" == "fail" ]]; then
                    new_status="ci_failed"
                elif [[ "$review_state" == "CHANGES_REQUESTED" ]]; then
                    new_status="changes_requested"
                elif [[ "$review_state" == "APPROVED" && "$ci_status" == "pass" ]]; then
                    new_status="mergeable"
                elif [[ "$review_state" == "APPROVED" ]]; then
                    new_status="approved"
                elif [[ "$ci_status" == "pass" ]]; then
                    new_status="review_pending"
                elif [[ "$ci_status" == "pending" ]]; then
                    new_status="ci_pending"
                else
                    new_status="pr_open"
                fi

                if [[ "$new_status" != "$current_status" ]]; then
                    cmd_update "$id" --status "$new_status"
                fi
            fi

            # v8.45.0: Fire reactions
            if [[ "$react_mode" == true && -x "$REACTIONS" ]]; then
                "$REACTIONS" check "$id" 2>/dev/null || true
            fi
        else
            # No PR yet — check if worktree process is alive
            local worktree
            worktree=$(jq -r --arg id "$id" '.agents[] | select(.id == $id) | .worktree // ""' "$REGISTRY_FILE")

            if [[ -n "$worktree" && -d "$worktree" ]]; then
                # Check if any claude process is running in the worktree
                if pgrep -f "claude.*$worktree" >/dev/null 2>&1; then
                    echo "still running (no PR yet)"
                else
                    echo -e "${YELLOW}process not found${NC} (may have completed or crashed)"
                    if [[ "$auto_update" == true ]]; then
                        cmd_update "$id" --status "failed" --error "Process not found"
                    fi
                fi
            else
                # Check for stuck agent
                if [[ "$react_mode" == true && -x "$REACTIONS" ]]; then
                    "$REACTIONS" check "$id" 2>/dev/null || true
                fi
                echo "no PR, no worktree — status unknown"
            fi
        fi
    done
}

# Cleanup completed/failed agents older than N days
cmd_cleanup() {
    _init

    local max_age_days=7
    [[ "${1:-}" == "--max-age" ]] && max_age_days="${2:-7}"

    local cutoff
    cutoff=$(date -u -v-${max_age_days}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
             date -u -d "${max_age_days} days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
             echo "")

    if [[ -z "$cutoff" ]]; then
        echo "WARNING: Could not calculate date cutoff, skipping age-based cleanup" >&2
        return 0
    fi

    # Archive old completed/failed/merged agents
    local archived
    archived=$(jq --arg cutoff "$cutoff" '
        [.agents[] | select(
            (.status == "done" or .status == "failed" or .status == "merged") and
            (.completed_at != null) and
            (.completed_at < $cutoff)
        )]
    ' "$REGISTRY_FILE")

    local archive_count
    archive_count=$(echo "$archived" | jq 'length')

    if [[ "$archive_count" -gt 0 ]]; then
        local archive_file="${ARCHIVE_DIR}/archive-$(date +%Y%m%d).json"
        if [[ -f "$archive_file" ]]; then
            local merged
            merged=$(jq -s '.[0] + .[1]' "$archive_file" <(echo "$archived"))
            echo "$merged" > "$archive_file"
        else
            echo "$archived" > "$archive_file"
        fi

        # Remove archived agents from active registry
        local updated
        updated=$(jq --arg cutoff "$cutoff" '
            .agents = [.agents[] | select(
                not(
                    (.status == "done" or .status == "failed" or .status == "merged") and
                    (.completed_at != null) and
                    (.completed_at < $cutoff)
                )
            )]
        ' "$REGISTRY_FILE")

        _atomic_write "$REGISTRY_FILE" "$updated"
        echo "Archived $archive_count agent(s) older than $max_age_days days"
    else
        echo "No agents to archive"
    fi

    # Clean up orphaned worktrees
    jq -r '.agents[] | select(.worktree != null) | .worktree' "$REGISTRY_FILE" | while read -r wt; do
        if [[ -n "$wt" && ! -d "$wt" ]]; then
            echo "WARNING: Worktree $wt no longer exists"
        fi
    done
}

# Main dispatcher
case "${1:-}" in
    register) shift; cmd_register "$@" ;;
    update)   shift; cmd_update "$@" ;;
    get)      shift; cmd_get "$@" ;;
    list)     shift; cmd_list "$@" ;;
    health)   shift; cmd_health "$@" ;;
    cleanup)  shift; cmd_cleanup "$@" ;;
    *)
        cat <<'EOF'
Usage: agent-registry.sh COMMAND [ARGS]

Commands:
  register <id> <branch> [worktree]  Register a new coding agent
  update   <id> --status <s> ...     Update agent status, PR, CI
  get      <id>                      Get agent details (JSON)
  list     [--status <s>] [--json]   List agents
  health   [--auto-update] [--react] Check health + fire reactions
  cleanup  [--max-age <days>]        Archive old completed agents

Statuses: running, retrying, pr_open, ci_pending, ci_failed,
          review_pending, changes_requested, approved, mergeable,
          merged, done, failed, stuck
CI values: pass, fail, pending
EOF
        exit 1
        ;;
esac
