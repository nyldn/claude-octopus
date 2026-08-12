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
model="${OCTOPUS_COPILOT_MODEL:-auto}"
tool_policy="${OCTOPUS_COPILOT_TOOL_POLICY:-auto}"
case "$tool_policy" in
    auto)
        exec copilot -p "$prompt" --model "$model" --no-ask-user -s \
            --disable-builtin-mcps
        ;;
    none)
        # Review prompts already contain the complete diff. Deny every built-in
        # tool kind and expose an empty tool inventory so untrusted code cannot
        # read files, execute commands, delegate, write state, fetch URLs, or
        # persist memory in CI (#893).
        exec copilot -p "$prompt" --model "$model" --no-ask-user -s \
            --disable-builtin-mcps --available-tools='' \
            --deny-tool=shell,write,read,url,memory
        ;;
    *)
        echo "copilot-exec: invalid tool policy: $tool_policy" >&2
        exit 64
        ;;
esac
