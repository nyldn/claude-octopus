# Triggers Guide - What Activates What

This guide explains exactly what natural language phrases trigger external CLI execution versus Claude subagents.

## Quick Reference

| User Says | What Triggers | Provider(s) | Indicator |
|-----------|---------------|-------------|-----------|
| "research X" | Probe workflow | Codex + Gemini + Claude | 🐙 🔍 |
| "build X" | Tangle workflow | Codex + Gemini + Claude | 🐙 🛠️ |
| "review X" | Ink workflow | Codex + Gemini + Claude | 🐙 ✅ |
| "define requirements for X" | Grasp workflow | Codex + Gemini + Claude | 🐙 🎯 |
| "/debate X" | Debate skill | Gemini + Codex + Claude | 🐙 (debate) |
| "read file.ts" | Read tool | Claude only | (none) |
| "what does this do?" | Analysis | Claude only | (none) |

---

## Probe Workflow (Research)

### Triggers 🐙 🔍

**Exact phrases that trigger probe:**
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
✅ "Research OAuth 2.0 authentication patterns"
   → Triggers probe workflow, multi-provider research

✅ "Explore different caching strategies for Node.js"
   → Triggers probe workflow

✅ "What are the options for state management in React?"
   → Triggers probe workflow

✅ "Compare Redis vs Memcached for session storage"
   → Triggers probe workflow
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

## Tangle Workflow (Build/Implement)

### Triggers 🐙 🛠️

**Exact phrases that trigger tangle:**
- "build X"
- "implement Y"
- "create Z"
- "develop a feature for X"
- "write code to do Y"
- "add functionality for Z"
- "generate implementation for X"

**Examples:**
```
✅ "Build a user authentication system"
   → Triggers tangle workflow, multi-provider implementation

✅ "Implement JWT token generation"
   → Triggers tangle workflow

✅ "Create an API endpoint for user registration"
   → Triggers tangle workflow

✅ "Add real-time notifications to the app"
   → Triggers tangle workflow
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

## Ink Workflow (Review/Validate)

### Triggers 🐙 ✅

**Exact phrases that trigger ink:**
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
✅ "Review the authentication implementation"
   → Triggers ink workflow, multi-provider validation

✅ "Validate the API endpoints"
   → Triggers ink workflow

✅ "Check for security vulnerabilities in auth.ts"
   → Triggers ink workflow

✅ "Verify the caching layer works correctly"
   → Triggers ink workflow
```

### Does NOT Trigger

**Uses built-in review skills or Read tool instead:**
```
❌ "What does this code do?" (code reading)
❌ "Explain this function" (code analysis)
❌ "Show me the tests" (file read)
```

---

## Grasp Workflow (Define/Clarify)

### Triggers 🐙 🎯

**Exact phrases that trigger grasp:**
- "define the requirements for X"
- "clarify the scope of Y"
- "what exactly does X need to do"
- "help me understand the problem with Y"
- "scope out the Z feature"
- "what are the specific requirements for X"

**Examples:**
```
✅ "Define the exact requirements for our authentication system"
   → Triggers grasp workflow, multi-provider problem definition

✅ "Clarify the scope of the notification feature"
   → Triggers grasp workflow

✅ "What exactly does the caching layer need to do?"
   → Triggers grasp workflow

✅ "Scope out the user profile feature"
   → Triggers grasp workflow
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

**Exact command:**
- `/debate <question>`
- `/debate -r N -d STYLE <question>`

**Natural language alternatives:**
- "run a debate about X"
- "I want gemini and codex to review X"
- "debate whether X or Y"

**Examples:**
```
✅ /debate Should we use Redis or in-memory cache?
   → Triggers debate skill, 3-way debate

✅ /debate -r 3 -d adversarial "Review our API design"
   → Triggers debate skill, 3 rounds, adversarial mode

✅ "Run a debate about whether to use TypeScript"
   → Triggers debate skill

✅ "I want gemini and codex to review this architecture"
   → Triggers debate skill
```

### Does NOT Trigger

**Not debate-appropriate:**
```
❌ "What is the best cache?" (research question → probe)
❌ "Build a cache system" (implementation → tangle)
❌ "Review the cache code" (validation → ink)
```

---

## Parallel Agents Command

### Triggers 🐙

**Exact command:**
- `/parallel-agents "<task>"`

**This is the manual override** - explicitly invoke multi-provider mode for any task, even if it wouldn't normally trigger a workflow.

**Examples:**
```
✅ /parallel-agents "Research OAuth patterns"
   → Forces multi-provider execution

✅ /parallel-agents "Review this code"
   → Forces multi-provider execution even for simple reviews
```

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

## Forcing Multi-Provider Mode

If you want to use external CLIs even for tasks that wouldn't normally trigger them:

### Use /parallel-agents
```
/parallel-agents "Explain how Redis works"
```
Forces multi-provider analysis even though it's a simple question.

### Use /debate
```
/debate "What is the best caching strategy?"
```
Forces 3-way debate even for questions that could be answered simply.

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

| Trigger Words | Workflow | External CLIs | Typical Cost |
|---------------|----------|---------------|--------------|
| research, explore, investigate | Probe | Yes | $0.01-0.05 |
| build, implement, create | Tangle | Yes | $0.02-0.10 |
| review, validate, audit | Ink | Yes | $0.02-0.08 |
| define, clarify, scope | Grasp | Yes | $0.01-0.05 |
| /debate | Debate | Yes | $0.05-0.15 |
| read, show, explain | (none) | No | Included |
| git, bash commands | (none) | No | Included |

---

For more information:
- [Visual Indicators Guide](./VISUAL-INDICATORS.md) - Understanding what's running
- [CLI Reference](./CLI-REFERENCE.md) - Direct CLI usage
- [README](../README.md) - Main documentation
