---
description: "Smart router - Single entry point with natural language intent detection"
disable-model-invocation: true
---

# Smart Router (/octo:auto)

Single entry point for all Claude Octopus workflows. Analyzes your natural language request and routes to the optimal workflow automatically.

```
/octo:auto research OAuth authentication patterns
/octo:auto debug the failing test in auth.ts
/octo:auto should we use Redis or Memcached?
/octo:auto write tests for the payment module
/octo:auto create a complete e-commerce platform
```

All `/octo:*` commands also work directly, bypassing the router.

### Premium automatic peer check

When Premium mode is active, eligible single-owner implementation, review,
design, copywriting, and general work receives one automatic cross-provider
peer check after the owner returns a result. Users do not need a flag or a
second command. Budget and Standard modes do not add this call.

Octopus skips the extra check for quick or direct requests, setup and status
work, image and research routes, and workflows that already run councils,
debates, crossfire, parallel work, or a full review. Explicit provider/model
pins and provider restrictions still win. Set `OCTOPUS_PREMIUM_PEER_CHECK=off`
to disable only this automatic addition.

The peer receipt records whether the bounded result review completed. A peer
response is advisory and does not prove correctness.

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:auto <query>` or says `octo <query>`, you MUST use the native path below. The detailed routing table later in this file is reference material for the shared runtime, not a second classifier.

### NATIVE PATH: SINGLE AUTHORITATIVE ROUTER

For every non-meta request, pass the complete original query to the shared
automatic runtime before doing any local intent matching:

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
bash "${OCTO_ROOT}/scripts/orchestrate.sh" auto "<full original query>"
```

Treat the runtime's task classification and selected workflow as authoritative.
If it reports Direct mode, continue handling the original request natively in
the current Claude Code conversation. If it dispatches an external or
parallel workflow, let that workflow complete and do not start a second route.
If it reports a Native workflow request, load the named installed command and
follow that command's contract in the current conversation. Do not continue to
STEP 1 or choose a different route. This avoids two classifiers choosing
different workflows and keeps Premium peer policy at the workflow root.

The `help`, `list`, and `capabilities` requests below may be answered locally
without invoking the runtime.

## ROUTING REFERENCE (not a second execution path)

The following steps document the intent categories used by the runtime. They
must not be executed separately by a native `/octo:auto` invocation.

### STEP 1: Input Validation

If the query exceeds 500 characters, use only the first 500 characters for intent analysis. Pass the full original query to the shared runtime.

### STEP 2: Meta Command Check

If the query matches any of: `help`, `list`, `commands`, `what can you do`, `capabilities`, `options`, `workflows`:
- Display the **Complete Workflow Menu** (see STEP 5c) and STOP. Do not route.

### STEP 3: Analyze Intent

Match the query against keywords below. Check categories **in priority order** — higher priority wins when intents conflict.

#### Priority 1 — Specialized Workflows (check first, highest specificity)

Explicit multi-provider requests and security intent retain their priority.
For other requests, resolve prototype intent before the keyword table: an engineering experiment
to measure feasibility, throughput, compatibility or a technical assumption
routes to `octo:plan` for its bounded prototype proposal. A screen, wireframe
or interaction prototype routes to `octo:design-ui-ux`. Use the full request's
context; for an ambiguous "prototype" ask which outcome is intended.

| Intent | Trigger Keywords | Routes To |
|--------|-----------------|-----------|
| Lifecycle | end-to-end, complete lifecycle, full workflow, entire project, whole system | `octo:embrace` |
| Multi-LLM | multi, multi-llm, multi-provider, all providers, force multi, cross-model | `octo:multi` |
| Parallel | parallel, team of teams, decompose, work packages, split into | `octo:parallel` |
| Specification | spec, nlspec, specification, requirements doc, define scope, write spec | `octo:spec` |
| Security | security audit, OWASP, vulnerability, pentest, threat model, CVE, attack surface | `octo:security` |
| TDD | TDD, test-driven, write tests, test first, unit test, test coverage | `octo:tdd` |
| Debug | debug, fix bug, troubleshoot, broken, error trace, stacktrace, failing, crash | `octo:debug` |
| Design | UI design, UX design, wireframe, mockup, design system, layout, UI prototype | `octo:design-ui-ux` |
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

No explicit intent + query asks between two named technologies/options (`X or Y`, `X vs Y`, two code-formatted names)
  → MEDIUM confidence debate candidate (`octo:debate`)

No explicit intent + substantial what/how/why/which question (40+ characters)
  → MEDIUM confidence research candidate (`octo:discover`)

No intent keywords matched
  → LOW confidence
```

### STEP 5: Route Based on Confidence

Before loading any route, validate it against this closed allowlist: `embrace`,
`multi`, `parallel`, `spec`, `security`, `tdd`, `debug`, `design-ui-ux`, `prd`,
`brainstorm`, `deck`, `docs`, `discover`, `review`, `debate`, `develop`, `plan`, `quick`.
The token is control data, never user input: do not derive it from the query or
accept a user-supplied path. Reject `..`, `/`, `\\`, or non-allowlisted values.
The full query is passed only as workflow arguments. Both high-confidence
execution and confirmed medium-confidence execution use the shared automatic
runtime below; confirmation selects whether to proceed, not a different
dispatch path.

**STEP 5a — HIGH confidence (auto-route):**

Display:
```
Routing to [Workflow Name] (/octo:[command])
```

Then display the visual indicator banner (STEP 6), and execute the shared
automatic router through Bash. This keeps the native `/octo:auto` entrypoint
on the same workflow-root path as direct `orchestrate.sh auto` calls, including
the Premium automatic peer gate:

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
bash "${OCTO_ROOT}/scripts/orchestrate.sh" auto "<full original query>"
```

Do not manually invoke the selected command file from this entrypoint; doing
so would bypass the root-level routing policy. Do not use the Skill tool;
Octopus components are hidden from model invocation by design.

**STEP 5b — MEDIUM confidence (confirm first):**

Display:
```
I detected [intent]. Route to:
  [Primary] (/octo:[command]) — [one-line description]
  [Alternative] (/octo:[command]) — [one-line description]

Which would you prefer, or rephrase your request?
```

Wait for user confirmation. After confirmation, execute the shared automatic
router from STEP 5a with the full original query; do not manually load the
selected command file, because that would bypass the root-level routing policy.

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
11. Multi-LLM   (/octo:multi)          — Force all providers on any task
12. Parallel    (/octo:parallel)       — Team of Teams decomposition

Creative & Documentation:
13. Design      (/octo:design-ui-ux)   — UI/UX design workflow
14. PRD         (/octo:prd)            — Product requirements document
15. Docs        (/octo:docs)           — Documentation delivery
16. Brainstorm  (/octo:brainstorm)     — Creative ideation
17. Deck        (/octo:deck)           — Slide deck generation

Quick:
18. Quick       (/octo:quick)          — Fast ad-hoc execution
```

### STEP 6: Display Visual Indicators

**MANDATORY: For multi-AI workflows, you MUST use the Bash tool to check provider availability BEFORE displaying the banner:**

```bash
echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "agy:%s\n" "$(command -v agy >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
```

Then render the provider banner from actual provider checks. Do not hand-write or summarize this banner; run this block and display its output exactly. The output MUST include the Antigravity line even when `agy` is missing.

```bash
status_cli() { command -v "$1" >/dev/null 2>&1 && echo "Available ✓" || echo "Not installed ✗"; }
status_env() { [[ -n "${1:-}" ]] && echo "Configured ✓" || echo "Not configured ✗"; }
codex_status="$(status_cli codex)"
agy_status="$(status_cli agy)"
opencode_status="$(status_cli opencode)"
copilot_status="$(status_cli copilot)"
qwen_status="$(status_cli qwen)"
if command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then ollama_status="Available ✓"; else ollama_status="Not installed ✗"; fi
perplexity_status="$(status_env "${PERPLEXITY_API_KEY:-}")"
cat <<BANNER
🐙 **CLAUDE OCTOPUS ACTIVATED** - [Workflow Type]
[Phase Emoji] [Phase Name]: [Brief description]

Providers:
🔴 Codex CLI: ${codex_status}
🧭 Antigravity CLI: ${agy_status}
🟤 OpenCode: ${opencode_status}
🟢 Copilot CLI: ${copilot_status}
🟠 Qwen CLI: ${qwen_status}
⚫ Ollama: ${ollama_status}
🔵 Claude: Available ✓
🟣 Perplexity: ${perplexity_status}
BANNER
```

The rendered banner must look like this shape, with ACTUAL statuses:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - [Workflow Type]
[Phase Emoji] [Phase Name]: [Brief description]

Providers:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🧭 Antigravity CLI: [Available ✓ / Not installed ✗]
🟤 OpenCode: [Available ✓ / Not installed ✗]
🟢 Copilot CLI: [Available ✓ / Not installed ✗]
🟠 Qwen CLI: [Available ✓ / Not installed ✗]
⚫ Ollama: [Available ✓ / Not installed ✗]
🔵 Claude: Available ✓
🟣 Perplexity: [Configured ✓ / Not configured ✗]
```

**PROHIBITED: Displaying only "🔵 Claude: Available ✓" without checking and listing other providers.**

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
- Target workflow executed through the shared `orchestrate.sh auto` entrypoint
- Visual indicators displayed (for multi-AI workflows)

### Prohibited Actions

- Auto-routing when confidence is MEDIUM or LOW
- Routing without checking keyword priority order
- Routing to non-existent skills
- Skipping visual indicators for multi-AI workflows
- Simulating workflow execution instead of following the selected command file
- Using percentage-based confidence scoring (use the decision tree above)
- Dropping any of the full original query when handing off to the command
