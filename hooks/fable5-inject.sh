#!/usr/bin/env bash
# fable5-inject.sh — Inject Fable 5 dispatch guidance on SessionStart when a
# claude-fable-5 env pin is detected (OCTOPUS_OPUS_MODEL / OCTOPUS_CLAUDE_SDK_MODEL),
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
        if [[ "${OCTOPUS_OPUS_MODEL:-}" == "claude-fable-5" || "${OCTOPUS_CLAUDE_SDK_MODEL:-}" == "claude-fable-5" ]]; then
            _active=true
        fi
        ;;
esac

if [[ "$_active" != "true" ]]; then
    echo '{}'
    exit 0
fi

DIRECTIVE='🐙 FABLE 5 MODE ACTIVE — a claude-fable-5 pin was detected. Three guards are auto-enforced by orchestrate.sh (OCTOPUS_FABLE5_MODE=off to disable): (1) security-audit dispatches reroute to Opus 4.8 because Fable 5 safety classifiers can refuse adversarial security phrasing; (2) effort clamps xhigh/max to high — Fable 5 effort applies per tool call and higher settings widen scope at 2x cost without extending runs; (3) the claude-sdk seat retries a refused/empty Fable 5 dispatch once on Opus 4.8. When writing prompts for Fable 5 dispatches: never ask it to reveal or transcribe its reasoning (triggers the reasoning_extraction refusal); no token or context countdowns; drop CRITICAL/MUST emphasis unless strict compliance is required; prefer a boundary plus checkable acceptance criteria over micromanaged step plans. Full profile: skills/blocks/fable5-prompting.md.'

# Escape for JSON
ESCAPED=$(printf '%s' "$DIRECTIVE" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
