# Triggers Guide - What Activates What

This guide explains exactly what natural language phrases trigger external CLI execution versus Claude subagents.

## Reliable Activation: Use "octo" Prefix

**Common words like "research" or "build" may conflict with Claude's base behaviors.** For reliable multi-AI workflow activation, use the "octo" prefix:

| Reliable Trigger | Workflow | Indicator |
|------------------|----------|-----------|
| `octo research X` | Discover (probe) | 🐙 🔍 |
| `octo build X` | Develop (tangle) | 🐙 🛠️ |
| `octo review X` | Deliver (ink) | 🐙 ✅ |
| `octo define X` | Define (grasp) | 🐙 🎯 |
| `octo debate X` | AI Debate Hub | 🐙 |

**Alternative prefixes that also work:**
- `co-research X`, `co-build X`, `co-review X`
- `/octo:discover X`, `/octo:develop X`, `/octo:deliver X`

---

## Quick Reference

| User Says | What Triggers | Provider(s) | Indicator |
|-----------|---------------|-------------|-----------|
| `octo research X` | Discover workflow | Codex + Gemini + Claude | 🐙 🔍 |
| `octo build X` | Develop workflow | Codex + Gemini + Claude | 🐙 🛠️ |
| `octo review X` | Deliver workflow | Codex + Gemini + Claude | 🐙 ✅ |
| `octo define X` | Define workflow | Codex + Gemini + Claude | 🐙 🎯 |
| `octo debate X` | Debate skill | Gemini + Codex + Claude | 🐙 |
| "read file.ts" | Read tool | Claude only | (none) |
| "what does this do?" | Analysis | Claude only | (none) |

**Note:** Bare triggers like "research X" may work but can conflict with Claude's base behaviors. Use "octo" prefix for guaranteed activation.

---

## Discover Workflow (Research)

### Triggers 🐙 🔍

**Reliable triggers (always work):**
- `octo research X`
- `octo discover X`
- `octo explore X`
- `co-research X`
- `/octo:discover X`

**Natural language triggers (may conflict with Claude's base behaviors):**
- "research X"
- "explore Y"
- "investigate Z"
- "what are the options for X"
- "find information about Y"
- "analyze different approaches to Z"
- "compare X vs Y"
- "what are the best practices for X"

**Examples:**
```
✅ "octo research OAuth 2.0 authentication patterns"
   → Guaranteed to trigger discover workflow

✅ "octo explore different caching strategies for Node.js"
   → Guaranteed to trigger discover workflow

⚠️ "Research OAuth 2.0 authentication patterns"
   → May trigger discover workflow (but could conflict with WebSearch)

⚠️ "What are the options for state management in React?"
   → May trigger discover workflow
```

### Does NOT Trigger

**Uses Claude subagent instead:**
```
❌ "What files handle authentication?" (simple search)
❌ "Read the README.md" (file read)
❌ "Show me the code in auth.ts" (file read)
❌ "What does this function do?" (code analysis)
```

---

## Develop Workflow (Build/Implement)

### Triggers 🐙 🛠️

**Reliable triggers (always work):**
- `octo build X`
- `octo develop X`
- `octo implement X`
- `co-build X`
- `/octo:develop X`

**Natural language triggers (may conflict):**
- "build X"
- "implement Y"
- "create Z"
- "develop a feature for X"
- "write code to do Y"
- "add functionality for Z"
- "generate implementation for X"

**Examples:**
```
✅ "octo build a user authentication system"
   → Guaranteed to trigger develop workflow

✅ "octo implement JWT token generation"
   → Guaranteed to trigger develop workflow

⚠️ "Build a user authentication system"
   → May trigger develop workflow (but not guaranteed)

⚠️ "Create an API endpoint for user registration"
   → May trigger develop workflow
```

### Does NOT Trigger

**Uses Claude subagent or Edit tool instead:**
```
❌ "Add a comment to this function" (simple edit)
❌ "Fix this typo in README" (simple edit)
❌ "Change variable name from x to y" (simple refactor)
❌ "Update the version number" (trivial change)
```

---

## Deliver Workflow (Review/Validate)

### Triggers 🐙 ✅

**Reliable triggers (always work):**
- `octo review X`
- `octo validate X`
- `octo deliver X`
- `co-review X`
- `/octo:deliver X`

**Natural language triggers (may conflict):**
- "review X"
- "validate Y"
- "test Z"
- "check if X works correctly"
- "verify the implementation of Y"
- "find issues in Z"
- "quality check for X"
- "ensure Y meets requirements"
- "audit X for security"

**Examples:**
```
✅ "octo review the authentication implementation"
   → Guaranteed to trigger deliver workflow

✅ "octo validate the API endpoints"
   → Guaranteed to trigger deliver workflow

⚠️ "Review the authentication implementation"
   → May trigger deliver workflow (but not guaranteed)

⚠️ "Check for security vulnerabilities in auth.ts"
   → May trigger deliver workflow
```

### Does NOT Trigger

**Uses built-in review skills or Read tool instead:**
```
❌ "What does this code do?" (code reading)
❌ "Explain this function" (code analysis)
❌ "Show me the tests" (file read)
```

---

## Define Workflow (Define/Clarify)

### Triggers 🐙 🎯

**Reliable triggers (always work):**
- `octo define X`
- `octo scope X`
- `octo clarify X`
- `co-define X`
- `/octo:define X`

**Natural language triggers (may conflict):**
- "define the requirements for X"
- "clarify the scope of Y"
- "what exactly does X need to do"
- "help me understand the problem with Y"
- "scope out the Z feature"
- "what are the specific requirements for X"

**Examples:**
```
✅ "octo define the requirements for our authentication system"
   → Guaranteed to trigger define workflow

✅ "octo scope the notification feature"
   → Guaranteed to trigger define workflow

⚠️ "Define the exact requirements for our authentication system"
   → May trigger define workflow (but not guaranteed)

⚠️ "Clarify the scope of the notification feature"
   → May trigger define workflow
```

### Does NOT Trigger

**Uses Claude analysis instead:**
```
❌ "What is OAuth?" (factual question)
❌ "How does JWT work?" (explanation)
❌ "Explain the project structure" (code navigation)
```

---

## Debate Skill

### Triggers 🐙 (Debate)

**Reliable triggers (always work):**
- `octo debate X`
- `co-debate X`
- `/octo:debate X`
- `/debate <question>`
- `/debate -r N -d STYLE <question>`

**Natural language alternatives (may conflict):**
- "run a debate about X"
- "I want gemini and codex to review X"
- "debate whether X or Y"

**Examples:**
```
✅ "octo debate whether we should use Redis or in-memory cache"
   → Guaranteed to trigger debate skill

✅ /octo:debate -r 3 -d adversarial "Review our API design"
   → Guaranteed to trigger debate skill, 3 rounds

⚠️ "Run a debate about whether to use TypeScript"
   → May trigger debate skill

⚠️ "I want gemini and codex to review this architecture"
   → May trigger debate skill
```

### Does NOT Trigger

**Not debate-appropriate:**
```
❌ "What is the best cache?" (research question → probe)
❌ "Build a cache system" (implementation → tangle)
❌ "Review the cache code" (validation → ink)
```

---

## Multi Command (Force Multi-Provider)

### Triggers 🐙 (Force Multi-Provider)

**Explicit command:**
- `/octo:multi "<task>"`

**Natural language triggers (force parallel mode):**
- "run this with all providers: [task]"
- "I want all three AI models to look at [topic]"
- "get multiple perspectives on [question]"
- "use all providers for [analysis]"
- "force multi-provider analysis of [topic]"
- "have all AIs analyze [subject]"

**This is the manual override** - explicitly invoke multi-provider mode for any task, even if it wouldn't normally trigger a workflow.

**Examples:**
```
✅ /octo:multi "What is OAuth?"
   → Forces multi-provider execution for simple question

✅ /octo:multi "Explain the difference between JWT and OAuth"
   → Forces parallel mode even for simple questions

✅ "Run this with all providers: Review this simple function"
   → Natural language force trigger

✅ "I want all three AI models to look at our architecture"
   → Forces comprehensive multi-model analysis

⚠️  "octo research OAuth patterns"
   → Automatically triggers discover workflow (no force needed)

⚠️  "octo build auth system"
   → Automatically triggers develop workflow (no force needed)
```

### When to Force Parallel Mode

**Use forced parallel mode when:**
- Simple questions deserve multiple perspectives for thorough understanding
- Comparing how different models approach the same problem
- High-stakes decisions requiring comprehensive analysis from all providers
- Automatic routing underestimates task complexity
- Learning different approaches to the same concept

**Don't force parallel mode when:**
- Task already auto-triggers workflows (octo research, octo build, octo review)
- Simple factual questions Claude can answer reliably
- Cost efficiency is important (see cost implications below)
- File operations or code navigation tasks

### Cost Implications

Forcing parallel mode uses external CLIs for every task:

| Provider | Cost per Query | What It Uses |
|----------|----------------|--------------|
| 🔴 Codex CLI | ~$0.01-0.05 | Your OPENAI_API_KEY |
| 🟡 Gemini CLI | ~$0.01-0.03 | Your GEMINI_API_KEY |
| 🔵 Claude | Included | Claude Code subscription |

**Total: ~$0.02-0.08 per forced query**

Use judiciously for tasks where multiple perspectives genuinely add value.

### Comparison: Auto-Trigger vs Force

**Auto-triggered workflows (built-in intelligence):**
```
"octo research OAuth" → 🐙 🔍 Discover Phase
"octo build auth"     → 🐙 🛠️ Develop Phase
"octo review code"    → 🐙 ✅ Deliver Phase
```
→ Automatically uses multi-provider when beneficial

**Forced parallel mode (manual override):**
```
/octo:multi "What is OAuth?" → 🐙 Multi-provider mode
"Run with all providers: explain JWT" → 🐙 Multi-provider mode
```
→ Forces multi-provider even for simple tasks

**Key difference:** Forced mode is for tasks that wouldn't normally trigger workflows but where you want comprehensive multi-model perspectives anyway.

### Visual Indicator

When forced parallel mode activates:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider mode
Force parallel execution

Providers:
🔴 Codex CLI - Technical perspective
🟡 Gemini CLI - Ecosystem perspective
🔵 Claude - Synthesis and integration
```

### See Also

- `/octo:debate` - Better for adversarial analysis with structured rounds
- `/octo:research` - Auto-triggers multi-provider for research tasks
- `/octo:review` - Auto-triggers multi-provider for validation tasks

---

## Knowledge Mode

### When Knowledge Mode is ON

When you've enabled Knowledge Mode, research-oriented tasks automatically use external CLIs:

```bash
/octo:km on
```

**Then these trigger multi-provider:**
- "Research market opportunities in healthcare" → probe
- "Analyze user research findings" → probe
- "Synthesize literature on X" → probe
- "What are the competitive dynamics in Y market?" → probe

**These still don't:**
- "Read the UX research doc" → Claude Read tool
- "Show me the survey results" → Claude Read tool

---

## Built-In Commands (Never Trigger External CLIs)

These commands are Claude Code built-ins and **never** trigger Octopus workflows:

```
❌ /plugin <anything>
❌ /init
❌ /help
❌ /clear
❌ /commit
❌ /remember
❌ /config
```

**Why:** These are core Claude Code features, not tasks that benefit from multi-AI collaboration.

---

## Simple Operations (Claude Subagent Only)

These operations use Claude's built-in tools, **no external CLIs**:

### File Operations
- "read X.ts"
- "show me Y.md"
- "what's in the config file?"
- "list files in src/"

### Git Operations
- "show git status"
- "what's the last commit?"
- "show git diff"
- "list branches"

### Code Navigation
- "where is the User model defined?"
- "find all API routes"
- "show me the database schema"
- "what files import X?"

### Simple Edits
- "add a comment here"
- "fix this typo"
- "rename variable X to Y"
- "update the version number"

---

## Decision Tree: Will This Trigger External CLIs?

Use this decision tree to determine if your request will use external CLIs:

```
START
  |
  ├─ Is it a built-in command (/plugin, /init, /help, etc.)?
  │   └─ YES → Claude only, no external CLIs
  |
  ├─ Is it a simple file operation (read, list, search)?
  │   └─ YES → Claude only, no external CLIs
  |
  ├─ Is it a git/bash command?
  │   └─ YES → Claude only, no external CLIs
  |
  ├─ Does it involve research/exploration?
  │   └─ YES → probe workflow → External CLIs (🐙 🔍)
  |
  ├─ Does it involve building/implementing?
  │   └─ YES → tangle workflow → External CLIs (🐙 🛠️)
  |
  ├─ Does it involve reviewing/validating?
  │   └─ YES → ink workflow → External CLIs (🐙 ✅)
  |
  ├─ Does it involve defining requirements?
  │   └─ YES → grasp workflow → External CLIs (🐙 🎯)
  |
  ├─ Is it a /debate command?
  │   └─ YES → debate skill → External CLIs (🐙)
  |
  └─ Otherwise → Claude only, no external CLIs
```

---

## Examples with Explanations

### Example 1: Research Task
```
User: "Research the best caching strategies for Node.js"

Analysis:
- Contains "research" → Triggers probe workflow
- Multi-provider needed for comprehensive ecosystem analysis
- Result: 🐙 🔍 External CLIs (Codex + Gemini + Claude)
```

### Example 2: Simple Question
```
User: "What is Redis?"

Analysis:
- Factual question
- Claude knows this from training data
- Single perspective sufficient
- Result: Claude only (no external CLIs)
```

### Example 3: Implementation
```
User: "Build a caching layer using Redis"

Analysis:
- Contains "build" → Triggers tangle workflow
- Multi-provider beneficial for different implementation approaches
- Result: 🐙 🛠️ External CLIs (Codex + Gemini + Claude)
```

### Example 4: File Read
```
User: "Read the cache.ts file and explain it"

Analysis:
- File read operation
- Code analysis (Claude's strength)
- Single perspective sufficient
- Result: Claude only (Read tool + analysis)
```

### Example 5: Code Review
```
User: "Review the caching implementation for issues"

Analysis:
- Contains "review" → Triggers ink workflow
- Multi-provider valuable for thorough review
- Result: 🐙 ✅ External CLIs (Codex + Gemini + Claude)
```

### Example 6: Requirements Definition
```
User: "Define the exact requirements for the caching system"

Analysis:
- Contains "define requirements" → Triggers grasp workflow
- Multi-provider helps identify both technical and business requirements
- Result: 🐙 🎯 External CLIs (Codex + Gemini + Claude)
```

---

## Avoiding External CLIs

If you want to ensure you're **not** using external CLIs (to save costs):

### Be Explicit
```
✅ "Read cache.ts and explain it" (uses Read tool)
✅ "Show me the cache implementation" (uses Read tool)
✅ "What does this caching code do?" (analysis only)
```

### Avoid Trigger Words
```
❌ "Research caching" → triggers probe
✅ "Explain caching to me" → Claude only

❌ "Build a cache" → triggers tangle
✅ "Write a cache function" → might stay Claude-only

❌ "Review the cache" → triggers ink
✅ "Explain the cache code" → Claude only
```

---

## Summary Table

| Reliable Trigger | Workflow | External CLIs | Typical Cost |
|------------------|----------|---------------|--------------|
| `octo research X` | Discover | Yes | $0.01-0.05 |
| `octo build X` | Develop | Yes | $0.02-0.10 |
| `octo review X` | Deliver | Yes | $0.02-0.08 |
| `octo define X` | Define | Yes | $0.01-0.05 |
| `octo debate X` | Debate | Yes | $0.05-0.15 |
| `/octo:multi X` | Force Multi | Yes | $0.02-0.08 |
| read, show, explain | (none) | No | Included |
| git, bash commands | (none) | No | Included |

**Pro tip:** Always use `octo` prefix for guaranteed workflow activation. Bare triggers like "research X" may work but can conflict with Claude's base behaviors.

---

For more information:
- [Visual Indicators Guide](./VISUAL-INDICATORS.md) - Understanding what's running
- [CLI Reference](./CLI-REFERENCE.md) - Direct CLI usage
- [README](../README.md) - Main documentation
