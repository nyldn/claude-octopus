---
command: octo
description: Smart router - Single entry point with natural language intent detection
version: 2.0.0
category: workflow
tags: [router, intent-detection, workflow, smart-routing]
created: 2025-02-03
updated: 2026-03-12
---

# Smart Router (/octo:octo)

Single entry point for all Claude Octopus workflows. Analyzes your natural language request and routes to the optimal workflow automatically.

```
/octo:octo research OAuth authentication patterns
/octo:octo debug the failing test in auth.ts
/octo:octo should we use Redis or Memcached?
/octo:octo write tests for the payment module
/octo:octo create a complete e-commerce platform
```

All `/octo:*` commands also work directly, bypassing the router.

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:octo <query>` or says `octo <query>`, you MUST follow these steps in order:

### STEP 1: Input Validation

If the query exceeds 500 characters, use only the first 500 characters for intent analysis. Pass the full original query to the target workflow.

### STEP 2: Meta Command Check

If the query matches any of: `help`, `list`, `commands`, `what can you do`, `capabilities`, `options`, `workflows`:
- Display the **Complete Workflow Menu** (see STEP 5c) and STOP. Do not route.

### STEP 3: Analyze Intent

Match the query against keywords below. Check categories **in priority order** — higher priority wins when intents conflict.

#### Priority 1 — Specialized Workflows (check first, highest specificity)

| Intent | Trigger Keywords | Routes To |
|--------|-----------------|-----------|
| Lifecycle | end-to-end, complete lifecycle, full workflow, entire project, whole system | `octo:embrace` |
| Parallel | parallel, team of teams, decompose, work packages, split into, multi-instance | `octo:parallel` |
| Specification | spec, nlspec, specification, requirements doc, define scope, write spec | `octo:spec` |
| Security | security audit, OWASP, vulnerability, pentest, threat model, CVE, attack surface | `octo:security` |
| TDD | TDD, test-driven, write tests, test first, unit test, test coverage | `octo:tdd` |
| Debug | debug, fix bug, troubleshoot, broken, error trace, stacktrace, failing, crash | `octo:debug` |
| Design | UI design, UX design, wireframe, mockup, design system, layout, prototype | `octo:design-ui-ux` |
| PRD | PRD, product requirements, product spec, feature requirements | `octo:prd` |
| Brainstorm | brainstorm, ideate, ideas, creative, thought experiment, what if | `octo:brainstorm` |
| Deck | presentation, slides, deck, pitch deck, slide deck | `octo:deck` |
| Docs | document, documentation, README, API docs, write docs, docstring | `octo:docs` |

#### Priority 2 — Core Workflows

| Intent | Trigger Keywords | Routes To |
|--------|-----------------|-----------|
| Research | research, investigate, explore, study, understand patterns, analyze ecosystem | `octo:discover` |
| Review | validate, review code, check quality, audit code, inspect, verify, code review | `octo:review` |
| Debate | should we, X vs Y, compare, versus, decide between, which is better, trade-off | `octo:debate` |

#### Priority 3 — Build Workflows (broadest keywords, check last)

| Intent | Trigger Keywords | Routes To |
|--------|-----------------|-----------|
| Build (Clear) | build X, create X, implement X, develop X — where X is a specific target noun | `octo:develop` |
| Build (Vague) | build, create, make — without a clear target noun | `octo:plan` |
| Quick | quick, just do it, simple, fast, straightforward | `octo:quick` |

**Priority resolution:** When keywords from multiple intents match, the highest-priority intent wins. Example: "analyze the security of our API" matches both Research ("analyze") and Security ("security") — Security wins because Priority 1 > Priority 2.

### STEP 4: Determine Confidence

Apply this decision tree (NOT percentage-based scoring):

```
Single intent matched + specific target noun present
  → HIGH confidence

Single intent matched + target is vague or absent
  → MEDIUM confidence

Multiple intents matched + resolved by priority ordering
  → HIGH confidence (route to the higher-priority intent)

Multiple intents matched at same priority level
  → MEDIUM confidence (present top 2 candidates)

No intent keywords matched
  → LOW confidence
```

### STEP 5: Route Based on Confidence

**STEP 5a — HIGH confidence (auto-route):**

Display:
```
Routing to [Workflow Name] (/octo:[command])
```

Then display the visual indicator banner (STEP 6) and invoke:
```
Skill(skill: "octo:[command]", args: "<full user query>")
```

**STEP 5b — MEDIUM confidence (confirm first):**

Display:
```
I detected [intent]. Route to:
  [Primary] (/octo:[command]) — [one-line description]
  [Alternative] (/octo:[command]) — [one-line description]

Which would you prefer, or rephrase your request?
```

Wait for user confirmation before invoking the Skill tool.

**STEP 5c — LOW confidence (show complete menu):**

Display:
```
Which workflow would you like?

Core Workflows:
 1. Research    (/octo:discover)       — Multi-AI research and exploration
 2. Build       (/octo:develop)        — Implementation with quality gates
 3. Plan        (/octo:plan)           — Clarify requirements before building
 4. Review      (/octo:review)         — Code quality assurance and validation
 5. Debate      (/octo:debate)         — Multi-AI structured deliberation
 6. Embrace     (/octo:embrace)        — Full 4-phase lifecycle workflow

Engineering:
 7. Debug       (/octo:debug)          — Systematic multi-provider debugging
 8. Security    (/octo:security)       — Security audit with OWASP coverage
 9. TDD         (/octo:tdd)            — Test-driven development workflow
10. Spec        (/octo:spec)           — NLSpec structured authoring
11. Parallel    (/octo:parallel)       — Team of Teams decomposition

Creative & Documentation:
12. Design      (/octo:design-ui-ux)   — UI/UX design workflow
13. PRD         (/octo:prd)            — Product requirements document
14. Docs        (/octo:docs)           — Documentation delivery
15. Brainstorm  (/octo:brainstorm)     — Creative ideation
16. Deck        (/octo:deck)           — Slide deck generation

Quick:
17. Quick       (/octo:quick)          — Fast ad-hoc execution
```

### STEP 6: Display Visual Indicators

For multi-AI workflows, display before executing:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - [Workflow Type]
[Phase Emoji] [Phase Name]: [Brief description]

Providers:
🔴 Codex CLI - [role in this workflow]
🟡 Gemini CLI - [role in this workflow]
🔵 Claude - [your role]
```

### STEP 7: Record Routing Decision

After successful routing, append a log entry using the Bash tool:
```bash
mkdir -p ~/.claude-octopus && echo "[$(date +%Y-%m-%d\ %H:%M:%S)] intent=<matched_intent> confidence=<HIGH|MEDIUM|LOW> routed_to=<command>" >> ~/.claude-octopus/routing.log
```

If the user **rejects** a routing suggestion or says "no, I meant X":
1. Route to what the user actually wants
2. Save the correction to auto-memory: "Routing correction: '<query summary>' should route to <correct workflow>, not <wrong workflow>"
3. In future sessions, check auto-memory for routing corrections before keyword matching
4. If **claude-mem** MCP tools are available, also search past routing decisions with `search("routing correction")` to inform future routing

This allows the router to learn user preferences over time.

### Validation Gates

- Input validated (length check applied)
- Meta command check performed
- Intent detected via priority-ordered keyword matching
- Confidence determined via decision tree (not percentage formula)
- User confirmation obtained (if MEDIUM confidence)
- Target workflow executed via Skill tool
- Visual indicators displayed (for multi-AI workflows)

### Prohibited Actions

- Auto-routing when confidence is MEDIUM or LOW
- Routing without checking keyword priority order
- Routing to non-existent skills
- Skipping visual indicators for multi-AI workflows
- Simulating workflow execution (MUST use Skill tool)
- Using percentage-based confidence scoring (use the decision tree above)
- Passing queries to Skill tool without the full original text
