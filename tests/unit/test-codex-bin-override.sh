#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex binary override"

export OCTOPUS_CODEX_SANDBOX="workspace-write"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
migrate_provider_config() { :; }
resolve_octopus_model() { echo "test-model"; }
validate_model_allowed() { return 0; }

test_default_codex_bin() {
    test_case "Codex command defaults to codex binary"
    unset OCTOPUS_CODEX_BIN || true
    local cmd
    cmd="$(get_agent_command codex)"
    if [[ "$cmd" == "codex exec --skip-git-repo-check --model test-model --sandbox workspace-write -" ]]; then
        test_pass
    else
        test_fail "unexpected command: $cmd"
        return 1
    fi
}

test_custom_codex_bin() {
    test_case "OCTOPUS_CODEX_BIN overrides codex binary"
    export OCTOPUS_CODEX_BIN="/opt/octopus/bin/deepseek-codex"
    local cmd
    cmd="$(get_agent_command codex-spark)"
    unset OCTOPUS_CODEX_BIN
    if [[ "$cmd" == "/opt/octopus/bin/deepseek-codex exec --skip-git-repo-check --model test-model --sandbox workspace-write -" ]]; then
        test_pass
    else
        test_fail "unexpected command: $cmd"
        return 1
    fi
}

test_invalid_codex_bin_falls_back() {
    test_case "Invalid OCTOPUS_CODEX_BIN falls back to codex"
    export OCTOPUS_CODEX_BIN="codex;rm -rf /"
    local cmd
    cmd="$(get_agent_command codex)"
    unset OCTOPUS_CODEX_BIN
    if [[ "$cmd" == "codex exec --skip-git-repo-check --model test-model --sandbox workspace-write -" ]]; then
        test_pass
    else
        test_fail "unexpected command: $cmd"
        return 1
    fi
}


test_codex_review_uses_custom_bin() {
    test_case "OCTOPUS_CODEX_BIN overrides codex-review binary"
    export OCTOPUS_CODEX_BIN="/opt/octopus/bin/deepseek-codex"
    local cmd
    cmd="$(get_agent_command codex-review)"
    unset OCTOPUS_CODEX_BIN
    if [[ "$cmd" == "/opt/octopus/bin/deepseek-codex exec --skip-git-repo-check review" ]]; then
        test_pass
    else
        test_fail "unexpected command: $cmd"
        return 1
    fi
}

test_default_codex_bin
test_custom_codex_bin
test_invalid_codex_bin_falls_back
test_codex_review_uses_custom_bin

test_summary
