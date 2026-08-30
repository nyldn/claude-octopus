---
command: setup
disable-model-invocation: true
description: Get Claude Octopus ready, verify it locally, or open advanced setup
aliases:
  - sys-setup
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Claude Octopus Setup

**Your first output line MUST be:** `🐙 Octopus Setup`

The default path gets the user to a verified first success. It does not install
optional companions, tune models, or contact a provider service. Every install,
login, or configuration write requires an explicit choice first.

Always show the interactive setup choice when this command is invoked, even when
the current readiness summary is already healthy.

Never ask the user to paste a secret into chat. Use the provider's login command
or documented environment configuration. Never turn a failed recheck into a
success message.

## Default path

### 1. Resolve the installed plugin

Use the active plugin root when available, then the stable Octopus symlink. The
fallback search is read-only; setup must not repair paths before the user has
made a choice.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ ! -x "$OCTO_ROOT/scripts/helpers/preflight.sh" ]]; then
  OCTO_ROOT="${HOME}/.claude-octopus/plugin"
fi
if [[ ! -x "$OCTO_ROOT/scripts/helpers/preflight.sh" ]]; then
  OCTO_ROOT="$(find "${HOME}/.claude/plugins/cache" "${HOME}/Library/Application Support/Claude" "${LOCALAPPDATA:-/dev/null}/Claude" "${XDG_DATA_HOME:-${HOME}/.local/share}/Claude" -maxdepth 8 -path '*/nyldn-plugins/octo/*/scripts/helpers/preflight.sh' -print -quit 2>/dev/null | sed 's#/scripts/helpers/preflight.sh$##')"
fi
[[ -x "$OCTO_ROOT/scripts/helpers/preflight.sh" ]] || {
  echo "Octopus installation not found. Reinstall octo@nyldn-plugins, then run /octo:setup again."
  exit 1
}
export OCTO_ROOT
```

### 2. Show shared readiness

Run one static, local-only readiness check. This is the same Provider Registry
2.0 contract used by Doctor, `detect-providers`, and workflow admission.

```bash
READINESS_JSON="$(bash "${OCTO_ROOT}/scripts/helpers/preflight.sh" --json 2>/dev/null)"
if ! jq -e '
  .check_kind == "static" and
  (.results | type == "array" and length > 0) and
  all(.results[];
    has("provider") and has("status") and has("reason_code") and
    has("checked_at") and has("duration_ms") and has("remediation"))
' <<<"$READINESS_JSON" >/dev/null 2>&1; then
  echo "Provider readiness report is invalid. Run /octo:skill-doctor in Claude Code or 'octopus doctor providers --json' in a shell."
  exit 1
fi

printf 'Provider readiness:\n'
jq -r '.results[] | "  \(.provider): \(.status) [\(.reason_code)]"' <<<"$READINESS_JSON"
```

Render only those shared objects. Do not run separate binary, auth, model,
quota, or network checks while explaining the result. Use each object's
`remediation` when a provider needs attention.

### 3. Choose the shortest useful path

```javascript
AskUserQuestion({
  questions: [{
    question: "How would you like to finish setup?",
    header: "Setup",
    multiSelect: false,
    options: [
      {label: "Use Claude alone (Recommended)", description: "Finish now with Claude Code's built-in model; add a provider later if useful."},
      {label: "Configure one provider", description: "Choose one external provider and follow its exact readiness remediation."},
      {label: "Open Advanced setup", description: "Configure optional tools, routing, models, or project preferences."}
    ]
  }]
})
```

If the user chooses **Use Claude alone**, make no provider changes and continue
to verification.

If the user chooses **Configure one provider**, show providers from
`READINESS_JSON`, prioritizing `degraded` before `missing`. Ask which single
provider they want. Registered options include Codex, Antigravity (`agy`),
Perplexity, and the other providers present in the shared result. Then show its
`remediation` and the exact proposed command or file change. Ask for
confirmation before running it. Authentication commands that open a browser
must be run by the user in their shell; remote sessions must never launch them
automatically.

After the selected provider is configured, rerun only:

```bash
bash "${OCTO_ROOT}/scripts/helpers/preflight.sh" --json
```

Confirm that provider's shared result is `available`. If it is not, show its
new `reason_code` and `remediation`, then stop without claiming success.

If the user chooses **Open Advanced setup**, jump to the Advanced setup section.

### 4. Run a deterministic no-billing verification

This validates the captured contract and shipped shell entry points. It makes
no provider request and cannot incur provider usage.

```bash
jq -e '.results | length > 0' <<<"$READINESS_JSON" >/dev/null
bash -n \
  "${OCTO_ROOT}/scripts/helpers/check-providers.sh" \
  "${OCTO_ROOT}/scripts/helpers/preflight.sh" \
  "${OCTO_ROOT}/scripts/orchestrate.sh"
printf 'setup-verification:pass (no provider request)\n'
```

Only after the user selected a completion path and this verification passed,
persist setup completion. Completing setup enables routing suggestions, never
automatic provider invocation, and preserves an existing opt-out.

```bash
if source "${OCTO_ROOT}/scripts/lib/user-config.sh" 2>/dev/null; then
  octo_config_write "setup_complete" 'true'
  octo_pref_write_default "auto_router_mode" '"suggest"'
fi
```

Tell the user:

> Octopus can now suggest a matching command when a prompt clearly fits. It
> never runs a provider on its own. Set `OCTOPUS_AUTO_ROUTER_MODE=off` to turn
> suggestions off.

Finish with exactly this quick-start block:

Next commands:

```text
/octo:auto
/octo:skill-doctor
/octo:setup
```

`/octo:auto` routes a task, `/octo:skill-doctor` diagnoses plugin skills inside
Claude Code, and `/octo:setup` returns here. From a shell, use `octopus doctor`
for environment diagnostics.

## Advanced setup

Advanced setup is opt-in. Show this menu only when the user chose it from the
default path. Each option must display its proposed commands and ask for
confirmation before making a change.

```javascript
AskUserQuestion({
  questions: [{
    question: "What would you like to configure?",
    header: "Advanced",
    multiSelect: false,
    options: [
      {label: "Models and routing", description: "Open /octo:model-config or adjust routing, cost mode, and project tier."},
      {label: "Developer tools", description: "Configure RTK, Graphify, or the optional memory companion."},
      {label: "Automation", description: "Configure scheduler behavior, remote-session defaults, or prompt caching."}
    ]
  }]
})
```

### Models and routing

- Use `/octo:model-config` for model overrides.
- Explain cost impact before changing cost mode.
- Treat `OCTO_TIER=prototype|mvp|production` as a routing hint, not policy.
- Never change routing, model, or tier configuration without confirmation.

### Developer tools

- **RTK:** show the detected install state, then offer its documented install
  and hook commands. Do not install or initialize it automatically.
- **Graphify:** optional architecture context. Offer `uv tool install graphifyy`
  and `graphify extract .` only after confirmation.
- **Memory companion:** optional cross-session context. Explain where its data
  is stored and obtain confirmation before installing or connecting it. After
  confirmation, connect Claude Code with `agentmemory connect claude-code`;
  users who want to force this backend can set
  `OCTOPUS_MEMORY_BACKEND=agentmemory`.

### Automation

- Scheduler setup must state what runs, when it runs, and which providers it
  may contact before enabling anything.
- In a remote session, do not launch browser login flows.
- Prompt-cache settings affect Claude traffic only; external providers manage
  their own caching.

After any advanced change, return to the default readiness summary. Use
`/octo:skill-doctor` inside Claude Code or `octopus doctor` in a shell for
troubleshooting.
