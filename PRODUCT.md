---
last_reviewed: 2026-05-25
---

# PRODUCT.md

## Mission

Put up to 9 AI models on every task so blind spots surface before you ship — not after.

## Vision

A world where every significant code decision gets adversarial review from multiple AI perspectives, and single-model overconfidence stops being a production incident.

## Target Personas

### Persona 1: Senior Engineer on a small team
- **Goal:** Ship high-confidence code without the overhead of a formal review process
- **Pain point:** Claude is good but sometimes confidently wrong — no second opinion catches the blind spot until production
- **Gap exposure:** Onboarding friction (setup complexity), provider availability gaps

### Persona 2: AI-augmented team lead
- **Goal:** Establish multi-model governance across their team's Claude Code workflows
- **Pain point:** Different engineers using different AI tools inconsistently — no shared quality gate
- **Gap exposure:** Missing team-configuration primitives, council consensus scoring not yet surfaced in PRs

### Persona 3: Power user / AI-native developer
- **Goal:** Squeeze maximum quality from the full frontier model ecosystem (Claude, Codex, Antigravity, Qwen, Ollama)
- **Pain point:** Orchestrating multiple CLIs manually is brittle and repetitive
- **Gap exposure:** Provider CLI version drift, cost surprises from multi-model dispatch

## What the Product Actually Is

Claude Octopus is a **multi-runtime orchestration plugin** with three architectural layers:

| Layer | What it does | Gap it closes |
|-------|-------------|---------------|
| **Provider adapters** (`scripts/orchestrate.sh`, `bin/check-providers.sh`) | Detects, authenticates, and dispatches to up to 9 AI CLIs | Eliminates manual per-provider boilerplate |
| **Workflow engine** (`skills/`) | Structures every task into Discover → Define → Develop → Deliver with quality gates | Stops ad-hoc "just ask Claude" from shipping low-confidence output |
| **Consensus layer** | 75% gate: flags disagreements across providers before code is finalized | The actual blind-spot catcher — surfaces the 1-in-5 case where Claude was wrong |

49 slash commands, 54 skills, 32 specialized personas activate the right layer for the right job.

## Core Value Propositions

- **Blind spot elimination:** Any model can be wrong; 9 providers rarely agree on the same wrong answer
- **Zero-friction escalation:** Claude-native for ordinary tasks, Octopus for anything that deserves a second opinion
- **Six providers can cost nothing extra when you already have access:** Codex (OAuth), Antigravity CLI (included with Antigravity access/subscription; backend cost depends on selected `OCTOPUS_AGY_MODEL`), Qwen (1K-2K free/day), Copilot (GitHub subscription), Ollama (local) — pay only when you add metered providers such as Perplexity or OpenRouter
- **Dark Factory autonomy:** Spec in, software out — full Discover→Define→Develop→Deliver pipeline without step-by-step prompting
- **Opinionated four-phase methodology:** Infrastructure plus the workflow that uses it correctly

## Design Principles

**Operational principles:**

1. **Fail loud on dispatch failure** — If multi-LLM dispatch does not execute, report "VALIDATION FAILED" rather than silently falling back to Claude-only
2. **Claude-native first** — Use `/init`, `/review`, and `/security-review` when Claude is enough; escalate to Octopus only when multiple opinions add value
3. **Cost transparency always** — Display provider indicators (🔴🧭🔵) and per-provider cost context before every multi-model dispatch
4. **Consensus gate, not consensus override** — 75% agreement flags disagreement; it does not suppress the minority view
5. **Zero providers to start** — Claude is built in; every additional provider is opt-in, not required

## Competitive Positioning

| Alternative | Where They Win | Where We Win |
|-------------|---------------|--------------|
| Claude Code (native) | Simpler, lower overhead, tighter integration | No multi-model consensus; single blind spot exposure |
| LangChain / LangGraph | Deeper programmatic orchestration, Python-native | Complex setup; not designed for Claude Code's slash-command UX |
| OpenHands / Devin-style agents | More autonomous end-to-end task completion | Less transparent; harder to inspect or override mid-task |
| Manual multi-tab AI use | Free, no setup | Not reproducible, no consensus gate, high cognitive overhead |

## Strategic Bet

Frontier AI models will remain individually overconfident for the foreseeable future. The productivity gap between teams that build adversarial review into their AI workflow and teams that trust a single model will become measurable and embarrassing. The bet: **multi-model consensus gates will be table stakes for AI-augmented engineering teams by 2027**, and the tool that makes it frictionless today wins the default position.

## Evidence

**Traction (as of 2026-05-25):**
- GitHub stars: 3,410
- GitHub forks: 302
- Test suites passing: 117
- Version: 9.40.3 (active release cadence)
- Runtimes supported: Claude Code, Codex CLI, Cursor (MCP), Antigravity CLI

**Measured Impact:**
- 75% consensus gate: quantifiable disagreement detection before production
- Token compression (`bin/octo-compress`): ~7,300 tokens saved per session
- 170+ Claude Code feature flags tracked through v2.1.132

## Known Product Gaps

| Gap | Impact | Status |
|-----|--------|--------|
| Onboarding requires multiple manual steps (clone → install → `/octo:setup`) | New users abandon before first workflow | Open |
| Provider CLI version drift causes silent failures | Orchestration breaks when external provider CLIs update; no version-lock | Open |
| Council consensus score not surfaced in GitHub PRs | Teams can't enforce multi-LLM gate in CI without manual extraction | Open |
| Windows native support untested | Windows users get degraded experience; shell scripts assume POSIX | Open |
| No persistent provider-auth across sessions | Re-auth friction on every new Claude Code session for some providers | Open |

## Usage

This file enables product-aware council reviews:

- **`/pre-mortem`** — Automatically includes `product` perspectives (user-value, adoption-barriers, competitive-position) alongside plan-review judges when this file exists.
- **`/vibe`** — Automatically includes `developer-experience` perspectives (api-clarity, error-experience, discoverability) alongside code-review judges when this file exists.
- **`/council --preset=product`** — Run product review on demand.
- **`/council --preset=developer-experience`** — Run DX review on demand.

Explicit `--preset` overrides from the user skip auto-include (user intent takes precedence).
