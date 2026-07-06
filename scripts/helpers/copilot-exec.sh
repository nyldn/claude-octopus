#!/usr/bin/env bash
# GitHub Copilot CLI stdin->argv shim. octo pipes prompts via stdin (spawn.sh
# contract), but copilot's only non-interactive mode is `-p/--prompt <text>`,
# which takes the prompt as an argv argument. Without this shim dispatch.sh runs
# copilot with no prompt; copilot then opens an interactive session, hangs on the
# piped stdin, and is killed by the spawn timeout (silently dropped from the
# fleet). Read stdin and re-pass it via -p. Mirrors grok-exec.sh / vibe-exec.sh.
# Auth (COPILOT_GITHUB_TOKEN/GH_TOKEN/GITHUB_TOKEN/keychain/gh) is inherited from
# the environment, same as the other shims.
set -euo pipefail
prompt=""
[[ ! -t 0 ]] && prompt="$(cat)"
if [[ -z "${prompt//[[:space:]]/}" ]]; then
    echo "copilot-exec: no prompt provided on stdin" >&2
    exit 64
fi
exec copilot -p "$prompt" --no-ask-user -s --disable-builtin-mcps
