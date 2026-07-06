#!/usr/bin/env bash
# Regression checks for tangle failed-subtask retry feedback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle retry feedback"

PLUGIN_DIR="$PROJECT_ROOT"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
rm -rf "$TEST_TMP_DIR"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$TEST_TMP_DIR/results"
mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"

CAPTURED="$TEST_TMP_DIR/captured-spawn.txt"
CAPTURED_RESUME="$TEST_TMP_DIR/captured-resume.txt"
FAILED_RESULT="$TEST_TMP_DIR/codex-tangle-123-2.md"
RETRY_RESULT="$TEST_TMP_DIR/codex-tangle-123-retry1-2.md"
HEADERLESS_RESULT="$TEST_TMP_DIR/codex-tangle-123-3.md"
DIAG_WORKDIR="$TEST_TMP_DIR/diagnostic-workdir"
mkdir -p "$DIAG_WORKDIR/test"
(
    cd "$DIAG_WORKDIR"
    git init -q
    git config user.email test@example.invalid
    git config user.name "Octopus Test"
    cat > package.json <<'EOFJSON'
{"scripts":{"test":"node test/openapi-smoke.mjs"}}
EOFJSON
    cat > test/openapi-smoke.mjs <<'EOFJS'
const PORT = 33097;
console.log('initial');
EOFJS
    git add package.json test/openapi-smoke.mjs
    git commit -qm init
    cat > test/openapi-smoke.mjs <<'EOFJS'
const PORT = 33097;
const url = `http://127.0.0.1:\${PORT}\${urlPath}`;
console.log(`FAIL: \${e.message}`);
EOFJS
)

cat > "$FAILED_RESULT" <<'EOF'
# Agent: codex
# Task ID: tangle-123-2
# Role: implementer
# Prompt: Original task context:
Implement the missing bounded POST route.
## Output expectations
Preserve existing GET compatibility.
# Started: Mon Jun 29 13:41:36 WEST 2026
OpenAI Codex v0.57.0
--------
workdir: __DIAG_WORKDIR__
model: deepseek-ai/DeepSeek-V4-Pro
provider: pioneer

## Output
```
Partial plan only; no final verification.
```

## Status: FAILED (Missing completion marker)
# Completed: Mon Jun 29 13:41:45 WEST 2026
EOF
python3 - "$FAILED_RESULT" "$DIAG_WORKDIR" <<'PYSUBST'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('__DIAG_WORKDIR__', sys.argv[2]))
PYSUBST

cat > "$TEST_TMP_DIR/.tmp-tangle-123-2.err" <<'EOF'
node --check test/openapi-smoke.mjs exited 1:
SyntaxError: Invalid or unexpected token
FAIL: ${e.message}
Error: listen EADDRINUSE: address already in use :::33099
EOF

cat > "$RETRY_RESULT" <<'EOF'
# Agent: codex
# Task ID: tangle-123-retry1-2
# Role: implementer
# Started: Mon Jun 29 13:42:00 WEST 2026

## Output
retry artifact without prompt header

## Status: FAILED (Missing completion marker)
EOF

cat > "$HEADERLESS_RESULT" <<'EOF'
# Task ID: tangle-123-3
# Role: implementer
# Prompt: Headerless agent task
# Started: Mon Jun 29 13:43:00 WEST 2026

## Output
headerless provider artifact

## Status: FAILED (Missing completion marker)
EOF

log() { :; }
is_provider_locked() { return 0; }
get_alternate_provider() { echo "gemini"; }
search_similar_errors() { echo 0; }
flag_repeat_error() { :; }
should_use_agent_teams() { return 0; }
spawn_agent() {
    {
        echo "agent=$1"
        echo "task_id=$3"
        echo "role=$4"
        echo "phase=$5"
        echo "--- prompt ---"
        printf '%s\n' "$2"
    } > "$CAPTURED"
}
spawn_agent_capture_pid() {
    echo "spawn_agent_capture_pid should not be used in this test" >&2
    return 1
}

source "$PROJECT_ROOT/scripts/lib/agent-utils.sh"

test_case "extract_tangle_retry_prompt preserves multiline prompt body"
prompt=$(extract_tangle_retry_prompt "$FAILED_RESULT")
if [[ "$prompt" == *"Original task context:"* ]] && \
   [[ "$prompt" == *"Implement the missing bounded POST route."* ]] && \
   [[ "$prompt" == *"## Output expectations"* ]] && \
   [[ "$prompt" == *"Preserve existing GET compatibility."* ]]; then
    test_pass
else
    test_fail "retry prompt extraction did not preserve multiline prompt"
fi

test_case "retry artifacts without prompt headers fall back to previous artifact context"
retry_prompt=$(extract_tangle_retry_prompt "$RETRY_RESULT")
if [[ "$retry_prompt" == *"Implement the missing bounded POST route."* ]] &&    [[ "$retry_prompt" == *"Preserve existing GET compatibility."* ]]; then
    test_pass
else
    test_fail "retry artifact did not recover prompt context from previous result"
fi

test_case "agent-teams instruction prompt fallback is used when result has no prompt"
mkdir -p "$WORKSPACE_DIR/agent-teams"
cat > "$WORKSPACE_DIR/agent-teams/tangle-123-retry1-2.json" <<'EOF'
{"prompt":"Prompt recovered from agent-teams instruction file"}
EOF
mv "$TEST_TMP_DIR/codex-tangle-123-2.md" "$TEST_TMP_DIR/codex-tangle-123-2.md.hidden"
FAILED_SUBTASKS="result:${RETRY_RESULT}"$'
'
MAX_QUALITY_RETRIES=1
SUPPORTS_CONTINUATION=false
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=false
retry_failed_subtasks "123" "1"
mv "$TEST_TMP_DIR/codex-tangle-123-2.md.hidden" "$TEST_TMP_DIR/codex-tangle-123-2.md"
if grep -F "Prompt recovered from agent-teams instruction file" "$CAPTURED" >/dev/null; then
    test_pass
else
    test_fail "retry artifact did not recover prompt context from agent-teams instruction file"
fi

test_case "retry feedback prompt includes deterministic hard-gate feedback when present"
TANGLE_HARD_GATE_RETRY_FEEDBACK=$'Hard gate failure: missing explicit file coverage.\nMissing explicit files from the approved task/plan:\n- test/openapi-smoke.mjs\n\nApply a delta-only correction.\n'
feedback=$(build_tangle_retry_feedback_prompt "$FAILED_RESULT" "$prompt")
unset TANGLE_HARD_GATE_RETRY_FEEDBACK
if [[ "$feedback" == *"Hard gate failure: missing explicit file coverage."* ]] && \
   [[ "$feedback" == *"test/openapi-smoke.mjs"* ]] && \
   [[ "$feedback" == *"Apply a delta-only correction."* ]]; then
    test_pass
else
    test_fail "hard gate retry feedback was not injected into result-file retry prompt"
fi

test_case "retry feedback prompt names failure and instructs same-provider retry"
feedback=$(build_tangle_retry_feedback_prompt "$FAILED_RESULT" "$prompt")
output_excerpt_block=$(printf '%s\n' "$feedback" | awk '
    /^Previous output excerpt, if any:/ { in_excerpt=1; next }
    /^Original subtask prompt:/ { in_excerpt=0 }
    in_excerpt { print }
')
if [[ "$feedback" == *"RETRY FEEDBACK:"* ]] && \
   [[ "$feedback" == *"Failure status: FAILED (Missing completion marker)"* ]] && \
   [[ "$feedback" == *"same provider/role path"* ]] && \
   [[ "$feedback" == *"Complete only the failed assigned subtask"* ]] && \
   [[ "$output_excerpt_block" == *"Partial plan only; no final verification."* ]] && \
   [[ "$output_excerpt_block" != *"## Output expectations"* ]] && \
   [[ "$feedback" == *"Observed diagnostics from transcript and worktree:"* ]] && \
   [[ "$feedback" == *"SyntaxError: Invalid or unexpected token"* ]] && \
   [[ "$feedback" == *"EADDRINUSE"* ]] && \
   [[ "$feedback" == *"test/openapi-smoke.mjs"* ]] && \
   [[ "$feedback" == *"Suspicious literal template placeholders"* ]] && \
   [[ "$feedback" == *"## Worktree Changes"* ]]; then
    test_pass
else
    test_fail "feedback prompt does not contain required retry instructions"
fi

test_case "result-file retry keeps codex even when provider is locked"
FAILED_SUBTASKS="result:${FAILED_RESULT}"$'\n'
MAX_QUALITY_RETRIES=1
SUPPORTS_CONTINUATION=false
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=false
retry_failed_subtasks "123" "1"
if grep -F "agent=codex" "$CAPTURED" >/dev/null && \
   ! grep -F "agent=gemini" "$CAPTURED" >/dev/null && \
   grep -F "Failure status: FAILED (Missing completion marker)" "$CAPTURED" >/dev/null && \
   grep -F "Implement the missing bounded POST route." "$CAPTURED" >/dev/null; then
    test_pass
else
    test_fail "result-file retry did not keep codex with feedback"
fi

test_case "result-file retry can switch provider when explicitly enabled"
FAILED_SUBTASKS="result:${FAILED_RESULT}"$'
'
MAX_QUALITY_RETRIES=1
SUPPORTS_CONTINUATION=false
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=true
retry_failed_subtasks "123" "1"
if grep -F "agent=gemini" "$CAPTURED" >/dev/null; then
    test_pass
else
    test_fail "result-file retry did not switch provider when explicitly enabled"
fi
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=false

test_case "headerless result-file retry infers provider from filename for opt-in switch"
FAILED_SUBTASKS="result:${HEADERLESS_RESULT}"$'
'
MAX_QUALITY_RETRIES=1
SUPPORTS_CONTINUATION=false
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=true
retry_failed_subtasks "123" "1"
if grep -F "agent=gemini" "$CAPTURED" >/dev/null; then
    test_pass
else
    test_fail "headerless result-file retry did not infer provider for opt-in switch"
fi
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=false

test_case "result-file continuation retry uses artifact task id suffix"
bridge_get_agent_id() {
    echo "lookup=$1" > "$CAPTURED_RESUME"
    [[ "$1" == "tangle-123-2" ]] && echo "prev-agent-id"
}
resume_agent() {
    {
        echo "retry_task_id=$3"
        echo "role=$4"
        echo "phase=$5"
    } >> "$CAPTURED_RESUME"
    return 0
}
FAILED_SUBTASKS="result:${FAILED_RESULT}"$'\n'
SUPPORTS_CONTINUATION=true
OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=false
retry_failed_subtasks "123" "1"
if grep -F "lookup=tangle-123-2" "$CAPTURED_RESUME" >/dev/null && \
   grep -F "retry_task_id=tangle-123-retry1-2" "$CAPTURED_RESUME" >/dev/null; then
    test_pass
else
    test_fail "result-file continuation retry did not use artifact task id"
fi

SUPPORTS_CONTINUATION=false

test_case "validate_tangle_results stores failed result paths for retry"
if (
    VALIDATE_RESULTS_DIR="$TEST_TMP_DIR/validate-results"
    rm -rf "$VALIDATE_RESULTS_DIR"
    mkdir -p "$VALIDATE_RESULTS_DIR"
    RESULTS_DIR="$VALIDATE_RESULTS_DIR"
    FAILED_SUBTASKS=""
    LOOP_UNTIL_APPROVED=true
    MAX_QUALITY_RETRIES=0
    QUALITY_THRESHOLD=75
    OCTOPUS_ANTISYCOPHANCY=false
    OCTOPUS_FILE_VALIDATION=false
    GREEN=""
    RED=""
    YELLOW=""
    DIM=""
    NC=""
    _BOX_TOP=""
    _BOX_BOT=""
    log() { :; }
    record_task_metric() { :; }
    write_structured_decision() { :; }
    get_gate_threshold() { echo 75; }
    evaluate_quality_branch() { echo abort; }
    source "$PROJECT_ROOT/scripts/lib/testing.sh"
    cat > "$RESULTS_DIR/codex-tangle-999-2.md" <<'EOF'
# Agent: codex
# Task ID: tangle-999-2
# Role: implementer
# Prompt: Original task context:
Retry me
# Started: test

## Output
partial

## Status: FAILED (Missing completion marker)
EOF
    set +e
    validate_tangle_results "999" "implement scripts/lib/testing.sh" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "$rc" -ne 0 ]] && [[ "$FAILED_SUBTASKS" == *"result:${RESULTS_DIR}/codex-tangle-999-2.md"* ]]
); then
    test_pass
else
    test_fail "validate_tangle_results did not store failed result path for retry"
fi

test_summary
