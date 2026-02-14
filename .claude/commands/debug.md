---
command: debug
description: Systematic debugging with methodical problem investigation
---

# Debug - Multi-AI Debugging

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:debug <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider debugging mode
🔧 Debug: <brief description of the bug>

Providers:
🔴 Codex CLI - Code analysis and root cause
🟡 Gemini CLI - Pattern matching and similar issues
🔵 Claude - Synthesis and fix recommendation
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" probe "Debug: <user's bug description>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct debugging.

### Step 3: Read Synthesis

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "probe-synthesis-*.md" 2>/dev/null | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

### Step 4: Present Results

Read the synthesis file content and present it to the user with this footer:

```text
---
Multi-AI Debugging powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

## PROHIBITIONS

- Do NOT debug the issue yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use `Task(octo:personas:debugger)` or any Task agent
- If orchestrate.sh fails, tell the user - do NOT work around it

## Debugging Approach

1. **Reproduce**: Understand and reproduce the issue
2. **Isolate**: Narrow down the root cause
3. **Analyze**: Examine code, logs, and state
4. **Hypothesize**: Form theories about the bug
5. **Test**: Validate hypotheses
6. **Fix**: Implement and verify the solution

## What You Get

- Step-by-step debugging plan
- Root cause analysis
- Fix recommendations
- Prevention strategies
- Test cases to prevent regression

## Natural Language Examples

```text
"Debug the failing test in test_auth.py"
"Help me debug why the API is returning 500 errors"
"Systematic debugging of the memory usage issue"
```
