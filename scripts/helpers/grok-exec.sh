#!/usr/bin/env bash
# xAI Grok CLI stdin→argv shim. octo pipes prompts via stdin (spawn.sh contract);
# grok's `-p/--single` takes the prompt as an argv argument, so read stdin and
# re-pass it. Model via OCTOPUS_GROK_MODEL (default: grok's own default).
set -euo pipefail
prompt=""
[[ ! -t 0 ]] && prompt="$(cat)"
if [[ -z "${prompt//[[:space:]]/}" ]]; then
    if declare -f log >/dev/null 2>&1; then log ERROR "grok-exec: no prompt provided on stdin"; else echo "grok-exec: no prompt provided on stdin" >&2; fi
    exit 64
fi
model="${OCTOPUS_GROK_MODEL:-default}"
workdir="${OCTOPUS_GROK_CWD:-$PWD}"
cmd=(grok -p "$prompt" --output-format plain --cwd "$workdir" --disable-web-search)
if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
fi
exec "${cmd[@]}"
