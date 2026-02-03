#!/usr/bin/env bash
# Project-level state management for Claude Octopus
# Manages .octo/ directory with STATE.md, PROJECT.md, ROADMAP.md, etc.

set -eo pipefail

# Configuration
OCTO_DIR=".octo"
STATE_FILE="$OCTO_DIR/STATE.md"
PROJECT_FILE="$OCTO_DIR/PROJECT.md"
ROADMAP_FILE="$OCTO_DIR/ROADMAP.md"
CONFIG_FILE="$OCTO_DIR/config.json"
ISSUES_FILE="$OCTO_DIR/ISSUES.md"
LESSONS_FILE="$OCTO_DIR/LESSONS.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Valid status values
VALID_STATUSES="ready planned planning building in_progress complete complete_with_gaps shipped blocked paused"

# Valid context tiers
VALID_TIERS="minimal planning execution brownfield full auto"

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

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

info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

# Validate phase is an integer >= 1
validate_phase() {
    local phase="$1"
    if ! [[ "$phase" =~ ^[0-9]+$ ]] || [[ "$phase" -lt 1 ]]; then
        error "Phase must be a positive integer (got: '$phase')"
    fi
}

# Validate status is in enum
validate_status() {
    local status="$1"
    local found=false
    for valid in $VALID_STATUSES; do
        if [[ "$status" == "$valid" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" != "true" ]]; then
        error "Invalid status '$status'. Valid values: $VALID_STATUSES"
    fi
}

# Validate tier is in enum
validate_tier() {
    local tier="$1"
    local found=false
    for valid in $VALID_TIERS; do
        if [[ "$tier" == "$valid" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" != "true" ]]; then
        error "Invalid tier '$tier'. Valid values: $VALID_TIERS"
    fi
}

# Get current timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ATOMIC WRITE
# ═══════════════════════════════════════════════════════════════════════════════

atomic_write() {
    local target_file="$1"
    local content="$2"
    local temp_file="${target_file}.tmp.$$"
    
    # Ensure directory exists
    mkdir -p "$(dirname "$target_file")"
    
    # Write to temp file
    echo "$content" > "$temp_file"
    
    # Verify temp file was written
    if [[ ! -f "$temp_file" ]]; then
        error "Failed to write temporary file"
    fi
    
    # Atomic move
    mv "$temp_file" "$target_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEMPLATE FILES
# ═══════════════════════════════════════════════════════════════════════════════

generate_state_template() {
    local timestamp
    timestamp=$(get_timestamp)
    cat <<EOF
# Octo State

**Schema:** 2.0
**Last Updated:** $timestamp
**Current Phase:** 1
**Current Position:** Project initialized
**Status:** ready

## Blockers

(none)

## History

- [$timestamp] Phase 1: Project initialized (ready)
EOF
}

generate_project_template() {
    cat <<EOF
# Project

## Vision

(Describe the project's purpose and goals)

## Requirements

### Functional Requirements

- [ ] Requirement 1
- [ ] Requirement 2

### Non-Functional Requirements

- [ ] Performance targets
- [ ] Security requirements

## Constraints

- Timeline: (specify)
- Resources: (specify)
- Technical: (specify)

## Decisions

| Date | Decision | Rationale | Impact |
|------|----------|-----------|--------|
| | | | |
EOF
}

generate_roadmap_template() {
    cat <<EOF
# Roadmap

## Overview

Total Phases: 1
Current Phase: 1

## Phase 1: Initial Setup

**Status:** ready
**Success Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

**Dependencies:** None

**Plans:**
(To be defined)

## Milestone Deliverables

- [ ] Deliverable 1
- [ ] Deliverable 2
EOF
}

generate_config_template() {
    local timestamp
    timestamp=$(get_timestamp)
    cat <<EOF
{
  "interaction_mode": "interactive",
  "git_strategy": "per_task",
  "review_depth": "detailed",
  "security_audit": true,
  "simplification_review": true,
  "iac_validation": "auto",
  "documentation_generation": true,
  "codebase_docs_path": ".octo/codebase",
  "model_routing": {
    "validation": "haiku",
    "building": "sonnet",
    "planning": "sonnet",
    "architecture": "opus",
    "debugging": "opus",
    "review": "sonnet",
    "security_audit": "sonnet"
  },
  "context_tier": "auto",
  "created_at": "$timestamp",
  "version": "1.0"
}
EOF
}

generate_issues_template() {
    cat <<EOF
# Issues

## Active

(none)

## Resolved

(none)
EOF
}

generate_lessons_template() {
    cat <<EOF
# Lessons Learned

## Technical

(none yet)

## Process

(none yet)

## Architecture

(none yet)
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# INIT_PROJECT
# ═══════════════════════════════════════════════════════════════════════════════

init_project() {
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done
    
    if [[ "$dry_run" == "true" ]]; then
        echo "DRY RUN: Would create the following structure:"
        echo ""
        echo "$OCTO_DIR/"
        echo "├── STATE.md        # Current session position, status, history"
        echo "├── PROJECT.md      # Project vision, requirements, constraints"
        echo "├── ROADMAP.md      # Phase structure, success criteria, dependencies"
        echo "├── config.json     # Configuration (interaction mode, git strategy, etc.)"
        echo "├── ISSUES.md       # Active and resolved issues"
        echo "├── LESSONS.md      # Lessons learned"
        echo "├── phases/         # Phase-specific plans and summaries"
        echo "└── codebase/       # Codebase analysis (brownfield projects)"
        echo ""
        echo "To create: ./octo-state.sh init_project"
        return 0
    fi
    
    # Check if already initialized
    if [[ -d "$OCTO_DIR" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            warning ".octo/ directory already exists. Use 'read_state' to view current state."
            return 0
        fi
    fi
    
    # Create directory structure
    mkdir -p "$OCTO_DIR"
    mkdir -p "$OCTO_DIR/phases"
    mkdir -p "$OCTO_DIR/codebase"
    
    # Generate template files
    atomic_write "$STATE_FILE" "$(generate_state_template)"
    atomic_write "$PROJECT_FILE" "$(generate_project_template)"
    atomic_write "$ROADMAP_FILE" "$(generate_roadmap_template)"
    atomic_write "$CONFIG_FILE" "$(generate_config_template)"
    atomic_write "$ISSUES_FILE" "$(generate_issues_template)"
    atomic_write "$LESSONS_FILE" "$(generate_lessons_template)"
    
    success "Initialized .octo/ directory with template files"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $PROJECT_FILE with your project vision and requirements"
    echo "  2. Edit $ROADMAP_FILE with your phase breakdown"
    echo "  3. Run 'octo-state.sh read_state' to view current state"
}

# ═══════════════════════════════════════════════════════════════════════════════
# READ_STATE
# ═══════════════════════════════════════════════════════════════════════════════

read_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "State file not found. Run 'init_project' first."
    fi
    
    # Parse STATE.md fields
    local schema last_updated current_phase current_position status
    
    schema=$(grep -E "^\*\*Schema:\*\*" "$STATE_FILE" | sed 's/\*\*Schema:\*\* //' || echo "unknown")
    last_updated=$(grep -E "^\*\*Last Updated:\*\*" "$STATE_FILE" | sed 's/\*\*Last Updated:\*\* //' || echo "unknown")
    current_phase=$(grep -E "^\*\*Current Phase:\*\*" "$STATE_FILE" | sed 's/\*\*Current Phase:\*\* //' || echo "0")
    current_position=$(grep -E "^\*\*Current Position:\*\*" "$STATE_FILE" | sed 's/\*\*Current Position:\*\* //' || echo "unknown")
    status=$(grep -E "^\*\*Status:\*\*" "$STATE_FILE" | sed 's/\*\*Status:\*\* //' || echo "unknown")
    
    # Output as simple key=value pairs for easy parsing
    echo "schema=$schema"
    echo "last_updated=$last_updated"
    echo "current_phase=$current_phase"
    echo "current_position=$current_position"
    echo "status=$status"
}

# ═══════════════════════════════════════════════════════════════════════════════
# WRITE_STATE
# ═══════════════════════════════════════════════════════════════════════════════

write_state() {
    local phase=""
    local position=""
    local status=""
    local blocker=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                phase="$2"
                shift 2
                ;;
            --position)
                position="$2"
                shift 2
                ;;
            --status)
                status="$2"
                shift 2
                ;;
            --blocker)
                blocker="$2"
                shift 2
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done
    
    if [[ ! -f "$STATE_FILE" ]]; then
        error "State file not found. Run 'init_project' first."
    fi
    
    # Read current state
    local current_schema current_phase_val current_position_val current_status
    current_schema=$(grep -E "^\*\*Schema:\*\*" "$STATE_FILE" | sed 's/\*\*Schema:\*\* //' || echo "2.0")
    current_phase_val=$(grep -E "^\*\*Current Phase:\*\*" "$STATE_FILE" | sed 's/\*\*Current Phase:\*\* //' || echo "1")
    current_position_val=$(grep -E "^\*\*Current Position:\*\*" "$STATE_FILE" | sed 's/\*\*Current Position:\*\* //' || echo "unknown")
    current_status=$(grep -E "^\*\*Status:\*\*" "$STATE_FILE" | sed 's/\*\*Status:\*\* //' || echo "ready")
    
    # Extract existing history (everything after "## History")
    local history
    history=$(sed -n '/^## History/,$ p' "$STATE_FILE" | tail -n +2 || echo "")
    
    # Use provided values or keep current
    local new_phase="${phase:-$current_phase_val}"
    local new_position="${position:-$current_position_val}"
    local new_status="${status:-$current_status}"
    
    # Validate inputs
    validate_phase "$new_phase"
    validate_status "$new_status"
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Build blocker section
    local blocker_section="(none)"
    if [[ -n "$blocker" ]]; then
        blocker_section="- $blocker"
    fi
    
    # Build new history entry
    local new_history_entry="- [$timestamp] Phase $new_phase: $new_position ($new_status)"
    
    # Generate new STATE.md content
    local new_content
    new_content=$(cat <<EOF
# Octo State

**Schema:** $current_schema
**Last Updated:** $timestamp
**Current Phase:** $new_phase
**Current Position:** $new_position
**Status:** $new_status

## Blockers

$blocker_section

## History

$new_history_entry
$history
EOF
)
    
    atomic_write "$STATE_FILE" "$new_content"
    success "Updated STATE.md (phase=$new_phase, status=$new_status)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# UPDATE_PHASE
# ═══════════════════════════════════════════════════════════════════════════════

update_phase() {
    local phase="$1"
    local position="${2:-Phase $phase started}"
    local status="${3:-in_progress}"
    
    if [[ -z "$phase" ]]; then
        error "Phase number required. Usage: update_phase <phase> [position] [status]"
    fi
    
    validate_phase "$phase"
    validate_status "$status"
    
    write_state --phase "$phase" --position "$position" --status "$status"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GET_CONTEXT_TIER
# ═══════════════════════════════════════════════════════════════════════════════

get_context_tier() {
    local tier="${1:-auto}"
    
    validate_tier "$tier"
    
    # If auto, determine tier from status
    if [[ "$tier" == "auto" ]]; then
        if [[ ! -f "$STATE_FILE" ]]; then
            tier="minimal"
        else
            local status
            status=$(grep -E "^\*\*Status:\*\*" "$STATE_FILE" | sed 's/\*\*Status:\*\* //' || echo "ready")
            
            case "$status" in
                ready|planned|planning|complete|shipped)
                    tier="planning"
                    ;;
                building|in_progress)
                    tier="execution"
                    ;;
                blocked|paused)
                    tier="execution"
                    ;;
                *)
                    tier="planning"
                    ;;
            esac
        fi
    fi
    
    echo "=== Context Tier: $tier ==="
    echo ""
    
    case "$tier" in
        minimal)
            # ~300 tokens: STATE.md only
            if [[ -f "$STATE_FILE" ]]; then
                echo "### STATE.md"
                cat "$STATE_FILE"
            else
                echo "(STATE.md not found)"
            fi
            ;;
        planning)
            # ~1200 tokens: STATE.md + PROJECT.md + ROADMAP.md (first 80 lines)
            if [[ -f "$STATE_FILE" ]]; then
                echo "### STATE.md"
                cat "$STATE_FILE"
                echo ""
            fi
            if [[ -f "$PROJECT_FILE" ]]; then
                echo "### PROJECT.md"
                cat "$PROJECT_FILE"
                echo ""
            fi
            if [[ -f "$ROADMAP_FILE" ]]; then
                echo "### ROADMAP.md (first 80 lines)"
                head -n 80 "$ROADMAP_FILE"
                echo ""
            fi
            ;;
        execution)
            # ~2000 tokens: planning + phase plans + recent summaries
            if [[ -f "$STATE_FILE" ]]; then
                echo "### STATE.md"
                cat "$STATE_FILE"
                echo ""
            fi
            if [[ -f "$PROJECT_FILE" ]]; then
                echo "### PROJECT.md"
                cat "$PROJECT_FILE"
                echo ""
            fi
            if [[ -f "$ROADMAP_FILE" ]]; then
                echo "### ROADMAP.md (first 80 lines)"
                head -n 80 "$ROADMAP_FILE"
                echo ""
            fi
            # Phase plans (first 50 lines each, max 3)
            local plan_count=0
            for plan in "$OCTO_DIR"/phases/phase-*-plan.md; do
                if [[ -f "$plan" ]] && [[ $plan_count -lt 3 ]]; then
                    echo "### $(basename "$plan") (first 50 lines)"
                    head -n 50 "$plan"
                    echo ""
                    ((plan_count++))
                fi
            done
            # Recent summaries (first 30 lines each, max 3)
            local summary_count=0
            for summary in "$OCTO_DIR"/phases/phase-*-summary.md; do
                if [[ -f "$summary" ]] && [[ $summary_count -lt 3 ]]; then
                    echo "### $(basename "$summary") (first 30 lines)"
                    head -n 30 "$summary"
                    echo ""
                    ((summary_count++))
                fi
            done
            ;;
        brownfield)
            # ~3500 tokens: execution + codebase analysis
            # First output execution tier
            get_context_tier "execution" 2>/dev/null | tail -n +3  # Skip header
            
            # Add codebase analysis
            for doc in STACK.md ARCHITECTURE.md CONVENTIONS.md CONCERNS.md; do
                if [[ -f "$OCTO_DIR/codebase/$doc" ]]; then
                    echo "### codebase/$doc (first 40 lines)"
                    head -n 40 "$OCTO_DIR/codebase/$doc"
                    echo ""
                fi
            done
            ;;
        full)
            # ~6000+ tokens: everything in .octo/
            echo "### Full Context (all .octo/ files)"
            echo ""
            for file in "$OCTO_DIR"/*.md "$OCTO_DIR"/*.json; do
                if [[ -f "$file" ]]; then
                    echo "#### $(basename "$file")"
                    cat "$file"
                    echo ""
                fi
            done
            # All phase plans and summaries
            for file in "$OCTO_DIR"/phases/*.md; do
                if [[ -f "$file" ]]; then
                    echo "#### phases/$(basename "$file")"
                    cat "$file"
                    echo ""
                fi
            done
            # All codebase docs
            for file in "$OCTO_DIR"/codebase/*.md; do
                if [[ -f "$file" ]]; then
                    echo "#### codebase/$(basename "$file")"
                    cat "$file"
                    echo ""
                fi
            done
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELP
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    cat <<EOF
Octo State Manager - Project-level state management for Claude Octopus

Usage: octo-state.sh <command> [options]

Commands:
  init_project [--dry-run]           Initialize .octo/ directory with template files
                                     --dry-run: Show what would be created without making changes

  read_state                         Read and parse .octo/STATE.md
                                     Returns key=value pairs for easy scripting

  write_state [options]              Update .octo/STATE.md with atomic write
                                     --phase <N>        Set current phase (positive integer)
                                     --position <text>  Set current position description
                                     --status <status>  Set status (see valid values below)
                                     --blocker <text>   Set blocker description

  update_phase <phase> [position] [status]
                                     Shorthand for updating phase with position and status
                                     Defaults: position="Phase N started", status="in_progress"

  get_context_tier [tier]            Return context based on tier
                                     Tiers: minimal, planning, execution, brownfield, full, auto
                                     Default: auto (detects from status)

  help                               Show this help message

Valid Status Values:
  ready              - Phase initialized, ready to plan
  planned            - Phase decomposed into plans
  planning           - Planning in progress
  building           - Build in progress
  in_progress        - Execution in progress
  complete           - Phase complete, all gates passed
  complete_with_gaps - Phase complete but with known gaps
  shipped            - Milestone delivered
  blocked            - Workflow blocked by external issue
  paused             - Workflow paused by user

Context Tiers:
  minimal   (~300 tokens)   - STATE.md only
  planning  (~1200 tokens)  - + PROJECT.md + ROADMAP.md (first 80 lines)
  execution (~2000 tokens)  - + phase plans + recent summaries
  brownfield (~3500 tokens) - + codebase analysis
  full      (~6000+ tokens) - everything in .octo/
  auto      (default)       - detect from status field

Examples:
  octo-state.sh init_project --dry-run
  octo-state.sh init_project
  octo-state.sh read_state
  octo-state.sh write_state --phase 2 --status planning --position "Planning phase 2"
  octo-state.sh update_phase 3 "Building authentication module" building
  octo-state.sh get_context_tier planning
  octo-state.sh get_context_tier auto
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        init_project)
            init_project "$@"
            ;;
        read_state)
            read_state
            ;;
        write_state)
            write_state "$@"
            ;;
        update_phase)
            update_phase "$@"
            ;;
        get_context_tier)
            get_context_tier "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command. Run 'octo-state.sh help' for usage."
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
