#!/usr/bin/env bash
# Context file management for Claude Octopus
# Manages phase context files that capture user vision and decisions

set -euo pipefail

# Configuration
CONTEXT_DIR=".claude-octopus/context"

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

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

# Initialize context directory
init_context_dir() {
    mkdir -p "$CONTEXT_DIR"
    success "Context directory initialized at $CONTEXT_DIR"
}

# Create a context file for a workflow
create_context() {
    local workflow="$1"
    local content="$2"

    if [ -z "$workflow" ]; then
        error "Workflow name required"
    fi

    if [ -z "$content" ]; then
        error "Content required"
    fi

    # Ensure directory exists
    mkdir -p "$CONTEXT_DIR"

    local context_file="${CONTEXT_DIR}/${workflow}-context.md"

    # Write content
    echo "$content" > "$context_file"

    success "Created context file: $context_file"
}

# Read a context file
read_context() {
    local workflow="$1"

    if [ -z "$workflow" ]; then
        error "Workflow name required"
    fi

    local context_file="${CONTEXT_DIR}/${workflow}-context.md"

    if [ ! -f "$context_file" ]; then
        echo "null"
        return
    fi

    cat "$context_file"
}

# Update an existing context file
update_context() {
    local workflow="$1"
    local new_content="$2"

    if [ -z "$workflow" ]; then
        error "Workflow name required"
    fi

    if [ -z "$new_content" ]; then
        error "Content required"
    fi

    local context_file="${CONTEXT_DIR}/${workflow}-context.md"

    # Backup existing file if it exists
    if [ -f "$context_file" ]; then
        cp "$context_file" "${context_file}.backup"
    fi

    # Write new content
    echo "$new_content" > "$context_file"

    success "Updated context file: $context_file"
}

# Append to an existing context file
append_context() {
    local workflow="$1"
    local content="$2"

    if [ -z "$workflow" ]; then
        error "Workflow name required"
    fi

    if [ -z "$content" ]; then
        error "Content required"
    fi

    local context_file="${CONTEXT_DIR}/${workflow}-context.md"

    # Ensure file exists
    if [ ! -f "$context_file" ]; then
        error "Context file does not exist: $context_file"
    fi

    # Append content
    echo "" >> "$context_file"
    echo "$content" >> "$context_file"

    success "Appended to context file: $context_file"
}

# Delete a context file
delete_context() {
    local workflow="$1"

    if [ -z "$workflow" ]; then
        error "Workflow name required"
    fi

    local context_file="${CONTEXT_DIR}/${workflow}-context.md"

    if [ ! -f "$context_file" ]; then
        error "Context file does not exist: $context_file"
    fi

    # Backup before deleting
    cp "$context_file" "${context_file}.deleted.$(date +%s)"
    rm "$context_file"

    success "Deleted context file: $context_file"
}

# List all context files
list_contexts() {
    if [ ! -d "$CONTEXT_DIR" ]; then
        echo "No context files (directory does not exist)"
        return
    fi

    if [ -z "$(ls -A "$CONTEXT_DIR"/*.md 2>/dev/null)" ]; then
        echo "No context files found"
        return
    fi

    echo "Context files in $CONTEXT_DIR:"
    ls -lh "$CONTEXT_DIR"/*.md 2>/dev/null | awk '{print $9, "(" $5 ")"}'
}

# Create a templated context file with standard sections
create_templated_context() {
    local workflow="$1"
    local title="$2"
    local user_vision="${3:-Not specified}"
    local approach="${4:-Not specified}"
    local scope_in="${5:-To be determined}"
    local scope_out="${6:-To be determined}"

    if [ -z "$workflow" ]; then
        error "Workflow name required"
    fi

    if [ -z "$title" ]; then
        error "Title required"
    fi

    local context_file="${CONTEXT_DIR}/${workflow}-context.md"

    # Ensure directory exists
    mkdir -p "$CONTEXT_DIR"

    # Create context file with printf to avoid heredoc issues
    {
        echo "# Context: $title"
        echo ""
        echo "## User Vision"
        echo "$user_vision"
        echo ""
        echo "## Technical Approach"
        echo "$approach"
        echo ""
        echo "## Scope"
        echo ""
        echo "**In Scope:**"
        echo "$scope_in"
        echo ""
        echo "**Out of Scope:**"
        echo "$scope_out"
        echo ""
        echo "## Decisions Made"
        echo "[Key decisions will be added here]"
        echo ""
        echo "---"
        echo "*Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)*"
    } > "$context_file"

    success "Created templated context file: $context_file"
}

# Display help
show_help() {
    cat <<EOF
Claude Octopus Context Manager

Usage: context-manager.sh <command> [args]

Commands:
  init_context_dir                              Initialize context directory
  create_context <workflow> <content>           Create context file
  read_context <workflow>                       Read context file
  update_context <workflow> <content>           Update context file
  append_context <workflow> <content>           Append to context file
  delete_context <workflow>                     Delete context file
  list_contexts                                 List all context files
  create_templated_context <workflow> <title> [vision] [approach] [scope_in] [scope_out]
                                                Create templated context file
  help                                          Show this help

Examples:
  context-manager.sh init_context_dir
  context-manager.sh create_context "define" "User wants JWT auth"
  context-manager.sh read_context "define"
  context-manager.sh create_templated_context "define" "User Authentication" "Passwordless magic links"
  context-manager.sh list_contexts
EOF
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init_context_dir)
            init_context_dir
            ;;
        create_context)
            create_context "$@"
            ;;
        read_context)
            read_context "$@"
            ;;
        update_context)
            update_context "$@"
            ;;
        append_context)
            append_context "$@"
            ;;
        delete_context)
            delete_context "$@"
            ;;
        list_contexts)
            list_contexts
            ;;
        create_templated_context)
            create_templated_context "$@"
            ;;
        help)
            show_help
            ;;
        *)
            error "Unknown command: $command. Run 'context-manager.sh help' for usage."
            ;;
    esac
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
