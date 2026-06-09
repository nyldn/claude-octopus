#!/usr/bin/env bash
# Regression checks for /octo:develop parallel write-scope safety.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle write-scope safety"

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
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
RESULTS_DIR="$TEST_TMP_DIR/tangle-write-scope-safety"
LOGS_DIR="$RESULTS_DIR/logs"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
rm -rf "$RESULTS_DIR"
mkdir -p "$WORKSPACE_DIR/.octo/agents"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

DIRECT_PROMPT=""
DIRECT_TASK_ID=""
PARALLEL_SPAWNED=false
VALIDATION_CALLED=false
TANGLE_STATUS=0

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
design_review_ceremony() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
run_agent_sync() {
    cat <<'EOF'
1. [CODING] Add the reference prefix. Files: src/lib/templates/NA02_REQUEST_REPORT.ts
2. [CODING] Add legal wording to the same template. Files: src/lib/templates/NA02_REQUEST_REPORT.ts, src/lib/legal/legalReferenceCatalog.ts
EOF
}
spawn_agent_capture_pid() {
    PARALLEL_SPAWNED=true
    printf '12345\n'
}
spawn_agent() {
    DIRECT_PROMPT="$2"
    DIRECT_TASK_ID="$3"
}
validate_tangle_results() {
    VALIDATION_CALLED=true
}

test_case "directory write scopes overlap contained files"
if tangle_scopes_overlap "src/lib/templates/" "src/lib/templates/NA02_REQUEST_REPORT.ts" && \
   ! tangle_scopes_overlap "src/lib/templates/" "src/lib/legal/legalReferenceCatalog.ts"; then
    test_pass
else
    test_fail "directory/file overlap detection is incorrect"
fi

test_case "write scope extraction reads only Files clause"
scopes=$(tangle_extract_write_scopes "[CODING] Update docs after reading src/context.ts. Files: README.md, docs/setup.md")
if [[ "$scopes" == *"README.md"* ]] && \
   [[ "$scopes" == *"docs/setup.md"* ]] && \
   [[ "$scopes" != *"src/context.ts"* ]]; then
    test_pass
else
    test_fail "write scope extraction did not isolate Files clause; got: $scopes"
fi

test_case "write scope extraction requires explicit Files clause"
scopes=$(tangle_extract_write_scopes "[CODING] Update src/context.ts after reading README.md")
if [[ -z "$scopes" ]]; then
    test_pass
else
    test_fail "write scope extraction parsed arbitrary prose without Files clause: $scopes"
fi

test_case "write scope extraction accepts root-level filenames"
scopes=$(tangle_extract_write_scopes "[CODING] Update build files. Files: Makefile, Dockerfile, package.json")
if [[ "$scopes" == *"Makefile"* ]] && \
   [[ "$scopes" == *"Dockerfile"* ]] && \
   [[ "$scopes" == *"package.json"* ]]; then
    test_pass
else
    test_fail "write scope extraction rejected root-level filenames; got: $scopes"
fi

test_case "known scope lookup falls back to pwd when PROJECT_ROOT is invalid"
real_project_root="$PROJECT_ROOT"
if (
    cd "$real_project_root"
    PROJECT_ROOT="$TEST_TMP_DIR/missing-project-root"
    tangle_scope_is_known_or_explicit_new_file "scripts/lib/workflows.sh"
); then
    test_pass
else
    test_fail "known scope lookup did not fall back when PROJECT_ROOT was invalid"
fi

test_case "repo context resolution falls back to pwd when PROJECT_ROOT is invalid"
resolved_scopes=$(
    cd "$real_project_root"
    PROJECT_ROOT="$TEST_TMP_DIR/missing-project-root" \
        tangle_resolve_repo_context_files "Update workflow safety. Files: scripts/lib/workflows.sh"
)
if [[ "$resolved_scopes" == *"scripts/lib/workflows.sh"* ]]; then
    test_pass
else
    test_fail "repo context resolution did not fall back when PROJECT_ROOT was invalid: $resolved_scopes"
fi

test_case "existing non-git PROJECT_ROOT does not resolve scopes from unrelated pwd repo"
resolved_scopes=$(
    cd "$real_project_root"
    mkdir -p "$TEST_TMP_DIR/not-a-repo"
    PROJECT_ROOT="$TEST_TMP_DIR/not-a-repo" \
        tangle_resolve_repo_context_files "Update workflow safety. Files: scripts/lib/workflows.sh"
)
if [[ -z "$resolved_scopes" ]]; then
    test_pass
else
    test_fail "repo context resolution used cwd repo despite explicit non-git PROJECT_ROOT: $resolved_scopes"
fi

test_case "known scope lookup honors existing non-git PROJECT_ROOT files"
if (
    cd "$real_project_root"
    mkdir -p "$TEST_TMP_DIR/not-a-repo/scripts/lib"
    touch "$TEST_TMP_DIR/not-a-repo/scripts/lib/workflows.sh"
    PROJECT_ROOT="$TEST_TMP_DIR/not-a-repo"
    tangle_scope_is_known_or_explicit_new_file "scripts/lib/workflows.sh"
); then
    test_pass
else
    test_fail "known scope lookup ignored files under explicit non-git PROJECT_ROOT"
fi

original_prompt="Update src/lib/templates/NA02_REQUEST_REPORT.ts and src/lib/legal/legalReferenceCatalog.ts without producing duplicate subject prefixes."

tangle_develop "$original_prompt" >/dev/null && TANGLE_STATUS=0 || TANGLE_STATUS=$?

test_case "overlapping coding scopes fail closed"
if [[ "$TANGLE_STATUS" -eq 1 ]] && [[ "$PARALLEL_SPAWNED" == "false" ]]; then
    test_pass
else
    test_fail "overlapping write scopes did not fail closed before parallel spawn"
fi

test_case "unsafe decomposition does not spawn direct fallback"
if [[ -z "$DIRECT_TASK_ID" && -z "$DIRECT_PROMPT" ]]; then
    test_pass
else
    test_fail "direct fallback was spawned despite unsafe decomposition"
fi

test_case "unsafe fail-closed path returns before tangle validation"
if [[ "$VALIDATION_CALLED" == "false" ]]; then
    test_pass
else
    test_fail "validation ran even though unsafe decomposition was not spawned"
fi

test_summary
