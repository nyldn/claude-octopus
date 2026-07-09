# Troubleshooting

The most common failure is a provider that will not authenticate or is silently skipped. Start with the two built-in diagnostics, then use the per-provider table.

```bash
/octo:doctor          # full health check: install, auth, version, connectivity per provider
octopus <cmd> --verbose   # per-dispatch detail: which provider, which model, why skipped
```

For model-selection questions specifically, `OCTOPUS_TRACE_MODELS=1` prints the resolution tier (env pin, session override, phase route, capability map, default) for every dispatch.

## Provider auth failures

A provider is used only when its CLI is installed AND its auth check passes. If a provider you expect is missing from banners and agent tables, it failed one of these checks.

| Provider | Availability check | Fix |
|----------|-------------------|-----|
| 🔴 Codex | `codex` on PATH, auth configured | `codex login` (ChatGPT subscription) or set `OPENAI_API_KEY` |
| 🟡 Gemini | `gemini` on PATH, auth configured | Sign in via `gemini` (Google account) or set `GEMINI_API_KEY` |
| 🧭 Antigravity | `agy` on PATH | Install the Antigravity CLI and sign in; verify with `agy models` |
| 🟢 Copilot | `copilot` on PATH plus one of: `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, `~/.copilot/config.json`, or `gh auth status` passing | `gh auth login` is the simplest path |
| 🟤 Qwen | `qwen` on PATH plus `~/.qwen/oauth_creds.json` or `QWEN_API_KEY` | Free OAuth ended 2026-04-15; set `QWEN_API_KEY` or Coding-Plan auth (`OPENAI_API_KEY` + `OPENAI_BASE_URL`) |
| ⚫ Ollama | `ollama` on PATH AND server responding at `http://localhost:11434` | `ollama serve`; a missing model is NOT auto-pulled (see below) |
| 🟣 Perplexity | `PERPLEXITY_API_KEY` set | Export the key; no CLI needed |
| 🌐 OpenRouter | Enabled in config AND `OPENROUTER_API_KEY` set | Export the key |
| 🟤 OpenCode | `opencode` on PATH, `opencode auth list` succeeds | `opencode auth login` |
| ⚡ Grok | `cursor-agent` binary present plus `CURSOR_API_KEY` or authenticated `~/.cursor/cli-config.json` | Sign in to the Cursor CLI or export `CURSOR_API_KEY` |
| 🔵 claude-sdk seat | `CLAUDE_SDK_API_KEY` set | Export an Anthropic API key; the shim exits with code 78 and "CLAUDE_SDK_API_KEY is not set" without it |

## Common non-auth failures

**"Circuit open for <provider> — skipping"** — the provider failed repeatedly this session and its circuit breaker tripped. It recovers automatically after the cooldown; to force it back immediately, start a new session or clear session state.

**Provider quota-dead** — a provider that hit quota or auth-death earlier in the session is skipped for the rest of it. Check the provider's own dashboard, then restart the session.

**Ollama model missing, nothing downloads** — intentional. Auto-pull is fail-closed to prevent unbounded multi-GB downloads. Pull explicitly (`ollama pull <model>`) or allow it with `OCTOPUS_OLLAMA_ALLOW_PULL=true` (capped by `OCTOPUS_OLLAMA_MAX_PULL_GB`, default 20).

**A provider is installed but you want it out of the roster** — `/octo:model-config disable <provider> --session` removes it from detection and fanout for the current session; `clear-allowlist --session` restores defaults.

**Config changes not taking effect** — settings are re-read when the ConfigChange hook fires; if in doubt, check for the reload log line ("ConfigChange detected") or restart the session.

**Fable 5 dispatch refused or empty** — expected for security-audit phrasing on `claude-fable-5` pins; the plugin reroutes security passes to Opus 4.8 and retries refused claude-sdk dispatches automatically. Details: `skills/blocks/fable5-prompting.md`. Disable the guards with `OCTOPUS_FABLE5_MODE=off`.

**Empty results from a dispatch that "succeeded"** — check `~/.claude-octopus/results/` for the raw artifact and `~/.claude-octopus/logs/` for the dispatch log. `--verbose` on the next run shows the constructed command.

## Escalation

If `/octo:doctor` is green and a workflow still fails, capture `--verbose` output plus the session log and open an issue: https://github.com/nyldn/claude-octopus/issues
