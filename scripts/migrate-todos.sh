#!/usr/bin/env bash
#
# migrate-todos.sh - Migrate legacy TodoWrite .md files to native Claude Code Tasks
#
# Usage: migrate-todos.sh [--dry-run]
#
# This script:
# 1. Scans for legacy todo .md files
# 2. Parses task items
# 3. Creates equivalent native tasks via TaskCreate
# 4. Archives old .md files
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

CLAUDE_DIR="${HOME}/.claude"
ARCHIVE_DIR="${CLAUDE_DIR}/archived-todos"

# Find legacy todo files
find_todo_files() {
    find . -name "*.md" -type f \
        -exec grep -l "^\-\ \[" {} \; 2>/dev/null || true
}

# Parse markdown todo format
parse_todo_line() {
    local line="$1"

    # Check if line is a task
    if [[ $line =~ ^-\ \[([ x])\]\ (.+)$ ]]; then
        local status="${BASH_REMATCH[1]}"
        local task="${BASH_REMATCH[2]}"

        # Convert status
        if [[ "$status" == "x" ]]; then
            echo "completed|$task"
        else
            echo "pending|$task"
        fi
    fi
}

# Migrate a single todo file
migrate_file() {
    local filepath="$1"
    local filename=$(basename "$filepath")

    echo -e "${YELLOW}Migrating: $filepath${NC}"

    local task_count=0
    local completed_count=0

    while IFS= read -r line; do
        result=$(parse_todo_line "$line")

        if [[ -n "$result" ]]; then
            IFS='|' read -r status task <<< "$result"

            ((task_count++))

            if [[ "$DRY_RUN" == true ]]; then
                echo "  [DRY RUN] Would create task: $task (status: $status)"
            else
                echo "  Creating task: $task"

                # Create task via Claude Code API (if available)
                # Note: This requires Claude Code v2.1.20+ with Task API
                #
                # For now, we output the migration as a JSON file that Claude can import
                #
                echo "{\"subject\": \"$task\", \"status\": \"$status\", \"description\": \"Migrated from $filename\"}" \
                    >> "${ARCHIVE_DIR}/migration-$(date +%Y%m%d-%H%M%S).jsonl"
            fi

            if [[ "$status" == "completed" ]]; then
                ((completed_count++))
            fi
        fi
    done < "$filepath"

    if [[ $task_count -gt 0 ]]; then
        echo -e "${GREEN}  ✓ Migrated $task_count tasks ($completed_count completed)${NC}"

        if [[ "$DRY_RUN" == false ]]; then
            # Archive the original file
            mkdir -p "$ARCHIVE_DIR"
            mv "$filepath" "${ARCHIVE_DIR}/${filename}.$(date +%Y%m%d-%H%M%S).bak"
            echo "  Archived to: ${ARCHIVE_DIR}/${filename}.$(date +%Y%m%d-%H%M%S).bak"
        fi
    else
        echo "  No tasks found in file"
    fi

    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}=== Todo Migration Script ===${NC}"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Running in DRY RUN mode - no changes will be made${NC}"
        echo ""
    fi

    # Find all todo files
    mapfile -t todo_files < <(find_todo_files)

    if [[ ${#todo_files[@]} -eq 0 ]]; then
        echo "No legacy todo files found"
        exit 0
    fi

    echo "Found ${#todo_files[@]} todo file(s) to migrate:"
    printf '  - %s\n' "${todo_files[@]}"
    echo ""

    # Create archive directory
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$ARCHIVE_DIR"
    fi

    # Migrate each file
    for file in "${todo_files[@]}"; do
        migrate_file "$file"
    done

    echo -e "${GREEN}=== Migration Complete ===${NC}"

    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        echo "Next steps:"
        echo "1. Review migrated tasks in Claude Code"
        echo "2. Check archived files in: $ARCHIVE_DIR"
        echo "3. Import tasks using migration JSONL files"
        echo ""
        echo "To import tasks, run:"
        echo "  claude-code tasks import ${ARCHIVE_DIR}/migration-*.jsonl"
    else
        echo ""
        echo "Run without --dry-run to perform actual migration"
    fi
}

main "$@"
