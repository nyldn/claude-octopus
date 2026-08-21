# 🐙 Claude Octopus

Every AI model has blind spots. Claude Octopus supports ten external provider integrations — Codex, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, OrcaRouter, OpenCode, and Grok — alongside the built-in Claude Code host, with consensus gates that flag disagreements before you ship.

**Claude-native first, Octopus for escalation.** Use Claude-native `/init`, `/review`, and `/security-review` when Claude is enough. Use Octopus when you want multiple model opinions, adversarial review, or stricter multi-LLM workflows.

<p align="center">
  <img src="docs/assets/demo.gif" alt="Claude Octopus Demo — debate and research with multiple AI providers" width="720">
</p>

<p align="center">
  <a href="https://claude.ai"><img src="https://img.shields.io/badge/Claude-Built_with_AI-c96442?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJhMTAgMTAgMCAxIDAgMCAyMCAxMCAxMCAwIDAgMCAwLTIwbTAgMS44YTEuMiAxLjIgMCAwIDEgLjg1LjM1bDEuNSA0LjVhLjYuNiAwIDAgMCAuMzUuMzVsNC41IDEuNWExLjIgMS4yIDAgMCAxIDAgMi4yN2wtNC41IDEuNWEuNi42IDAgMCAwLS4zNS4zNWwtMS41IDQuNWExLjIgMS4yIDAgMCAxLTIuMjcgMGwtMS41LTQuNWEuNi42IDAgMCAwLS4zNS0uMzVsLTQuNS0xLjVhMS4yIDEuMiAwIDAgMSAwLTIuMjdsNC41LTEuNWEuNi42IDAgMCAwIC4zNS0uMzVsMS41LTQuNUExLjIgMS4yIDAgMCAxIDEyIDMuOCIvPjwvc3ZnPg==&labelColor=333" alt="Built with Claude"></a>
  <a href="https://github.com/nyldn/claude-octopus/actions/workflows/test.yml"><img src="https://github.com/nyldn/claude-octopus/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <img src="https://img.shields.io/badge/Version-9.65.0-blue" alt="Version 9.65.0">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.14+_required-blueviolet" alt="Requires Claude Code v2.1.14+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

🐙 **Research, build, review, and ship — with ten external providers checking the host's work.** Claude-native handles the ordinary path. Octopus remains dormant until you explicitly run `/octo:*`, then handles the escalated path. A 75% consensus gate catches disagreements before they reach production.

🧠 **Remembers across sessions.** Integrates with [claude-mem](https://github.com/thedotmack/claude-mem) and [agentmemory](https://github.com/rohitg00/agentmemory) for persistent memory — past decisions, research, and context survive session boundaries.

⚡ **Spec in, software out.** Dark Factory mode takes a spec and autonomously runs the full pipeline — research, define, develop, deliver. You review the output, not every step.

🔄 **Four-phase methodology, not just tools.** Every task moves through Discover → Define → Develop → Deliver, with quality gates between phases. Other orchestrators give you infrastructure. Octopus gives you the workflows.

🐙 **32 specialized personas** (role-specific AI agents like security-auditor, backend-architect), **54 commands** (slash commands you type), **63 skills** (reusable workflow modules). Explicit workflows select the experts they need; ordinary Claude requests do not activate Octopus.

🐙 **Works with just Claude. Adds up to ten external provider integrations.** Zero external providers are needed to start. Add them one at a time — each becomes available when detected and runs only inside an explicit workflow.

💰 **Four providers cost nothing extra when you already have access.** Codex, Antigravity CLI, and Copilot use existing subscriptions or local auth. Ollama runs locally for free. Qwen now requires API-key or Coding-Plan auth; its free OAuth tier ended on 2026-04-15.

---

## What's New

<!-- BEGIN CURRENT RELEASE -->
> 🆕 **v9.65.0 — Setup enables routing suggestions; council and tangle runs stay recoverable.**
>
> **Default roster:** Claude Opus 5 leads architecture, planning, security reasoning, and final judgment; GPT-5.6 Sol is the independent implementation/review peer; Claude Sonnet 5 is the standard Claude seat; Fable 5 remains an opt-in judgment escalation. Existing model pins and provider configuration still win. See [the routing strategy](docs/MODEL-ROUTING-STRATEGY.md).
<!-- END CURRENT RELEASE -->
>
> ```bash
> /octo:model-config                         # inspect or override the frontier roster
> OCTOPUS_OPUS5_AUTO_XHIGH=1                 # opt in to automatic xhigh Opus 5 phases
> OCTOPUS_OPUS_MODEL=claude-fable-5          # explicitly opt in to Fable 5
> ```

> 🆕 **v9.41 — Multi-LLM Council.** `/octo:council` runs a structured 3/5/7-persona deliberation across Claude, Codex, Antigravity, and OpenCode with goal modes (`advice`, `decision`, `plan`, `implement`, `review`), styles (`balanced`, `adversarial`, `red-team`, `executive`, `implementation`), benchmark-aware role routing, quorum + critical-veto gates, budget caps, and gated worktree handoff for approved plans. Use it when one model's opinion isn't enough.
>
> ```bash
> /octo:council --goal decision --style adversarial "Should this service stay monolithic?"
> /octo:council --goal implement --implement plan-only "Refactor the auth flow"
> ```

| Version | Best Features |
|---------|--------------|
| **v9.65.0** (new) | Setup enables routing suggestions; council and tangle runs stay recoverable. |
| **v9.50** | **Claude Code 2026 compatibility layer** — routines manifest (schedule + GitHub-event automations), SubagentStop quality/cost gate, `/octo:usage` cost attribution, `worktree.bgIsolation` opt-out, Claude Agent SDK seat (introduced with Opus 4.8 and now following the current Opus 5 default), starter skills pack, `/plugin browse` manifest with projected context cost. |
| **v9.41** | **`/octo:council`** promoted to first-class workflow — structured multi-LLM deliberation with goal modes, adversarial/red-team styles, benchmark-aware persona routing, quorum and critical-veto gates, budget preflight, and gated worktree handoff for approved implementation plans. |
| **v9** | Up to 10 external provider integrations (Codex, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, OrcaRouter, OpenCode, and Grok) alongside the Claude Code host. Structured provider debates and configurable multi-LLM councils. Explicit-only activation by default, with an optional smart router. Agent summary tables show which providers actually contributed. Provider-aware prompt preflight prevents silent oversize failures. Research breadth modes fan out light, standard, or exhaustive investigations. Setup aliases and fuzzy `/octo:*` corrections reduce command friction. Opt-in discipline gates and token compression. Two-stage review. Circuit breakers with automatic provider recovery inside active workflows. Cursor + OpenCode + Codex cross-compatibility. `bin/octopus` CLI. 182 Claude Code capability flags through v2.1.219, including Opus 5, Sonnet 5, and dynamic workflow awareness. |
| **v8** | Multi-LLM code review with inline PR comments. Parallel workstreams in isolated git worktrees. Reaction engine — auto-responds to CI failures. 32 specialized personas. Dark Factory autonomous pipeline. |
| **v7** | Double Diamond workflow. Multi-provider dispatch. Quality gates and consensus scoring. Configurable sandbox modes. |

[Full changelog →](CHANGELOG.md)

<details>
<summary>Upgrading to 9.5x</summary>

<!-- BEGIN CURRENT MODEL DEFAULTS -->
- Current fresh configurations use **GPT-5.6 Sol** for Codex implementation/review, **Claude Opus 5** for premium Claude work, and **Claude Sonnet 5** for the standard Claude seat. Existing environment, session, and `providers.json` pins remain unchanged; `OCTOPUS_LEGACY_ROLES=1` restores the pre-frontier role mapping.
<!-- END CURRENT MODEL DEFAULTS -->
- New claude-sdk seat env vars (v9.50): `CLAUDE_SDK_API_KEY`, `OCTOPUS_CLAUDE_SDK_MODEL`, `OCTOPUS_CLAUDE_SDK_MAX_TOKENS`, `OCTOPUS_CLAUDE_SDK_ALLOWED_MODELS`, `OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET`.
- New Fable 5 guard env vars (v9.51): `OCTOPUS_FABLE5_MODE` (auto/off/on), `OCTOPUS_FABLE5_NO_RETRY`. Guards auto-enable only when you pin `claude-fable-5`.
- Premium Claude role routing (architect, strategist, security-reviewer to Opus) landed in v9.29; restore the older mapping with `OCTOPUS_LEGACY_ROLES=1`.

</details>

## Quickstart

```bash
# Terminal (not inside a Claude Code session):
claude plugin marketplace add https://github.com/nyldn/plugins.git
claude plugin install octo@nyldn-plugins

# Then inside Claude Code:
/octo:setup
```

That's it. Setup detects installed providers, shows what's missing, and walks you through configuration. You need **zero** external providers to start — Claude is built in.

### Dormant by default

Installing Octopus does not route ordinary prompts, launch provider workflows,
or delegate to Octopus agents. Every shipped command and skill uses Claude
Code's native manual-invocation gate. Start it with `/octo:*`.

> **Seeing `cannot be used with Skill tool due to disable-model-invocation`?**
> That is the gate working as intended — the model tried to auto-invoke an
> Octopus skill. Run the command explicitly instead: type `/octo:doctor` (the
> command), not a model call to the `skill-doctor` skill. Slash commands are
> user-invoked, so they bypass this invocation gate; the model will not call
> Octopus skills on its own unless you opt into the router below. Rule of thumb:
> **invoke Octopus with
> `/octo:…`, don't expect Claude to reach for it for you.**

Optional automation remains available, but it is explicit opt-in:

```bash
export OCTOPUS_AUTO_ROUTER_MODE=suggest  # suggest a route for plain prompts
# or: OCTOPUS_AUTO_ROUTER_MODE=invoke    # load the matched command route
export OCTO_DONE_CRITERIA=on             # compound-task completion coaching
export OCTOPUS_COMPRESS_ENABLED=true     # PostToolUse output compression
export OCTO_STRATEGY_ROTATION=on         # failure strategy rotation
export OCTOPUS_CONTEXT_AWARENESS=on      # statusline-to-context reinforcement
export OCTOPUS_SESSION_MEMORY=on         # SessionStart preference restoration
```

This legacy opt-in examines ordinary prompts. `invoke` can start paid
external-provider workflows and share the routed prompt context with configured
providers; prefer `suggest` unless that behavior is intentional. Provider-side
retention follows each provider account's policy. Unset the variable (or set it
to `off`) to opt out without disabling direct `/octo:*` commands.

Safety guards that prevent invalid direct Codex, Qwen, or retired Gemini CLI
dispatch remain available, but host-side command filters keep them out of
unrelated tool calls.

Claude Code **v2.1.14+** is the minimum supported runtime. Newer Claude Code releases unlock additional Octopus diagnostics and release checks automatically; the current plugin tracks 182 Claude Code capability flags through **Claude Code v2.1.219**.

<details>
<summary>Install for Codex CLI</summary>

```bash
codex plugin marketplace add https://github.com/nyldn/plugins.git
codex plugin add claude-octopus@nyldn-plugins
```

Restart Codex. Skills appear automatically — invoke with `$skill-doctor`, `$skill-debug`, etc.

Codex owns the versioned cache. To refresh an existing installation without
editing cache files or symlinks directly:

```bash
codex plugin marketplace upgrade nyldn-plugins
codex plugin add claude-octopus@nyldn-plugins
```

</details>

<details>
<summary>Install for Cursor IDE</summary>

Cursor uses Octopus as an **MCP server** (not a plugin — Cursor doesn't have Claude Code's plugin system). You get MCP tools like `octopus_discover`, `octopus_review`, etc. instead of `/octo:*` slash commands.

> **Important:** Just cloning the repo is not enough. You must complete all three steps below — install dependencies and configure the MCP server — for Cursor to pick up Octopus tools.

```bash
# 1. Clone the repo
git clone --depth 1 https://github.com/nyldn/claude-octopus.git ~/.cursor/claude-octopus

# 2. Install MCP server dependencies
cd ~/.cursor/claude-octopus/mcp-server && npm install

# 3. Configure Cursor — add to ~/.cursor/mcp.json (global) or .cursor/mcp.json (per-project):
```

```json
{
  "mcpServers": {
    "claude-octopus": {
      "command": "npx",
      "args": ["tsx", "${userHome}/.cursor/claude-octopus/mcp-server/src/index.ts"],
      "env": {
        "OCTO_CLAW_ENABLED": "true",
        "OPENAI_API_KEY": "${env:OPENAI_API_KEY}"
      }
    }
  }
}
```

Restart Cursor. Tools appear in Cursor's AI chat — invoke by asking e.g. "use octopus_discover to research X".

<details>
<summary>Using Cursor on WSL?</summary>

If you're running Cursor on Windows with WSL, clone the repo inside WSL and point the MCP config through `wsl.exe`:

```json
{
  "mcpServers": {
    "claude-octopus": {
      "command": "wsl",
      "args": ["npx", "tsx", "/home/<user>/.cursor/claude-octopus/mcp-server/src/index.ts"],
      "env": {
        "OPENAI_API_KEY": "${env:OPENAI_API_KEY}"
      }
    }
  }
}
```

Replace `<user>` with your WSL username. Make sure `node` and `npm` are installed inside WSL.
</details>

See [docs/IDE-INTEGRATION.md](docs/IDE-INTEGRATION.md) for the full guide including `ide-attach.sh` auto-setup.
</details>

<details>
<summary>Install for OpenCode</summary>

```bash
git clone --depth 1 https://github.com/nyldn/claude-octopus.git ~/.opencode/claude-octopus
mkdir -p ~/.agents/skills
ln -s ~/.opencode/claude-octopus/skills ~/.agents/skills/claude-octopus
```
</details>

<details>
<summary>Other install methods (Claude Code)</summary>

**From the Claude Code UI:** Type `/plugin` in a session → **Marketplace** tab → install **octo**.

**Factory AI (Droid):**
```bash
droid plugin marketplace add https://github.com/nyldn/claude-octopus.git
droid plugin install octo@nyldn-plugins
```
</details>

<details>
<summary>Update / Troubleshooting</summary>

[Claude Code leaves auto-update off by default for third-party marketplaces](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates).
To opt in to host-managed startup updates, run `/plugin`, open
**Marketplaces**, select **nyldn-plugins**, and choose **Enable auto-update**.
When Claude reports that Octopus was updated, run `/reload-plugins` (or restart
Claude Code) before using the new version.

```bash
# Manual update
claude plugin marketplace update nyldn-plugins
claude plugin update octo@nyldn-plugins

# Or let Octopus select the active host's supported plugin-manager commands
~/.claude-octopus/plugin/scripts/orchestrate.sh update-plugin

# Clean reinstall (if update fails)
claude plugin uninstall claude-octopus 2>/dev/null
claude plugin uninstall octo 2>/dev/null
rm -rf ~/.claude/plugins/cache/nyldn-plugins/octo
claude plugin marketplace remove nyldn-plugins
claude plugin marketplace add https://github.com/nyldn/plugins.git
claude plugin install octo@nyldn-plugins
```

Octopus also checks local host metadata at SessionStart. The advisory is
cooldown-limited and performs no network, package-manager, or authentication
calls; it only reports disabled auto-update, a locally known newer version, or
a loaded session that needs a reload. Run focused diagnostics at any time:

```bash
octopus doctor config   # install path, version, manifest, Claude Code feature flags
octopus doctor skills   # skill loading, skillOverrides, plugin zip/URL capability notes
octopus doctor updates  # loaded/install/catalog/cache versions and auto-update state
```

This cannot make an arbitrarily old installation self-heal: code that predates
the advisory must be updated once manually. It does make future stale states
visible and hands the actual mutation to Claude Code or Codex, which own their
plugin caches and lifecycle. See [Plugin Update Safety](docs/PLUGIN-UPDATES.md).

For Anthropic-compatible gateways, Claude Code v2.1.129+ requires an explicit opt-in before `/model` discovers models from `/v1/models`:

```bash
export ANTHROPIC_BASE_URL=https://your-gateway.example/v1
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
```

Claude Code v2.1.129+ also supports `skillOverrides` in Claude settings. Use it to keep rarely used Octopus skills installable while reducing context load, for example by setting niche skills to `name-only` or `user-invocable-only`.
</details>

---

## Claude Code Web and Remote Sessions

When an explicit Octopus workflow is running in a hosted, web, or remote-control environment, set `OCTOPUS_REMOTE_SESSION=true` in that environment. Claude hosting alone does not activate Octopus. Once a workflow starts, `orchestrate.sh` also recognizes `CLAUDE_CODE_REMOTE=true` or `CLAUDE_CODE_WEB=true` and applies unattended-safe runtime defaults:

- `CLAUDE_OCTOPUS_AUTONOMY=autonomous` / `OCTOPUS_AUTONOMY=autonomous` unless already set
- provider smoke tests and Codex tier probes are skipped
- the statusline uses a lightweight remote-safe display

Set `OCTOPUS_REMOTE_STATUSLINE=full` to opt back into the full local HUD, or `OCTOPUS_REMOTE_STATUSLINE=off` to suppress statusline output entirely.

Cloud environment setup should install provider CLIs and expose only the credentials required for the workflow. Paste this into the cloud environment setup script:

```bash
#!/usr/bin/env bash
set -e

npm install -g @openai/codex @qwen-code/qwen-code 2>/dev/null || true

echo "Octopus cloud setup:"
command -v codex >/dev/null 2>&1 && echo "  Codex CLI: installed" || echo "  Codex CLI: missing"
command -v agy >/dev/null 2>&1 && echo "  Antigravity CLI: installed" || echo "  Antigravity CLI: missing"
command -v qwen >/dev/null 2>&1 && echo "  Qwen CLI: installed" || echo "  Qwen CLI: missing"
command -v gh >/dev/null 2>&1 && echo "  GitHub CLI: installed" || echo "  GitHub CLI: optional, install if Sentinel needs GitHub"
```

Set environment variables in the cloud environment, not in the script:

```bash
OPENAI_API_KEY=...
PERPLEXITY_API_KEY=...   # optional
OPENROUTER_API_KEY=...   # optional
```

Provider API calls require internet access from the hosted environment.

For scheduled Claude Code tasks, run `/octo:sentinel` for triage and `/octo:security` for recurring audits. Keep jobs read-only by default and route fixes through `/octo:debug`, `/octo:review`, or `/octo:embrace` after triage.

Set `OCTO_TIER=prototype|mvp|production` as a project hint. It does not hard-block behavior; it helps setup, doctor, and workflow prompts recommend the right amount of verification and provider spend.

---

## 9 Commands That Matter Most

Nine high-traffic commands cover the common Octopus workflows: lifecycle execution, councils, debate, research, design, quality, and specs.

```bash
/octo:embrace build stripe integration     # Full lifecycle: research → define → develop → deliver
/octo:factory "build a CLI that converts CSV to JSON"  # Autonomous pipeline — spec in, software out
/octo:council --goal decision "Should we keep this service monolithic?"  # Persona council with budget/veto gates
/octo:debate monorepo vs microservices     # Structured provider debate with consensus
/octo:research --breadth=standard htmx vs react in 2026  # Attributed multi-provider research
/octo:design mobile checkout redesign       # UI/UX design with BM25 style intelligence
/octo:tdd create user auth                 # Red-green-refactor with test discipline
/octo:security                              # OWASP vulnerability scan + remediation
/octo:prd mobile checkout redesign          # AI-optimized PRD with 100-point scoring
```

`/octo:council` uses the real runner by default. Single-model simulation is only used when explicitly requested with `--simulate` or `--single-model`; `--research-first` writes a research artifact before fanout, and `--corpus-mode append|require` preserves synthesis and plans in project corpus workflows.

Plus 40+ more: review, debug, extract, deck, docs, schedule, parallel, sentinel, optimize, brainstorm, claw, doctor, and [the full set](docs/COMMAND-REFERENCE.md).

Don't remember the command name? Just describe what you need:

```
/octo:auto research microservices patterns    -> routes to discover phase
/octo:auto build user authentication          -> routes to develop phase
/octo:auto compare Redis vs DynamoDB          -> routes to debate
```

The smart router parses your intent and selects the right workflow.

Multi-provider runs also write an agent status ledger. Use `octopus agent-summary` to see which providers contributed, which ran degraded, and which failed before synthesis.

---

## Pick a Command by Goal

Not sure which command to use? Pick by goal:

| I want to... | Use |
|--------------|-----|
| Research a topic thoroughly | `/octo:research` or `/octo:discover` |
| Get a panel recommendation or gated implementation plan | `/octo:council` |
| Debate two approaches | `/octo:debate` |
| Build a feature end-to-end | `/octo:embrace` |
| Design a UI or style system | `/octo:design` |
| Review existing code | `/octo:review` |
| Write tests first, then code | `/octo:tdd` |
| Scan for vulnerabilities | `/octo:security` |
| Write a product spec | `/octo:prd` |
| Go from spec to shipping code | `/octo:factory` |
| Debug a tricky issue | `/octo:debug` |
| Reduce token usage | `/octo:doctor` (includes RTK install + token tips) |
| Just run something quick | `/octo:quick` |

Or type `/octo:auto <what you want>` and the smart router picks for you. Plain-prompt routing is off until you run `/octo:setup`, which turns on **suggestions** (Octopus names a matching command; it never dispatches a provider on its own). Set `OCTOPUS_AUTO_ROUTER_MODE=off` to silence them, or `invoke` to let a matched route load automatically. 🔍

<details>
<summary><strong>How does this compare to Superpowers or plain Claude Code?</strong></summary>

| | Claude Code alone | [Superpowers](https://github.com/obra/superpowers) | Claude Octopus |
|---|---|---|---|
| **Core idea** | One model, your prompts | Structured methodology for one agent | Built-in Claude plus up to 10 external integrations cross-checking each other |
| **Providers** | Claude only | Claude only | Claude host; Codex, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, OpenCode, Grok |
| **Workflow** | Ad-hoc | Spec → plan → subagent-driven dev | Discover → Define → Develop → Deliver (Double Diamond) |
| **Strength** | Simple, no setup | Long autonomous runs with discipline | Multiple perspectives catching blind spots |
| **Consensus gates** | No | No | Yes — 75% agreement threshold |
| **Best for** | Quick tasks, simple features | Large builds with clear specs | Research, review, debates, multi-provider validation |
| **Setup** | Nothing | Install plugin | Install plugin, optionally add providers |

**tl;dr:** Superpowers makes one agent work really well for hours. Octopus makes multiple agents check each other's work. They solve different problems.

</details>

---

## How It Works

### How 10 External Providers Work Together

Claude Octopus coordinates ten external provider integrations alongside the built-in Claude Code host. The optional `claude-sdk` route is a second Anthropic seat, so it is shown below but is not counted as a separate provider family.

| Provider | Role |
|----------|------|
| 🔴 Codex (OpenAI, GPT-5.6 Sol/Terra/Luna) | Code review + implementation — edge-case hunting, terminal-heavy execution, patch/test loops |
| 🧭 Antigravity CLI (`agy`) | Google Antigravity perspective via native stdin print-mode dispatch |
| 🟣 Perplexity | Live web search — CVE lookups, dependency research, current docs |
| 🌐 OpenRouter | Alternative model routing — access 100+ models via single API |
| 🐋 OrcaRouter | OpenAI-compatible gateway routing with policy enforcement and model fallbacks |
| 🟢 Copilot (GitHub) | Zero-cost research — uses existing GitHub Copilot subscription |
| 🟤 Qwen (Alibaba) | Qwen3-Coder research via API-key or Coding-Plan auth |
| ⚫ Ollama (Local) | Zero-cost local LLM — offline, privacy-sensitive, fallback |
| 🟠 OpenCode | Alternate coding-agent integration and cross-checking seat |
| ⚡ Grok (xAI, via cursor-agent) | Frontier-model second opinion — added as a first-class seat in v9.48 |
| 🔵 Claude (Anthropic, Opus 5 + Sonnet 5) | Architecture, strategy, security review, orchestration, consensus, final synthesis |
| 🔵 Claude Agent SDK seat (`claude-sdk`) | Optional second Anthropic seat: Opus 5 with the 1M-token context window, independent of the host session (set `CLAUDE_SDK_API_KEY`) |

Explicit research-breadth, debate, council, and adversarial-review workflows use multiple providers. Generic mergeable work starts with one capable owner and adds another model only for a distinct job. A 75% consensus quality gate prevents questionable work from shipping. Only Claude is required — all others are optional and auto-detected.

**Frontier routing** defaults `architect`, `strategist`, `security-reviewer`, and opt-in `implementer-heavy` to Opus 5 on Claude Code v2.1.219+, with Opus 4.8/4.7/4.6 fallbacks. `code-reviewer` and `implementer` use GPT-5.6 Sol; `synthesizer` uses Sonnet 5 on Claude Code v2.1.197+. Fable 5 remains an opt-in judgment escalation. Existing pins/configs win, and `OCTOPUS_LEGACY_ROLES=1` restores the v9.28 mapping. See [the routing strategy](docs/MODEL-ROUTING-STRATEGY.md).

**Native dynamic workflows:** Claude Code v2.1.154+ can run native dynamic workflows for huge single-Claude migrations. Use that path when one Claude workflow is enough; use Octopus when you need multi-provider disagreement, councils, adversarial review, external model validation, or blind-spot coverage.

### Four Phases: Discover, Define, Develop, Deliver

Four structured phases adapted from the UK Design Council's methodology:

| Phase | Command | What happens |
|-------|---------|-------------|
| Discover | `/octo:discover` | Multi-AI research and broad exploration |
| Define | `/octo:define` | Requirements clarification with consensus |
| Develop | `/octo:develop` | Implementation with quality gates |
| Deliver | `/octo:deliver` | Adversarial review and go/no-go scoring |

Run phases individually or all four with `/octo:embrace`. Configure autonomy: supervised (approve each phase), semi-autonomous (intervene on failures), or autonomous (run all four).

### 32 Specialist Personas

Specialized agents selected by explicit Octopus workflows. `/octo:security` can select security-auditor and `/octo:design-ui-ux` can select ui-ux-designer; ordinary requests never delegate to these agents merely because keywords match.

Categories: Software Engineering (11), Specialized Development (6), Documentation & Communication (5), Research & Strategy (3), Business & Compliance (3), Creative & Design (4).

[Full persona reference](docs/AGENTS.md) | [All 63 skills](docs/COMMAND-REFERENCE.md)

### Built-in Reaction Engine

When agents create PRs, the reaction engine monitors what happens next — CI failures, review comments, stale agents — and responds automatically. No new commands to learn. It fires transparently inside workflows you already use:

| Integration Point | When It Fires |
|-------------------|---------------|
| `/octo:parallel` | Between poll cycles while monitoring work packages |
| `/octo:sentinel` | After triage scan completes |
| `agent-registry.sh health --react` | On-demand health check |

**What it auto-handles:**

| Event | Reaction | Limits |
|-------|----------|--------|
| CI failure | Collects failure logs into agent inbox | 3 retries, escalates after 30m |
| Changes requested | Collects review comments into agent inbox | 2 retries, escalates after 60m |
| Agent stuck | Escalates to human | After 15m with no progress |
| PR approved + CI green | Notifies you it's ready to merge | — |
| PR merged | Marks agent complete | — |

**Override defaults per project** by creating `.octo/reactions.conf`:

```
# EVENT|ACTION|MAX_RETRIES|ESCALATE_AFTER_MIN|ENABLED
ci_failed|forward_logs|5|45|true
changes_requested|forward_comments|3|90|true
stuck|escalate|0|10|true
```

Reactions track 13 agent lifecycle states: `running` → `pr_open` → `ci_pending` → `ci_failed` / `review_pending` → `changes_requested` / `approved` → `mergeable` → `merged` → `done`.

---

## Providers and What They Cost

### Authentication

| Method | Codex | Antigravity | Claude |
|--------|-------|-------------|--------|
| OAuth/subscription (recommended) | `codex login` — included in ChatGPT subscription | `agy` auth — included with Antigravity access | Built into Claude Code |
| API key | `OPENAI_API_KEY` — per-token billing | n/a | Built into Claude Code |

OAuth users pay nothing beyond their existing subscriptions. Qwen is the exception: its free OAuth tier ended on 2026-04-15, so use `QWEN_API_KEY` or Coding-Plan (`OPENAI_API_KEY` + `OPENAI_BASE_URL`).

### What a Typical Run Costs

Illustrative token-only estimates, using standard global API rates checked **2026-07-27**: [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) $5/$30, [Sonar Pro](https://docs.perplexity.ai/docs/getting-started/pricing) $3/$15, and [Opus 5](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model) $5/$25 per million input/output tokens. The ranges assume roughly 90% input and 10% output tokens, standard (not batch, flex, priority, or fast) processing, no cache discounts, and a representative mix of those models. OAuth/subscription seats (Codex via ChatGPT, Antigravity, Copilot) bill nothing extra; Ollama is free.

The table excludes provider tool charges. Sonar Pro adds a **request fee** of $6-$14 per 1,000 requests depending on search-context size. Long-context and provider-specific rate rules can push large runs above these bounds, so check the linked rate cards before material spend.

| Run | Typical volume | Illustrative API token cost (tool fees excluded) |
|-----|----------------|-----------------------------------------------|
| Single probe / quick question (one provider) | 5-20K tokens | $0.01-0.20 |
| Debate (2-3 providers, multi-round) | 30-80K tokens | $0.20-1.00 |
| Council (4-6 seats + synthesis) | 60-150K tokens | $0.50-2.50 |
| Full embrace (4 phases, multi-provider) | 150-400K tokens | $1.00-6.00+ |

Before an expensive run, `/octo:costs` shows a session cost projection; after runs, `/octo:usage` breaks down actual spend per provider and skill. Anything projected over $1 is called out before dispatch.

### What You Get With Just Claude

Everything except multi-AI features. You get all 32 personas, structured workflows, smart routing, context detection, and every skill. Multi-AI orchestration (parallel analysis, debate, consensus) activates when external providers are configured.

---

## Claude Code 2026 Compatibility Layer

v9.50.0 aligns the plugin with Claude Code's 2026 native capabilities. Each piece degrades gracefully on older Claude Code versions via the existing `SUPPORTS_*` feature detection.

- **Routines** (`.claude-plugin/routines.json`): saved automation configs mapping schedule and GitHub-event triggers to `/octo:` commands. All ship disabled; each entry carries a provider roster and a cost note so you know what enabling it will bill.
- **SubagentStop gate** (`hooks/subagent-stop-gate.sh`): quality scoring, provider attribution, cost logging, and council verdict pre-screening before a subagent's summary reaches the lead.
- **`/octo:usage`**: per-provider, per-skill, and per-MCP-server token and cost breakdown in Claude Code's `/usage` schema, built from local usage records (no provider dispatch).
- **Worktree bgIsolation opt-out**: mirror of Claude Code's `worktree.bgIsolation` session flag; disables background worktree cloning for fast direct-edit runs.
- **Claude Agent SDK seat** (`claude-sdk`): with `CLAUDE_SDK_API_KEY` set, workflows can seat Opus 5 with the 1M-token context window independent of the host session.
- **Starter pack** (`skills/octopus-starter-pack/`): debate kickoff, council verdict interpretation, provider health summary, and model cost comparison skills.
- **`/plugin browse` manifest** (`.claude-plugin/plugin-manifest.json`): projected context cost and component inventory for the plugin browse pane.

### New environment variables (v9.50.0)

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_SDK_API_KEY` | unset | Enables the `claude-sdk` provider seat (Claude Agent SDK; Opus 5, 1M context) |
| `OCTOPUS_CLAUDE_SDK_MODEL` | `claude-opus-5` | Model for the `claude-sdk` seat |
| `OCTOPUS_CLAUDE_SDK_MAX_TOKENS` | `32768` | Max output tokens for the `claude-sdk` seat (SDK CLI path) |
| `OCTOPUS_CLAUDE_SDK_ALLOWED_MODELS` | unset | Comma-separated model allowlist for the `claude-sdk` seat |
| `OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET` | `1000000` | Prompt context budget for `claude-sdk` agent types |
| `OCTOPUS_WORKTREE_BG_ISOLATION` | `true` | Set `false` to skip background worktree cloning (fast direct-edit runs) |
| `OCTOPUS_SUBAGENT_GATE_STRICT` | `false` | Set `true` to let the SubagentStop gate block malformed council verdicts and low-quality summaries |
| `OCTOPUS_SUBAGENT_MIN_QUALITY` | `0` | Quality floor (0-100) enforced by the gate in strict mode; `0` disables |

---

## Fable 5 Support

v9.51.0 added first-class support for Claude Fable 5 (Anthropic's Mythos-class model, $10/$50 per MTok — 2x Opus 5). Fable 5 is never auto-selected; pin it with `OCTOPUS_OPUS_MODEL=claude-fable-5` (opus seats) or `OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5` (the 1M-context SDK seat). When a pin is detected, the plugin auto-enables three guards and prints a one-line banner:

- **Security reroute** — security-audit dispatches (security-auditor persona, squeeze red/blue workflow) run on Opus 5 instead of Fable 5, whose safety classifiers can refuse adversarial security phrasing even in authorized audits.
- **Effort clamp** — `xhigh`/`max` effort clamps to `high` for Fable dispatches. Fable 5 effort applies per tool call; higher settings widen scope at 2x cost without extending runs.
- **Refusal retry** — a refused or empty Fable 5 dispatch on the `claude-sdk` seat retries once on Opus 5 instead of failing the seat.

A SessionStart hook injects the dispatch profile (prompt anti-patterns, judgment routing, risk-surface escalation) whenever a pin is active. Full guidance: `skills/blocks/fable5-prompting.md`.

### New environment variables (v9.51.0)

| Variable | Default | Effect |
|----------|---------|--------|
| `OCTOPUS_FABLE5_MODE` | `auto` | `off` disables all Fable 5 guards; `on` forces them without a pin |
| `OCTOPUS_FABLE5_NO_RETRY` | unset | Set `1` to disable the refusal retry on the `claude-sdk` seat |
| `OCTOPUS_FABLE5_FALLBACK_MODEL` | `claude-opus-5` | Override the Fable security/refusal fallback |

---

## Trust, Safety, and Limits

**Command namespace** — Slash commands are namespaced under `/octo:*` and the `octo` natural-language prefix routes through the plugin's intent detection. Lifecycle hooks (session start/end, prompt submit, tool use, compaction, plan mode, worktrees, task lifecycle, idle, config change, permission events) also attach to Claude Code so multi-provider routing, freeze/discipline modes, and the work-queue watcher can function. See `hooks/hooks.json` for the full list. Uninstall removes every hook.

**Data locations** — Results in `~/.claude-octopus/results/`, logs in `~/.claude-octopus/logs/`, project state in `.octo/`. Nothing hidden.

**Provider transparency** — Every command shows a 🐙 activation indicator on launch. Provider markers such as 🔴 🟡 🧭 🟣 🔵 show exactly which providers are running and when external APIs are called. You always know what's happening.

**Session provider controls** — Temporarily disable exhausted providers without uninstalling them. For example, `/octo:model-config disable codex --session` keeps Codex out of provider detection and multi-LLM fanout for the current session; `/octo:model-config clear-allowlist --session` restores the default.

**Clean uninstall** — Run `claude plugin uninstall octo` from your terminal. If you see a scope error, add `--scope project`. No residual config changes.

---

## Works With OpenClaw

Claude Octopus ships with a compatibility layer for [OpenClaw](https://github.com/openclaw/openclaw), the open-source AI assistant framework. This lets you expose Octopus workflows to messaging platforms (Telegram, Discord, Signal, WhatsApp) without modifying the Claude Code plugin.

### Architecture

```
Claude Code Plugin (unchanged)
  └── .mcp.json ─── MCP Server ─── orchestrate.sh
                                        ↑
OpenClaw Extension ─────────────────────┘
```

Three components, zero changes to the core plugin:

| Component | Location | Purpose |
|-----------|----------|---------|
| MCP Server | `mcp-server/` | Exposes 10 Octopus tools via Model Context Protocol |
| OpenClaw Extension | `openclaw/` | Wraps workflows for OpenClaw's extension API |
| Skill Schema | `mcp-server/src/schema/skill-schema.json` | Universal skill metadata format |

### MCP Server

The MCP server is **opt-in** — it does not start automatically. This prevents a permanent `✘ failed` status in Claude Code's `/mcp` panel for users who don't need it.

To enable it, add the server to your project's `.mcp.json` or global Claude Code settings:

```json
{
  "mcpServers": {
    "octo-claw": {
      "command": "node",
      "args": ["--require", "./mcp-server/check-node-version.js", "./mcp-server/dist/index.js"],
      "cwd": "<path-to-claude-octopus>",
      "env": {
        "OCTO_CLAW_ENABLED": "true"
      }
    }
  }
}
```

Once enabled, it exposes:

- `octopus_discover`, `octopus_define`, `octopus_develop`, `octopus_deliver` — Individual phases
- `octopus_embrace` — Full Double Diamond workflow
- `octopus_debate`, `octopus_council`, `octopus_review`, `octopus_security` — Specialized workflows
- `octopus_list_skills`, `octopus_status` — Introspection

Any MCP-compatible client can connect to the server.

### OpenClaw Extension

Install in an OpenClaw instance from git:

```bash
npm install github:nyldn/claude-octopus#main --prefix openclaw
```

Or clone and link locally:

```bash
cd openclaw && npm install && npm run build
```

The extension registers as an OpenClaw plugin with configurable workflows, autonomy modes, and Claude Code path resolution.

### Build & Validate

```bash
./scripts/build-openclaw.sh          # Regenerate skill registry from frontmatter
./scripts/build-openclaw.sh --check  # CI mode — exits non-zero if out of sync
./tests/validate-openclaw.sh         # 13-check validation suite
```

---

## FAQ

**Do I need every AI provider?**
No. One external provider plus Claude gives you multi-AI features. No external providers still gives you personas, workflows, and skills.

**Will this break my existing Claude Code setup?**
No. Activates only with the `octo` prefix. Results stored separately. Uninstalls cleanly.

**What happens if a provider times out?**
The workflow continues with available providers. You'll see the status in the visual indicators.

**Why "octopus"?**
🐙 *Fun fact: a real octopus has three hearts, blue blood, and 500 million neurons — two-thirds of which live in its eight arms.* Each arm can taste, touch, and act independently. Claude Octopus works the same way: each tentacle (command) operates autonomously with its own squeeze of logic, then ink flows back as the final deliverable. The crossfire review? That's the squeeze — adversarial pressure that untangles everything before it ships.

**How do I debug when something goes wrong?**
Run commands with the `--verbose` flag to get detailed debugging output. Logs are stored in `~/.claude-octopus/logs/` for inspection. You can also use `/octo:doctor` to run diagnostics and identify potential issues.

---

## Community

Join [r/ClaudeOctopus](https://www.reddit.com/r/ClaudeOctopus/) for help, workflow tips, showcases, and updates.

[![Star History Chart](https://api.star-history.com/image?repos=nyldn/claude-octopus&type=date&legend=top-left)](https://www.star-history.com/?repos=nyldn%2Fclaude-octopus&type=date&legend=top-left)

### Contributing

1. [Report issues](https://github.com/nyldn/claude-octopus/issues)
2. Submit PRs following existing code style
3. `git clone https://github.com/nyldn/claude-octopus.git && make test`

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for details.

---

## Documentation

- [Documentation Guide](docs/README.md) — Start here
- [Command Reference](docs/COMMAND-REFERENCE.md) — Commands, triggers, and provider indicators
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Provider auth failures and common errors
- [Architecture](docs/ARCHITECTURE.md) — Provider flow and execution model
- [Agents & Personas](docs/AGENTS.md) — All 32 personas
- [Provider Wiring Map](docs/PROVIDERS.md) — How a provider is wired (contributors)
- [Developer Guide](docs/DEVELOPER.md) — Modular config, E2E testing, enforcement patterns
- [Scheduler](docs/SCHEDULER.md) — Scheduled workflow runner
- [Privacy](docs/PRIVACY.md) — What leaves your machine and when
- [Security Policy](SECURITY.md) — Threat model and trust boundaries
- [Releasing](RELEASING.md) — Release checklist (maintainers)
- [Changelog](CHANGELOG.md)

---

## Attribution

- **[wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)** — AI Debate Hub. MIT License.
- **[obra/superpowers](https://github.com/obra/superpowers)** — Discipline skills patterns, verification-before-completion philosophy, two-stage review approach, and review response patterns. MIT License.
- **[nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)** — BM25 design intelligence databases. MIT License.
- **[UK Design Council](https://www.designcouncil.org.uk/our-resources/the-double-diamond/)** — Double Diamond methodology.

---

## License

MIT — see [LICENSE](LICENSE)

<p align="center">
  <a href="https://github.com/nyldn">nyldn</a> | MIT License | <a href="https://www.reddit.com/r/ClaudeOctopus/">r/ClaudeOctopus</a> | <a href="https://github.com/nyldn/claude-octopus/issues">Report Issues</a>
</p>
