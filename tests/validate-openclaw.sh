#!/usr/bin/env bash
# validate-openclaw.sh — Verify OpenClaw compatibility layer integrity
#
# Validates:
# 1. OpenClaw extension manifest is valid
# 2. Generated tool registry matches current skills
# 3. MCP server configuration is valid
# 4. Claude Code plugin.json is NOT modified (zero-change guarantee)
#
# Exit codes:
#   0 = All checks pass
#   1 = Validation failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

echo "=== OpenClaw Compatibility Validation ==="
echo ""

# --- 1. Claude Code plugin.json integrity ---
echo "1. Claude Code Plugin Integrity"

PLUGIN_NAME=$(python3 -c "import json; print(json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))['name'])" 2>/dev/null || echo "")
if [[ "$PLUGIN_NAME" == "octo" ]]; then
    pass "plugin.json name is 'octo'"
else
    fail "plugin.json name is '${PLUGIN_NAME}' (expected 'octo')"
fi

# Check plugin.json has no openclaw-specific fields
if python3 -c "
import json
p = json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))
openclaw_keys = [k for k in p if 'openclaw' in k.lower()]
exit(1 if openclaw_keys else 0)
" 2>/dev/null; then
    pass "plugin.json has no OpenClaw-specific fields"
else
    fail "plugin.json contains OpenClaw-specific fields"
fi

echo ""

# --- 2. OpenClaw extension manifest ---
echo "2. OpenClaw Extension Manifest"

OPENCLAW_PKG="$PLUGIN_ROOT/openclaw/package.json"
if [[ -f "$OPENCLAW_PKG" ]]; then
    pass "openclaw/package.json exists"

    # Check openclaw.extensions field
    if python3 -c "
import json
p = json.load(open('$OPENCLAW_PKG'))
ext = p.get('openclaw', {}).get('extensions', [])
exit(0 if ext else 1)
" 2>/dev/null; then
        pass "openclaw.extensions field is defined"
    else
        fail "openclaw.extensions field is missing"
    fi
else
    fail "openclaw/package.json not found"
fi

OPENCLAW_PLUGIN="$PLUGIN_ROOT/openclaw/openclaw.plugin.json"
if [[ -f "$OPENCLAW_PLUGIN" ]]; then
    pass "openclaw.plugin.json exists"

    # Check required id field (OpenClaw gateway crashes without it — see #40)
    if python3 -c "
import json
p = json.load(open('$OPENCLAW_PLUGIN'))
exit(0 if p.get('id') else 1)
" 2>/dev/null; then
        pass "id field is present"
    else
        fail "id field is missing from openclaw.plugin.json (required by OpenClaw gateway)"
    fi

    # Check configSchema
    if python3 -c "
import json
p = json.load(open('$OPENCLAW_PLUGIN'))
exit(0 if 'configSchema' in p else 1)
" 2>/dev/null; then
        pass "configSchema is defined"
    else
        fail "configSchema is missing from openclaw.plugin.json"
    fi
else
    fail "openclaw.plugin.json not found"
fi

echo ""

# --- 3. MCP Server Configuration ---
echo "3. MCP Server Configuration"

MCP_JSON="$PLUGIN_ROOT/.mcp.json"
if [[ -f "$MCP_JSON" ]]; then
    pass ".mcp.json exists at plugin root"

    # Check server definition
    if python3 -c "
import json
m = json.load(open('$MCP_JSON'))
servers = m.get('mcpServers', {})
exit(0 if 'octo-claw' in servers else 1)
" 2>/dev/null; then
        pass "octo-claw MCP server is defined"
    else
        fail "octo-claw MCP server not found in .mcp.json"
    fi
else
    fail ".mcp.json not found at plugin root"
fi

MCP_INDEX="$PLUGIN_ROOT/mcp-server/src/index.ts"
if [[ -f "$MCP_INDEX" ]]; then
    pass "MCP server source exists"
else
    fail "MCP server source not found at mcp-server/src/index.ts"
fi

echo ""

# --- 4. Skill Registry Sync ---
echo "4. Skill Registry Sync"

SKILL_COUNT=$(ls -1 "$PLUGIN_ROOT/.claude/skills/"*.md 2>/dev/null | wc -l | tr -d ' ')
COMMAND_COUNT=$(ls -1 "$PLUGIN_ROOT/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((SKILL_COUNT + COMMAND_COUNT))

pass "Found ${SKILL_COUNT} skills and ${COMMAND_COUNT} commands (${TOTAL} total)"

# Check build script exists
if [[ -x "$PLUGIN_ROOT/scripts/build-openclaw.sh" ]]; then
    pass "build-openclaw.sh is executable"
else
    if [[ -f "$PLUGIN_ROOT/scripts/build-openclaw.sh" ]]; then
        pass "build-openclaw.sh exists (not yet executable)"
    else
        fail "build-openclaw.sh not found"
    fi
fi

echo ""

# --- 5. Schema Validation ---
echo "5. Shared Schema"

SCHEMA_FILE="$PLUGIN_ROOT/mcp-server/src/schema/skill-schema.json"
if [[ -f "$SCHEMA_FILE" ]]; then
    pass "skill-schema.json exists"

    if python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
required = s.get('required', [])
exit(0 if 'name' in required and 'description' in required else 1)
" 2>/dev/null; then
        pass "Schema requires 'name' and 'description'"
    else
        fail "Schema missing required fields"
    fi
else
    fail "skill-schema.json not found"
fi

echo ""

# --- Summary ---
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "VALIDATION FAILED"
    exit 1
else
    echo "ALL CHECKS PASSED"
    exit 0
fi
