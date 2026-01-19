---
name: flow-discover
aliases:
  - discover
  - discover-workflow
  - probe
  - probe-workflow
description: |
  Discover phase workflow - Research and exploration using external CLI providers.
  Part of the Double Diamond methodology (Discover phase).
  Uses Codex and Gemini CLIs for multi-perspective research.
  
  Use PROACTIVELY when user says:
  - "octo research X", "octo discover Y", "octo explore Z"
  - "co-research X", "co-discover Y"
  - "research X", "explore Y", "investigate Z"
  - "what are the options for X", "what are my choices for Y"
  - "find information about Y", "look up Z", "analyze different approaches"
  - "compare X vs Y", "X vs Y comparison", "pros and cons of X"
  - "what should I use for X", "best tool for Y", "tradeoffs between X and Y"
  - Questions about best practices, patterns, or ecosystem research
  
  PRIORITY TRIGGERS (always invoke): "octo research", "octo discover", "co-research", "co-discover"
  
  DO NOT use for: simple file searches (use Read/Grep), questions Claude can answer directly,
  debugging issues (use skill-debug), or "what are my options" for decision support.
trigger: |
  AUTOMATICALLY ACTIVATE when user requests research or exploration:
  - "research X" or "explore Y" or "investigate Z"
  - "what are the options for X" or "what are my choices for Y"
  - "find information about Y" or "look up Z"
  - "analyze different approaches to Z" or "evaluate approaches"
  - Questions about best practices, patterns, or ecosystem research
  - Comparative analysis ("compare X vs Y" or "X vs Y comparison")
  - "what should I use for X" or "best tool for Y"
  - "pros and cons of X" or "tradeoffs between Y and Z"

  DO NOT activate for:
  - Simple file searches or code reading (use Read/Grep tools)
  - Questions Claude can answer directly from knowledge
  - Built-in commands (/plugin, /help, etc.)
  - Questions about specific code in the current project
  - Debugging issues (use skill-debug instead)
  - "what are my options" when asking for alternatives (use skill-decision-support)
---

# Discover Workflow - Discovery Phase 🔍

## ⚠️ MANDATORY: Context Detection & Visual Indicators

**BEFORE executing ANY workflow actions, you MUST:**

### Step 1: Detect Work Context

Analyze the user's prompt and project to determine context:

**Knowledge Context Indicators** (in prompt):
- Business/strategy terms: "market", "ROI", "stakeholders", "strategy", "competitive", "business case"
- Research terms: "literature", "synthesis", "academic", "papers", "personas", "interviews"
- Deliverable terms: "presentation", "report", "PRD", "proposal", "executive summary"

**Dev Context Indicators** (in prompt):
- Technical terms: "API", "endpoint", "database", "function", "implementation", "library"
- Action terms: "implement", "debug", "refactor", "build", "deploy", "code"

**Also check**: Does the project have `package.json`, `Cargo.toml`, etc.? (suggests Dev Context)

### Step 2: Output Context-Aware Banner

**For Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: [Brief description of technical research]

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and library comparison
🔵 Claude - Strategic synthesis
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Knowledge] Discover Phase: [Brief description of strategic research]

Providers:
🔴 Codex CLI - Data analysis and frameworks
🟡 Gemini CLI - Market and competitive research
🔵 Claude - Strategic synthesis
```

**This is NOT optional.** Users need to see which AI providers are active and understand they are being charged for external API calls (🔴 🟡).

---

**Part of Double Diamond: DISCOVER** (divergent thinking)

```
    DISCOVER (probe)

    \         /
     \   *   /
      \ * * /
       \   /
        \ /

   Diverge then
    converge
```

## What This Workflow Does

The **discover** phase executes multi-perspective research using external CLI providers:

1. **🔴 Codex CLI** - Technical implementation analysis, code patterns, framework specifics
2. **🟡 Gemini CLI** - Broad ecosystem research, community insights, alternative approaches
3. **🔵 Claude (You)** - Strategic synthesis and recommendation

This is the **divergent** phase - we cast a wide net to explore all possibilities before narrowing down.

---

## When to Use Discover

Use discover when you need:

### Dev Context Examples
- **Technical Research**: "What are authentication best practices in 2025?"
- **Library Comparison**: "Compare Redis vs Memcached for session storage"
- **Pattern Discovery**: "What are common API pagination patterns?"
- **Ecosystem Analysis**: "What's the state of React server components?"

### Knowledge Context Examples
- **Market Research**: "What are the market opportunities in healthcare AI?"
- **Competitive Analysis**: "Analyze our competitors' pricing strategies"
- **Literature Review**: "Synthesize research on remote work productivity"
- **UX Research**: "What are best practices for user onboarding flows?"

**Don't use discover for:**
- Reading files in the current project (use Read tool)
- Questions about specific implementation details (use code review)
- Quick factual questions Claude knows (no need for multi-provider)

---

## Visual Indicators

Before execution, you'll see:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider orchestration
🔍 Discover Phase: Research and exploration mode

Providers:
🔴 Codex CLI - Technical analysis
🟡 Gemini CLI - Ecosystem research
🔵 Claude - Strategic synthesis
```

---

## How It Works

### Step 1: Invoke Discover Phase

```bash
./scripts/orchestrate.sh discover "<user's research question>"
```

### Step 2: Multi-Provider Research

The orchestrate.sh script will:
1. Call **Codex CLI** with the research question
2. Call **Gemini CLI** with the research question
3. You (Claude) contribute your analysis
4. Synthesize all perspectives into recommendations

### Step 3: Read Results

Results are saved to:
```
~/.claude-octopus/results/${SESSION_ID}/discover-synthesis-<timestamp>.md
```

### Step 4: Present Synthesis

Read the synthesis file and present key findings to the user in the chat.

---

## Implementation Instructions

When this skill activates:

1. **Detect work context**
   
   Analyze the user's prompt:
   - Contains "market", "ROI", "stakeholders", "strategy", "competitive", "personas", "interviews", "presentation", "report", "PRD"? → **Knowledge Context**
   - Contains "API", "endpoint", "database", "implementation", "library", "code", "function", "deploy"? → **Dev Context**
   - If ambiguous, check if project has package.json/Cargo.toml → **Dev Context**
   - Default fallback: **Dev Context** in code repos, **Knowledge Context** otherwise

2. **Confirm research with context-aware banner**
   
   **For Dev Context:**
   ```
   I'll research "<question>" using multiple AI perspectives.

   🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
   🔍 [Dev] Discover Phase: Technical research on <topic>
   
   Providers:
   🔴 Codex CLI - Technical implementation analysis
   🟡 Gemini CLI - Ecosystem and library comparison
   🔵 Claude - Strategic synthesis
   ```
   
   **For Knowledge Context:**
   ```
   I'll research "<question>" using multiple AI perspectives.

   🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
   🔍 [Knowledge] Discover Phase: Strategic research on <topic>
   
   Providers:
   🔴 Codex CLI - Data analysis and frameworks
   🟡 Gemini CLI - Market and competitive research
   🔵 Claude - Strategic synthesis
   ```

3. **Execute probe workflow**
   ```bash
   ./scripts/orchestrate.sh probe "<user's question>"
   ```

4. **Monitor execution**
   - Watch for provider responses
   - Check for errors or quality issues
   - Ensure all providers complete successfully

5. **Read synthesis results**
   ```bash
   # Find the latest synthesis file
   SYNTHESIS_FILE=$(ls -t ~/.claude-octopus/results/${CLAUDE_CODE_SESSION}/probe-synthesis-*.md 2>/dev/null | head -n1)

   # Read and present to user
   cat "$SYNTHESIS_FILE"
   ```

6. **Present context-appropriate findings**

   **For Dev Context:**
   ```
   # Technical Research: <question>

   ## Key Technical Insights
   [Synthesized technical insights]

   ## Recommended Implementation Approach
   [Technical recommendation with code considerations]

   ## Library/Tool Comparison
   [If applicable, comparison of technical options]

   ## Perspectives
   ### Codex Analysis (Implementation Focus)
   [Technical implementation details]

   ### Gemini Analysis (Ecosystem Focus)
   [Community adoption, alternatives, trends]

   ### Claude Synthesis
   [Integrated technical recommendation]

   ## Next Steps
   [Technical action items]
   ```
   
   **For Knowledge Context:**
   ```
   # Strategic Research: <question>

   ## Key Strategic Insights
   [Synthesized business/research insights]

   ## Recommended Approach
   [Strategic recommendation with business rationale]

   ## Framework Analysis
   [If applicable, relevant frameworks applied]

   ## Perspectives
   ### Codex Analysis (Data/Analytical Focus)
   [Quantitative analysis, data points]

   ### Gemini Analysis (Market/Competitive Focus)
   [Market trends, competitive landscape]

   ### Claude Synthesis
   [Integrated strategic recommendation]

   ## Next Steps
   [Strategic action items]
   ```

---

## Example Usage

### Example 1: Research Best Practices

```
User: Research OAuth 2.0 authentication patterns for React apps

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth 2.0 patterns

[Executes: ./scripts/orchestrate.sh probe "OAuth 2.0 authentication patterns for React apps"]

[After completion, reads synthesis and presents:]

# Research Findings: OAuth 2.0 Authentication Patterns

## Key Insights

Based on multi-provider analysis, the recommended approach for React apps in 2025 is:
- **Authorization Code Flow with PKCE** for single-page apps
- Dedicated auth libraries (Auth0 SDK, Firebase Auth, or NextAuth.js)
- Token storage in memory + refresh token rotation

## Recommended Approaches

1. **NextAuth.js** (if using Next.js) - Built-in session management
2. **Auth0 React SDK** - Enterprise-grade, comprehensive
3. **Firebase Auth** - Simple, good for smaller apps

## Perspectives

### Codex Analysis
- Focus on implementation details with React hooks
- Code examples using popular libraries
- Security considerations for token storage

### Gemini Analysis
- Broader ecosystem view (community adoption, trends)
- Comparison of different OAuth providers
- Migration patterns and compatibility

### Claude Synthesis
- Strategic recommendation based on use case
- Trade-offs between different approaches
- Integration with existing React patterns

Full research saved to: ~/.claude-octopus/results/abc-123/probe-synthesis-20250118-143022.md
```

### Example 2: Technology Comparison

```
User: Compare different state management options for my React app

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Comparing React state management options

[Executes probe workflow]

[Presents comparative analysis with perspectives from all providers]
[Includes pros/cons, use cases, and strategic recommendation]
```

---

## Integration with Other Workflows

Probe is the **first phase** of the Double Diamond:

```
PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)
```

After probe completes, you may continue to:
- **Grasp**: Narrow down to specific requirements
- **Tangle**: Build the implementation
- **Ink**: Validate and deliver

Or use standalone for pure research tasks.

---

## Quality Checklist

Before completing probe workflow, ensure:

- [ ] All providers (Codex, Gemini, Claude) responded
- [ ] Synthesis file created and readable
- [ ] Key findings presented clearly in chat
- [ ] Strategic recommendation provided
- [ ] User understands next steps
- [ ] Full research path shared with user

---

## Cost Awareness

**External API Usage:**
- 🔴 Codex CLI uses your OPENAI_API_KEY (costs apply)
- 🟡 Gemini CLI uses your GEMINI_API_KEY (costs apply)
- 🔵 Claude analysis included with Claude Code

Probe workflows typically cost $0.01-0.05 per query depending on complexity and response length.

---

**Ready to research!** This skill activates automatically when users request research or exploration.
