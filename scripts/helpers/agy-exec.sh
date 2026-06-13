#!/usr/bin/env bash
# Antigravity CLI stdin adapter.
set -euo pipefail

model="${OCTOPUS_AGY_MODEL:-Claude Sonnet 4.6 (Thinking)}"
print_timeout="${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}"

cmd=(agy --print --sandbox --print-timeout "$print_timeout")
if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
fi

exec "${cmd[@]}"
