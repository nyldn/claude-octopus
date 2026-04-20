#!/usr/bin/env bash
# Test Suite: v8.41.0 Feature Adoption
# Tests for new hooks, agent definitions, persona-agent sync,
# and other feature adoption improvements.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "v8.41.0 Feature Adoption"

ALL_SRC=$(mktemp)
cat "$PLUGIN_ROOT/scripts/orchestrate.sh" "$PLUGIN_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

PASS=0
FAIL=0
ERRORS=""

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

echo "═══════════════════════════════════════════════════════════════"
echo "Test Suite: v8.41.0 Feature Adoption"
echo "═══════════════════════════════════════════════════════════════"

# ─── Suite 1: New Hook Registration ─────────────────────────────
echo ""
echo "Suite 1: New Hook Registration"
echo "───────────────────────────────"

HOOKS_JSON="$PLUGIN_ROOT/.claude-plugin/hooks.json"

# 1.1 PreCompact hook registered
if grep -c '"PreCompact"' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "1.1 PreCompact event registered in hooks.json"
else
    fail "1.1 PreCompact event NOT registered in hooks.json"
fi

# 1.2 SessionEnd hook registered
if grep -c '"SessionEnd"' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "1.2 SessionEnd event registered in hooks.json"
else
    fail "1.2 SessionEnd event NOT registered in hooks.json"
fi

# 1.3 UserPromptSubmit hook registered
if grep -c '"UserPromptSubmit"' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "1.3 UserPromptSubmit event registered in hooks.json"
else
    fail "1.3 UserPromptSubmit event NOT registered in hooks.json"
fi

# 1.4 PreCompact hook script exists and is executable
if [[ -x "$PLUGIN_ROOT/hooks/pre-compact.sh" ]]; then
    pass "1.4 pre-compact.sh exists and is executable"
else
    fail "1.4 pre-compact.sh missing or not executable"
fi

# 1.5 SessionEnd hook script exists and is executable
if [[ -x "$PLUGIN_ROOT/hooks/session-end.sh" ]]; then
    pass "1.5 session-end.sh exists and is executable"
else
    fail "1.5 session-end.sh missing or not executable"
fi

# 1.6 UserPromptSubmit hook script exists and is executable
if [[ -x "$PLUGIN_ROOT/hooks/user-prompt-submit.sh" ]]; then
    pass "1.6 user-prompt-submit.sh exists and is executable"
else
    fail "1.6 user-prompt-submit.sh missing or not executable"
fi

# 1.7 PreCompact hook references correct script path
if grep -c 'pre-compact.sh' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "1.7 hooks.json references pre-compact.sh"
else
    fail "1.7 hooks.json does NOT reference pre-compact.sh"
fi

# 1.8 SessionEnd hook references correct script path
if grep -c 'session-end.sh' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "1.8 hooks.json references session-end.sh"
else
    fail "1.8 hooks.json does NOT reference session-end.sh"
fi

# 1.9 UserPromptSubmit hook references correct script path
if grep -c 'user-prompt-submit.sh' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "1.9 hooks.json references user-prompt-submit.sh"
else
    fail "1.9 hooks.json does NOT reference user-prompt-submit.sh"
fi

# 1.10 All hooks use set -euo pipefail
for hook_file in pre-compact.sh session-end.sh user-prompt-submit.sh; do
    if grep -c 'set -euo pipefail' "$PLUGIN_ROOT/hooks/$hook_file" >/dev/null 2>&1; then
        pass "1.10.$hook_file uses set -euo pipefail"
    else
        fail "1.10.$hook_file missing set -euo pipefail"
    fi
done

# 1.11 PreCompact hook persists workflow state to snapshot
if grep -c 'pre-compact-snapshot.json' "$PLUGIN_ROOT/hooks/pre-compact.sh" >/dev/null 2>&1; then
    pass "1.11 PreCompact saves to pre-compact-snapshot.json"
else
    fail "1.11 PreCompact does NOT save snapshot"
fi

# 1.12 SessionEnd hook writes session metrics
if grep -c 'session-summary' "$PLUGIN_ROOT/hooks/session-end.sh" >/dev/null 2>&1; then
    pass "1.12 SessionEnd writes session summary metrics"
else
    fail "1.12 SessionEnd does NOT write metrics"
fi

# 1.13 UserPromptSubmit classifies intent
if grep -c 'detected_intent' "$PLUGIN_ROOT/hooks/user-prompt-submit.sh" >/dev/null 2>&1; then
    pass "1.13 UserPromptSubmit classifies and stores detected_intent"
else
    fail "1.13 UserPromptSubmit does NOT classify intent"
fi

# 1.14 hooks.json is valid JSON
if python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null; then
    pass "1.14 hooks.json is valid JSON"
else
    fail "1.14 hooks.json is INVALID JSON"
fi

# 1.15 Total hook event count (should be 13 after adding 3 new ones)
HOOK_EVENT_COUNT=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    d = json.load(f)
print(len(d))
" 2>/dev/null)
if [[ "$HOOK_EVENT_COUNT" -ge 13 ]]; then
    pass "1.15 Hook events count >= 13 (got $HOOK_EVENT_COUNT)"
else
    fail "1.15 Hook events count < 13 (got $HOOK_EVENT_COUNT)"
fi

# ─── Suite 2: Agent Definitions (Persona-Agent Sync) ────────────
echo ""
echo "Suite 2: Agent Definitions (Persona-Agent Sync)"
echo "────────────────────────────────────────────────"

AGENTS_DIR="$PLUGIN_ROOT/.claude/agents"
PERSONAS_DIR="$PLUGIN_ROOT/agents/personas"

# 2.1 .claude/agents/ directory exists
if [[ -d "$AGENTS_DIR" ]]; then
    pass "2.1 .claude/agents/ directory exists"
else
    fail "2.1 .claude/agents/ directory does NOT exist"
fi

# 2.2 Minimum agent count (top-tier personas exposed)
AGENT_COUNT=$(find "$AGENTS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$AGENT_COUNT" -ge 8 ]]; then
    pass "2.2 At least 8 agent definitions found (got $AGENT_COUNT)"
else
    fail "2.2 Fewer than 8 agent definitions (got $AGENT_COUNT)"
fi

# 2.3 Every agent file has a matching persona file
AGENT_SYNC_PASS=true
for agent_file in "$AGENTS_DIR"/*.md; do
    [[ ! -f "$agent_file" ]] && continue
    agent_name=$(basename "$agent_file" .md)
    if [[ ! -f "$PERSONAS_DIR/$agent_name.md" ]]; then
        fail "2.3 Agent '$agent_name' has NO matching persona in agents/personas/"
        AGENT_SYNC_PASS=false
    fi
done
if [[ "$AGENT_SYNC_PASS" == "true" ]]; then
    pass "2.3 All agent definitions have matching persona files"
fi

# 2.4 Agent files have required frontmatter fields
for agent_file in "$AGENTS_DIR"/*.md; do
    [[ ! -f "$agent_file" ]] && continue
    agent_name=$(basename "$agent_file" .md)

    if grep -c '^name:' "$agent_file" >/dev/null 2>&1 && \
       grep -c '^description:' "$agent_file" >/dev/null 2>&1 && \
       grep -c '^model:' "$agent_file" >/dev/null 2>&1; then
        pass "2.4.$agent_name has name/description/model frontmatter"
    else
        fail "2.4.$agent_name missing required frontmatter fields"
    fi
done

# 2.5 Agent descriptions are concise (≤120 chars)
for agent_file in "$AGENTS_DIR"/*.md; do
    [[ ! -f "$agent_file" ]] && continue
    agent_name=$(basename "$agent_file" .md)
    desc_len=$(grep '^description:' "$agent_file" | sed 's/^description: //' | wc -c | tr -d ' ')
    if [[ "$desc_len" -le 121 ]]; then
        pass "2.5.$agent_name description ≤120 chars ($desc_len)"
    else
        fail "2.5.$agent_name description too long ($desc_len chars)"
    fi
done

# 2.6 Agent model values are valid
for agent_file in "$AGENTS_DIR"/*.md; do
    [[ ! -f "$agent_file" ]] && continue
    agent_name=$(basename "$agent_file" .md)
    model=$(grep '^model:' "$agent_file" | sed 's/^model: //' | tr -d ' ')
    case "$model" in
        opus|sonnet|inherit) pass "2.6.$agent_name model is valid ($model)" ;;
        *) fail "2.6.$agent_name model is invalid ($model)" ;;
    esac
done

# 2.7 Critical personas are exposed as agents
CRITICAL_AGENTS="security-auditor code-reviewer backend-architect debugger performance-engineer frontend-developer"
for critical in $CRITICAL_AGENTS; do
    if [[ -f "$AGENTS_DIR/$critical.md" ]]; then
        pass "2.7 Critical agent '$critical' is defined"
    else
        fail "2.7 Critical agent '$critical' is MISSING"
    fi
done

# ─── Suite 3: Hook Script Quality ───────────────────────────────
echo ""
echo "Suite 3: Hook Script Quality"
echo "────────────────────────────"

# 3.1 All hook scripts have shebangs
for hook_file in "$PLUGIN_ROOT"/hooks/*.sh; do
    [[ ! -f "$hook_file" ]] && continue
    hook_name=$(basename "$hook_file")
    if head -1 "$hook_file" | grep -c '^#!/' >/dev/null 2>&1; then
        : # pass silently for brevity
    else
        fail "3.1.$hook_name missing shebang"
    fi
done
pass "3.1 All hook scripts have shebangs"

# 3.2 New hooks exit cleanly (exit 0)
for hook_file in pre-compact.sh session-end.sh user-prompt-submit.sh; do
    if grep -c 'exit 0' "$PLUGIN_ROOT/hooks/$hook_file" >/dev/null 2>&1; then
        pass "3.2.$hook_file exits cleanly (exit 0)"
    else
        fail "3.2.$hook_file does NOT exit cleanly"
    fi
done

# 3.3 SessionEnd cleans up transient files
if grep -c 'pre-compact-snapshot.json' "$PLUGIN_ROOT/hooks/session-end.sh" >/dev/null 2>&1; then
    pass "3.3 SessionEnd cleans up pre-compact snapshot"
else
    fail "3.3 SessionEnd does NOT clean up snapshot"
fi

# 3.4 UserPromptSubmit is fast (no network calls, no heavy processing)
if ! grep -c 'curl\|wget\|http' "$PLUGIN_ROOT/hooks/user-prompt-submit.sh" >/dev/null 2>&1; then
    pass "3.4 UserPromptSubmit has no network calls (fast path)"
else
    fail "3.4 UserPromptSubmit makes network calls (will be slow)"
fi

# 3.5 PreCompact captures key workflow fields
for field in phase workflow autonomy completed_phases; do
    if grep -c "$field" "$PLUGIN_ROOT/hooks/pre-compact.sh" >/dev/null 2>&1; then
        pass "3.5 PreCompact captures '$field'"
    else
        fail "3.5 PreCompact does NOT capture '$field'"
    fi
done

# ─── Suite 4: Auto-Memory Integration ───────────────────────────
echo ""
echo "Suite 4: Auto-Memory Integration"
echo "─────────────────────────────────"

# 4.1 SessionEnd persists to auto-memory directory
if grep -c 'MEMORY_DIR\|\.claude/projects' "$PLUGIN_ROOT/hooks/session-end.sh" >/dev/null 2>&1; then
    pass "4.1 SessionEnd references auto-memory directory"
else
    fail "4.1 SessionEnd does NOT reference auto-memory"
fi

# 4.2 Writes octopus-preferences.md
if grep -c 'octopus-preferences.md' "$PLUGIN_ROOT/hooks/session-end.sh" >/dev/null 2>&1; then
    pass "4.2 SessionEnd writes octopus-preferences.md"
else
    fail "4.2 SessionEnd does NOT write preferences file"
fi

# 4.3 Persists autonomy preference
if grep -c 'autonomy' "$PLUGIN_ROOT/hooks/session-end.sh" >/dev/null 2>&1; then
    pass "4.3 SessionEnd persists autonomy preference"
else
    fail "4.3 SessionEnd does NOT persist autonomy"
fi

# ─── Suite 4b: SessionStart Auto-Memory Restoration ──────────────
echo ""
echo "Suite 4b: SessionStart Auto-Memory Restoration"
echo "────────────────────────────────────────────────"

# 4b.1 session-start-memory.sh exists and is executable
if [[ -x "$PLUGIN_ROOT/hooks/session-start-memory.sh" ]]; then
    pass "4b.1 session-start-memory.sh exists and is executable"
else
    fail "4b.1 session-start-memory.sh missing or not executable"
fi

# 4b.2 session-start-memory.sh registered in hooks.json under SessionStart
if grep -c 'session-start-memory.sh' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "4b.2 session-start-memory.sh registered in hooks.json"
else
    fail "4b.2 session-start-memory.sh NOT registered in hooks.json"
fi

# 4b.3 session-start-memory.sh reads octopus-preferences.md
if grep -c 'octopus-preferences.md' "$PLUGIN_ROOT/hooks/session-start-memory.sh" >/dev/null 2>&1; then
    pass "4b.3 session-start-memory.sh reads octopus-preferences.md"
else
    fail "4b.3 session-start-memory.sh does NOT read preferences"
fi

# 4b.4 session-start-memory.sh restores autonomy preference
if grep -c 'autonomy' "$PLUGIN_ROOT/hooks/session-start-memory.sh" >/dev/null 2>&1; then
    pass "4b.4 session-start-memory.sh restores autonomy preference"
else
    fail "4b.4 session-start-memory.sh does NOT restore autonomy"
fi

# 4b.5 session-start-memory.sh uses set -euo pipefail
if grep -c 'set -euo pipefail' "$PLUGIN_ROOT/hooks/session-start-memory.sh" >/dev/null 2>&1; then
    pass "4b.5 session-start-memory.sh uses set -euo pipefail"
else
    fail "4b.5 session-start-memory.sh missing set -euo pipefail"
fi

# 4b.6 session-start-memory.sh exits cleanly
if grep -c 'exit 0' "$PLUGIN_ROOT/hooks/session-start-memory.sh" >/dev/null 2>&1; then
    pass "4b.6 session-start-memory.sh exits cleanly (exit 0)"
else
    fail "4b.6 session-start-memory.sh does NOT exit cleanly"
fi

# 4b.7 session-start-memory.sh sets restored_from_memory flag
if grep -c 'restored_from_memory' "$PLUGIN_ROOT/hooks/session-start-memory.sh" >/dev/null 2>&1; then
    pass "4b.7 session-start-memory.sh sets restored_from_memory flag"
else
    fail "4b.7 session-start-memory.sh missing restored_from_memory flag"
fi

# ─── Suite 5: Telemetry HTTP Hook Readiness ─────────────────────
echo ""
echo "Suite 5: Telemetry Hook"
echo "───────────────────────"

# 5.1 Telemetry webhook exists
if [[ -f "$PLUGIN_ROOT/hooks/telemetry-webhook.sh" ]]; then
    pass "5.1 telemetry-webhook.sh exists"
else
    fail "5.1 telemetry-webhook.sh missing"
fi

# 5.2 Telemetry skips silently when unconfigured
if grep -c 'OCTOPUS_WEBHOOK_URL' "$PLUGIN_ROOT/hooks/telemetry-webhook.sh" >/dev/null 2>&1; then
    pass "5.2 Telemetry is opt-in (checks OCTOPUS_WEBHOOK_URL)"
else
    fail "5.2 Telemetry is NOT opt-in"
fi

# 5.3 Telemetry runs async (non-blocking)
if grep -c 'async.*true\|&$' "$PLUGIN_ROOT/hooks/telemetry-webhook.sh" >/dev/null 2>&1; then
    pass "5.3 Telemetry runs async/non-blocking"
else
    fail "5.3 Telemetry may block workflow execution"
fi

# 5.4 Telemetry uses command hook (native HTTP hooks deferred — telemetry-webhook.sh handles this)
if [[ -x "$PLUGIN_ROOT/hooks/telemetry-webhook.sh" ]]; then
    pass "5.4 Telemetry hook exists (command-type via telemetry-webhook.sh)"
else
    fail "5.4 Telemetry hook missing"
fi

# 5.5 Telemetry webhook checks OCTOPUS_WEBHOOK_URL
if grep -q 'OCTOPUS_WEBHOOK_URL' "$PLUGIN_ROOT/hooks/telemetry-webhook.sh" 2>/dev/null; then
    pass "5.5 Telemetry webhook uses OCTOPUS_WEBHOOK_URL"
else
    fail "5.5 Telemetry webhook does NOT use OCTOPUS_WEBHOOK_URL"
fi

# 5.6 Shell fallback skips when HTTP hooks supported
if grep -c 'SUPPORTS_HTTP_HOOKS' "$PLUGIN_ROOT/hooks/telemetry-webhook.sh" >/dev/null 2>&1; then
    pass "5.6 Shell fallback skips when SUPPORTS_HTTP_HOOKS=true"
else
    fail "5.6 Shell fallback has no SUPPORTS_HTTP_HOOKS guard"
fi

# ─── Suite 6: Task Manager Simplification ───────────────────────
echo ""
echo "Suite 6: Task Manager"
echo "─────────────────────"

# 6.1 Task manager exists
if [[ -f "$PLUGIN_ROOT/scripts/task-manager.sh" ]]; then
    pass "6.1 task-manager.sh exists"
else
    fail "6.1 task-manager.sh missing"
fi

# 6.2 Task manager has cleanup command
if grep -c 'cleanup' "$PLUGIN_ROOT/scripts/task-manager.sh" >/dev/null 2>&1; then
    pass "6.2 Task manager has cleanup command"
else
    fail "6.2 Task manager missing cleanup"
fi

# ─── Suite 7: Factory Droid Generation ─────────────────────────
echo ""
echo "Suite 7: Factory Droid Generation"
echo "──────────────────────────────────"

DROIDS_DIR="$PLUGIN_ROOT/agents/droids"

# 7.1 agents/droids/ directory exists
if [[ -d "$DROIDS_DIR" ]]; then
    pass "7.1 agents/droids/ directory exists"
else
    fail "7.1 agents/droids/ directory does NOT exist"
fi

# 7.2 Droid count matches agent count
if [[ -d "$DROIDS_DIR" && -d "$AGENTS_DIR" ]]; then
    DROID_COUNT=$(find "$DROIDS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$DROID_COUNT" -eq "$AGENT_COUNT" ]]; then
        pass "7.2 Droid count ($DROID_COUNT) matches agent count ($AGENT_COUNT)"
    else
        fail "7.2 Droid count ($DROID_COUNT) != agent count ($AGENT_COUNT)"
    fi
fi

# 7.3 Every agent has a corresponding droid (with octo- prefix)
if [[ -d "$DROIDS_DIR" ]]; then
    DROID_SYNC_PASS=true
    for agent_file in "$AGENTS_DIR"/*.md; do
        [[ ! -f "$agent_file" ]] && continue
        agent_basename=$(basename "$agent_file")
        droid_name="octo-${agent_basename}"
        if [[ ! -f "$DROIDS_DIR/$droid_name" ]]; then
            fail "7.3 Agent '$agent_basename' has NO matching droid (expected $droid_name)"
            DROID_SYNC_PASS=false
        fi
    done
    if [[ "$DROID_SYNC_PASS" == "true" ]]; then
        pass "7.3 All agents have matching Factory droids (octo- prefixed)"
    fi
fi

# 7.4 Droids have required frontmatter (name, description, model)
if [[ -d "$DROIDS_DIR" ]]; then
    DROID_FM_PASS=true
    for droid_file in "$DROIDS_DIR"/*.md; do
        [[ ! -f "$droid_file" ]] && continue
        droid_name=$(basename "$droid_file" .md)
        if grep -c '^name:' "$droid_file" >/dev/null 2>&1 && \
           grep -c '^description:' "$droid_file" >/dev/null 2>&1 && \
           grep -c '^model:' "$droid_file" >/dev/null 2>&1; then
            : # pass silently
        else
            fail "7.4 Droid '$droid_name' missing frontmatter fields"
            DROID_FM_PASS=false
        fi
    done
    if [[ "$DROID_FM_PASS" == "true" ]]; then
        pass "7.4 All droids have name/description/model frontmatter"
    fi
fi

# 7.5 build-factory-skills.sh generates droids
if grep -c 'agents/droids\|DROIDS_OUT' "$PLUGIN_ROOT/scripts/build-factory-skills.sh" >/dev/null 2>&1; then
    pass "7.5 build-factory-skills.sh includes droid generation"
else
    fail "7.5 build-factory-skills.sh does NOT generate droids"
fi

# 7.6 All droids use octo- prefix (namespace consistency with commands)
if [[ -d "$DROIDS_DIR" ]]; then
    NON_PREFIXED=$(find "$DROIDS_DIR" -name '*.md' ! -name 'octo-*' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$NON_PREFIXED" -eq 0 ]]; then
        pass "7.6 All droids use octo- prefix"
    else
        fail "7.6 $NON_PREFIXED droids missing octo- prefix"
    fi
fi
test_summary
