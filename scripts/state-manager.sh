#!/usr/bin/env bash
# State management utilities for Claude Octopus
# Provides persistent state tracking across sessions

# v9.7.8: Use -eo (not -euo) to match orchestrate.sh's strictness level.
# When sourced, -u (nounset) would escalate globally and crash on any unguarded
# ${VAR} in the 14K+ line caller and its libraries (#108, #189).
set -eo pipefail

# Configuration. Both standalone and orchestrated calls default to the
# host/plugin-data workspace, namespaced by project, so merely inspecting or
# starting a workflow never dirties the user's repository (#841). Set
# OCTOPUS_WORKFLOW_STATE_DIR to opt into a different location.
configure_state_paths() {
    STATE_DIR="${1:-.claude-octopus}"
    STATE_FILE="$STATE_DIR/state.json"
    BACKUP_FILE="$STATE_DIR/state.json.backup"
}

# Resolve the persistent host workspace identically for standalone commands and
# the orchestrator. CLAUDE_PLUGIN_DATA is host-owned; the user override remains
# second in precedence. A missing HOME falls back to the physical caller path.
resolve_octopus_workspace() {
    local workspace home_base
    home_base="${HOME:-$PWD}"
    workspace="${CLAUDE_PLUGIN_DATA:-${CLAUDE_OCTOPUS_WORKSPACE:-${home_base}/.claude-octopus}}"
    if [[ "$workspace" == \~* ]]; then
        workspace="${home_base}${workspace#\~}"
    fi
    printf '%s\n' "$workspace"
}

state_project_id() {
    local project_root="${1:-$PWD}"
    local identity digest remote resolved_root
    remote="$(git -C "$project_root" config --get remote.origin.url 2>/dev/null || true)"
    resolved_root="$(cd "$project_root" 2>/dev/null && pwd -P || printf '%s' "$project_root")"
    identity="${remote}|${resolved_root}"

    if command -v sha256sum >/dev/null 2>&1; then
        digest="$(printf '%s' "$identity" | sha256sum | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        digest="$(printf '%s' "$identity" | shasum -a 256 | awk '{print $1}')"
    elif command -v md5sum >/dev/null 2>&1; then
        digest="$(printf '%s' "$identity" | md5sum | awk '{print $1}')"
    elif command -v md5 >/dev/null 2>&1; then
        digest="$(printf '%s' "$identity" | md5 -q)"
    else
        digest="$(printf '%s' "$identity" | cksum | awk '{print $1 "-" $2}')"
    fi
    printf '%s\n' "$digest"
}

if [[ -n "${OCTOPUS_WORKFLOW_STATE_DIR:-}" ]]; then
    configure_state_paths "$OCTOPUS_WORKFLOW_STATE_DIR"
else
    _octopus_workflow_project_root="${OCTOPUS_STATE_PROJECT_ROOT:-$PWD}"
    _octopus_workflow_state_base="$(resolve_octopus_workspace)"
    configure_state_paths "${_octopus_workflow_state_base}/projects/$(state_project_id "$_octopus_workflow_project_root")"
    unset _octopus_workflow_project_root _octopus_workflow_state_base
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling
error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

# All JSON mutations hold the same directory lock through publication. The
# writer's subshell owns descriptor 9, so every exit releases the lock.
state_writer_lock() {
    exec 9< "$STATE_DIR" || return 1
    python3 -I - <<'LOCK'
import fcntl
import sys
import time

deadline = time.monotonic() + 10
while True:
    try:
        fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.monotonic() >= deadline:
            sys.exit("ERROR: Timed out waiting for the workflow state writer")
        time.sleep(0.05)
LOCK
}

# Initialize state file with default structure
init_state() (
    mkdir -p "$STATE_DIR" || return 1
    state_writer_lock || return 1
    if [[ ( -e "$STATE_FILE" || -L "$STATE_FILE" ) && ! -f "$STATE_FILE" ]]; then
        printf 'ERROR: State destination is not a regular file: %s\n' "$STATE_FILE" >&2
        return 1
    fi
    mkdir -p "$STATE_DIR/context" "$STATE_DIR/summaries" "$STATE_DIR/quick" || return 1

    # If state file already exists, validate it
    if [ -f "$STATE_FILE" ]; then
        if jq empty "$STATE_FILE" 2>/dev/null; then
            success "State file already exists and is valid"
            return 0
        else
            warning "State file is corrupted, backing up and recreating"
            local backup_timestamp recovery_file
            backup_timestamp="$(date +%s)" || return 1
            recovery_file="$(mktemp "${STATE_FILE}.corrupt.${backup_timestamp}.XXXXXX")" || return 1
            if ! mv "$STATE_FILE" "$recovery_file"; then
                rm -f "$recovery_file"
                return 1
            fi
        fi
    fi

    # Generate a stable project ID without assuming GNU md5sum is installed.
    local project_id session_start
    project_id="$(state_project_id "${OCTOPUS_STATE_PROJECT_ROOT:-$PWD}")" || return 1
    [[ -n "$project_id" ]] || return 1
    session_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 1

    # Prepare the JSON before publishing it so readers see a complete file.
    local initial_state
    initial_state="$(cat <<EOF
{
  "version": "1.0.0",
  "project_id": "$project_id",
  "current_workflow": null,
  "current_phase": null,
  "session_start": "$session_start",
  "decisions": [],
  "blockers": [],
  "context": {
    "discover": null,
    "define": null,
    "develop": null,
    "deliver": null
  },
  "metrics": {
    "phases_completed": 0,
    "total_execution_time_minutes": 0,
    "provider_usage": {
      "codex": 0,
      "agy": 0,
      "perplexity": 0,
      "claude": 0
    }
  }
}
EOF
)" || return 1
    atomic_write "$initial_state" || return 1
    success "Initialized state file at $STATE_FILE"
)

# Read and display current state
read_state() {
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        error "State file is corrupted"
    fi

    cat "$STATE_FILE"
}

# Get current phase
get_current_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "null"
        return
    fi

    jq -r '.current_phase // "null"' "$STATE_FILE"
}

# Get current workflow
get_current_workflow() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "null"
        return
    fi

    jq -r '.current_workflow // "null"' "$STATE_FILE"
}

# Atomic write helper (prevents corruption)
atomic_write() {
    local content="$1" temp_file
    temp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")" || return 1
    if ! printf '%s\n' "$content" > "$temp_file" ||
       ! jq -es 'length == 1 and (.[0] | type == "object")' "$temp_file" >/dev/null; then
        rm -f "$temp_file"
        printf '%s\n' 'ERROR: Could not prepare valid workflow state JSON' >&2
        return 1
    fi
    if [ -f "$STATE_FILE" ] && ! cp "$STATE_FILE" "$BACKUP_FILE"; then
        rm -f "$temp_file"
        return 1
    fi
    if ! mv "$temp_file" "$STATE_FILE"; then
        rm -f "$temp_file"
        return 1
    fi
}

# Set current workflow and phase
set_current_workflow() (
    local workflow="$1"
    local phase="${2:-null}"

    state_writer_lock || return 1
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    updated=$(jq --arg workflow "$workflow" --arg phase "$phase" \
        '.current_workflow = $workflow | .current_phase = $phase' \
        "$STATE_FILE") || return 1

    atomic_write "$updated" || return 1
    success "Set current workflow to '$workflow', phase to '$phase'"
)

# Write a decision
write_decision() (
    local phase="$1"
    local decision="$2"
    local rationale="$3"
    local commit="${4:-$(git rev-parse HEAD 2>/dev/null || echo 'none')}"

    state_writer_lock || return 1
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local decision_obj day
    day="$(date -u +%Y-%m-%d)" || return 1
    decision_obj=$(jq -n \
        --arg phase "$phase" \
        --arg decision "$decision" \
        --arg rationale "$rationale" \
        --arg date "$day" \
        --arg commit "$commit" \
        '{phase: $phase, decision: $decision, rationale: $rationale, date: $date, commit: $commit}') || return 1

    local updated
    updated=$(jq --argjson decision "$decision_obj" \
        '.decisions += [$decision]' \
        "$STATE_FILE") || return 1

    atomic_write "$updated" || return 1
    success "Recorded decision for phase '$phase'"
)

# Write a blocker
write_blocker() (
    local description="$1"
    local phase="$2"
    local status="${3:-active}"

    state_writer_lock || return 1
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local blocker_obj day
    day="$(date -u +%Y-%m-%d)" || return 1
    blocker_obj=$(jq -n \
        --arg description "$description" \
        --arg phase "$phase" \
        --arg status "$status" \
        --arg created "$day" \
        '{description: $description, phase: $phase, status: $status, created: $created}') || return 1

    local updated
    updated=$(jq --argjson blocker "$blocker_obj" \
        '.blockers += [$blocker]' \
        "$STATE_FILE") || return 1

    atomic_write "$updated" || return 1
    success "Recorded blocker for phase '$phase'"
)

# Update blocker status
update_blocker_status() (
    local description="$1"
    local new_status="$2"

    state_writer_lock || return 1
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    updated=$(jq --arg desc "$description" --arg status "$new_status" \
        '(.blockers[] | select(.description == $desc) | .status) = $status' \
        "$STATE_FILE") || return 1

    atomic_write "$updated" || return 1
    success "Updated blocker status to '$new_status'"
)

# Update phase context
update_context() (
    local phase="$1"
    local context="$2"

    state_writer_lock || return 1
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    updated=$(jq --arg phase "$phase" --arg context "$context" \
        '.context[$phase] = $context' \
        "$STATE_FILE") || return 1

    atomic_write "$updated" || return 1
    success "Updated context for phase '$phase'"
)

# Get phase context
get_context() {
    local phase="$1"

    if [ ! -f "$STATE_FILE" ]; then
        echo "null"
        return
    fi

    jq -r --arg phase "$phase" '.context[$phase] // "null"' "$STATE_FILE"
}

# Update metrics
update_metrics() (
    local metric_type="$1"
    local value="$2"

    state_writer_lock || return 1
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    case "$metric_type" in
        "phases_completed")
            updated=$(jq '.metrics.phases_completed += 1' "$STATE_FILE") || return 1
            ;;
        "execution_time")
            updated=$(jq --argjson time "$value" \
                '.metrics.total_execution_time_minutes += $time' \
                "$STATE_FILE") || return 1
            ;;
        "provider")
            local provider="$value"
            updated=$(jq --arg provider "$provider" \
                '.metrics.provider_usage[$provider] += 1' \
                "$STATE_FILE") || return 1
            ;;
        *)
            error "Unknown metric type: $metric_type"
            ;;
    esac

    atomic_write "$updated" || return 1
    success "Updated metric '$metric_type'"
)

# Get all decisions for a phase
get_decisions() {
    local phase="${1:-all}"

    if [ ! -f "$STATE_FILE" ]; then
        echo "[]"
        return
    fi

    if [ "$phase" = "all" ]; then
        jq -r '.decisions' "$STATE_FILE"
    else
        jq -r --arg phase "$phase" '.decisions[] | select(.phase == $phase)' "$STATE_FILE"
    fi
}

# Get active blockers
get_active_blockers() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "[]"
        return
    fi

    jq -r '.blockers[] | select(.status == "active")' "$STATE_FILE"
}

# Display state summary
show_summary() {
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local summary
    summary=$(jq -ser '
        if length != 1 then error("Expected one state document") else .[0] end |
        if (.blockers | type) != "array" then error("Expected a blocker array") else . end |
        [
        "=== Claude Octopus State Summary ===", "",
        "Project ID: \(.project_id)",
        "Session Start: \(.session_start)",
        "Current Workflow: \(.current_workflow // "none")",
        "Current Phase: \(.current_phase // "none")", "",
        "Metrics:",
        "  Phases Completed: \(.metrics.phases_completed)",
        "  Execution Time: \(.metrics.total_execution_time_minutes) minutes",
        "  Provider Usage:",
        "    - Codex: \(.metrics.provider_usage.codex)",
        "    - Antigravity: \(.metrics.provider_usage.agy // 0)",
        "    - Perplexity: \(.metrics.provider_usage.perplexity // 0)",
        "    - Claude: \(.metrics.provider_usage.claude)", "",
        "Decisions: \(.decisions | length)",
        "Active Blockers: \([.blockers[] | select(.status == "active")] | length)"
    ] | .[]' "$STATE_FILE") || return 1
    printf '%s\n' "$summary"
}

# v8.14.0: Generate human-readable STATE.md from state.json
write_state_md() {
    if [ ! -f "$STATE_FILE" ]; then
        return 0
    fi

    local state_md="$STATE_DIR/STATE.md"
    local wf ph start pc et

    wf=$(jq -r '.current_workflow // "none"' "$STATE_FILE")
    ph=$(jq -r '.current_phase // "none"' "$STATE_FILE")
    start=$(jq -r '.session_start // "unknown"' "$STATE_FILE")
    pc=$(jq -r '.metrics.phases_completed // 0' "$STATE_FILE")
    et=$(jq -r '.metrics.total_execution_time_minutes // 0' "$STATE_FILE")

    local provider_usage decisions active_blockers phase_context

    provider_usage=$(jq -r '.metrics.provider_usage | to_entries[] | "- **\(.key):** \(.value) calls"' "$STATE_FILE" 2>/dev/null || echo "None tracked.")
    decisions=$(jq -r '.decisions[] | "- [\(.phase)] \(.decision) — \(.rationale) (\(.date))"' "$STATE_FILE" 2>/dev/null || echo "None yet.")
    active_blockers=$(jq -r '.blockers[] | select(.status == "active") | "- [\(.phase)] \(.description) (since \(.created))"' "$STATE_FILE" 2>/dev/null || echo "None.")
    phase_context=$(jq -r '.context | to_entries[] | select(.value != null) | "### \(.key | ascii_upcase)\n\(.value)\n"' "$STATE_FILE" 2>/dev/null || echo "No context captured yet.")

    cat > "$state_md" << STATEMD
# Project State

**Last updated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Current Position

- **Workflow:** $wf
- **Phase:** $ph
- **Session start:** $start
- **Phases completed:** $pc
- **Execution time:** ${et} minutes

## Provider Usage

$provider_usage

## Decisions

$decisions

## Active Blockers

$active_blockers

## Phase Context

$(echo -e "$phase_context")

## Recent Structured Decisions
$(if [[ -f "${STATE_DIR}/../.octo/decisions.md" ]]; then tail -60 "${STATE_DIR}/../.octo/decisions.md" 2>/dev/null || echo "No structured decisions recorded."; else echo "No structured decisions recorded."; fi)
STATEMD
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init_state)
            init_state
            ;;
        read_state)
            read_state
            ;;
        state_path)
            printf '%s\n' "$STATE_FILE"
            ;;
        handoff_path)
            if [[ -n "${OCTOPUS_WORKFLOW_STATE_DIR:-}" ]]; then
                # An explicit directory is already stable and remains authoritative.
                printf '%s\n' "$STATE_DIR/discovery-handoff.json"
            else
                python3 "$(dirname "${BASH_SOURCE[0]}")/helpers/discovery-handoff.py" locate "$(resolve_octopus_workspace)" "$STATE_FILE"
            fi
            ;;
        get_current_phase)
            get_current_phase
            ;;
        get_current_workflow)
            get_current_workflow
            ;;
        set_current_workflow)
            set_current_workflow "$@"
            ;;
        write_decision)
            write_decision "$@"
            ;;
        write_blocker)
            write_blocker "$@"
            ;;
        update_blocker_status)
            update_blocker_status "$@"
            ;;
        update_context)
            update_context "$@"
            ;;
        get_context)
            get_context "$@"
            ;;
        update_metrics)
            update_metrics "$@"
            ;;
        get_decisions)
            get_decisions "$@"
            ;;
        get_active_blockers)
            get_active_blockers
            ;;
        show_summary)
            show_summary
            ;;
        write_state_md)
            write_state_md
            ;;
        help)
            cat <<EOF
Claude Octopus State Manager

Usage: state-manager.sh <command> [args]

Commands:
  init_state                                  Initialize state file
  read_state                                  Display current state (JSON)
  state_path                                  Display the resolved state file path
  get_current_phase                           Get current phase
  handoff_path                                Resolve stable discovery state, adopting legacy records
  get_current_workflow                        Get current workflow
  set_current_workflow <workflow> [phase]     Set current workflow and phase
  write_decision <phase> <decision> <rationale> [commit]
                                              Record a decision
  write_blocker <description> <phase> [status]
                                              Record a blocker
  update_blocker_status <description> <status>
                                              Update blocker status
  update_context <phase> <context>            Update phase context
  get_context <phase>                         Get phase context
  update_metrics <type> <value>               Update metrics
                                              Types: phases_completed, execution_time, provider
  get_decisions [phase]                       Get decisions (all or by phase)
  get_active_blockers                         Get active blockers
  show_summary                                Display state summary
  write_state_md                              Generate human-readable STATE.md
  help                                        Show this help

Examples:
  state-manager.sh init_state
  state-manager.sh write_decision "define" "React 19" "Modern DX"
  state-manager.sh update_context "discover" "researched auth patterns"
  state-manager.sh update_metrics "provider" "agy"
  state-manager.sh show_summary
EOF
            ;;
        *)
            error "Unknown command: $command. Run 'state-manager.sh help' for usage."
            ;;
    esac
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
