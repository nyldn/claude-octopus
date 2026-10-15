#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Command Code Harness"

FIXTURE_DIR="$TEST_TMP_DIR/commandcode"
MOCK_ARGS="$FIXTURE_DIR/args"
mkdir -p "$FIXTURE_DIR/bin"
cat > "$FIXTURE_DIR/bin/command-code" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_ARGS"
cat > "${MOCK_STDIN:-/dev/null}"
printf '%s\n' '{"type":"event","event":{"type":"tool_running"}}'
printf '%s\n' "${MOCK_RESULT:-{\"type\":\"result\",\"subtype\":\"success\",\"sessionId\":\"abc\",\"finalText\":\"HARNESS_OK\"}}"
exit "${MOCK_RC:-0}"
EOF
chmod +x "$FIXTURE_DIR/bin/command-code"
unset OCTOPUS_COMMANDCODE_BIN MOCK_RESULT MOCK_RC
export PATH="$FIXTURE_DIR/bin:$PATH" MOCK_ARGS MOCK_STDIN="$FIXTURE_DIR/stdin"

test_case "extracts final text and passes plan-mode arguments"
out=$(printf 'inspect only' | "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro plan)
if [[ "$out" == "HARNESS_OK" ]] && grep -Fx -- '--permission-mode' "$MOCK_ARGS" >/dev/null && grep -Fx -- 'plan' "$MOCK_ARGS" >/dev/null && grep -Fx -- '--output-format' "$MOCK_ARGS" >/dev/null && grep -Fx -- 'json' "$MOCK_ARGS" >/dev/null && ! grep -Fx -- '--max-turns' "$MOCK_ARGS" >/dev/null && ! grep -Fx -- 'inspect only' "$MOCK_ARGS" >/dev/null && [[ "$(cat "$MOCK_STDIN")" == "inspect only" ]]; then
    test_pass
else
    test_fail "expected finalText and plan/json arguments without an Octopus max-turns override"
fi

test_case "uses yolo only when explicitly selected"
out=$(printf 'implement' | "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" minimaxai/minimax-m3 yolo)
if [[ "$out" == "HARNESS_OK" ]] && grep -Fx -- '--yolo' "$MOCK_ARGS" >/dev/null && grep -Fx -- 'minimaxai/minimax-m3' "$MOCK_ARGS" >/dev/null; then
    test_pass
else
    test_fail "expected explicit yolo and selected model"
fi

test_case "returns non-zero for a structured error result"
export MOCK_RESULT='{"type":"result","subtype":"error","error":{"message":"denied"}}' MOCK_RC=0
if printf 'fail' | "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro plan >/dev/null 2>&1; then
    test_fail "expected structured error to fail"
else
    test_pass
fi
unset MOCK_RESULT MOCK_RC

test_case "preserves non-zero CLI exit status"
export MOCK_RESULT='{"type":"result","subtype":"error","error":{"message":"failed"}}' MOCK_RC=7
set +e
printf 'fail' | "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro plan >/dev/null 2>&1
rc=$?
set -e
unset MOCK_RESULT MOCK_RC
if [[ "$rc" -eq 7 ]]; then test_pass; else test_fail "expected exit 7, got $rc"; fi

test_case "dispatch selects yolo for implementers and plan for verifiers"
export PLUGIN_DIR="$PROJECT_ROOT" OCTOPUS_PLATFORM=Linux HOME="$FIXTURE_DIR/home"
mkdir -p "$HOME/.claude-octopus/config"
# dispatch.sh's log() lives in orchestrate.sh, which this harness never
# sources; stub it so ERROR-path assertions can see the emitted text
# instead of a bare "log: command not found".
log() { local level="$1"; shift; printf '%s: %s\n' "$level" "$*" >&2; }
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
export OCTOPUS_COMMANDCODE_MODEL=deepseek/deepseek-v4-pro
impl_cmd="$(get_agent_command commandcode tangle implementer)"
verify_cmd="$(get_agent_command commandcode verify verifier)"
if [[ "$impl_cmd" == *'commandcode-exec.sh deepseek/deepseek-v4-pro yolo' ]] && [[ "$verify_cmd" == *'commandcode-exec.sh deepseek/deepseek-v4-pro plan' ]]; then
    test_pass
else
    test_fail "unexpected role permission mapping"
fi

# Issue #710: OCTOPUS_COMMANDCODE_PERMISSION_MODE was accepted by
# commandcode-exec.sh but dispatch always passed an explicit positional
# argument, so the env var was dead on the dispatch path.
test_case "OCTOPUS_COMMANDCODE_PERMISSION_MODE override is honoured on the dispatch path"
override_mismatch=""
for mode in plan default dont-ask auto-accept yolo; do
    export OCTOPUS_COMMANDCODE_PERMISSION_MODE="$mode"
    override_cmd="$(get_agent_command commandcode tangle implementer)"
    if [[ "$override_cmd" != *"commandcode-exec.sh deepseek/deepseek-v4-pro ${mode}" ]]; then
        override_mismatch="mode=${mode} got: ${override_cmd}"
        break
    fi
done
unset OCTOPUS_COMMANDCODE_PERMISSION_MODE
if [[ -z "$override_mismatch" ]]; then
    test_pass
else
    test_fail "expected env override to win over the role-derived default, ${override_mismatch}"
fi

test_case "invalid OCTOPUS_COMMANDCODE_PERMISSION_MODE is rejected and falls back to the role default"
export OCTOPUS_COMMANDCODE_PERMISSION_MODE=danger-full-access
error_log="$FIXTURE_DIR/invalid-commandcode-permission-mode.err"
invalid_cmd="$(get_agent_command commandcode tangle implementer 2>"$error_log")"
unset OCTOPUS_COMMANDCODE_PERMISSION_MODE
if [[ "$invalid_cmd" == *'commandcode-exec.sh deepseek/deepseek-v4-pro yolo' ]] &&
   grep -F -- 'ERROR: Invalid OCTOPUS_COMMANDCODE_PERMISSION_MODE value:' "$error_log" >/dev/null; then
    test_pass
else
    test_fail "expected fallback to role default (yolo) with logged error, got: $invalid_cmd"
fi

test_case "override dispatch command passes validate_agent_command"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
export OCTOPUS_COMMANDCODE_PERMISSION_MODE=auto-accept
override_valid_cmd="$(get_agent_command commandcode verify verifier)"
unset OCTOPUS_COMMANDCODE_PERMISSION_MODE
if [[ "$override_valid_cmd" != *' auto-accept' ]]; then
    test_fail "expected auto-accept override to be forwarded, got: $override_valid_cmd"
elif validate_agent_command "$override_valid_cmd" >/dev/null 2>&1; then
    test_pass
else
    test_fail "override dispatch command rejected by validate_agent_command"
fi

# The command dispatch actually returns must survive validate_agent_command, or
# every commandcode dispatch aborts the phase before the CLI is ever invoked —
# the same failure mode as #697 (copilot-exec.sh) and #705 (agy-exec.sh). Asserting
# the shape of get_agent_command's output is not enough; validate it.
test_case "dispatch commands for commandcode pass validate_agent_command"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
if validate_agent_command "$impl_cmd" >/dev/null 2>&1 && validate_agent_command "$verify_cmd" >/dev/null 2>&1; then
    test_pass
else
    test_fail "commandcode dispatch command rejected by validate_agent_command"
fi

test_case "provider environment forwards only dedicated controls"
export COMMAND_CODE_API_KEY=test-key CMD_ZDR=1 OCTOPUS_COMMANDCODE_BIN=/custom/cmd
build_provider_env commandcode
joined=" ${PROVIDER_ENV_ARRAY[*]} "
if [[ "$joined" == *' COMMAND_CODE_API_KEY=test-key '* ]] && [[ "$joined" == *' CMD_ZDR=1 '* ]] && [[ "$joined" == *' OCTOPUS_COMMANDCODE_BIN=/custom/cmd '* ]]; then
    test_pass
else
    test_fail "missing isolated Command Code environment entries"
fi

SLOW_CLI="$FIXTURE_DIR/bin/slow-command-code"
cat > "$SLOW_CLI" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$MOCK_PID_FILE"
cat >/dev/null
for _ in 1 2 3; do
    printf '%s\n' '{"type":"event","event":{"type":"tool_running"}}'
    if [[ -n "${MOCK_CHILD_PID_FILE:-}" ]]; then
        sleep "${MOCK_EVENT_GAP:-1}" &
        printf '%s\n' "$!" > "$MOCK_CHILD_PID_FILE"
        wait "$!"
    else
        sleep "${MOCK_EVENT_GAP:-1}"
    fi
done
printf '%s\n' '{"type":"result","subtype":"success","sessionId":"abc","finalText":"SLOW_OK"}'
MOCK
chmod +x "$SLOW_CLI"

test_case "reports progress on stderr while the event stream grows"
export MOCK_PID_FILE="$FIXTURE_DIR/slow.pid" MOCK_EVENT_GAP=1
progress_err="$FIXTURE_DIR/progress.err"
out=$(printf 'implement' | OCTOPUS_COMMANDCODE_BIN="$SLOW_CLI" OCTOPUS_COMMANDCODE_HEARTBEAT_SECS=1 \
    "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro yolo 2>"$progress_err")
if [[ "$out" == "SLOW_OK" ]] && grep -q 'commandcode: still working' "$progress_err"; then
    test_pass
else
    test_fail "expected final text and a progress line, got out=$out err=$(cat "$progress_err")"
fi

test_case "the CLI does not outlive a killed helper"
# A CLI reparented to a PID 1 that never reaps stays as a zombie; that is gone too.
cli_gone() {
    kill -0 "$1" 2>/dev/null || return 0
    [[ "$(ps -o stat= -p "$1" 2>/dev/null)" == Z* ]]
}
rm -f "$MOCK_PID_FILE"
export MOCK_EVENT_GAP=20
printf 'implement' | OCTOPUS_COMMANDCODE_BIN="$SLOW_CLI" \
    "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro yolo >/dev/null 2>&1 &
helper_pid=$!
for _ in $(seq 1 50); do [[ -s "$MOCK_PID_FILE" ]] && break; sleep 0.1; done
cli_pid="$(cat "$MOCK_PID_FILE" 2>/dev/null || true)"
kill -KILL "$helper_pid" 2>/dev/null || true
wait "$helper_pid" 2>/dev/null || true
for _ in $(seq 1 50); do cli_gone "$cli_pid" && break; sleep 0.1; done
if [[ -n "$cli_pid" ]] && cli_gone "$cli_pid"; then
    test_pass
else
    kill -KILL "$cli_pid" 2>/dev/null || true
    test_fail "CLI $cli_pid survived its helper"
fi
unset MOCK_PID_FILE MOCK_EVENT_GAP

fallback_descendant_cleanup() {
    local variant="$1" extra_tool="${2:-}" tool tool_path
    local tools=(awk bash cat jq mktemp ps rm sleep wc)
    [[ -z "$extra_tool" ]] || tools+=("$extra_tool")
    NO_GROUP_BIN="$FIXTURE_DIR/no-process-group-bin-$variant"
    mkdir -p "$NO_GROUP_BIN"
    for tool in "${tools[@]}"; do
        tool_path="$(command -v "$tool" 2>/dev/null || true)"
        [[ -x "$tool_path" ]] && ln -sf "$tool_path" "$NO_GROUP_BIN/$tool"
    done
    export MOCK_PID_FILE="$FIXTURE_DIR/no-group-$variant-cli.pid" MOCK_CHILD_PID_FILE="$FIXTURE_DIR/no-group-$variant-child.pid" MOCK_EVENT_GAP=20
    rm -f "$MOCK_PID_FILE" "$MOCK_CHILD_PID_FILE"
    printf 'implement' | PATH="$NO_GROUP_BIN" OCTOPUS_COMMANDCODE_BIN="$SLOW_CLI" \
        "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro yolo >/dev/null 2>"$FIXTURE_DIR/no-group-$variant.err" &
    helper_pid=$!
    for _ in $(seq 1 50); do
        [[ -s "$MOCK_PID_FILE" && -s "$MOCK_CHILD_PID_FILE" ]] && break
        sleep 0.1
    done
    cli_pid="$(cat "$MOCK_PID_FILE" 2>/dev/null || true)"
    child_pid="$(cat "$MOCK_CHILD_PID_FILE" 2>/dev/null || true)"
    kill -KILL "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
    for _ in $(seq 1 50); do cli_gone "$cli_pid" && cli_gone "$child_pid" && break; sleep 0.1; done
    if [[ -n "$cli_pid" && -n "$child_pid" ]] && cli_gone "$cli_pid" && cli_gone "$child_pid"; then
        test_pass
    else
        kill -KILL "$cli_pid" "$child_pid" 2>/dev/null || true
        test_fail "CLI $cli_pid or child $child_pid survived fallback cleanup: $(tail -5 "$FIXTURE_DIR/no-group-$variant.err" 2>/dev/null || true)"
    fi
    unset MOCK_PID_FILE MOCK_CHILD_PID_FILE MOCK_EVENT_GAP
}
test_case "fallback cleanup stops CLI descendants without process-group helpers"
fallback_descendant_cleanup no-group

test_case "fallback cleanup preserves descendants until the watcher can stop them when only setpriv exists"
if command -v setpriv >/dev/null 2>&1; then
    fallback_descendant_cleanup setpriv-only setpriv
else
    test_skip "setpriv is unavailable on this platform; portable watcher fallback is covered separately"
fi

test_case "TERM cleanup preserves its status and removes files after the watcher exits"
cleanup_dir="$FIXTURE_DIR/cancel-tmp"
mkdir -p "$cleanup_dir"
export MOCK_PID_FILE="$FIXTURE_DIR/cancel.pid" MOCK_EVENT_GAP=20
cancel_trace="$FIXTURE_DIR/cancel.trace"
printf 'implement' | TMPDIR="$cleanup_dir" OCTOPUS_COMMANDCODE_BIN="$SLOW_CLI" \
    bash -x "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" deepseek/deepseek-v4-pro yolo >/dev/null 2>"$cancel_trace" &
helper_pid=$!
watcher_pid=""
cli_pid=""
for _ in $(seq 1 50); do
    cli_pid="$(cat "$MOCK_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$cli_pid" ]]; then
        watcher_pid="$(ps -axo pid=,ppid= | awk -v parent="$helper_pid" -v cli="$cli_pid" '$2 == parent && $1 != cli { print $1; exit }')"
        [[ -n "$watcher_pid" ]] && break
    fi
    sleep 0.1
done
if [[ -n "$watcher_pid" ]]; then
    kill -TERM "$watcher_pid" 2>/dev/null || true
    for _ in $(seq 1 50); do cli_gone "$watcher_pid" && break; sleep 0.1; done
fi
kill -TERM "$helper_pid" 2>/dev/null || true
cleanup_rc=0
wait "$helper_pid" 2>/dev/null || cleanup_rc=$?
remaining_files="$(find "$cleanup_dir" -type f -print)"
cli_kill_attempts="$(grep -Ec "^[+]+ kill -KILL (-- )?-?${cli_pid}$" "$cancel_trace" || true)"
if [[ -n "$cli_pid" && -n "$watcher_pid" && "$cleanup_rc" -eq 143 && -z "$remaining_files" && "$cli_kill_attempts" -eq 1 ]] && cli_gone "$cli_pid"; then
    test_pass
else
    kill -KILL "$cli_pid" 2>/dev/null || true
    test_fail "expected TERM status 143, one CLI kill and no temporary files; got status=$cleanup_rc kills=$cli_kill_attempts files=$remaining_files"
fi
unset MOCK_PID_FILE MOCK_EVENT_GAP

test_summary
