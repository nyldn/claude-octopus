# Next Minor and Major Direction - June 2026

This research pass looked at current Claude Code plugin and agent tooling on
June 13, 2026, then converted the strongest patterns into scoped Octopus work.

## Signals

- [Claude Code plugin docs](https://code.claude.com/docs/en/discover-plugins)
  emphasize marketplaces, component inventories, plugin load errors, token cost,
  and trust review before installation.
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) defines
  plugins as bundled skills, agents, hooks, MCP servers, LSP servers, and
  monitors.
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
  was the highest-signal official source: curated marketplace structure plus a
  strong warning that third-party plugins can bring their own files, MCP
  servers, and runtime behavior.
- [wshobson/agents](https://github.com/wshobson/agents) showed the most mature
  cross-harness pattern: one catalog of agents and skills emitted into Claude
  Code, Codex CLI, Cursor, OpenCode, Copilot, and Gemini.
- [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud),
  [disler/claude-code-hooks-multi-agent-observability](https://github.com/disler/claude-code-hooks-multi-agent-observability),
  and [patoles/agent-flow](https://github.com/patoles/agent-flow) all point in
  the same direction: agent systems need ambient observability, not only final
  summaries.
- [zilliztech/claude-context](https://github.com/zilliztech/claude-context)
  reinforced that semantic code context is becoming a plugin-level primitive.
- [JuliusBrussee/cavekit](https://github.com/JuliusBrussee/cavekit) showed a
  useful spec-driven loop: failures and review findings should backpropagate
  into durable invariants, not only patch the immediate bug.
- [hamelsmu/claude-review-loop](https://github.com/hamelsmu/claude-review-loop)
  and [ReflexioAI/claude-smart](https://github.com/ReflexioAI/claude-smart)
  make the same point for review and correction loops: agent systems should
  learn from repeated corrections.

Live GitHub star counts at research time put these in the high-signal cluster:
`wshobson/agents` around 36.7k, `anthropics/claude-plugins-official` around
30.1k, `jarrodwatts/claude-hud` around 25.1k, `zilliztech/claude-context`
around 11.8k, `disler/claude-code-hooks-multi-agent-observability` around
1.5k, `JuliusBrussee/cavekit` around 1.0k, `patoles/agent-flow` around 970,
and `Dicklesworthstone/claude_code_agent_farm` around 840.

## Implemented Now

### Minor: Provider Contract Audit

The qwen auth regression was a concrete version of a broader marketplace
problem: provider assumptions drift faster than docs, setup guidance, and
dispatch gates. Octopus now has `scripts/helpers/audit-provider-contracts.sh`
to enforce the provider contract that matters before release:

- `check-providers.sh` must use strict mode and document `available`,
  `missing`, and `degraded`.
- qwen must fail closed when OAuth is expired or cannot be validated.
- qwen setup guidance must point at API-key or Coding-Plan auth, not the retired
  free OAuth tier.
- provider version floors must stay env-overridable and match provider CLI
  version schemes.
- OAuth expiry parsing must avoid brittle regex extraction.
- provider checks can emit opt-in `provider.status` events.

### Major Groundwork: Local Event Stream

Octopus now has `scripts/lib/events.sh`, an opt-in JSONL event emitter:

```bash
OCTO_EVENT_LOG=auto bash scripts/helpers/check-providers.sh
OCTO_EVENT_LOG=/tmp/octo-events.jsonl bash scripts/helpers/check-providers.sh
```

When enabled, `check-providers.sh` appends `provider.status` events without
changing normal stdout. This is intentionally small: it gives future HUD,
dashboard, monitor, and agent-flow work a shared event substrate without adding
a server dependency or changing the CLI contract.

## Next Minor

Ship the provider contract audit as part of the release gate:

- call `scripts/helpers/audit-provider-contracts.sh` from release validation;
- add contract checks for new providers before they can be marked dispatchable;
- include the audit output in proof packets for PRs that touch provider auth,
  versions, docs, or setup help.

## Next Major

Build an Octopus control plane around the event stream:

- structured lifecycle events for provider selection, dispatch start/end,
  timeout, circuit breaker, review finding, and synthesis;
- a local monitor/HUD that can render events without scraping terminal output;
- invariant backprop from repeated review findings into durable specs;
- optional semantic context adapters so large-codebase discovery is explicit and
  measurable;
- lock-aware parallel agent scheduling with leases and recovery reports.

The control-plane version should preserve Octopus' current advantage: local
multi-provider orchestration with explicit safety gates. The new capability is
visibility and durable learning, not a hosted service dependency.
