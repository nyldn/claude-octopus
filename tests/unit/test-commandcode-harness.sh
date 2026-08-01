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
if [[ "$out" == "HARNESS_OK" ]] && grep -Fx -- '--permission-mode' "$MOCK_ARGS" >/dev/null && grep -Fx -- 'plan' "$MOCK_ARGS" >/dev/null && grep -Fx -- '--output-format' "$MOCK_ARGS" >/dev/null && grep -Fx -- 'json' "$MOCK_ARGS" >/dev/null && ! grep -Fx -- 'inspect only' "$MOCK_ARGS" >/dev/null && [[ "$(cat "$MOCK_STDIN")" == "inspect only" ]]; then
    test_pass
else
    test_fail "expected finalText and plan/json arguments"
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
export COMMAND_CODE_API_KEY=test-key CMD_ZDR=1 OCTOPUS_COMMANDCODE_BIN=/custom/cmd OCTOPUS_COMMANDCODE_MAX_TURNS=12
build_provider_env commandcode
joined=" ${PROVIDER_ENV_ARRAY[*]} "
if [[ "$joined" == *' COMMAND_CODE_API_KEY=test-key '* ]] && [[ "$joined" == *' CMD_ZDR=1 '* ]] && [[ "$joined" == *' OCTOPUS_COMMANDCODE_BIN=/custom/cmd '* ]] && [[ "$joined" == *' OCTOPUS_COMMANDCODE_MAX_TURNS=12 '* ]]; then
    test_pass
else
    test_fail "missing isolated Command Code environment entries"
fi

test_summary
