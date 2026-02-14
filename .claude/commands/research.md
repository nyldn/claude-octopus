---
command: research
description: Deep research with multi-source synthesis and comprehensive analysis
---

# Research - Deep Multi-AI Research

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:research <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Deep Research: <brief description of topic>

Providers:
🔴 Codex CLI - Technical analysis
🟡 Gemini CLI - Ecosystem research
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
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "probe-synthesis-*.md" -mmin -10 2>/dev/null | sort -r | head -n1)
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

## Quick Usage

Just use natural language:
```text
"Research OAuth 2.0 authentication patterns"
"Deep research on microservices architecture best practices"
"Research the trade-offs between Redis and Memcached"
```

## What You Get

- Multi-source synthesis (academic papers, documentation, community discussions)
- Comparative analysis of different approaches
- Pros/cons evaluation
- Best practice recommendations
- Implementation considerations
