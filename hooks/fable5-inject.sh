#!/usr/bin/env bash
# fable5-inject.sh — Inject Fable 5 dispatch guidance on SessionStart when a
# Fable 5 or 5.1 environment pin is detected,
# or when OCTOPUS_FABLE5_MODE=on forces it. OCTOPUS_FABLE5_MODE=off suppresses.
# Full guidance: skills/blocks/fable5-prompting.md; guards: scripts/lib/fable5.sh.

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero (issue #313).
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

_active=false
case "${OCTOPUS_FABLE5_MODE:-auto}" in
    off) _active=false ;;
    on)  _active=true ;;
    *)
        for _model in "${OCTOPUS_OPUS_MODEL:-}" "${OCTOPUS_CLAUDE_SDK_MODEL:-}" \
            "${OCTOPUS_CLAUDE_MODEL:-}" "${CLAUDE_MODEL:-}"; do
            case "$_model" in
                claude-fable-5|claude-fable-5-1) _active=true; break ;;
            esac
        done
        ;;
esac

if [[ "$_active" != "true" ]]; then
    # Nothing to inject: EMPTY stdout (a bare {} fails v2.1.178 hook-output validation).
    exit 0
fi

DIRECTIVE='🐙 FABLE 5 MODE ACTIVE — a Fable 5 or 5.1 pin was detected. Three guards are enforced by orchestrate.sh (OCTOPUS_FABLE5_MODE=off to disable): (1) security-audit dispatches reroute to Opus 5 by default because Fable safety classifiers can refuse adversarial security phrasing; OCTOPUS_FABLE5_FALLBACK_MODEL may replace that target; (2) effort defaults to a high ceiling; OCTOPUS_FABLE5_MAX_EFFORT can raise it for a bounded run; (3) the claude-sdk seat retries a refused or empty Fable dispatch once on the same configured fallback. When writing Fable prompts: never ask it to reveal or transcribe its reasoning; omit token or context countdowns; drop CRITICAL/MUST emphasis unless strict compliance is required; prefer a boundary plus checkable acceptance criteria over micromanaged step plans. Full profile: skills/blocks/fable5-prompting.md.'

# Escape for JSON
ESCAPED=$(printf '%s' "$DIRECTIVE" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
