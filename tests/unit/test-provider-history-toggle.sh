#!/usr/bin/env bash
# Regression checks for disabling provider history read/write/injection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "provider history toggle"

WORKSPACE_DIR="$TEST_TMP_DIR/provider-history-toggle"
RESULTS_DIR="$WORKSPACE_DIR/results"
LOG_LEVEL="WARN"
log() { :; }

assert_provider_history_toggle_for_script() (
    local script_path="$1"
    rm -rf "$WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
    log() { :; }
    source "$script_path"

    export OCTOPUS_PROVIDER_HISTORY=off
    append_provider_history codex tangle "task" "learned"
    [[ ! -e "$WORKSPACE_DIR/.octo/providers/codex-history.md" ]] || return 1

    mkdir -p "$WORKSPACE_DIR/.octo/providers"
    cat > "$WORKSPACE_DIR/.octo/providers/codex-history.md" <<'EOF'
### tangle | 2026-01-01T00:00:00Z
**Task:** stale task
**Learned:** stale learning
---
EOF
    [[ -z "$(read_provider_history codex)" ]] || return 1
    [[ -z "$(build_provider_context codex)" ]] || return 1

    unset OCTOPUS_PROVIDER_HISTORY || true
    rm -rf "$WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
    append_provider_history codex tangle "task" "learned"
    local ctx
    ctx="$(build_provider_context codex)"
    [[ "$ctx" == *"Provider History (codex)"* ]] && [[ "$ctx" == *"learned"* ]]
)

test_case "provider-routing.sh honors OCTOPUS_PROVIDER_HISTORY"
if assert_provider_history_toggle_for_script "$PROJECT_ROOT/scripts/lib/provider-routing.sh"; then
    test_pass
else
    test_fail "provider-routing.sh provider history toggle behavior regressed"
fi

test_case "quality.sh honors OCTOPUS_PROVIDER_HISTORY"
if assert_provider_history_toggle_for_script "$PROJECT_ROOT/scripts/lib/quality.sh"; then
    test_pass
else
    test_fail "quality.sh provider history toggle behavior regressed"
fi

test_summary
