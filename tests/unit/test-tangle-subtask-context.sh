#!/usr/bin/env bash
# Regression checks for /octo:develop subtask prompt context preservation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle subtask context preservation"

# These tests exercise tangle dispatch/validation behavior, not contextual review.
export OCTOPUS_TANGLE_CODE_REVIEW=false

test_case "workflows.sh has valid bash syntax"
if bash -n "$WORKFLOWS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in workflows.sh"
fi

# shellcheck source=/dev/null
source "$WORKFLOWS"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$TEST_TMP_DIR/tangle-subtask-context"
LOGS_DIR="$RESULTS_DIR/logs"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
CAPTURE_DIR="$RESULTS_DIR/captured-prompts"
rm -rf "$RESULTS_DIR"
mkdir -p "$WORKSPACE_DIR/.octo/agents" "$CAPTURE_DIR"
trap 'rm -rf "$RESULTS_DIR"' EXIT

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
design_review_ceremony() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
validate_tangle_results() { :; }

test_case "subtask prompt builder validates required inputs"
set +e
empty_prompt_error=$(build_tangle_subtask_prompt "" "1. [CODING] Files: README.md" 2>&1 >/dev/null)
empty_prompt_status=$?
set -e
if [[ "$empty_prompt_status" -eq 64 && "$empty_prompt_error" == *"original task is required"* ]]; then
    test_pass
else
    test_fail "expected original-task validation failure; status=$empty_prompt_status output=$empty_prompt_error"
fi

run_agent_sync() {
    cat <<'EOF'
1. [CODING] Template polish. Files: src/lib/templates/NA10_HANDLE_SILENCE.ts
2. [REASONING] Integration review
EOF
}

spawn_agent_capture_pid() {
    local _agent="$1"
    local prompt="$2"
    local task_id="$3"
    printf '%s' "$prompt" > "$CAPTURE_DIR/${task_id}.prompt"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    printf '12345\n'
}

original_prompt="Update src/lib/templates/NA10_HANDLE_SILENCE.ts and src/lib/templates/NA20_REQUEST_MISSING_INFO.ts. Do not modify src/lib/render/renderEmailTemplate.ts."

tangle_develop "$original_prompt" >/dev/null

prompt_files=("$CAPTURE_DIR"/*.prompt)
if [[ ! -e "${prompt_files[0]}" ]]; then
    captured_prompts=""
else
    captured_prompts="$(cat "${prompt_files[@]}")"
fi

test_case "captures exactly one prompt per decomposed subtask"
if [[ ${#prompt_files[@]} -eq 2 && -e "${prompt_files[0]}" && -e "${prompt_files[1]}" ]]; then
    test_pass
else
    test_fail "expected exactly 2 captured prompts, got ${#prompt_files[@]}"
fi

test_case "subtask prompts include original task context"
if [[ "$captured_prompts" == *"Original task context:"* ]] && \
   [[ "$captured_prompts" == *"src/lib/templates/NA10_HANDLE_SILENCE.ts"* ]] && \
   [[ "$captured_prompts" == *"src/lib/templates/NA20_REQUEST_MISSING_INFO.ts"* ]]; then
    test_pass
else
    test_fail "spawned subtasks did not receive the original task context and explicit file targets"
fi

test_case "subtask prompts preserve original forbidden changes"
if [[ "$captured_prompts" == *"Do not modify src/lib/render/renderEmailTemplate.ts"* ]]; then
    test_pass
else
    test_fail "spawned subtasks did not receive the original forbidden-change constraint"
fi

test_case "subtask prompts still include the assigned subtask"
if [[ "$captured_prompts" == *"Assigned subtask:"* ]] && \
   [[ "$captured_prompts" == *"Template polish"* ]] && \
   [[ "$captured_prompts" == *"Integration review"* ]]; then
    test_pass
else
    test_fail "spawned prompts lost the assigned subtask text"
fi

test_case "coding subtask prompts require direct edits and integration evidence"
if [[ "$captured_prompts" == *"edit the repository files directly"* ]] && \
   [[ "$captured_prompts" == *"exclusive write scope"* ]] && \
   [[ "$captured_prompts" == *"Tests alone are not integration evidence"* ]] && \
   [[ "$captured_prompts" == *"## Worktree Changes"* ]] && \
   [[ "$captured_prompts" == *"## Integration Evidence"* ]]; then
    test_pass
else
    test_fail "spawned prompts did not require direct worktree edits and integration evidence"
fi

test_summary
