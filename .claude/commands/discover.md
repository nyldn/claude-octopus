---
command: discover
description: "Discovery phase - Multi-AI research and exploration"
aliases:
  - research-phase
---

# Discover - Discovery Phase 🔍

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:discover <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting discovery, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure high-quality research:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "How deep should the research go?",
      header: "Depth",
      multiSelect: false,
      options: [
        {label: "Quick overview", description: "High-level summary of key points"},
        {label: "Moderate depth", description: "Balanced exploration with examples"},
        {label: "Comprehensive", description: "Detailed analysis with trade-offs"},
        {label: "Deep dive", description: "Exhaustive research with edge cases"}
      ]
    },
    {
      question: "What's your primary focus area?",
      header: "Focus",
      multiSelect: false,
      options: [
        {label: "Technical implementation", description: "Code patterns, frameworks, APIs"},
        {label: "Best practices", description: "Industry standards and conventions"},
        {label: "Ecosystem & tools", description: "Libraries, tools, community insights"},
        {label: "Trade-offs & comparisons", description: "Pros/cons of different approaches"}
      ]
    },
    {
      question: "How should the output be formatted?",
      header: "Output",
      multiSelect: false,
      options: [
        {label: "Summary", description: "Concise key findings"},
        {label: "Detailed report", description: "Comprehensive write-up"},
        {label: "Comparison table", description: "Side-by-side analysis"},
        {label: "Recommendations", description: "Actionable next steps"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the research prompt.**

### Step 2: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Discover Phase: <brief description of research topic>

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

### Step 3: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" probe "<user's research question>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct research.

### Step 4: Read Synthesis

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

### Step 5: Present Results

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

## Usage

```bash
/octo:discover       # Discovery phase
```

## Natural Language Examples

```text
"Research OAuth authentication patterns"
"Explore caching strategies for high-traffic APIs"
"Investigate microservices best practices"
```

## Part of the Full Workflow

Discover is phase 1 of 4 in the embrace (full) workflow:
1. **Discover** - You are here
2. Define
3. Develop
4. Deliver

To run all 4 phases: `/octo:embrace`
