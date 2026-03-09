#!/usr/bin/env bash
# Claude Octopus Reaction Engine (v8.45.0)
# Configurable auto-response system for agent lifecycle events.
# Fires transparently inside health checks, monitoring loops, and sentinel triage.
#
# Usage:
#   reactions.sh react     <agent_id> <event>         Fire reaction for an event
#   reactions.sh check     <agent_id>                 Detect events and react
#   reactions.sh config    [--show]                   Show active reaction config
#   reactions.sh reset     <agent_id>                 Reset retry counters
#
# Events: ci_failed, changes_requested, approved, stuck, review_pending, merged
# Actions: forward_logs, forward_comments, notify, escalate, auto_merge

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="${SCRIPT_DIR}/agent-registry.sh"
REACTIONS_DIR="${HOME}/.claude-octopus/agents/reactions"
CONFIG_OVERRIDE=".octo/reactions.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ─── Default Reaction Configuration ───────────────────────────────────────────
# Format: EVENT|ACTION|MAX_RETRIES|ESCALATE_AFTER_MIN|ENABLED
# These defaults are overridden by .octo/reactions.conf if present.

_default_reactions() {
    cat <<'DEFAULTS'
ci_failed|forward_logs|3|30|true
changes_requested|forward_comments|2|60|true
approved|notify|0|0|true
stuck|escalate|0|15|true
review_pending|notify|0|0|true
merged|notify|0|0|true
DEFAULTS
}

# ─── Config Loading ───────────────────────────────────────────────────────────

_load_config() {
    # Start with defaults
    local config
    config=$(_default_reactions)

    # Override with project-level config if present
    if [[ -f "$CONFIG_OVERRIDE" ]]; then
        # Project config uses same pipe-delimited format
        # Lines starting with # are comments, blank lines skipped
        local override
        override=$(grep -v '^#' "$CONFIG_OVERRIDE" 2>/dev/null | grep -v '^$' || true)
        if [[ -n "$override" ]]; then
            # Replace matching events, keep defaults for unmatched
            while IFS='|' read -r event action max_retries escalate_min enabled; do
                config=$(echo "$config" | grep -v "^${event}|" || true)
                config="${config}"$'\n'"${event}|${action}|${max_retries}|${escalate_min}|${enabled}"
            done <<< "$override"
        fi
    fi

    echo "$config" | grep -v '^$'
}

# Get config for a specific event
_get_reaction() {
    local event="$1"
    _load_config | grep "^${event}|" | head -1
}

# ─── Reaction State (per-agent retry tracking) ───────────────────────────────

_init_reactions_dir() {
    mkdir -p "$REACTIONS_DIR"
}

_state_file() {
    local agent_id="$1"
    echo "${REACTIONS_DIR}/${agent_id}.state"
}

_get_retry_count() {
    local agent_id="$1"
    local event="$2"
    local state_file
    state_file=$(_state_file "$agent_id")

    if [[ -f "$state_file" ]]; then
        grep "^${event}=" "$state_file" 2>/dev/null | cut -d= -f2 || echo "0"
    else
        echo "0"
    fi
}

_get_first_seen() {
    local agent_id="$1"
    local event="$2"
    local state_file
    state_file=$(_state_file "$agent_id")

    if [[ -f "$state_file" ]]; then
        grep "^${event}_first=" "$state_file" 2>/dev/null | cut -d= -f2 || echo ""
    else
        echo ""
    fi
}

_increment_retry() {
    local agent_id="$1"
    local event="$2"
    local state_file
    state_file=$(_state_file "$agent_id")

    _init_reactions_dir

    local current
    current=$(_get_retry_count "$agent_id" "$event")
    local new_count=$((current + 1))

    if [[ -f "$state_file" ]]; then
        # Update existing count
        if grep -q "^${event}=" "$state_file" 2>/dev/null; then
            local temp="${state_file}.tmp.$$"
            sed "s/^${event}=.*/${event}=${new_count}/" "$state_file" > "$temp"
            mv "$temp" "$state_file"
        else
            echo "${event}=${new_count}" >> "$state_file"
        fi
    else
        echo "${event}=${new_count}" > "$state_file"
    fi

    # Record first-seen timestamp if not set
    local first_seen
    first_seen=$(_get_first_seen "$agent_id" "$event")
    if [[ -z "$first_seen" ]]; then
        echo "${event}_first=$(date -u +%s)" >> "$state_file"
    fi

    echo "$new_count"
}

_reset_state() {
    local agent_id="$1"
    local state_file
    state_file=$(_state_file "$agent_id")
    rm -f "$state_file"
}

# ─── Actions ──────────────────────────────────────────────────────────────────

_action_forward_logs() {
    local agent_id="$1"
    local pr_num="$2"

    if [[ -z "$pr_num" || "$pr_num" == "null" ]]; then
        echo -e "  ${YELLOW}→ Cannot forward CI logs: no PR number${NC}"
        return 1
    fi

    echo -e "  ${BLUE}→ Forwarding CI failure logs to agent ${agent_id}...${NC}"

    # Get failed check details
    local logs=""
    if command -v gh &>/dev/null; then
        logs=$(gh pr checks "$pr_num" 2>&1 | grep -i "fail" || true)
        if [[ -z "$logs" ]]; then
            logs=$(gh pr checks "$pr_num" 2>&1 | tail -20 || true)
        fi
    fi

    if [[ -z "$logs" ]]; then
        echo -e "  ${YELLOW}→ No CI logs retrieved${NC}"
        return 1
    fi

    # Write to agent's reaction inbox
    local inbox_dir="${REACTIONS_DIR}/inbox/${agent_id}"
    mkdir -p "$inbox_dir"
    local inbox_file="${inbox_dir}/ci-failure-$(date +%s).md"

    cat > "$inbox_file" << CIEOF
# CI Failure Report for ${agent_id}

**PR:** #${pr_num}
**Time:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Event:** ci_failed

## Failed Checks

\`\`\`
${logs}
\`\`\`

## Suggested Action

Review the failing checks above and push a fix to the PR branch.
Common causes: lint errors, test failures, type errors, build failures.
CIEOF

    echo -e "  ${GREEN}→ CI logs written to ${inbox_file}${NC}"

    # Update agent registry
    if [[ -x "$REGISTRY" ]]; then
        "$REGISTRY" update "$agent_id" --retry 2>/dev/null || true
    fi
}

_action_forward_comments() {
    local agent_id="$1"
    local pr_num="$2"

    if [[ -z "$pr_num" || "$pr_num" == "null" ]]; then
        echo -e "  ${YELLOW}→ Cannot forward review comments: no PR number${NC}"
        return 1
    fi

    echo -e "  ${BLUE}→ Forwarding review comments to agent ${agent_id}...${NC}"

    # Get review comments
    local comments=""
    if command -v gh &>/dev/null; then
        comments=$(gh api "repos/{owner}/{repo}/pulls/${pr_num}/reviews" \
            --jq '.[] | select(.state == "CHANGES_REQUESTED") | "**\(.user.login):** \(.body)"' 2>/dev/null || true)

        # Also get inline comments
        local inline
        inline=$(gh api "repos/{owner}/{repo}/pulls/${pr_num}/comments" \
            --jq '.[] | "**\(.user.login)** on `\(.path):\(.line // .original_line)`:\n\(.body)\n"' 2>/dev/null || true)

        if [[ -n "$inline" ]]; then
            comments="${comments}"$'\n\n'"## Inline Comments"$'\n'"${inline}"
        fi
    fi

    if [[ -z "$comments" ]]; then
        echo -e "  ${YELLOW}→ No review comments retrieved${NC}"
        return 1
    fi

    # Write to agent's reaction inbox
    local inbox_dir="${REACTIONS_DIR}/inbox/${agent_id}"
    mkdir -p "$inbox_dir"
    local inbox_file="${inbox_dir}/review-comments-$(date +%s).md"

    cat > "$inbox_file" << REVEOF
# Review Comments for ${agent_id}

**PR:** #${pr_num}
**Time:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Event:** changes_requested

## Reviewer Feedback

${comments}

## Suggested Action

Address each reviewer comment and push fixes to the PR branch.
REVEOF

    echo -e "  ${GREEN}→ Review comments written to ${inbox_file}${NC}"

    # Update agent registry
    if [[ -x "$REGISTRY" ]]; then
        "$REGISTRY" update "$agent_id" --retry 2>/dev/null || true
    fi
}

_action_notify() {
    local agent_id="$1"
    local event="$2"
    local pr_num="${3:-}"

    case "$event" in
        approved)
            echo -e "  ${GREEN}→ PR #${pr_num} approved for agent ${agent_id}${NC}"
            ;;
        review_pending)
            echo -e "  ${CYAN}→ PR #${pr_num} waiting for review (agent ${agent_id})${NC}"
            ;;
        merged)
            echo -e "  ${GREEN}→ PR #${pr_num} merged! Agent ${agent_id} complete.${NC}"
            ;;
        *)
            echo -e "  ${BLUE}→ Event '${event}' for agent ${agent_id}${NC}"
            ;;
    esac
}

_action_escalate() {
    local agent_id="$1"
    local event="$2"
    local pr_num="${3:-}"
    local minutes_elapsed="${4:-0}"

    echo ""
    echo -e "  ${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}║  ⚠  ESCALATION: Agent needs human attention     ║${NC}"
    echo -e "  ${RED}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "  ${RED}║${NC}  Agent:   ${agent_id}"
    echo -e "  ${RED}║${NC}  Event:   ${event}"
    if [[ -n "$pr_num" && "$pr_num" != "null" ]]; then
        echo -e "  ${RED}║${NC}  PR:      #${pr_num}"
    fi
    echo -e "  ${RED}║${NC}  Elapsed: ${minutes_elapsed} minutes"
    echo -e "  ${RED}║${NC}"
    echo -e "  ${RED}║${NC}  The agent has exhausted retries or exceeded"
    echo -e "  ${RED}║${NC}  the escalation timeout. Manual intervention"
    echo -e "  ${RED}║${NC}  is required."
    echo -e "  ${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Write escalation to log
    local log_dir="${HOME}/.claude-octopus/logs"
    mkdir -p "$log_dir"
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ESCALATION: agent=${agent_id} event=${event} pr=${pr_num} elapsed=${minutes_elapsed}m" \
        >> "${log_dir}/escalations.log"
}

_action_auto_merge() {
    local agent_id="$1"
    local pr_num="$2"

    if [[ -z "$pr_num" || "$pr_num" == "null" ]]; then
        echo -e "  ${YELLOW}→ Cannot auto-merge: no PR number${NC}"
        return 1
    fi

    # Auto-merge is NOTIFY ONLY — we don't actually merge without user consent
    echo -e "  ${GREEN}→ PR #${pr_num} is approved and CI green. Ready to merge.${NC}"
    echo -e "  ${CYAN}  Run: gh pr merge ${pr_num} --squash${NC}"
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

_dispatch_action() {
    local agent_id="$1"
    local event="$2"
    local action="$3"
    local pr_num="${4:-}"
    local minutes_elapsed="${5:-0}"

    case "$action" in
        forward_logs)      _action_forward_logs "$agent_id" "$pr_num" ;;
        forward_comments)  _action_forward_comments "$agent_id" "$pr_num" ;;
        notify)            _action_notify "$agent_id" "$event" "$pr_num" ;;
        escalate)          _action_escalate "$agent_id" "$event" "$pr_num" "$minutes_elapsed" ;;
        auto_merge)        _action_auto_merge "$agent_id" "$pr_num" ;;
        *)
            echo -e "  ${YELLOW}→ Unknown action: ${action}${NC}"
            return 1
            ;;
    esac
}

# ─── Core: React to Event ────────────────────────────────────────────────────

cmd_react() {
    local agent_id="$1"
    local event="$2"

    if [[ -z "$agent_id" || -z "$event" ]]; then
        echo "Usage: reactions.sh react <agent_id> <event>" >&2
        return 1
    fi

    _init_reactions_dir

    # Look up reaction config for this event
    local reaction
    reaction=$(_get_reaction "$event")

    if [[ -z "$reaction" ]]; then
        # No reaction configured for this event
        return 0
    fi

    local r_event r_action r_max_retries r_escalate_min r_enabled
    IFS='|' read -r r_event r_action r_max_retries r_escalate_min r_enabled <<< "$reaction"

    if [[ "$r_enabled" != "true" ]]; then
        return 0
    fi

    # Get agent details for PR number
    local pr_num=""
    if [[ -x "$REGISTRY" ]]; then
        pr_num=$("$REGISTRY" get "$agent_id" 2>/dev/null | jq -r '.pr // empty' 2>/dev/null || echo "")
    fi

    # Check retry count
    local retry_count
    retry_count=$(_get_retry_count "$agent_id" "$event")

    # Check escalation timeout
    local minutes_elapsed=0
    local first_seen
    first_seen=$(_get_first_seen "$agent_id" "$event")
    if [[ -n "$first_seen" ]]; then
        local now
        now=$(date -u +%s)
        minutes_elapsed=$(( (now - first_seen) / 60 ))
    fi

    # Escalate if retries exhausted or timeout exceeded
    if [[ "$r_max_retries" -gt 0 && "$retry_count" -ge "$r_max_retries" ]]; then
        echo -e "  ${YELLOW}→ Max retries ($r_max_retries) reached for ${event} on ${agent_id}${NC}"
        _action_escalate "$agent_id" "$event" "$pr_num" "$minutes_elapsed"
        return 0
    fi

    if [[ "$r_escalate_min" -gt 0 && "$minutes_elapsed" -ge "$r_escalate_min" ]]; then
        echo -e "  ${YELLOW}→ Escalation timeout (${r_escalate_min}m) reached for ${event} on ${agent_id}${NC}"
        _action_escalate "$agent_id" "$event" "$pr_num" "$minutes_elapsed"
        return 0
    fi

    # Dispatch the configured action
    _dispatch_action "$agent_id" "$event" "$r_action" "$pr_num" "$minutes_elapsed"

    # Increment retry counter for retryable actions
    if [[ "$r_max_retries" -gt 0 ]]; then
        _increment_retry "$agent_id" "$event" >/dev/null
    fi
}

# ─── Core: Detect Events and React ───────────────────────────────────────────

cmd_check() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        echo "Usage: reactions.sh check <agent_id>" >&2
        return 1
    fi

    _init_reactions_dir

    if [[ ! -x "$REGISTRY" ]]; then
        echo "ERROR: agent-registry.sh not found at $REGISTRY" >&2
        return 1
    fi

    # Get agent details
    local agent_json
    agent_json=$("$REGISTRY" get "$agent_id" 2>/dev/null || echo "")

    if [[ -z "$agent_json" || "$agent_json" == "null" ]]; then
        return 0
    fi

    local status pr_num ci branch
    status=$(echo "$agent_json" | jq -r '.status // "unknown"')
    pr_num=$(echo "$agent_json" | jq -r '.pr // empty')
    ci=$(echo "$agent_json" | jq -r '.ci // empty')
    branch=$(echo "$agent_json" | jq -r '.branch // empty')

    # Skip terminal states
    if [[ "$status" == "done" || "$status" == "failed" || "$status" == "merged" ]]; then
        return 0
    fi

    # No PR yet — check for stuck agent
    if [[ -z "$pr_num" ]]; then
        local updated_at
        updated_at=$(echo "$agent_json" | jq -r '.updated_at // empty')
        if [[ -n "$updated_at" ]]; then
            # Check if agent hasn't updated in a while
            local updated_epoch now_epoch
            # macOS date -j vs GNU date
            updated_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null || \
                           date -d "$updated_at" +%s 2>/dev/null || echo "0")
            now_epoch=$(date -u +%s)
            local stale_minutes=$(( (now_epoch - updated_epoch) / 60 ))

            if [[ "$stale_minutes" -gt 15 ]]; then
                cmd_react "$agent_id" "stuck"
            fi
        fi
        return 0
    fi

    # Has PR — detect events from GitHub state
    if ! command -v gh &>/dev/null; then
        return 0
    fi

    # Detect current PR state
    local detected_event=""

    # Check if PR is merged
    local pr_state
    pr_state=$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null || echo "")
    if [[ "$pr_state" == "MERGED" ]]; then
        detected_event="merged"
        "$REGISTRY" update "$agent_id" --status "merged" 2>/dev/null || true
        cmd_react "$agent_id" "$detected_event"
        return 0
    fi

    # Check CI status
    if [[ "$ci" == "fail" ]]; then
        detected_event="ci_failed"
    fi

    # Check review state
    if [[ -z "$detected_event" || "$detected_event" != "ci_failed" ]]; then
        local review_state
        review_state=$(gh pr view "$pr_num" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "")

        case "$review_state" in
            CHANGES_REQUESTED)
                detected_event="changes_requested"
                "$REGISTRY" update "$agent_id" --status "changes_requested" 2>/dev/null || true
                ;;
            APPROVED)
                if [[ "$ci" == "pass" ]]; then
                    detected_event="approved"
                    "$REGISTRY" update "$agent_id" --status "mergeable" 2>/dev/null || true
                else
                    detected_event="approved"
                    "$REGISTRY" update "$agent_id" --status "approved" 2>/dev/null || true
                fi
                ;;
            "")
                if [[ "$ci" == "pass" ]]; then
                    detected_event="review_pending"
                    "$REGISTRY" update "$agent_id" --status "review_pending" 2>/dev/null || true
                fi
                ;;
        esac
    fi

    # Fire reaction if event detected
    if [[ -n "$detected_event" ]]; then
        cmd_react "$agent_id" "$detected_event"
    fi
}

# ─── Batch: Check All Active Agents ──────────────────────────────────────────

cmd_check_all() {
    _init_reactions_dir

    if [[ ! -x "$REGISTRY" ]]; then
        echo "ERROR: agent-registry.sh not found" >&2
        return 1
    fi

    local agents
    agents=$("$REGISTRY" list --json 2>/dev/null | jq -r '.[] | select(.status != "done" and .status != "failed" and .status != "merged") | .id' 2>/dev/null || echo "")

    if [[ -z "$agents" ]]; then
        return 0
    fi

    local count=0
    while IFS= read -r agent_id; do
        if [[ -n "$agent_id" ]]; then
            cmd_check "$agent_id"
            count=$((count + 1))
        fi
    done <<< "$agents"

    if [[ "$count" -gt 0 ]]; then
        echo -e "${BLUE}Checked reactions for ${count} active agent(s)${NC}"
    fi
}

# ─── Config Display ──────────────────────────────────────────────────────────

cmd_config() {
    echo -e "${CYAN}Reaction Engine Configuration${NC}"
    echo ""

    if [[ -f "$CONFIG_OVERRIDE" ]]; then
        echo -e "  Config source: ${GREEN}${CONFIG_OVERRIDE}${NC} (project override)"
    else
        echo -e "  Config source: ${BLUE}defaults (embedded)${NC}"
        echo -e "  Override: create ${CONFIG_OVERRIDE} with pipe-delimited rules"
    fi

    echo ""
    printf "  ${CYAN}%-22s %-18s %-12s %-15s %-8s${NC}\n" "EVENT" "ACTION" "MAX_RETRIES" "ESCALATE_AFTER" "ENABLED"
    printf "  %-22s %-18s %-12s %-15s %-8s\n" "─────" "──────" "───────────" "──────────────" "───────"

    _load_config | while IFS='|' read -r event action max_retries escalate_min enabled; do
        local escalate_str="${escalate_min}m"
        [[ "$escalate_min" == "0" ]] && escalate_str="—"
        local retries_str="$max_retries"
        [[ "$max_retries" == "0" ]] && retries_str="—"

        local enabled_color="$GREEN"
        [[ "$enabled" != "true" ]] && enabled_color="$RED"

        printf "  %-22s %-18s %-12s %-15s ${enabled_color}%-8s${NC}\n" \
            "$event" "$action" "$retries_str" "$escalate_str" "$enabled"
    done
}

# ─── Reset ────────────────────────────────────────────────────────────────────

cmd_reset() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        echo "Usage: reactions.sh reset <agent_id>" >&2
        return 1
    fi

    _reset_state "$agent_id"
    echo "Reset reaction state for agent: $agent_id"
}

# ─── Main Dispatcher ─────────────────────────────────────────────────────────

case "${1:-}" in
    react)     shift; cmd_react "$@" ;;
    check)     shift; cmd_check "$@" ;;
    check-all) shift; cmd_check_all "$@" ;;
    config)    shift; cmd_config "$@" ;;
    reset)     shift; cmd_reset "$@" ;;
    *)
        cat <<'EOF'
Usage: reactions.sh COMMAND [ARGS]

Commands:
  react     <id> <event>   Fire a reaction for a specific event
  check     <id>           Detect events for an agent and react
  check-all                Check all active agents for events
  config    [--show]       Show active reaction configuration
  reset     <id>           Reset retry counters for an agent

Events: ci_failed, changes_requested, approved, stuck, review_pending, merged
Actions: forward_logs, forward_comments, notify, escalate, auto_merge

Configuration:
  Defaults are embedded. Override per-project with .octo/reactions.conf
  Format: EVENT|ACTION|MAX_RETRIES|ESCALATE_AFTER_MIN|ENABLED
EOF
        exit 1
        ;;
esac
