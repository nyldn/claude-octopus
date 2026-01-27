#!/usr/bin/env bash
# Integration Script for Claude Code v2.1.20 Features
# Patches orchestrate.sh to add Task Management, Session Variables, MCP Detection, etc.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATE_FILE="${SCRIPT_DIR}/orchestrate.sh"
BACKUP_FILE="${ORCHESTRATE_FILE}.backup-$(date +%s)"

echo "Creating backup: $BACKUP_FILE"
cp "$ORCHESTRATE_FILE" "$BACKUP_FILE"

# Create a temporary patch file
PATCH_FILE=$(mktemp)

cat > "$PATCH_FILE" << 'PATCH_EOF'
# ═══════════════════════════════════════════════════════════════════════════
# CLAUDE CODE v2.1.16+ FEATURE INTEGRATION
# Added: Task Management, Session Variables, MCP Detection, Background Permissions
# ═══════════════════════════════════════════════════════════════════════════

# Source helper scripts
TASK_MANAGER="${SCRIPT_DIR}/task-manager.sh"
SESSION_MANAGER="${SCRIPT_DIR}/session-manager.sh"
MCP_DETECTION="${SCRIPT_DIR}/mcp-provider-detection.sh"
PERMISSIONS_MANAGER="${SCRIPT_DIR}/permissions-manager.sh"

# Initialize session variables (v2.1.9+ feature)
init_octopus_session() {
    if [[ -f "$SESSION_MANAGER" ]]; then
        source "$SESSION_MANAGER" export
    fi

    # Export session ID for use in all scripts
    export OCTOPUS_SESSION_ID="${OCTOPUS_SESSION_ID:-octopus-$(date +%s)}"
}

# Check MCP availability and use for provider detection if available
check_providers_with_mcp() {
    if [[ -f "$MCP_DETECTION" ]]; then
        local detection_result=$("$MCP_DETECTION" detect-all)
        echo "$detection_result"
    else
        echo '{"detection_method":"cli","providers":{"codex":{"status":"unknown"},"gemini":{"status":"unknown"},"claude":{"status":"available"}}}'
    fi
}

# Request background permission (v2.1.19+ feature)
request_background_permission_if_needed() {
    local workflow="$1"
    local autonomy="${AUTONOMY_MODE:-supervised}"

    # Skip if not using external CLIs
    if [[ "$USE_EXTERNAL_CLIS" != "true" ]]; then
        return 0
    fi

    if [[ -f "$PERMISSIONS_MANAGER" ]]; then
        if ! "$PERMISSIONS_MANAGER" check "$workflow" "$autonomy" "codex gemini"; then
            return 1
        fi
    fi

    return 0
}

# Create workflow tasks (v2.1.16+ feature)
create_workflow_tasks() {
    local workflow="$1"
    local prompt="$2"

    if [[ ! -f "$TASK_MANAGER" ]]; then
        return 0
    fi

    case "$workflow" in
        embrace)
            "$TASK_MANAGER" create-embrace "$prompt"
            ;;
        probe|discover|grasp|define|tangle|develop|ink|deliver)
            "$TASK_MANAGER" create-phase "$workflow" "$prompt"
            ;;
    esac
}

PATCH_EOF

# Now insert these functions into orchestrate.sh after the initial setup
# We'll add them after line 314 (after the workspace directory setup)

# Read the file line by line and insert our patch
awk -v patch_file="$PATCH_FILE" '
NR == 315 {
    print ""
    print "# ═══════════════════════════════════════════════════════════════════════════"
    print "# CLAUDE CODE v2.1.16+ FEATURE INTEGRATION"
    print "# ═══════════════════════════════════════════════════════════════════════════"
    print ""
    while ((getline line < patch_file) > 0) {
        print line
    }
    close(patch_file)
    print ""
}
{ print }
' "$ORCHESTRATE_FILE" > "${ORCHESTRATE_FILE}.tmp"

mv "${ORCHESTRATE_FILE}.tmp" "$ORCHESTRATE_FILE"

# Clean up
rm -f "$PATCH_FILE"

echo "✅ Integration complete!"
echo "Backup saved at: $BACKUP_FILE"
echo ""
echo "New features added:"
echo "  • Task Management System (v2.1.16+)"
echo "  • Session Variable Tracking (v2.1.9+)"
echo "  • MCP Provider Detection (v2.1.0+)"
echo "  • Background Agent Permissions (v2.1.19+)"
echo ""
echo "Helper scripts created:"
echo "  • scripts/task-manager.sh"
echo "  • scripts/session-manager.sh"
echo "  • scripts/mcp-provider-detection.sh"
echo "  • scripts/permissions-manager.sh"
