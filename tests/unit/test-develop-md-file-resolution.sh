#!/usr/bin/env bash
# Static regression checks for /octo:develop Markdown plan reference handling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "develop Markdown plan resolution"

assert_has() {
    local pattern="$1"
    local label="$2"
    test_case "$label"
    if grep -qE "$pattern" "$WORKFLOWS"; then
        test_pass
    else
        test_fail "pattern not found: $pattern"
    fi
}

assert_lacks() {
    local pattern="$1"
    local label="$2"
    test_case "$label"
    if grep -qE "$pattern" "$WORKFLOWS"; then
        test_fail "unexpected pattern found: $pattern"
    else
        test_pass
    fi
}

test_case "workflows.sh has valid bash syntax"
if bash -n "$WORKFLOWS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in workflows.sh"
fi

assert_lacks 'grep -oE .*\.\.md.*head -1|grep -oE .*\\.md.*head -1' \
    "plan reference scan avoids grep|head pipeline"

assert_has 'trimmed_prompt=' \
    "plan reference handling detects file-only prompts"

assert_has 'resolved_prompt="\$\{prompt\}' \
    "plan reference handling preserves surrounding user instructions"

assert_has 'spawn_agent "codex" "\$resolved_prompt"' \
    "direct fallback receives resolved prompt"

source "$WORKFLOWS"

CAPTURED_DECOMPOSE_PROMPT=""
CAPTURED_VALIDATE_PROMPT=""
CYAN=""
MAGENTA=""
NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$(mktemp -d)"
LOGS_DIR="$RESULTS_DIR/logs"
DECOMPOSE_CAPTURE_FILE="$RESULTS_DIR/decompose.prompt"
trap 'rm -rf "$RESULTS_DIR"' EXIT

log() { :; }
octopus_phase_banner() { :; }
design_review_ceremony() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
run_agent_sync() {
    printf '%s' "$2" > "$DECOMPOSE_CAPTURE_FILE"
    printf '%s\n' "No numbered subtasks required"
}
validate_tangle_results() {
    CAPTURED_VALIDATE_PROMPT="$2"
}

run_tangle_case() {
    CAPTURED_DECOMPOSE_PROMPT=""
    CAPTURED_VALIDATE_PROMPT=""
    rm -f "$DECOMPOSE_CAPTURE_FILE"
    tangle_develop "$1" >/dev/null || return 1
    [[ -f "$DECOMPOSE_CAPTURE_FILE" ]] && CAPTURED_DECOMPOSE_PROMPT=$(<"$DECOMPOSE_CAPTURE_FILE")
}

test_case "plan file references inject content while preserving prompt text"
plan_file="$RESULTS_DIR/session-plan.md"
printf '%s\n' "Update scripts/lib/workflows.sh with the regression fix." > "$plan_file"
run_tangle_case "please implement $plan_file carefully"
if [[ "$CAPTURED_DECOMPOSE_PROMPT" == *"please implement"* ]] && \
   [[ "$CAPTURED_DECOMPOSE_PROMPT" == *"Update scripts/lib/workflows.sh with the regression fix."* ]]; then
    test_pass
else
    test_fail "resolved prompt did not preserve instructions and plan content"
fi

test_case "validation receives resolved plan content"
if [[ "$CAPTURED_VALIDATE_PROMPT" == *"Update scripts/lib/workflows.sh with the regression fix."* ]]; then
    test_pass
else
    test_fail "validate_tangle_results received raw prompt instead of resolved content"
fi

test_case "wildcard-looking Markdown tokens are not glob-expanded"
glob_dir="$RESULTS_DIR/glob-case"
mkdir -p "$glob_dir"
printf '%s\n' "This file should not be injected from a wildcard prompt." > "$glob_dir/noise.md"
(
    cd "$glob_dir"
    run_tangle_case "review *.md"
)
if [[ "$CAPTURED_DECOMPOSE_PROMPT" == *"This file should not be injected"* ]]; then
    test_fail "wildcard token was expanded and injected as a plan file"
else
    test_pass
fi

test_summary
