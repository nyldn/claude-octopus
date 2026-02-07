---
name: skill-context-detection
description: "Auto-detect work context (Dev vs Knowledge) for workflow tailoring"
---

# Context Detection - Internal Skill

## Purpose

This skill provides **automatic context detection** to determine whether the user is working in a **Development context** (code-focused) or **Knowledge context** (research/strategy-focused). This replaces the manual `/octo:km` toggle with intelligent auto-detection.

## Detection Algorithm

When a workflow skill activates, detect context using these signals:

### Step 1: Check for Explicit Override

If user has explicitly set mode via `/octo:km on` or `/octo:km off`, respect that setting.

```bash
# Check if knowledge mode is explicitly set
if [[ -f ~/.claude-octopus/config/knowledge-mode ]]; then
  EXPLICIT_MODE=$(cat ~/.claude-octopus/config/knowledge-mode)
  if [[ "$EXPLICIT_MODE" == "on" ]]; then
    echo "knowledge"
    exit 0
  elif [[ "$EXPLICIT_MODE" == "off" ]]; then
    echo "dev"
    exit 0
  fi
fi
# If "auto" or not set, proceed with auto-detection
```

### Step 2: Analyze Prompt Content (Strongest Signal)

**Knowledge Context Indicators** (check prompt for these terms):
- Business/strategy: "market", "ROI", "stakeholders", "strategy", "business case", "competitive"
- Research: "literature", "synthesis", "academic", "papers", "research question"
- UX: "personas", "user research", "journey map", "pain points", "interviews"
- Deliverables: "presentation", "report", "PRD", "proposal", "executive summary"

**Dev Context Indicators** (check prompt for these terms):
- Technical: "API", "endpoint", "database", "function", "class", "module"
- Actions: "implement", "debug", "refactor", "test", "deploy", "build"
- Artifacts: "code", "tests", "migration", "schema", "controller"

**Scoring:**
- Count knowledge indicators in prompt
- Count dev indicators in prompt
- Higher count wins
- If tied, check project context (Step 3)

### Step 3: Analyze Project Context (Secondary Signal)

**Dev Project Indicators:**
- Has `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `pom.xml`
- Has `src/`, `lib/`, `app/` directories with code files
- Recent files are `.ts`, `.js`, `.py`, `.go`, `.rs`, `.java`

**Knowledge Project Indicators:**
- Has `docs/`, `research/`, `strategy/`, `reports/` directories
- Majority of files are `.md`, `.docx`, `.pdf`, `.pptx`
- No code package managers detected

### Step 4: Default Fallback

If signals are ambiguous or equal:
- In a git repo with code files → Default to **Dev Context**
- No code files detected → Default to **Knowledge Context**

---

## Context Output Format

Return detected context as a structured object for use by workflow skills:

```json
{
  "context": "dev" | "knowledge",
  "confidence": "high" | "medium" | "low",
  "signals": {
    "prompt_indicators": ["API", "endpoint", "database"],
    "project_type": "node_typescript",
    "explicit_override": false
  }
}
```

---

## How Workflow Skills Use Context

### flow-discover (Research)

| Aspect | Dev Context | Knowledge Context |
|--------|-------------|-------------------|
| **Research Focus** | Technical implementation, library comparison, code patterns | Market analysis, academic synthesis, competitive research |
| **Primary Agents** | Codex (implementation), Gemini (ecosystem) | Gemini (analysis), research-synthesizer |
| **Output Format** | Code examples, API comparisons, tech recommendations | Reports, frameworks, strategic recommendations |
| **Visual Banner** | `🔍 [Dev] Discover Phase: Technical research` | `🔍 [Knowledge] Discover Phase: Strategic research` |

### flow-develop (Build)

| Aspect | Dev Context | Knowledge Context |
|--------|-------------|-------------------|
| **Build Focus** | Code generation, implementation, architecture | PRDs, strategy docs, presentations |
| **Primary Agents** | Codex (code), backend-architect, tdd-orchestrator | product-writer, strategy-analyst, exec-communicator |
| **Output Format** | Source files, tests, migrations | Documents, frameworks, action plans |
| **Visual Banner** | `🛠️ [Dev] Develop Phase: Building code` | `🛠️ [Knowledge] Develop Phase: Building deliverables` |

### flow-deliver (Review)

| Aspect | Dev Context | Knowledge Context |
|--------|-------------|-------------------|
| **Review Focus** | Code quality, security, performance | Document quality, argument strength, completeness |
| **Primary Agents** | code-reviewer, security-auditor | exec-communicator, strategy-analyst |
| **Quality Gates** | OWASP, test coverage, maintainability | Evidence quality, clarity, actionability |
| **Visual Banner** | `✅ [Dev] Deliver Phase: Code review` | `✅ [Knowledge] Deliver Phase: Document review` |

---

## Visual Indicator Update

When context is detected, update the visual banner to show context:

**Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: Researching OAuth implementation patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and library comparison
🔵 Claude - Strategic synthesis
```

**Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Knowledge] Discover Phase: Researching market entry strategies

Providers:
🔴 Codex CLI - Data analysis and modeling
🟡 Gemini CLI - Market and competitive research
🔵 Claude - Strategic synthesis
```

---

## Implementation in Workflow Skills

Each flow skill should:

1. **Before executing workflow**, run context detection
2. **Show detected context** in visual banner
3. **Adjust behavior** based on context:
   - Agent selection
   - Prompt framing for external CLIs
   - Output format expectations
   - Quality gate criteria

### Example Integration (Pseudocode)

```markdown
When this skill activates:

1. **Detect context**
   - Analyze user's prompt for knowledge vs dev indicators
   - Check project type (code repo vs doc-heavy)
   - Check for explicit override (~/.claude-octopus/config/knowledge-mode)
   - Determine: "dev" or "knowledge" with confidence level

2. **Show context-aware banner**
   ```
   🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider [research|implementation|validation] mode
   [Phase Emoji] [Context] [Phase Name]: [Description]
   
   Detected Context: [Dev|Knowledge] (confidence: [high|medium|low])
   ```

3. **Execute workflow with context-appropriate behavior**
   - Frame prompts for Codex/Gemini based on context
   - Select appropriate synthesis approach
   - Apply context-specific quality gates
```

---

## Override Mechanism

Users can still explicitly set context when auto-detection is wrong:

```bash
# Force knowledge mode
/octo:km on

# Force dev mode  
/octo:km off

# Return to auto-detection
/octo:km auto
```

When explicit override is set, context detection respects it until user resets to "auto".

---

## Confidence Levels

- **High**: Strong signals in prompt AND project context agree
- **Medium**: Signals in prompt OR project context (not both)
- **Low**: Ambiguous signals, using fallback default

When confidence is "low", consider briefly mentioning the detected context to user:
> "I detected this as a [dev/knowledge] task. If that's wrong, you can use `/octo:km` to override."

---

## Testing Context Detection

To verify context detection is working:

1. In a code repository, ask "octo research caching patterns" → Should detect **Dev Context**
2. In same repo, ask "octo research market opportunities" → Should detect **Knowledge Context**
3. With `/octo:km on` set, ask "octo research API patterns" → Should use **Knowledge Context** (explicit override)
