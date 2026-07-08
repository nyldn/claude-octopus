#!/usr/bin/env bash
# Claude Agent SDK stdin shim (v9.50.0). Routes the claude-sdk provider seat
# to the Claude Agent SDK when CLAUDE_SDK_API_KEY is set, unlocking Opus 4.8
# and the 1M-token context window independent of the host Claude Code session.
#
# octo pipes prompts via stdin (spawn.sh contract). Resolution order:
#   1. `claude-agent` CLI (Claude Agent SDK) if on PATH — preferred
#   2. `claude --print` headless fallback, authenticated with the SDK key
#      (ANTHROPIC_API_KEY set from CLAUDE_SDK_API_KEY, session markers stripped
#      so the inner claude never thinks it is a nested child — see #300 family)
#
# Env:
#   CLAUDE_SDK_API_KEY            required — refuses to run without it
#   OCTOPUS_CLAUDE_SDK_MODEL      default: claude-opus-4-8
#   OCTOPUS_CLAUDE_SDK_MAX_TOKENS default: 8192
set -euo pipefail

if [[ -z "${CLAUDE_SDK_API_KEY:-}" ]]; then
    # Standalone shim (exec'd by dispatch.sh) — matches grok-exec.sh / vibe-exec.sh
    # which also use raw echo>&2 for startup validation (no shared logger in scope).
    echo "claude-sdk-exec: CLAUDE_SDK_API_KEY is not set" >&2
    exit 78
fi

prompt=""
[[ ! -t 0 ]] && prompt="$(cat)"
if [[ -z "${prompt//[[:space:]]/}" ]]; then
    echo "claude-sdk-exec: no prompt provided on stdin" >&2
    exit 64
fi

model="${OCTOPUS_CLAUDE_SDK_MODEL:-claude-opus-4-8}"
max_tokens="${OCTOPUS_CLAUDE_SDK_MAX_TOKENS:-8192}"

if command -v claude-agent &>/dev/null; then
    exec env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID \
        -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH \
        "ANTHROPIC_API_KEY=${CLAUDE_SDK_API_KEY}" \
        claude-agent --print --model "$model" --max-tokens "$max_tokens" <<<"$prompt"
fi

if command -v claude &>/dev/null; then
    exec env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID \
        -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH \
        "ANTHROPIC_API_KEY=${CLAUDE_SDK_API_KEY}" \
        claude --print --model "$model" <<<"$prompt"
fi

echo "claude-sdk-exec: neither claude-agent (Agent SDK) nor claude CLI found in PATH" >&2
exit 69
