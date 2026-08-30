# Troubleshooting

The most common failure is a provider that will not authenticate or is silently skipped. Start with the two built-in diagnostics, then use the per-provider table.

```bash
octopus doctor                  # local install, auth signals, versions, and configuration
octopus doctor providers --live # bounded live AGY catalog/model/dispatch check
octopus <cmd> --verbose         # per-dispatch detail: which provider, which model, why skipped
```

Inside Claude Code, invoke the same diagnostics with `/octo:skill-doctor`.
That namespaced skill preserves Claude Code's native `/doctor` command.

For model-selection questions specifically, `OCTOPUS_TRACE_MODELS=1` prints the resolution tier (env pin, session override, phase route, capability map, default) for every dispatch.

## Provider auth failures

A provider is used only when its CLI is installed AND its auth check passes. If a provider you expect is missing from banners and agent tables, it failed one of these checks.

| Provider | Availability check | Fix |
|----------|-------------------|-----|
| 🔴 Codex | `codex` on PATH, auth configured | `codex login` (ChatGPT subscription) or set `OPENAI_API_KEY` |
| 🧭 Antigravity | `agy` on PATH; opt-in live check verifies catalog, model, and dispatch | Launch plain `agy` and finish its browser sign-in, then run `octopus doctor providers --live`. There is no separate login shell subcommand. On macOS keyring errors, open Keychain Access, find the Antigravity CLI item, and allow `agy` under Access Control. See the official [install/auth](https://antigravity.google/docs/cli/install) and [troubleshooting](https://antigravity.google/docs/cli/troubleshooting) guides. |
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

**Fable 5 dispatch refused or empty** — expected for security-audit phrasing on `claude-fable-5` pins; the plugin reroutes security passes and retries refused claude-sdk dispatches once on Opus 5 by default. Set `OCTOPUS_FABLE5_FALLBACK_MODEL` to replace that fallback target. Details: `skills/blocks/fable5-prompting.md`. Disable the guards with `OCTOPUS_FABLE5_MODE=off`.

**Empty results from a dispatch that "succeeded"** — check `~/.claude-octopus/results/` for the raw artifact and `~/.claude-octopus/logs/` for the dispatch log. `--verbose` on the next run shows the constructed command.

## Uninstall the plugin and keep local data

Run this from a terminal:

```bash
claude plugin uninstall octo
```

If Claude reports a scope mismatch, rerun it with `--scope project`. Reload or
restart Claude Code afterward so the removed commands and hooks are no longer
active.

Plugin uninstall does not delete your data. Results and logs remain in
`~/.claude-octopus/results/` and `~/.claude-octopus/logs/`. Configuration,
preferences, and other local state remain under `~/.claude-octopus/`. Each
project's run state remains in its `.octo/` directory. You can reinstall later
and keep using this data.

## Review retained data before manual removal

Inventory retained paths before deciding what to keep:

```bash
du -sh "${HOME}/.claude-octopus" 2>/dev/null
find "${HOME}/.claude-octopus" -mindepth 1 -maxdepth 2 -print 2>/dev/null
find . -maxdepth 3 -type d -name '.octo' -prune -print
```

These commands only list paths and disk use. They do not delete anything.
Archive results, logs, or configuration that you may need. Then review the
exact paths and require an explicit confirmation before deleting them with your
shell or file manager. Avoid wildcards and broad parent directories.

Claude Octopus does not provide an automatic purge command. A purge workflow
would need its own dry run, archive option, exact-path validation, and
confirmation gate before it could safely remove retained data.

## Escalation

If `octopus doctor` is green and a workflow still fails, capture `--verbose` output plus the session log and open an issue: https://github.com/nyldn/claude-octopus/issues
