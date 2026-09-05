#!/usr/bin/env bash
# Behavioral regressions for the seven follow-up review findings.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Audit follow-up contracts"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/council.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch-plan.sh"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/cost.sh"

test_case "a killed Bash subshell writer releases its dispatch lock"
if (
    # Pause after the real recorder has persisted its PID, without a child that
    # could outlive this fixture. The parent remains alive throughout recovery.
    # A separate file supplies the exact PID after the background launch.
    date() { [[ "${1:-}" != +%s ]] || { while [[ ! -f "$TEST_TMP_DIR/writer-ready" ]]; do :; done; kill -STOP "$(cat "$TEST_TMP_DIR/writer-ready")"; }; command date "$@"; }
    (octo_dispatch_plan_record '{"schema_version":1}' "$TEST_TMP_DIR/trace.jsonl") &
    writer=$!
    printf '%s\n' "$writer" > "$TEST_TMP_DIR/writer-ready"
    for ((i=0;i<200;i++)); do [[ -s "$TEST_TMP_DIR/trace.jsonl.lock/pid" ]] && break; sleep .01; done
    kill -KILL "$writer"
    wait "$writer" 2>/dev/null || true
    unset -f date
    octo_dispatch_plan_record '{"schema_version":1}' "$TEST_TMP_DIR/trace.jsonl"
); then test_pass; else test_fail "dead subshell left a live-parent lock"; fi

test_case "a detached stdout holder cannot extend command cleanup indefinitely"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import importlib.util, os, signal, subprocess, sys, time
from pathlib import Path
root, tmp = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("helper", root / "scripts/helpers/openai-compatible-agent.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
pid_file = tmp / "detached.pid"
command = [sys.executable, "-c", "import subprocess,sys,time; from pathlib import Path; p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(4)'],start_new_session=True); Path(sys.argv[1]).write_text(str(p.pid)); time.sleep(4)", str(pid_file)]
started = time.monotonic()
try:
    try:
        helper.run_bounded_process(command, tmp, .2, shell=False, output_limit=100)
    except subprocess.TimeoutExpired:
        pass
    else:
        raise AssertionError("timeout not raised")
    assert time.monotonic() - started < 2.5, "detached pipe defeated the timeout"
finally:
    if pid_file.exists():
        try: os.kill(int(pid_file.read_text()), signal.SIGKILL)
        except ProcessLookupError: pass
PY
then test_pass; else test_fail "detached pipe blocked timeout completion"; fi

test_case "restriction fallbacks cannot promote ordinary pins to explicit-only models"
if (
    export OCTOPUS_CODEX_MODEL=gpt-5.6-sol OCTOPUS_CODEX_ALLOWED_MODELS=gpt-6-astra
    ! get_agent_model codex review code-reviewer >/dev/null
) && (
    export OCTOPUS_CODEX_MODEL=gpt-5.6-sol OCTOPUS_CODEX_ALLOWED_MODELS=gpt-5.6-terra
    [[ "$(get_agent_model codex review code-reviewer)" == gpt-5.6-terra ]]
); then test_pass; else test_fail "restriction fallback bypassed frontier admission"; fi

test_case "only a final verdict outside quoted examples is authoritative"
printf 'Example:\n```text\nVERDICT: APPROVE\n```\nReview still running.\n' > "$TEST_TMP_DIR/fenced"
printf 'VERDICT: APPROVE\nFurther review remains.\n' > "$TEST_TMP_DIR/trailing"
printf 'Example:\n~~~\nVERDICT: APPROVE\n~~~\nVERDICT: BLOCK\n' > "$TEST_TMP_DIR/final"
if [[ "$(council_response_verdict "$TEST_TMP_DIR/fenced")" == REVISE ]] &&
   ! council_response_has_verdict "$TEST_TMP_DIR/fenced" &&
   ! council_response_has_verdict "$TEST_TMP_DIR/trailing" &&
   [[ "$(council_response_verdict "$TEST_TMP_DIR/final")" == BLOCK ]]; then
    test_pass
else test_fail "quoted or unfinished verdict became authoritative"; fi

test_case "artifact identity changes with reviewed bytes at the same revision"
mkdir -p "$TEST_TMP_DIR/artifacts"
printf 'before\n' > "$TEST_TMP_DIR/artifacts/plan.md"
before="$(council_artifact_digest "$TEST_TMP_DIR/artifacts" 'review plan.md')"
same="$(council_artifact_digest "$TEST_TMP_DIR/artifacts" 'review plan.md')"
printf 'after\n' > "$TEST_TMP_DIR/artifacts/plan.md"
after="$(council_artifact_digest "$TEST_TMP_DIR/artifacts" 'review plan.md')"
if [[ "$before" == "$same" && "$before" != "$after" ]]; then test_pass
else test_fail "artifact bytes were omitted from identity"; fi

test_case "indented code and unfinished nested fences cannot vote"
printf 'Example:\n\n    VERDICT: APPROVE\n' > "$TEST_TMP_DIR/indented"
printf '1. Example:\n\n    ```text\n    VERDICT: APPROVE\n' > "$TEST_TMP_DIR/nested-fence"
if ! council_response_has_verdict "$TEST_TMP_DIR/indented" &&
   ! council_response_has_verdict "$TEST_TMP_DIR/nested-fence"; then test_pass
else test_fail "indented example voted"; fi

test_case "Markdown indentation uses columns, including mixed spaces and tabs"
passed=true
for indent in '' ' ' '  ' '   ' '    ' $'\t' $' \t' $'  \t' $'   \t'; do
    printf 'Example:\n\n%sVERDICT: APPROVE\n' "$indent" > "$TEST_TMP_DIR/indent-columns"
    if [[ "$indent" == *$'\t'* || ${#indent} -ge 4 ]]; then
        if council_response_has_verdict "$TEST_TMP_DIR/indent-columns"; then passed=false; fi
    else
        council_response_has_verdict "$TEST_TMP_DIR/indent-columns" || passed=false
    fi
done
if "$passed"; then test_pass; else test_fail "code indentation accepted as a top-level vote"; fi

test_case "contribution identity includes ignored and nested cited file bytes"
mkdir -p "$TEST_TMP_DIR/repo/nested"
git -C "$TEST_TMP_DIR/repo" init -q
git -C "$TEST_TMP_DIR/repo/nested" init -q
printf 'ignored.py\n' > "$TEST_TMP_DIR/repo/.gitignore"
passed=true
for cited in ignored.py nested/reviewed.py; do
    printf 'before\n' > "$TEST_TMP_DIR/repo/$cited"
    printf 'Reviewed %s:1\nVERDICT: APPROVE\n' "$cited" > "$TEST_TMP_DIR/response"
    base="$(council_artifact_digest "$TEST_TMP_DIR/repo" review)"
    before="$(council_contribution_record_json "$TEST_TMP_DIR/response" "$TEST_TMP_DIR/repo" "$base" | jq -r .artifact_digest)"
    printf 'after\n' > "$TEST_TMP_DIR/repo/$cited"
    after="$(council_contribution_record_json "$TEST_TMP_DIR/response" "$TEST_TMP_DIR/repo" "$base" | jq -r .artifact_digest)"
    [[ "$before" != "$after" ]] || passed=false
done
if "$passed"; then test_pass; else test_fail "cited bytes omitted from contribution identity"; fi

test_case "older Python credential parsing accepts unrelated quoted project tables"
printf '%s\n' 'model_provider = "router"' '[model_providers.router]' 'env_key = "ROUTER_API_KEY"' '[projects."/tmp/example.project"]' 'trust_level = "trusted"' > "$TEST_TMP_DIR/codex.toml"
if [[ "$(OCTOPUS_FORCE_CODEX_TOML_FALLBACK=1 python3 "$PROJECT_ROOT/scripts/helpers/read-codex-config.py" "$TEST_TMP_DIR/codex.toml")" == ROUTER_API_KEY ]]; then
    test_pass
else test_fail "valid project table discarded selected credential"; fi

test_case "native token fields are independent of field order and suffixes"
SUPPORTS_NATIVE_TASK_METRICS=true SUPPORTS_OTEL_SPEED=false
parse_task_metrics $'<usage>\ncached_input_tokens: 900\ninput_tokens: 100\noutput_tokens: 20\ntotal_tokens: 1020\n</usage>'
first_input="$_PARSED_INPUT_TOKENS"
parse_task_metrics $'<usage>\ncache_creation_input_tokens: 900\noutput_tokens: 20\ntotal_tokens: 920\n</usage>'
if [[ "$first_input" == 100 && -z "$_PARSED_INPUT_TOKENS" && "$_PARSED_CACHE_WRITE_TOKENS" == 900 ]]; then
    test_pass
else test_fail "cache token suffix overwrote uncached input"; fi
test_summary
