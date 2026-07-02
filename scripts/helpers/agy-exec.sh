#!/usr/bin/env bash
# Antigravity CLI stdin adapter.
set -euo pipefail

# Default to "default" → don't pass --model, so agy uses the model you picked in
# its own `/model` UI (e.g. Gemini 3.5 Flash Medium). The old default ("Claude
# Sonnet 4.6 (Thinking)") forced agy onto the Claude/GPT quota group, which can be
# exhausted → agy returns empty and the council seat silently fails. Override per
# run with OCTOPUS_AGY_MODEL if you want a specific model.
model="${OCTOPUS_AGY_MODEL:-default}"
print_timeout="${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}"

# --dangerously-skip-permissions: auto-approve agy's folder-trust + tool prompts so
# council seats don't block on a per-worktree trust prompt (already --sandbox'd).
cmd=(agy --print --sandbox --dangerously-skip-permissions --print-timeout "$print_timeout")
case "$model" in
    ""|default|agy/default)
        ;;
    *)
        cmd+=(--model "$model")
        ;;
esac

exec "${cmd[@]}"
