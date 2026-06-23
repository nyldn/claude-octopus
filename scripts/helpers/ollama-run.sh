#!/usr/bin/env bash
# ollama-run.sh — guarded wrapper around `ollama run <model>`.
#
# WHY THIS EXISTS:
#   `ollama run <model>` SILENTLY auto-pulls a missing model. When a cloud
#   provider dies mid-workflow (observed 2026-06-20: Gemini auth-dead + Codex
#   pinned to an unavailable model) the fleet can fall back to the local Ollama
#   provider. If the configured OCTOPUS_OLLAMA_MODEL is not already present, that
#   fallback triggers an unbounded multi-GB download with NO human in the loop —
#   in the observed incident a ~42 GB pull kicked off by a provider-failure
#   cascade. An unbounded download fired by an automated retry is a real disk and
#   bandwidth risk.
#
#   This shim makes the local fallback FAIL CLOSED. The actual refuse/allow/cap
#   decision lives in helpers/ollama-pull-guard.lib.sh, shared with the codex
#   OSS guard (helpers/codex-run.sh) so both vectors decide identically. Because
#   dispatch routes ALL Ollama execution through this one shim, no provider-
#   failure cascade can sidestep the guard.
#
# Usage:   ollama-run.sh <model>            (the prompt arrives on stdin)
#
# Env:
#   OCTOPUS_OLLAMA_ALLOW_PULL=true|1   allow pulling absent models (default: off)
#   OCTOPUS_OLLAMA_MAX_PULL_GB=<n>     size cap for an allowed pull (default: 20)
#   OCTOPUS_OLLAMA_BIN=<path>          override the ollama binary (testing)
#
# Exit codes:
#   64  usage error (no model given)
#   69  ollama binary not found
#   70  model absent and auto-pull not opted in (refused — NO download)
#   75  allowed pull exceeded the size cap or otherwise did not complete

set -euo pipefail

_ollama_run_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# Fail CLOSED: if the shared guard cannot be loaded, refuse to run rather than
# fall back to a bare `ollama run` that would auto-pull unguarded.
if ! source "${_ollama_run_dir}/ollama-pull-guard.lib.sh" 2>/dev/null; then
    echo "ollama-run: cannot load ollama-pull-guard.lib.sh — refusing to run ollama unguarded." >&2
    exit 70
fi

main() {
    local model="${1:-}"
    if [[ -z "$model" ]]; then
        echo "ollama-run: no model specified" >&2
        exit 64
    fi

    local rc=0
    ollama_guard_ensure_present "$model" "Octopus Ollama provider" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        exit "$rc"
    fi

    # Model is present (or was pulled within the cap). stdin (the prompt) passes
    # straight through to `ollama run`.
    exec "$OLLAMA_PULL_GUARD_BIN" run "$model"
}

main "$@"
