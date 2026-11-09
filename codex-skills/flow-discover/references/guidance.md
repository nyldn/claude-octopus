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

### Step 2: Output Context-Aware Banner with Task Status

**First, check task status (if available):**
```bash
# Get task status summary from orchestrate.sh (v2.1.12+)
task_status=$("${OCTO_ROOT:?}/scripts/orchestrate.sh" get-task-status 2>/dev/null || echo "")
```

**For Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: [Brief description of technical research]
📋 Session: ${CLAUDE_SESSION_ID}
📝 Tasks: ${task_status}

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Antigravity CLI - Ecosystem and library comparison
🔵 Claude - Strategic synthesis
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Knowledge] Discover Phase: [Brief description of strategic research]
📋 Session: ${CLAUDE_SESSION_ID}

Providers:
🔴 Codex CLI - Data analysis and frameworks
🟡 Antigravity CLI - Market and competitive research
🔵 Claude - Strategic synthesis
```

{{VISUAL_INDICATORS}}


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
2. **🟡 Antigravity CLI** - Broad ecosystem research, community insights, alternative approaches
3. **🟣 Perplexity** - Live web search with citations (when PERPLEXITY_API_KEY is set)
4. **🔵 Claude (You)** - Strategic synthesis and recommendation

This is the **divergent** phase - we cast a wide net to explore all possibilities before narrowing down.


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


## Visual Indicators

Before execution, you'll see:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider orchestration
🔍 Discover Phase: Research and exploration mode

Providers:
🔴 Codex CLI - Technical analysis
🟡 Antigravity CLI - Ecosystem research
🟣 Perplexity - Live web search (if configured)
🔵 Claude - Strategic synthesis
```


## How It Works

### Step 1: Invoke Discover Phase

```bash
"${OCTO_ROOT:?}/scripts/orchestrate.sh" discover "<user's research question>"
```

### Step 2: Multi-Provider Research

The orchestrate.sh script will:
1. Call **Codex CLI** with the research question
2. Call **Antigravity CLI** with the research question
3. You (Claude) contribute your analysis
4. Synthesize all perspectives into recommendations

### Step 2a: Native Background Tasks (Claude Code 2.1.14+)

For enhanced coverage, spawn parallel explore agents alongside CLI calls:

```typescript
// Fire parallel background tasks for codebase context
background_task(agent="explore", prompt="Find implementations of [topic] in the codebase")
background_task(agent="librarian", prompt="Research external documentation for [topic]")

// Continue with CLI orchestration immediately
// System notifies when background tasks complete
```

**Benefits of hybrid approach:**
- External CLIs such as Codex and Antigravity provide broad ecosystem research
- Native background tasks provide codebase-specific context
- Parallel execution reduces total research time
- 2.1.14 memory fixes make native parallelism reliable

### Step 3: Read Results

Results are saved to:
```
~/.claude-octopus/results/${SESSION_ID}/discover-synthesis-<timestamp>.md
```

### Step 4: Present Synthesis

Read the synthesis file and present key findings to the user in the chat.


## Implementation Instructions

When this skill is invoked, follow the EXECUTION CONTRACT above exactly. The contract includes:

1. **Blocking Step 1**: Detect work context (Dev vs Knowledge)
2. **Blocking Step 2**: Check providers, display visual indicators
3. **Blocking Step 3**: Read prior state
4. **Blocking Step 3.5**: Parse intensity, build agent fleet
5. **Blocking Step 4**: Launch parallel Agent subagents via orchestrate.sh probe-single
6. **Blocking Step 5**: Collect results from background agents
7. **Blocking Step 6**: Synthesize in-conversation (Claude synthesizes directly)
8. **Step 7**: Verify, update state, present results

Each step is **mandatory and blocking** - you cannot proceed to the next step until the current one completes successfully.

### Task Management Integration

Create tasks to track execution progress:

```javascript
// At start of skill execution
TaskCreate({
  subject: "Execute discover workflow with multi-AI providers",
  description: "Run orchestrate.sh probe with available providers",
  activeForm: "Running multi-AI discover workflow"
})

// Mark in_progress when calling orchestrate.sh
TaskUpdate({taskId: "...", status: "in_progress"})

// Mark completed ONLY after synthesis file verified
TaskUpdate({taskId: "...", status: "completed"})
```

### Error Handling

If any step fails:
- **Step 1 (Context)**: Default to Dev Context if ambiguous
- **Step 2 (Providers)**: If all external providers are unavailable, suggest `/octo:setup` and STOP
- **Step 4 (Agent launch)**: If an agent fails, continue with remaining agents (graceful degradation)
- **Step 5 (Collection)**: If fewer than 2 results, report error and let user decide
- **Step 6 (Synthesis)**: If synthesis fails, present raw agent results without synthesis
- **Step 7 (Validation)**: If synthesis file missing, report error

DO NOT substitute with direct research if agent execution fails — fallback to single-model analysis defeats the purpose of multi-provider synthesis. Report the failure and let the user decide how to proceed.

### Context-Appropriate Presentation

After successful execution, present findings formatted for context:

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

   ### Antigravity Analysis (Ecosystem Focus)
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

   ### Antigravity Analysis (Market/Competitive Focus)
   [Market trends, competitive landscape]

   ### Claude Synthesis
   [Integrated strategic recommendation]

   ## Next Steps
   [Strategic action items]
   ```


## Example Usage

### Example 1: Research Best Practices

```
User: Research OAuth 2.0 authentication patterns for React apps

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth 2.0 patterns

[Executes: "${OCTO_ROOT:?}/scripts/orchestrate.sh" probe "OAuth 2.0 authentication patterns for React apps"]

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

### Antigravity Analysis
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


## Quality Checklist

Before completing probe workflow, ensure:

- [ ] Available providers responded
- [ ] Synthesis file created and readable
- [ ] Key findings presented clearly in chat
- [ ] Strategic recommendation provided
- [ ] User understands next steps
- [ ] Full research path shared with user


## Cost Awareness

**External API Usage:**
- 🔴 Codex CLI uses your OPENAI_API_KEY (costs apply)
- 🟡 Antigravity CLI uses your AGY_AUTH_TOKEN (costs apply)
- 🟣 Perplexity uses your PERPLEXITY_API_KEY (costs apply, optional)
- 🔵 Claude analysis included with Claude Code

Probe workflows typically cost 0.01-0.05 USD per query depending on complexity and response length.
