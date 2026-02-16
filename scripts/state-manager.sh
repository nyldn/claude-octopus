#!/usr/bin/env bash
# State management utilities for Claude Octopus
# Provides persistent state tracking across sessions

set -euo pipefail

# Configuration
STATE_DIR=".claude-octopus"
STATE_FILE="$STATE_DIR/state.json"
BACKUP_FILE="$STATE_DIR/state.json.backup"

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

# Initialize state file with default structure
init_state() {
    # Create directory if it doesn't exist
    mkdir -p "$STATE_DIR"
    mkdir -p "$STATE_DIR/context"
    mkdir -p "$STATE_DIR/summaries"
    mkdir -p "$STATE_DIR/quick"

    # If state file already exists, validate it
    if [ -f "$STATE_FILE" ]; then
        if jq empty "$STATE_FILE" 2>/dev/null; then
            success "State file already exists and is valid"
            return 0
        else
            warning "State file is corrupted, backing up and recreating"
            mv "$STATE_FILE" "${STATE_FILE}.corrupt.$(date +%s)"
        fi
    fi

    # Generate project ID from git remote or directory name
    project_id=$(git config --get remote.origin.url 2>/dev/null | md5sum | cut -d' ' -f1 || echo "$(basename "$PWD")" | md5sum | cut -d' ' -f1)

    # Create initial state
    cat > "$STATE_FILE" <<EOF
{
  "version": "1.0.0",
  "project_id": "$project_id",
  "current_workflow": null,
  "current_phase": null,
  "session_start": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
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
      "gemini": 0,
      "claude": 0
    }
  }
}
EOF

    success "Initialized state file at $STATE_FILE"
}

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
    local content="$1"
    local temp_file="${STATE_FILE}.tmp.$$"

    # Write to temp file
    echo "$content" > "$temp_file"

    # Validate JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        error "Generated invalid JSON, write aborted"
    fi

    # Backup current state
    if [ -f "$STATE_FILE" ]; then
        cp "$STATE_FILE" "$BACKUP_FILE"
    fi

    # Atomic move
    mv "$temp_file" "$STATE_FILE"
}

# Set current workflow and phase
set_current_workflow() {
    local workflow="$1"
    local phase="${2:-null}"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    updated=$(jq --arg workflow "$workflow" --arg phase "$phase" \
        '.current_workflow = $workflow | .current_phase = $phase' \
        "$STATE_FILE")

    atomic_write "$updated"
    success "Set current workflow to '$workflow', phase to '$phase'"
}

# Write a decision
write_decision() {
    local phase="$1"
    local decision="$2"
    local rationale="$3"
    local commit="${4:-$(git rev-parse HEAD 2>/dev/null || echo 'none')}"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local decision_obj
    decision_obj=$(jq -n \
        --arg phase "$phase" \
        --arg decision "$decision" \
        --arg rationale "$rationale" \
        --arg date "$(date -u +%Y-%m-%d)" \
        --arg commit "$commit" \
        '{phase: $phase, decision: $decision, rationale: $rationale, date: $date, commit: $commit}')

    local updated
    updated=$(jq --argjson decision "$decision_obj" \
        '.decisions += [$decision]' \
        "$STATE_FILE")

    atomic_write "$updated"
    success "Recorded decision for phase '$phase'"
}

# Write a blocker
write_blocker() {
    local description="$1"
    local phase="$2"
    local status="${3:-active}"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local blocker_obj
    blocker_obj=$(jq -n \
        --arg description "$description" \
        --arg phase "$phase" \
        --arg status "$status" \
        --arg created "$(date -u +%Y-%m-%d)" \
        '{description: $description, phase: $phase, status: $status, created: $created}')

    local updated
    updated=$(jq --argjson blocker "$blocker_obj" \
        '.blockers += [$blocker]' \
        "$STATE_FILE")

    atomic_write "$updated"
    success "Recorded blocker for phase '$phase'"
}

# Update blocker status
update_blocker_status() {
    local description="$1"
    local new_status="$2"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    updated=$(jq --arg desc "$description" --arg status "$new_status" \
        '(.blockers[] | select(.description == $desc) | .status) = $status' \
        "$STATE_FILE")

    atomic_write "$updated"
    success "Updated blocker status to '$new_status'"
}

# Update phase context
update_context() {
    local phase="$1"
    local context="$2"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    updated=$(jq --arg phase "$phase" --arg context "$context" \
        '.context[$phase] = $context' \
        "$STATE_FILE")

    atomic_write "$updated"
    success "Updated context for phase '$phase'"
}

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
update_metrics() {
    local metric_type="$1"
    local value="$2"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found. Run 'init_state' first."
    fi

    local updated
    case "$metric_type" in
        "phases_completed")
            updated=$(jq '.metrics.phases_completed += 1' "$STATE_FILE")
            ;;
        "execution_time")
            updated=$(jq --argjson time "$value" \
                '.metrics.total_execution_time_minutes += $time' \
                "$STATE_FILE")
            ;;
        "provider")
            local provider="$value"
            updated=$(jq --arg provider "$provider" \
                '.metrics.provider_usage[$provider] += 1' \
                "$STATE_FILE")
            ;;
        *)
            error "Unknown metric type: $metric_type"
            ;;
    esac

    atomic_write "$updated"
    success "Updated metric '$metric_type'"
}

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

    echo "=== Claude Octopus State Summary ==="
    echo ""
    echo "Project ID: $(jq -r '.project_id' "$STATE_FILE")"
    echo "Session Start: $(jq -r '.session_start' "$STATE_FILE")"
    echo "Current Workflow: $(jq -r '.current_workflow // "none"' "$STATE_FILE")"
    echo "Current Phase: $(jq -r '.current_phase // "none"' "$STATE_FILE")"
    echo ""
    echo "Metrics:"
    echo "  Phases Completed: $(jq -r '.metrics.phases_completed' "$STATE_FILE")"
    echo "  Execution Time: $(jq -r '.metrics.total_execution_time_minutes' "$STATE_FILE") minutes"
    echo "  Provider Usage:"
    echo "    - Codex: $(jq -r '.metrics.provider_usage.codex' "$STATE_FILE")"
    echo "    - Gemini: $(jq -r '.metrics.provider_usage.gemini' "$STATE_FILE")"
    echo "    - Claude: $(jq -r '.metrics.provider_usage.claude' "$STATE_FILE")"
    echo ""
    echo "Decisions: $(jq -r '.decisions | length' "$STATE_FILE")"
    echo "Active Blockers: $(jq -r '[.blockers[] | select(.status == "active")] | length' "$STATE_FILE")"
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
  get_current_phase                           Get current phase
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
  state-manager.sh update_metrics "provider" "gemini"
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
