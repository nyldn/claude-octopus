# PRD-0: Research Brief — The Best Multi-LLM Orchestration Tool for Claude Code

**Version:** 1.0
**Date:** 2026-06-15
**Status:** Research complete; grounds the PRD slate for the next claude-octopus version.
**Method:** Multi-provider probes via `orchestrate.sh probe` (Codex, Claude-Sonnet, Copilot contributing; Gemini and Perplexity quota-dead — see Limitations).

---

## 1. Executive Summary

The strongest, most defensible wedge for the next version of claude-octopus is the **observability/control-plane**: all three contributing providers selected it independently. The adoption unlock that must ship alongside it is **cost governance** (pre-dispatch estimates plus hard caps), promoted to co-P0 on the strength of provider-billing-lag evidence. Cross-harness reach is a distribution play, not a moat; autonomous reliability is contested ground already held by heavier tools. The critical constraint: a control plane that only *displays* is "dashboardware" — the wedge holds only if telemetry drives routing, retries, vetoes, spend, and handoff in real time.

## 2. Competitive Teardown

| Tool | Beats octopus at | Loses to octopus at | Tradeoff |
|---|---|---|---|
| **wshobson/agents** (~36.7k★) | Cross-harness distribution: one catalog deploys to CC, Codex, Cursor, OpenCode, Copilot, Gemini | No parallel dispatch, synthesis, or gates. A catalog, not an orchestrator ("npm vs CI pipeline") | Portability vs synthesis depth |
| **claude-flow → Ruflo** (ruvnet) | Autonomy: 100+ agents, swarms, persistent memory, background workers, web UI, cost tracker | Single-provider (Claude only) — no genuine multi-model diversity | Persistence vs diversity; Ruflo is heavier to adopt / harder for enterprise security |
| **claude-hud** (~25.1k★) | Rendered observability dashboard (cost, timeline, ~300ms refresh) | Read-only observer; cannot dispatch, gate, or reroute | Rendering depth vs control |
| **agent-flow** (~970★) | Visual flow introspection; replays JSONL; Codex+Claude side-by-side | Observer, not controller; no provider policy or cost control | Visual accessibility vs feature depth |
| **zilliztech/claude-context** (~11.8k★) | Large-codebase semantic context (vector file selection) | Context adapter only — no orchestration | Precision vs breadth; a gap to fill, not compete |
| **OpenCode** | Low overhead; provider-agnostic single CLI router | Sequential routing, no consensus/gates ("smart curl") | Simplicity vs synthesis (already integrated as an optional octopus provider) |
| **Cursor** | Native IDE + autonomous Composer + proprietary codebase indexing | Always one model at a time; no parallel synthesis or gates; IDE-locked | Hardest competitor, but Cursor-users and Claude-Code-users are a clean-ish partition |

## 3. Differentiation Wedge — ranked (3/3 provider consensus on #1)

1. **Observability/control-plane (STRONGEST).** v9.45 shipped the JSONL event substrate (`events.sh`, dispatch lifecycle); no competitor combines dispatch telemetry with multi-LLM orchestration because none has multi-provider dispatch to observe. Demand proven by claude-hud (25.1k★). **Risk:** unrealized until something consumes the stream; must close the loop (control), not just render.
2. **Cost governance (OPEN GAP).** No tool ships pre-dispatch estimation + confirmation gate + hard session cap. Procurement/SOC-2 enabler for shared-key teams.
3. **Autonomous reliability (CONTESTED).** Ruflo and Cursor beat octopus on persistence/recovery. Use as proof-of-wedge (circuit breakers, retry budgets, invariant backprop), not a head-to-head bet.
4. **Cross-harness reach (WEAKEST for differentiation).** Interoperate (one-way export to wshobson format) as a funnel; do not compete on a 36.7k★ community's terms.

## 4. Adoption Gates

- **Overhead:** the 15-20 min embrace overhead is the cost of synthesis. Worth it for architecture/security/PRD work; waste for typos. The unresolved middle (medium-complexity tasks) is where a pre-dispatch "~5 min, ~$0.04" estimate converts hesitation into action.
- **Cost surprise:** provider/API billing lags 24-48h, so a misrouted model (e.g., resolver silently picking $5/MTok over $0.25/MTok) can run up hundreds before anyone notices. A hard cap + concurrency ceiling is required, not just retroactive display.

## 5. Instrumentation Plan (closes gap: usage telemetry)

Current `events.sh` + `cost.sh` capture per-phase cost only. Five metrics to add, emitted to the JSONL event stream (now default-on via `OCTO_EVENT_LOG`, fixed in oco-7db):

1. **Per-provider win/contribution rate** — which provider's output reached the final answer. Caveat: consensus masking (when all agree you can't attribute the insight); weight wins only when dissent preceded consensus.
2. **Consensus-disagreement frequency** — categorize minor/same-reasoning/contradictory. Signals orchestration value (>95% agreement → overhead dominates). Caveat: disagreement ≠ quality; instrument ground-truth misses in disagreement cases.
3. **Workflow mix** — distribution of workflows actually invoked, at the dispatch boundary (not CLI entry — power users call `probe-single` directly). Track abandonment separately.
4. **Time-to-synthesis** — per-provider latency + synthesis-logic time vs single-Claude baseline. Separate provider API time from network jitter and output I/O.
5. **Cost per workflow, by provider** — including fallback cost ("attempted Codex 2s timeout + fell back to Claude $0.05") and cache-hit discounting. Normalize per-question, not per-provider (Gemini flat-rate vs Codex token-based).

## 6. Benchmark Methodology (closes gap: orchestration overhead)

The existing `tests/benchmark/` validates quality (TP/FP/FN), which is orthogonal to overhead. Add an **orchestration overhead profile**: measure single-Claude baseline vs full dispatch vs smart dispatch (early-exit at consensus) vs full+synthesis, across a matrix of query complexity (simple/medium/complex) × latency (p50/p95/p99) × cost (absolute/relative/per-provider) × quality (consensus rate, disagreement-resolution correctness, ground-truth miss rate). Output the thresholds that make overhead worth it (e.g., "multi-provider when cost delta < 30% premium" / "synthesis lag < 15% of total").

## 7. Recommended PRD Slate

| PRD | Priority | One-line | Tracking issues |
|---|---|---|---|
| **Control Plane + HUD** (loop-closing, not just rendering) | P0 | Render the event stream live; drive reroute/retry/veto/cap | oco-8gw, oco-aek |
| **Pre-dispatch Budget Governor** (estimate range + hard cap + concurrency ceiling) | P0 | Kill the "what will this cost" gate; procurement enabler | (new) |
| **Invariant Backprop** (review findings → proposed CLAUDE.md rules, propose-and-confirm) | P1 | Compounding quality; proof the control plane is real | oco-fgg |
| **Semantic Context Adapter** (opt-in, token-budgeted file selection) | P1 | Fix large-codebase overflow | oco-fgg |
| **Cross-Harness Export** (one-way to wshobson format) | P2 | Distribution funnel after the wedge is polished | — |

## 8. Reliability Prerequisites (surfaced during the research runs themselves)

The probes exposed real plugin bugs that gate the data this brief needed; fix before relying on telemetry/benchmarks:

- **oco-7db** (FIXED, #491): orchestrate.sh now defaults `OCTO_EVENT_LOG` on — runs were emitting zero telemetry.
- **oco-cbb** (P1): preflight reports API providers "available" on key-present but quota-dead (perplexity 401, gemini exhausted).
- **oco-48z** (P1): parallel probe path lacks quota/terminal-error fast-fail — failed providers burn the full timeout.
- **oco-2kw** (P1): gemini research-phase time controls (cap `maxSessionTurns`, adopt flash, disable MCP, add `OCTOPUS_GEMINI_TIMEOUT`). Note: `--approval-mode plan` is NOT a read-only lever — it auto-switches to YOLO when exiting plan mode in headless runs.
- **oco-803** (P0): `gemini-image` uses `gemini-3-pro-image-preview`, shut down 2026-06-25; migrate to Nano Banana Pro/2 and refresh the catalog to GA `gemini-3.5-flash`.

## 9. Methodology & Limitations

- **Providers contributing:** Codex (problem-space + analysis), Claude-Sonnet (technical teardown), Copilot (instrumentation + benchmark plan, via GitHub Copilot subscription through gh CLI).
- **Failed providers:** Gemini (API quota exhausted) and Perplexity (HTTP 401 insufficient_quota). The automated synthesis provider also hit the gemini quota and fell back to compact mode, so this brief is a manual synthesis of raw agent artifacts in `~/.claude-octopus/results/`.
- **Gaps:** no live usage data (telemetry only became default-on after oco-7db; this brief predates any captured data) and no executed overhead benchmark (methodology defined in §6, not yet run). Competitor star counts are carried from the prior roadmap pass and the June-2026 web docs, not all re-verified live. Treat PRD-1/PRD-2 acceptance criteria as evidence-gated until §5 telemetry and §6 benchmarks produce real numbers.

## Sources

- Gemini CLI: plan-mode (geminicli.com/docs/cli/plan-mode), settings/maxSessionTurns (github.com/google-gemini/gemini-cli, PR #3507).
- Gemini models: ai.google.dev/gemini-api/docs/models + changelog; developers.googleblog.com (Gemini 3 Flash in CLI).
- Competitor positioning: github.com/wshobson/agents, github.com/ruvnet/ruflo, github.com/jarrodwatts/claude-hud, github.com/patoles/agent-flow, github.com/zilliztech/claude-context.
- Internal: docs/roadmaps/2026-06-13-next-minor-major.md; v9.45 event substrate (scripts/lib/events.sh).
