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
if [[ ! -r "$OCTO_ROOT/scripts/helpers/preflight.sh" ]]; then
  OCTO_ROOT="${HOME}/.claude-octopus/plugin"
fi
if [[ ! -r "$OCTO_ROOT/scripts/helpers/preflight.sh" ]]; then
  OCTO_ROOT="$(find "${HOME}/.claude/plugins/cache" "${HOME}/Library/Application Support/Claude" "${LOCALAPPDATA:-/dev/null}/Claude" "${XDG_DATA_HOME:-${HOME}/.local/share}/Claude" -maxdepth 8 -path '*/nyldn-plugins/octo/*/scripts/helpers/preflight.sh' -exec test -r '{}' \; -print -quit 2>/dev/null | sed 's#/scripts/helpers/preflight.sh$##')"
fi
[[ -r "$OCTO_ROOT/scripts/helpers/preflight.sh" ]] || {
  echo "Octopus installation not found. Reinstall octo@nyldn-plugins, then run /octo:setup again."
  exit 1
}
export OCTO_ROOT
```

### 1.5 Read resumable setup state

Read the receipt without creating files. The physical plugin root and host kind
scope the receipt to this installation.

```bash

SETUP_STATE_HELPER="${OCTO_ROOT}/scripts/helpers/setup-state.py"
READINESS_CONTRACT_HELPER="${OCTO_ROOT}/scripts/helpers/readiness-contract.py"
[[ -r "$SETUP_STATE_HELPER" && -r "$READINESS_CONTRACT_HELPER" ]] || {
  echo "Octopus setup helpers are unavailable. Reinstall the plugin, then retry."
  exit 1
}
if [[ -n "${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}" ]]; then
  SETUP_HOST=codex
else
  SETUP_HOST=claude
fi
SETUP_ROOT="$(cd "$OCTO_ROOT" && pwd -P)"
SETUP_RECEIPT="$(jq -cn --arg host "$SETUP_HOST" --arg root "$SETUP_ROOT" \
  '{schema_version:1,action:"read",host:$host,plugin_root:$root}' |
  python3 "$SETUP_STATE_HELPER" --input -)" || {
  echo "Unable to read setup state safely. Fix the reported storage error before continuing."
  exit 1
}
SETUP_REVISION="$(jq -r '.revision' <<<"$SETUP_RECEIPT")"

setup_record() {
  local stage="$1" verification_json="$2" request response
  request="$(jq -cn \
    --arg host "$SETUP_HOST" --arg root "$SETUP_ROOT" \
    --arg flow "$SETUP_FLOW" --arg provider "$SETUP_PROVIDER" \
    --arg stage "$stage" --argjson revision "$SETUP_REVISION" \
    --argjson verification "$verification_json" \
    '{schema_version:1,action:"record",host:$host,plugin_root:$root,
      expected_revision:$revision,flow:$flow,provider:$provider,stage:$stage,
      verification:$verification}')" || return 1
  response="$(printf '%s\n' "$request" |
    python3 "$SETUP_STATE_HELPER" --input -)" || return $?
  SETUP_REVISION="$(jq -r '.revision' <<<"$response")"
  SETUP_LAST_RESPONSE="$response"
  printf '%s\n' "$response"
}

setup_fail_recheck() {
  local reason="$1" checked_at="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" verification_json
  verification_json="$(jq -cn --arg reason "$reason" --arg checked "$checked_at" \
    '{result:"failed",reason_code:$reason,checked_at:$checked}')" || return 1
  setup_record rechecked "$verification_json" >/dev/null
}

setup_invalidate_existing() {
  local reason="$1"
  [[ "$(jq -r '.found' <<<"$SETUP_RECEIPT")" == true ]] || return 0
  SETUP_FLOW="$(jq -r '.record.flow' <<<"$SETUP_RECEIPT")"
  SETUP_PROVIDER="$(jq -r '.record.provider' <<<"$SETUP_RECEIPT")"
  setup_fail_recheck "$reason"
}

setup_readiness_capture() {
  set -o pipefail
  bash "${OCTO_ROOT}/scripts/helpers/preflight.sh" --json 2>/dev/null |
    python3 "$READINESS_CONTRACT_HELPER" --input -
}
```

### 2. Show shared readiness

Run one static, local-only readiness check. This is the same Provider Registry
2.0 contract used by Doctor, `detect-providers`, and workflow admission.

```bash
if ! READINESS_JSON="$(setup_readiness_capture 2>/dev/null)"; then
  setup_invalidate_existing initial-readiness-check-failed || exit $?
  echo "Provider readiness check failed or returned invalid data. Run /octo:skill-doctor in Claude Code or 'octopus doctor providers --json' in a shell."
  exit 1
fi

if [[ "$(jq -r '.found' <<<"$SETUP_RECEIPT")" == true &&
      "$(jq -r '.record.flow' <<<"$SETUP_RECEIPT")" == one-provider ]]; then
  SETUP_FLOW=one-provider
  SETUP_PROVIDER="$(jq -r '.record.provider' <<<"$SETUP_RECEIPT")"
  SETUP_PROVIDER_RESULT="$(jq -c --arg provider "$SETUP_PROVIDER" \
    '.results[] | select(.provider == $provider)' <<<"$READINESS_JSON")"
  if [[ -z "$SETUP_PROVIDER_RESULT" ]]; then
    setup_fail_recheck provider-absent-from-readiness-report || exit $?
    SETUP_RECEIPT="$SETUP_LAST_RESPONSE"
  elif [[ "$(jq -r '.status' <<<"$SETUP_PROVIDER_RESULT")" != available ]]; then
    SETUP_VERIFICATION="$(jq -cn \
      --arg reason "$(jq -r '.reason_code' <<<"$SETUP_PROVIDER_RESULT")" \
      --arg checked "$(jq -r '.checked_at' <<<"$SETUP_PROVIDER_RESULT")" \
      '{result:"failed",reason_code:$reason,checked_at:$checked}')"
    setup_record rechecked "$SETUP_VERIFICATION" >/dev/null || exit $?
    SETUP_RECEIPT="$SETUP_LAST_RESPONSE"
  fi
fi

printf 'Provider readiness:\n'
jq -r '.results[] | "  \(.provider): \(.status) [\(.reason_code)]"' <<<"$READINESS_JSON"
```

Render only those shared objects. Do not run separate binary, auth, model,
quota, or network checks while explaining the result. Use each object's
`remediation` when a provider needs attention.

If `SETUP_RECEIPT.found` is `true`, offer to resume its recorded flow.
Always rerun this static readiness step before skipping a recorded stage. A
timestamp is context, not current authority. A failed recheck clears completion.

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
to verification. Set `SETUP_FLOW=host-only` and `SETUP_PROVIDER=''`.

If the user chooses **Configure one provider**, show providers from
`READINESS_JSON`, prioritizing `degraded` before `missing`, and ask which single
provider they want. Registered options include Codex, Antigravity (`agy`),
Perplexity, and the other providers present in the shared result.

Set `SETUP_FLOW=one-provider` and `SETUP_PROVIDER` to the selected registry ID.
For either default completion path, record the selection before verification or
any human action. Use the current revision from the last helper response and
read the returned revision before the next state change:

```bash
SETUP_EXISTING_FLOW="$(jq -r '.record.flow // ""' <<<"$SETUP_RECEIPT")"
SETUP_EXISTING_PROVIDER="$(jq -r '.record.provider // ""' <<<"$SETUP_RECEIPT")"
SETUP_CURRENT_STAGE="$(jq -r '.record.stage // ""' <<<"$SETUP_RECEIPT")"

if [[ "$(jq -r '.found' <<<"$SETUP_RECEIPT")" == true &&
      "$SETUP_EXISTING_FLOW" == "$SETUP_FLOW" &&
      "$SETUP_EXISTING_PROVIDER" == "$SETUP_PROVIDER" ]]; then
  : # Resume the existing selection at its current stage.
else
  setup_record selected null >/dev/null || exit $?
  SETUP_CURRENT_STAGE=selected
fi
```

Before showing provider instructions, persist the selected provider's current
readiness. This clears stale completion before any human action can be cancelled:

```bash
if [[ "$SETUP_FLOW" == one-provider ]]; then
  SETUP_PROVIDER_RESULT="$(jq -c --arg provider "$SETUP_PROVIDER" \
    '.results[] | select(.provider == $provider)' <<<"$READINESS_JSON")"
  [[ -n "$SETUP_PROVIDER_RESULT" ]] || {
    setup_fail_recheck provider-absent-from-readiness-report || exit $?
    echo "The selected provider is absent from the shared readiness report."
    exit 1
  }
  if [[ "$(jq -r '.status' <<<"$SETUP_PROVIDER_RESULT")" != available ]]; then
    SETUP_VERIFICATION="$(jq -cn \
      --arg reason "$(jq -r '.reason_code' <<<"$SETUP_PROVIDER_RESULT")" \
      --arg checked "$(jq -r '.checked_at' <<<"$SETUP_PROVIDER_RESULT")" \
      '{result:"failed",reason_code:$reason,checked_at:$checked}')"
    setup_record rechecked "$SETUP_VERIFICATION" >/dev/null || exit $?
    SETUP_CURRENT_STAGE=rechecked
  fi
fi
```

When the provider is not yet available, show its `remediation` and the exact
proposed command or file change, then ask for confirmation before running it.
Authentication commands that open a browser must be run by the user in their
shell; remote sessions must never launch them automatically. EOF or cancellation
leaves the failed recheck incomplete and prints a `/octo:setup` resume
instruction.

After the selected provider is configured, rerun the shared static check and
record its fresh result before deciding whether setup can continue:

```bash
if [[ "$SETUP_FLOW" == one-provider ]]; then
  if ! READINESS_JSON="$(setup_readiness_capture 2>/dev/null)"; then
    setup_fail_recheck readiness-check-failed || exit $?
    echo "Provider readiness check failed or returned invalid data. Run /octo:skill-doctor in Claude Code or 'octopus doctor providers --json' in a shell."
    exit 1
  fi

  SETUP_PROVIDER_RESULT="$(jq -c --arg provider "$SETUP_PROVIDER" \
    '.results[] | select(.provider == $provider)' <<<"$READINESS_JSON")"
  [[ -n "$SETUP_PROVIDER_RESULT" ]] || {
    setup_fail_recheck provider-absent-from-readiness-report || exit $?
    echo "The selected provider is absent from the shared readiness report."
    exit 1
  }
  SETUP_RESULT=failed
  [[ "$(jq -r '.status' <<<"$SETUP_PROVIDER_RESULT")" == available ]] && SETUP_RESULT=passed
  SETUP_VERIFICATION="$(jq -cn \
    --arg result "$SETUP_RESULT" \
    --arg reason "$(jq -r '.reason_code' <<<"$SETUP_PROVIDER_RESULT")" \
    --arg checked "$(jq -r '.checked_at' <<<"$SETUP_PROVIDER_RESULT")" \
    '{result:$result,reason_code:$reason,checked_at:$checked}')"
  setup_record rechecked "$SETUP_VERIFICATION" >/dev/null || exit $?
  if [[ "$SETUP_RESULT" != passed ]]; then
    jq -r '"Provider is not ready [\(.reason_code)]. \(.remediation)"' \
      <<<"$SETUP_PROVIDER_RESULT"
    exit 1
  fi
fi
```

The selected provider must be `available`. Any other result is persisted as a
failed recheck, clears prior completion, shows the new `reason_code` and
`remediation`, and stops without claiming success.

If the user chooses **Open Advanced setup**, jump to the Advanced setup section.

### 4. Run a deterministic no-billing verification

This validates the captured contract and shipped shell entry points. It makes
no provider request and cannot incur provider usage.

```bash
SETUP_LOCAL_FAILURE=''
if ! jq -e '.results | length > 0' <<<"$READINESS_JSON" >/dev/null; then
  SETUP_LOCAL_FAILURE=local-readiness-contract-invalid
fi
for setup_script in \
  "${OCTO_ROOT}/scripts/helpers/check-providers.sh" \
  "${OCTO_ROOT}/scripts/helpers/preflight.sh" \
  "${OCTO_ROOT}/scripts/orchestrate.sh"; do
  if [[ -z "$SETUP_LOCAL_FAILURE" ]] && ! bash -n "$setup_script"; then
    SETUP_LOCAL_FAILURE=local-shell-validation-failed
  fi
done
if [[ -n "$SETUP_LOCAL_FAILURE" ]]; then
  setup_fail_recheck "$SETUP_LOCAL_FAILURE" || exit $?
  echo "Local setup verification failed [$SETUP_LOCAL_FAILURE]. The setup receipt remains incomplete."
  exit 1
fi
printf 'setup-verification:pass (no provider request)\n'
```

Only after the user selected a completion path and this verification passed,
persist setup completion. Completing setup enables routing suggestions, never
automatic provider invocation, and preserves an existing opt-out.

```bash
if [[ "$SETUP_FLOW" == host-only ]]; then
  SETUP_VERIFICATION="$(jq -cn \
    --arg checked "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{result:"passed",reason_code:"local-verification",checked_at:$checked}')"
  setup_record rechecked "$SETUP_VERIFICATION" >/dev/null || exit $?
fi
setup_record verified "$SETUP_VERIFICATION" >/dev/null || exit $?

LEGACY_REQUEST='{"schema_version":1,"action":"legacy-update","key":"setup_complete","value":true}'
printf '%s\n' "$LEGACY_REQUEST" |
  python3 "$SETUP_STATE_HELPER" --input - >/dev/null || {
    echo "Local verification passed, but setup completion was not persisted. Resume with /octo:setup."
    exit 1
  }
jq -e '.setup_complete == true' "${HOME}/.claude-octopus/user-config.json" >/dev/null || {
  echo "Setup completion readback failed. The resume receipt remains incomplete."
  exit 1
}

PREFERENCE_PERSISTED=false
if source "${OCTO_ROOT}/scripts/lib/user-config.sh" 2>/dev/null; then
  octo_pref_write_default "auto_router_mode" '"suggest"'
  if jq -e '(.auto_router_mode == "suggest" or .auto_router_mode == "off" or .auto_router_mode == "invoke")' \
    "${HOME}/.claude-octopus/preferences.json" >/dev/null 2>&1; then
    PREFERENCE_PERSISTED=true
  fi
fi
[[ "$PREFERENCE_PERSISTED" == true ]] || {
  echo "Routing preference readback failed. The resume receipt remains incomplete."
  exit 1
}

COMPLETE_REQUEST="$(jq -cn --arg host "$SETUP_HOST" --arg root "$SETUP_ROOT" \
  --argjson revision "$SETUP_REVISION" \
  '{schema_version:1,action:"complete",host:$host,plugin_root:$root,
    expected_revision:$revision}')"
COMPLETE_RESPONSE="$(printf '%s\n' "$COMPLETE_REQUEST" |
  python3 "$SETUP_STATE_HELPER" --input -)" || exit $?
jq -e '.status == "complete" and .persisted == true' \
  <<<"$COMPLETE_RESPONSE" >/dev/null || exit 1
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
- Use `octopus profile core|orchestration|full` to control optional context
  hooks. Explain that profiles never disable safety or lifecycle hooks.
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
