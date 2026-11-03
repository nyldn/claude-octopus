---
command: preflight
disable-model-invocation: true
description: Check provider health before running multi-LLM workflows
allowed-tools: Bash
---

# Octopus Provider Readiness

Show the shared readiness result for every registered provider. The default is
a local-only static check: installation, safe configuration metadata, and
known quota state. It does not contact provider services.

```bash
OCTO_ROOT="${OCTO_ROOT:-${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "${OCTO_ROOT}/scripts/helpers/preflight.sh"
```

When the user explicitly asks to verify live provider health, run the bounded
live form:

```bash
bash "${OCTO_ROOT}/scripts/helpers/preflight.sh" --live
```

Both modes consume the Provider Registry 2.0 readiness contract. Do not run
separate binary, authentication, model, quota, or network checks while
rendering the result. Use `reason_code` and `remediation` from the shared
objects when explaining a provider that needs attention.

When `OCTOPUS_COUNCIL_DEFAULT_PROVIDERS` pins a council roster (for example
`claude,agy` when Codex leads the session), preflight checks exactly those
seats, names the list it used, and reports a seat that is not ready; the
orchestrator's `preflight` command fails in that case, and so does its smoke
test when any roster seat it tested fails. A roster seat with no provider
detection, such as `openai-tools`, is listed as not checked (`roster_unchecked`
in the JSON) rather than as not ready. When preflight runs inside a
Codex or Claude Code sandbox, a provider that needs a keychain login, the
network or files outside the workspace can fail there and work outside it; the
output says so, and the remedy is to re-run preflight outside the sandbox.

Use this before `/octo:embrace`, `/octo:research`, or `/octo:council` to confirm provider readiness and avoid mid-workflow surprises.

**Common issues:**
- `Ollama` requests a live check → rerun with `--live`; start it with `ollama serve` if the server is stopped
- `Codex CLI` unavailable → run `codex login` or `npm install -g @openai/codex`
- `Antigravity CLI` unavailable → verify `agy` is on PATH, then launch plain `agy` and complete its browser sign-in or reinstall Antigravity CLI

Run `/octo:setup` to install or configure any missing provider.
