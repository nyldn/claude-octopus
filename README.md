# 🐙 Claude Octopus

Every AI model has blind spots. Claude Octopus puts up to nine of them on every task, so blind spots surface before you ship — not after. It orchestrates Codex, Gemini, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, and OpenCode alongside Claude Code, with consensus gates that flag any disagreements.

**Claude-native first, Octopus for escalation.** Use Claude-native `/init`, `/review`, and `/security-review` when Claude is enough. Use Octopus when you want multiple model opinions, adversarial review, or stricter multi-LLM workflows.

<p align="center">
  <img src="docs/assets/demo.gif" alt="Claude Octopus Demo — debate and research with multiple AI providers" width="720">
</p>

<p align="center">
  <a href="https://claude.ai"><img src="https://img.shields.io/badge/Claude-Built_with_AI-c96442?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJhMTAgMTAgMCAxIDAgMCAyMCAxMCAxMCAwIDAgMCAwLTIwbTAgMS44YTEuMiAxLjIgMCAwIDEgLjg1LjM1bDEuNSA0LjVhLjYuNiAwIDAgMCAuMzUuMzVsNC41IDEuNWExLjIgMS4yIDAgMCAxIDAgMi4yN2wtNC41IDEuNWEuNi42IDAgMCAwLS4zNS4zNWwtMS41IDQuNWExLjIgMS4yIDAgMCAxLTIuMjcgMGwtMS41LTQuNWEuNi42IDAgMCAwLS4zNS0uMzVsLTQuNS0xLjVhMS4yIDEuMiAwIDAgMSAwLTIuMjdsNC41LTEuNWEuNi42IDAgMCAwIC4zNS0uMzVsMS41LTQuNUExLjIgMS4yIDAgMCAxIDEyIDMuOCIvPjwvc3ZnPg==&labelColor=333" alt="Built with Claude"></a>
  <a href="https://github.com/nyldn/claude-octopus/actions/workflows/test.yml"><img src="https://github.com/nyldn/claude-octopus/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <img src="https://img.shields.io/badge/Tests-117_suites_passing-brightgreen" alt="117 suites passing">
  <img src="https://img.shields.io/badge/Version-9.47.2-blue" alt="Version 9.47.2">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.14+_required-blueviolet" alt="Requires Claude Code v2.1.14+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

🐙 **Research, build, review, and ship — with nine AI providers checking each other's work.** Say what you need, and the right workflow runs. Claude-native handles the ordinary path; Octopus handles the escalated path. A 75% consensus gate catches disagreements before they reach production. No single model's blind spots slip through.

🧠 **Remembers across sessions.** Integrates with [claude-mem](https://github.com/thedotmack/claude-mem) for persistent memory — past decisions, research, and context survive session boundaries.

⚡ **Spec in, software out.** Dark Factory mode takes a spec and autonomously runs the full pipeline — research, define, develop, deliver. You review the output, not every step.

🔄 **Four-phase methodology, not just tools.** Every task moves through Discover → Define → Develop → Deliver, with quality gates between phases. Other orchestrators give you infrastructure. Octopus gives you the workflows.

🐙 **32 specialized personas** (role-specific AI agents like security-auditor, backend-architect), **49 commands** (slash commands you type), **54 skills** (reusable workflow modules). Say "audit my API" and the right expert activates. Don't know the command? The smart router figures it out.

🐙 **Works with just Claude. Scales to nine.** Zero providers needed to start. Add them one at a time — each activates automatically when detected.

💰 **Five providers cost nothing extra when you already have access.** Codex, Gemini, Antigravity CLI, and Copilot use existing subscriptions or local auth. Ollama runs locally for free. Qwen now requires API-key or Coding-Plan auth; its free OAuth tier ended on 2026-04-15.

---

## What's New

> 🆕 **v9.41 — Multi-LLM Council.** `/octo:council` runs a structured 3/5/7-persona deliberation across Claude, Codex, Gemini, and OpenCode with goal modes (`advice`, `decision`, `plan`, `implement`, `review`), styles (`balanced`, `adversarial`, `red-team`, `executive`, `implementation`), benchmark-aware role routing, quorum + critical-veto gates, budget caps, and gated worktree handoff for approved plans. Use it when one model's opinion isn't enough.
>
> ```bash
> /octo:council --goal decision --style adversarial "Should this service stay monolithic?"
> /octo:council --goal implement --implement plan-only "Refactor the auth flow"
> ```

| Version | Best Features |
|---------|--------------|
| **v9.41** (new) | **`/octo:council`** promoted to first-class workflow — structured multi-LLM deliberation with goal modes, adversarial/red-team styles, benchmark-aware persona routing, quorum and critical-veto gates, budget preflight, and gated worktree handoff for approved implementation plans. |
| **v9** (current) | Up to 9 providers (Codex, Gemini, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, OpenCode). Structured provider debates and configurable multi-LLM councils. Smart router — just say what you need. Agent summary tables show which providers actually contributed. Provider-aware prompt preflight prevents silent oversize failures. Research breadth modes fan out light, standard, or exhaustive investigations. Setup aliases and fuzzy `/octo:*` corrections reduce command friction. Discipline mode with 8 auto-invoke gates. Two-stage review. Circuit breakers with automatic provider recovery. Cursor + OpenCode + Codex cross-compatibility. Token compression: `bin/octo-compress` pipe + auto PostToolUse hook save ~7,300 tokens/session. PostCompact context recovery. `bin/octopus` CLI. 175+ CC feature flags through v2.1.157, including Opus 4.8 and dynamic workflow awareness. |
| **v8** | Multi-LLM code review with inline PR comments. Parallel workstreams in isolated git worktrees. Reaction engine — auto-responds to CI failures. 32 specialized personas. Dark Factory autonomous pipeline. |
| **v7** | Double Diamond workflow. Multi-provider dispatch. Quality gates and consensus scoring. Configurable sandbox modes. |

[Full changelog →](CHANGELOG.md)

## Quickstart

```bash
# Terminal (not inside a Claude Code session):
claude plugin marketplace add https://github.com/nyldn/plugins.git
claude plugin install octo@nyldn-plugins

# Then inside Claude Code:
/octo:setup
```

That's it. Setup detects installed providers, shows what's missing, and walks you through configuration. You need **zero** external providers to start — Claude is built in.

Claude Code **v2.1.14+** is the minimum supported runtime. Newer Claude Code releases unlock additional Octopus diagnostics and release checks automatically; the current plugin tracks feature flags through **Claude Code v2.1.157**.

<details>
<summary>Install for Codex CLI</summary>

```bash
git clone --depth 1 https://github.com/nyldn/claude-octopus.git ~/.codex/claude-octopus && mkdir -p ~/.agents/skills && ln -sf ~/.codex/claude-octopus/skills ~/.agents/skills/claude-octopus
```

Restart Codex. Skills appear automatically — invoke with `$skill-doctor`, `$skill-debug`, etc.
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
        "OPENAI_API_KEY": "${env:OPENAI_API_KEY}",
        "GEMINI_API_KEY": "${env:GEMINI_API_KEY}"
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
        "OPENAI_API_KEY": "${env:OPENAI_API_KEY}",
        "GEMINI_API_KEY": "${env:GEMINI_API_KEY}"
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

```bash
# Update
claude plugin marketplace update nyldn-plugins
claude plugin update octo@nyldn-plugins

# Clean reinstall (if update fails)
claude plugin uninstall claude-octopus 2>/dev/null
claude plugin uninstall octo 2>/dev/null
rm -rf ~/.claude/plugins/cache/nyldn-plugins/octo
claude plugin marketplace remove nyldn-plugins
claude plugin marketplace add https://github.com/nyldn/plugins.git
claude plugin install octo@nyldn-plugins
```

Run focused diagnostics after updating:

```bash
/octo:doctor config   # install path, version, manifest, Claude Code feature flags
/octo:doctor skills   # skill loading, skillOverrides, plugin zip/URL capability notes
```

For Anthropic-compatible gateways, Claude Code v2.1.129+ requires an explicit opt-in before `/model` discovers models from `/v1/models`:

```bash
export ANTHROPIC_BASE_URL=https://your-gateway.example/v1
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
```

Claude Code v2.1.129+ also supports `skillOverrides` in Claude settings. Use it to keep rarely used Octopus skills installable while reducing context load, for example by setting niche skills to `name-only` or `user-invocable-only`.
</details>

---

## Claude Code Web and Remote Sessions

When Claude Code is running in a hosted, web, or remote-control environment, set `OCTOPUS_REMOTE_SESSION=true` in that environment. If Claude Code itself exports `CLAUDE_CODE_REMOTE=true` or `CLAUDE_CODE_WEB=true`, Octopus detects that automatically. Remote sessions are treated as unattended by default:

- `CLAUDE_OCTOPUS_AUTONOMY=autonomous` / `OCTOPUS_AUTONOMY=autonomous` unless already set
- provider smoke tests and Codex tier probes are skipped
- the statusline uses a lightweight remote-safe display

Set `OCTOPUS_REMOTE_STATUSLINE=full` to opt back into the full local HUD, or `OCTOPUS_REMOTE_STATUSLINE=off` to suppress statusline output entirely.

Cloud environment setup should install provider CLIs and expose only the credentials required for the workflow. Paste this into the cloud environment setup script:

```bash
#!/usr/bin/env bash
set -e

npm install -g @openai/codex @google/gemini-cli @qwen-code/qwen-code 2>/dev/null || true

echo "Octopus cloud setup:"
command -v codex >/dev/null 2>&1 && echo "  Codex CLI: installed" || echo "  Codex CLI: missing"
command -v gemini >/dev/null 2>&1 && echo "  Gemini CLI: installed" || echo "  Gemini CLI: missing"
command -v agy >/dev/null 2>&1 && echo "  Antigravity CLI: installed" || echo "  Antigravity CLI: missing"
command -v qwen >/dev/null 2>&1 && echo "  Qwen CLI: installed" || echo "  Qwen CLI: missing"
command -v gh >/dev/null 2>&1 && echo "  GitHub CLI: installed" || echo "  GitHub CLI: optional, install if Sentinel needs GitHub"
```

Set environment variables in the cloud environment, not in the script:

```bash
OPENAI_API_KEY=...
GEMINI_API_KEY=...
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

Or skip the table — type `/octo:auto <what you want>` or just say `octo <what you want>`, and the smart router picks for you. 🔍

<details>
<summary><strong>How does this compare to Superpowers or plain Claude Code?</strong></summary>

| | Claude Code alone | [Superpowers](https://github.com/obra/superpowers) | Claude Octopus |
|---|---|---|---|
| **Core idea** | One model, your prompts | Structured methodology for one agent | Up to 9 providers cross-checking each other |
| **Providers** | Claude only | Claude only | Codex, Gemini, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, OpenCode |
| **Workflow** | Ad-hoc | Spec → plan → subagent-driven dev | Discover → Define → Develop → Deliver (Double Diamond) |
| **Strength** | Simple, no setup | Long autonomous runs with discipline | Multiple perspectives catching blind spots |
| **Consensus gates** | No | No | Yes — 75% agreement threshold |
| **Best for** | Quick tasks, simple features | Large builds with clear specs | Research, review, debates, multi-provider validation |
| **Setup** | Nothing | Install plugin | Install plugin, optionally add providers |

**tl;dr:** Superpowers makes one agent work really well for hours. Octopus makes multiple agents check each other's work. They solve different problems.

</details>

---

## How It Works

### How 9 Providers Work Together

Claude Octopus coordinates up to nine AI providers:

| Provider | Role |
|----------|------|
| 🔴 Codex (OpenAI, GPT-5.4) | Code review + implementation — edge-case hunting, terminal-heavy execution, patch/test loops |
| 🟡 Gemini (Google) | Ecosystem breadth — alternatives, research synthesis |
| 🧭 Antigravity CLI (`agy`) | Google Antigravity perspective via native stdin print-mode dispatch |
| 🟣 Perplexity | Live web search — CVE lookups, dependency research, current docs |
| 🌐 OpenRouter | Alternative model routing — access 100+ models via single API |
| 🟢 Copilot (GitHub) | Zero-cost research — uses existing GitHub Copilot subscription |
| 🟤 Qwen (Alibaba) | Qwen3-Coder research via API-key or Coding-Plan auth |
| ⚫ Ollama (Local) | Zero-cost local LLM — offline, privacy-sensitive, fallback |
| 🔵 Claude (Anthropic, Opus 4.8 + Sonnet 4.6) | Architecture, strategy, security review, orchestration, consensus, final synthesis |

Providers run in parallel for research, sequentially for problem scoping, and adversarially for review. A 75% consensus quality gate prevents questionable work from shipping. Only Claude is required — all others are optional and auto-detected.

**Premium Claude routing** defaults `architect`, `strategist`, `security-reviewer`, and opt-in `implementer-heavy` to the current Opus family. On Claude Code v2.1.154+ that is Opus 4.8; older supported hosts fall back to Opus 4.7 and then 4.6. `code-reviewer` and `implementer` default to GPT-5.4 (Terminal-Bench and edge-case review). Opt out with `OCTOPUS_LEGACY_ROLES=1` to restore the v9.28 mapping. See [CHANGELOG](CHANGELOG.md) and [GPT-5.4 prompting guide](docs/GPT-5.4-PROMPTING.md).

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

Specialized agents that activate automatically based on your request. When you say "audit my API for vulnerabilities," security-auditor activates. When you say "design a dashboard," ui-ux-designer takes over.

Categories: Software Engineering (11), Specialized Development (6), Documentation & Communication (5), Research & Strategy (3), Business & Compliance (3), Creative & Design (4).

[Full persona reference](docs/AGENTS.md) | [All 54 skills](docs/COMMAND-REFERENCE.md)

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

| Method | Codex | Gemini | Antigravity | Claude |
|--------|-------|--------|-------------|--------|
| OAuth/subscription (recommended) | `codex login` — included in ChatGPT subscription | Google account — included in AI subscription | `agy` auth — included with Antigravity access | Built into Claude Code |
| API key | `OPENAI_API_KEY` — per-token billing | `GEMINI_API_KEY` — per-token billing | n/a | Built into Claude Code |

OAuth users pay nothing beyond their existing subscriptions. Qwen is the exception: its free OAuth tier ended on 2026-04-15, so use `QWEN_API_KEY` or Coding-Plan (`OPENAI_API_KEY` + `OPENAI_BASE_URL`).

### What You Get With Just Claude

Everything except multi-AI features. You get all 32 personas, structured workflows, smart routing, context detection, and every skill. Multi-AI orchestration (parallel analysis, debate, consensus) activates when external providers are configured.

---

## Trust, Safety, and Limits

**Command namespace** — Slash commands are namespaced under `/octo:*` and the `octo` natural-language prefix routes through the plugin's intent detection. Lifecycle hooks (session start/end, prompt submit, tool use, compaction, plan mode, worktrees, task lifecycle, idle, config change, permission events) also attach to Claude Code so multi-provider routing, freeze/discipline modes, and the work-queue watcher can function. See `.claude-plugin/hooks.json` for the full list. Uninstall removes every hook.

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
- [Feature Gap Analysis](docs/FEATURE-GAP.md) — CC feature adoption tracker
- [Architecture](docs/ARCHITECTURE.md) — Provider flow and execution model
- [Plugin Architecture](docs/PLUGIN-ARCHITECTURE.md) — Internal plugin structure
- [Agents & Personas](docs/AGENTS.md) — All 32 personas
- [CLI Reference](docs/CLI-REFERENCE.md) — Direct CLI usage, debug mode, async, and tmux
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
