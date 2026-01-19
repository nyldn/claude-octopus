# Natural Language Trigger Patterns Reference

**Version:** 7.7.0
**Last Updated:** 2026-01-19

## Overview

Claude Octopus uses natural language trigger patterns to automatically activate the right skill for each user request. This guide documents all trigger patterns, provides examples, and explains how to customize them.

---

## How Triggers Work

### Trigger System Architecture

```
User Input
    ↓
Natural Language Analysis
    ↓
Pattern Matching (trigger: field in skill YAML)
    ↓
Skill Activation
    ↓
Skill Execution
```

### Two-Level System

1. **YAML Frontmatter Triggers** (in `.claude/skills/*.md`)
   - Natural language descriptions
   - Flexible, human-readable patterns
   - Primary activation mechanism

2. **Regex Triggers** (in `agents/config.yaml`)
   - Regex patterns for agent routing
   - Fallback and disambiguation
   - Lower-level matching

---

## Complete Trigger Pattern Catalog

### 🔧 Development & Workflow

#### skill-finish-branch

**Purpose:** Complete development work and prepare for merge/PR

**Activates on:**
- "commit and push"
- "git commit and push"
- "complete all tasks and commit and push"
- "proceed with all todos in sequence and push"
- "save and commit"
- "wrap this up and push"
- "I'm done with this feature"
- "ready to merge"
- "create PR for this work"

**Does NOT activate on:**
- Individual file commits (use built-in git tools)
- Work in progress without tests passing
- Exploratory commits
- Simple "git status" or "git diff" commands

**Examples:**
```
✓ "All tasks done, commit and push"
✓ "Complete all todos and push to remote"
✓ "I'm done with the auth feature, create a PR"
✗ "git commit -m 'WIP'" (use git directly)
✗ "show me git status" (use git directly)
```

---

#### skill-task-management

**Purpose:** Task orchestration, checkpointing, and resumption

**Activates on:**
- "add to the todo's" / "add this to todos"
- "resume tasks" / "continue tasks"
- "pick up where we left off"
- "save progress" / "save progress for Claude to pick up"
- "save progress to pickup later"
- "checkpoint this"
- "proceed to next steps"
- "continue to next"

**Does NOT activate on:**
- Git operations (use skill-finish-branch)
- Simple todo list viewing
- Task completion with push (use skill-finish-branch)

**Examples:**
```
✓ "Add implementing OAuth to my todos"
✓ "Save progress, I need to step away"
✓ "Resume tasks from yesterday"
✓ "Checkpoint this, I found a bug"
✗ "What's on my todo list?" (simple query)
✗ "Complete tasks and push" (use skill-finish-branch)
```

---

### 🐛 Debugging & Problem Solving

#### skill-debug

**Purpose:** Systematic debugging with root cause investigation

**Activates on:**
- "fix this bug" / "debug Y" / "troubleshoot X"
- "why is X failing" / "why isn't X working"
- "why doesn't X work"
- "why did X not work" / "why didn't X happen"
- "X does not work" / "X is broken" / "X is not working"
- "investigate Y" / "figure out why Z"
- "The X button does not work"
- "X preview button does not work"

**Does NOT activate on:**
- "Why do we use X?" (explanation, not debugging)
- "Why should I choose X?" (decision support)
- Known issues with clear solutions
- Documentation or architecture questions

**Examples:**
```
✓ "Why isn't the login form submitting?"
✓ "The preview button does not work"
✓ "Debug why tests are failing"
✓ "X is broken, figure out why"
✗ "Why do we use React?" (explanation request)
✗ "Why should I use TypeScript?" (decision support)
```

---

### 🔍 Research & Exploration

#### flow-discover (probe)

**Purpose:** Research, exploration, and information gathering

**Activates on:**
- "research X" / "explore Y" / "investigate Z"
- "what are the options for X"
- "what are my choices for Y"
- "find information about Y" / "look up Z"
- "analyze different approaches to Z"
- "evaluate approaches"
- "compare X vs Y" / "X vs Y comparison"
- "what should I use for X"
- "best tool for Y"
- "pros and cons of X"
- "tradeoffs between Y and Z"
- Questions about best practices, patterns, ecosystem research

**Does NOT activate on:**
- Simple file searches or code reading (use Read/Grep)
- Questions Claude can answer directly from knowledge
- Built-in commands (/plugin, /help, etc.)
- Questions about specific code in current project
- Debugging issues (use skill-debug)
- "what are my options" for decision support (use skill-decision-support)

**Examples:**
```
✓ "Research best authentication libraries for Node.js"
✓ "What are the options for state management in React?"
✓ "Compare PostgreSQL vs MongoDB for this use case"
✓ "Pros and cons of microservices architecture"
✗ "Find the UserController file" (use Grep/Glob)
✗ "What is OAuth?" (Claude can answer directly)
✗ "What are my options for fixing this bug?" (use skill-decision-support)
```

---

### 🎨 Visual & UI/UX

#### skill-visual-feedback

**Purpose:** Process image-based UI/UX feedback and fix visual issues

**Activates on:**
- "[Image X] The /settings should be Y"
- "[Image X] these button styles need to be fixed"
- "[Image X] When X is set to Y, it shows as Z"
- "button styles need to be fixed everywhere"
- "UI is a hot mess" / "UX still a hot mess"
- Screenshots with descriptions of visual issues

**Does NOT activate on:**
- Text-only feedback without visual context
- General feature requests
- Code-only issues
- Performance problems

**Examples:**
```
✓ "[Image] The logout button color is wrong"
✓ "Button styles are inconsistent everywhere"
✓ "The dashboard UX is a hot mess"
✓ "[Image] When logo position is Top right, shows Middle right"
✗ "Add a new feature to the settings page" (feature request)
✗ "The API is slow" (performance issue)
```

---

### 🤔 Decision Support & Options

#### skill-decision-support

**Purpose:** Present options and alternatives for decision-making

**Activates on:**
- "fix or provide options" / "fix them or provide me options"
- "give me options" / "what are my options"
- "show me alternatives" / "what else can we do"
- "help me decide" / "which approach should I take"

**Does NOT activate on:**
- Research questions (use flow-discover)
- Technical ecosystem research (use flow-discover)
- Implementation questions (use flow-tangle)

**Examples:**
```
✓ "The auth system is broken. Fix or provide options."
✓ "Give me options for caching"
✓ "Help me decide between REST and GraphQL"
✓ "Show me alternatives to this approach"
✗ "Research caching strategies" (use flow-discover)
✗ "Implement caching" (use flow-tangle)
```

---

### 🔁 Iterative Execution

#### skill-iterative-loop

**Purpose:** Execute tasks in loops with conditions

**Activates on:**
- "loop X times" / "loop around N times"
- "loop around 5 times auditing, enhancing, testing"
- "keep trying until" / "iterate until"
- "run until X passes" / "loop until Y works"
- "repeat N times" / "try N times"

**Does NOT activate on:**
- Single execution requests
- Manual retry requests
- Infinite loops (require max iterations)

**Examples:**
```
✓ "Loop 5 times optimizing until response time < 100ms"
✓ "Keep trying deployment until it succeeds, max 3 attempts"
✓ "Loop around 10 times auditing, fixing, testing"
✓ "Iterate until all tests pass, max 5 tries"
✗ "Run the tests" (single execution)
✗ "Try deploying" (no loop specified)
```

---

### ✅ Auditing & Verification

#### skill-audit

**Purpose:** Systematic audit and comprehensive checking

**Activates on:**
- "audit and check the entire app"
- "audit X for Y" / "check for broken features"
- "process to audit" / "systematic check"
- "scan for issues" / "find all instances of X"

**Does NOT activate on:**
- Security audits (use skill-security-audit)
- Code reviews (use skill-code-review)
- Simple grep/search operations

**Examples:**
```
✓ "Audit the entire app for broken features"
✓ "Check all forms for validation issues"
✓ "Create a process to audit API endpoints"
✓ "Find all instances of direct DOM manipulation"
✗ "Audit for security vulnerabilities" (use skill-security-audit)
✗ "Review this PR" (use skill-code-review)
✗ "Find files containing 'TODO'" (use Grep)
```

---

## Pattern Disambiguation

### When Multiple Skills Could Match

Sometimes user input could match multiple triggers. Here's how to choose:

#### "what are the options" vs "what are my options"

- **"what are the options for X"** → flow-discover (research)
  - User wants to learn about available options
  - Informational/educational intent
  - Example: "What are the options for authentication?"

- **"what are my options"** → skill-decision-support (decision)
  - User needs help choosing
  - Decision-making intent
  - Example: "This is broken. What are my options?"

#### "why" questions

- **"why is X failing"** → skill-debug (debugging)
  - Something is broken
  - Needs investigation
  - Example: "Why is the login failing?"

- **"why do we use X"** → Regular response (explanation)
  - Educational question
  - Not a bug
  - Example: "Why do we use Redis?"

#### "fix" requests

- **"fix this bug"** → skill-debug (systematic debugging)
  - Bug exists, needs root cause analysis
  - Example: "Fix the authentication bug"

- **"fix or provide options"** → skill-decision-support (choices)
  - Multiple solutions possible
  - User wants to choose approach
  - Example: "The API is slow. Fix or provide options."

---

## Writing Custom Triggers

### Best Practices

1. **Be Specific, Not Generic**
   ```yaml
   # Good
   trigger: |
     - "commit and push"
     - "complete all tasks and push"

   # Too generic (matches too much)
   trigger: |
     - "push"
     - "commit"
   ```

2. **Provide Clear Examples**
   ```yaml
   trigger: |
     AUTOMATICALLY ACTIVATE when user requests X:
     - "pattern 1" or "pattern 2"
     - "pattern 3"

     DO NOT activate for:
     - "anti-pattern 1" (use other-skill instead)
     - "anti-pattern 2"
   ```

3. **Include Negative Cases**
   - Always specify what NOT to match
   - Point to alternative skills
   - Prevents trigger conflicts

4. **Use Natural Language**
   - Write how users actually talk
   - Include variations ("commit and push" vs "push and commit")
   - Consider abbreviations and slang

### Trigger Template

```yaml
trigger: |
  AUTOMATICALLY ACTIVATE when user [describes intent]:
  - "pattern 1" or "variation 1"
  - "pattern 2" or "variation 2"
  - "pattern 3"
  - [Description of pattern category]

  ESPECIALLY use when [special conditions].

  DO NOT activate for:
  - "anti-pattern 1" (use skill-name instead)
  - "anti-pattern 2" (explanation)
  - [Category of non-matching cases]
```

---

## Testing Triggers

### Manual Testing

Test each pattern with real user input:

```bash
# Test positive cases
"commit and push"           → skill-finish-branch ✓
"why isn't login working"   → skill-debug ✓
"give me options for auth"  → skill-decision-support ✓

# Test negative cases
"git status"                → NOT skill-finish-branch ✓
"why do we use React"       → NOT skill-debug ✓
"research auth options"     → NOT skill-decision-support ✓
```

### Integration Testing

Use real prompts from `~/.local/state/opencode/prompt-history.jsonl`:

```bash
# Extract common patterns
jq -r '.prompt' ~/.local/state/opencode/prompt-history.jsonl | \
  grep -i "commit" | \
  sort | uniq -c | sort -nr
```

### Coverage Analysis

Track which patterns trigger which skills:

| Pattern | Expected Skill | Actual | Status |
|---------|---------------|--------|--------|
| "commit and push" | skill-finish-branch | ✓ | Pass |
| "why isn't X working" | skill-debug | ✓ | Pass |
| "add to todos" | skill-task-management | ✓ | Pass |

---

## Troubleshooting

### Skill Not Activating

**Problem:** User says "commit and push" but skill doesn't activate

**Diagnosis:**
1. Check trigger pattern in skill YAML frontmatter
2. Verify pattern includes this exact phrase
3. Check for conflicting triggers in other skills
4. Review agents/config.yaml for regex conflicts

**Solution:**
- Add the specific pattern to trigger list
- Update DO NOT activate section to prevent conflicts
- Test with exact user phrase

### Wrong Skill Activating

**Problem:** User says "what are my options" and flow-discover activates instead of skill-decision-support

**Diagnosis:**
1. Check both skills' trigger patterns
2. Identify which pattern is more specific
3. Check pattern order in plugin.json

**Solution:**
- Make patterns more specific
- Add negative cases ("DO NOT activate for")
- Reorder skills in plugin.json (more specific first)

### Multiple Skills Match

**Problem:** Two skills both claim to handle the same pattern

**Solution:**
1. **Disambiguate with context:**
   ```yaml
   # skill-A
   trigger: |
     - "research X for Y" (when Y is technical choice)

   # skill-B
   trigger: |
     - "research X for Y" (when Y is business strategy)
   ```

2. **Add exclusions:**
   ```yaml
   # skill-A
   trigger: |
     - "fix this"

     DO NOT activate for:
     - "fix or provide options" (use skill-decision-support)
   ```

3. **Create routing skill:**
   ```yaml
   # skill-router
   trigger: |
     - "ambiguous pattern"

   # Then ask user which they meant
   ```

---

## Metrics & Analytics

### v7.7.0 Coverage Analysis

Based on 50+ real user prompts:

| Category | Pattern Count | Trigger Coverage | Status |
|----------|--------------|------------------|--------|
| Task Completion & Git | 12 | 100% (12/12) | ✅ Complete |
| Task Management | 8 | 100% (8/8) | ✅ Complete |
| Problem-Solving | 15 | 93% (14/15) | ⚠️ Good |
| Visual/UI Feedback | 6 | 100% (6/6) | ✅ Complete |
| Options/Choices | 4 | 100% (4/4) | ✅ Complete |
| Iterative Loops | 3 | 100% (3/3) | ✅ Complete |
| Audit Patterns | 2 | 100% (2/2) | ✅ Complete |

**Overall Coverage:** 90%+ of identified user patterns

---

## Reference: All Skills with Triggers

Quick reference of all skills and their primary triggers:

| Skill | Primary Trigger Phrase | Category |
|-------|----------------------|----------|
| skill-finish-branch | "commit and push" | Development |
| skill-task-management | "add to todos" | Workflow |
| skill-debug | "why isn't X working" | Debugging |
| flow-discover | "research X" | Research |
| flow-define | "define requirements" | Planning |
| flow-develop | "implement X" | Development |
| flow-deliver | "verify and test" | Quality |
| skill-visual-feedback | "[Image] fix X" | UI/UX |
| skill-decision-support | "give me options" | Decision |
| skill-iterative-loop | "loop N times" | Execution |
| skill-audit | "audit the app" | Quality |
| skill-code-review | "review this code" | Quality |
| skill-security-audit | "check for vulnerabilities" | Security |
| skill-tdd | "write test first" | Testing |
| skill-debate | "debate this approach" | Analysis |

---

## Changelog

### v7.7.0 (2026-01-19)
- Added 5 new skills with trigger patterns
- Enhanced 3 existing skills with better triggers
- Added 7 new regex patterns to agents/config.yaml
- Coverage improved from ~60% to 90%+

### v7.6.3 (2026-01-18)
- Fixed plugin installation issues
- No trigger changes

### v7.6.0 (2026-01-17)
- Initial trigger pattern documentation

---

## Contributing

To add or modify trigger patterns:

1. Update skill YAML frontmatter (`trigger:` field)
2. Add regex pattern to `agents/config.yaml` if needed
3. Test with real user phrases
4. Update this documentation
5. Add entry to CHANGELOG.md

---

## Support

**Questions?** Open an issue at: https://github.com/nyldn/claude-octopus/issues

**Trigger not working?** Include:
- Exact user phrase
- Expected skill
- Actual behavior
- Skill YAML frontmatter content
