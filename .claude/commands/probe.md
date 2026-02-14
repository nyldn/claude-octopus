---
command: probe
description: Research and discovery phase - Multi-AI research with broad exploration
---

# Probe - Discovery Phase (Double Diamond)

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:probe <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Discover Phase: <brief description of research topic>

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" probe "<user's research question>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct research.

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
Multi-AI Research powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

## PROHIBITIONS

- Do NOT research the topic yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use WebSearch, WebFetch, or any Task agents
- If orchestrate.sh fails, tell the user - do NOT work around it

## What Is Probe?

The **Discover** phase of the Double Diamond methodology:
- Divergent thinking
- Broad exploration
- Multi-perspective research
- Problem space understanding

## What You Get

- Multi-AI research (Claude + Gemini + Codex)
- Comprehensive analysis of options
- Trade-off evaluation
- Best practice identification
- Implementation considerations

## When To Use

- Starting a new feature
- Researching technologies
- Exploring design patterns
- Understanding problem space
- Gathering requirements

## Natural Language Examples

```text
"Research OAuth 2.0 vs JWT authentication"
"Probe database options for our use case"
"Explore state management patterns for React"
```
