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

original_prompt="Update src/lib/templates/NA02_REQUEST_REPORT.ts and src/lib/legal/legalReferenceCatalog.ts without producing duplicate subject prefixes."

tangle_develop "$original_prompt" >/dev/null

test_case "overlapping coding scopes fall back to direct execution"
if [[ "$DIRECT_TASK_ID" == tangle-*-direct ]] && [[ "$PARALLEL_SPAWNED" == "false" ]]; then
    test_pass
else
    test_fail "overlapping write scopes were still spawned in parallel"
fi

test_case "direct fallback explains unsafe parallel decomposition"
if [[ "$DIRECT_PROMPT" == *"parallel decomposition is unsafe"* ]] && \
   [[ "$DIRECT_PROMPT" == *"overlaps"* ]] && \
   [[ "$DIRECT_PROMPT" == *"src/lib/templates/NA02_REQUEST_REPORT.ts"* ]]; then
    test_pass
else
    test_fail "direct fallback prompt did not preserve the overlap reason and original scope"
fi

test_case "unsafe fallback returns before tangle validation"
if [[ "$VALIDATION_CALLED" == "false" ]]; then
    test_pass
else
    test_fail "validation ran even though unsafe decomposition was not spawned"
fi

test_summary
