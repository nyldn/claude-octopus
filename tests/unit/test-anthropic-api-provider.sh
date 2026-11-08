#!/usr/bin/env bash
# Text-only API dispatch and environment contract. All transports are inert.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Anthropic Messages text seat"
log() { :; }
export PLUGIN_DIR="$PROJECT_ROOT" _BARE_OPT="" TMPDIR="$TEST_TMP_DIR" CLAUDE_CODE_SESSION="api-fixture-$$"
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
printf '%s\n' '{"version":"3.0","providers":{}}' > "$OCTOPUS_PROVIDERS_CONFIG"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch-plan.sh"

test_case "Messages payload, effort compatibility, response types and HTTP errors"
if python3 "$SCRIPT_DIR/test-anthropic-api-provider.py"; then test_pass; else test_fail "Messages transport contracts failed"; fi

test_case "provider identity, runtime and text-only restrictions agree"
if octo_provider_validate_contracts &&
   [[ "$(octo_provider_canonical anthropic-api)" == anthropic-api ]] &&
   octo_provider_has_capability anthropic-api text-only &&
   ! octo_provider_has_capability anthropic-api council &&
   [[ "$(get_agent_model anthropic-api probe researcher)" == claude-sonnet-5-5 ]] &&
   is_api_based_provider anthropic-api; then
    test_pass
else
    test_fail "text-only provider metadata diverged"
fi

test_case "tool-requiring and unspecified roles fail before dispatch"
failed=false
for role in implementer developer debugger verifier release unknown ''; do
    if get_agent_command anthropic-api develop "$role" >/dev/null 2>&1; then failed=true; fi
done
if [[ "$failed" == false ]]; then test_pass; else test_fail "a tool-requiring role received a text-only seat"; fi

test_case "explicit incompatible thinking and effort settings fail before dispatch"
if OCTOPUS_ANTHROPIC_API_THINKING=between_tools OCTOPUS_ANTHROPIC_API_REASONING=max get_agent_command anthropic-api probe planner >/dev/null 2>&1 ||
   OCTOPUS_ANTHROPIC_API_THINKING=disabled get_agent_command anthropic-api probe planner >/dev/null 2>&1 ||
   OCTOPUS_ANTHROPIC_API_MODEL=claude-opus-5-5 OCTOPUS_ANTHROPIC_API_THINKING=between_tools get_agent_command anthropic-api probe planner >/dev/null 2>&1 ||
   OCTOPUS_ANTHROPIC_API_MODEL='claude-sonnet-5-5 --tools' get_agent_command anthropic-api probe planner >/dev/null 2>&1; then
    test_fail "unsafe or unsupported thinking/model configuration was admitted"
else
    test_pass
fi

test_case "local health requires an explicit API key and never infers CLI login"
if (unset ANTHROPIC_API_KEY; check_provider_health anthropic-api >/dev/null 2>&1); then
    test_fail "CLI login was used instead of an explicit API key"
elif ANTHROPIC_API_KEY=inert-fixture check_provider_health anthropic-api; then
    test_pass
else
    test_fail "an explicit API key and Python did not pass local prerequisite checks"
fi

real_python="$(command -v python3)"
fixture="$TEST_TMP_DIR/transport"
mkdir -p "$fixture"
cat > "$fixture/driver.py" <<'PYDRIVER'
import importlib.util, io, json, os, pathlib, sys
base = pathlib.Path(__file__).parent
argv = sys.argv[1:]
assert argv.pop(0) == '-I'
helper = argv.pop(0)
spec = importlib.util.spec_from_file_location('api', helper)
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
def transport(request, timeout):
    (base / 'request.json').write_bytes(request.data)
    (base / 'env.json').write_text(json.dumps(sorted(os.environ)))
    return io.BytesIO(b'{"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"fixture answer"}],"stop_reason":"end_turn"}')
api.urlopen = transport
sys.argv = [helper] + argv
sys.exit(api.main())
PYDRIVER
printf '#!/usr/bin/env bash\nexec "%s" "%s/driver.py" "$@"\n' "$real_python" "$fixture" > "$fixture/python3"
chmod +x "$fixture/python3"

export ANTHROPIC_API_KEY=inert-fixture OPENAI_API_KEY=unrelated-fixture CLAUDE_SDK_API_KEY=unrelated-sdk
export PATH="$fixture:$PATH" OCTOPUS_ANTHROPIC_API_MAX_TOKENS=4096
command="$(OCTOPUS_ANTHROPIC_API_REASONING=medium get_agent_command anthropic-api probe researcher)"
test_case "emitted command validates while extra arguments and foreign helper paths fail"
if validate_agent_command "$command" &&
   ! validate_agent_command "$command --endpoint https://other.example" &&
   ! validate_agent_command "/tmp/scripts/helpers/anthropic-api-exec.sh --model claude-sonnet-5-5 --effort medium --thinking auto"; then
    test_pass
else
    test_fail "API command did not survive validation or admitted an untrusted helper"
fi
read -r -a argv <<< "$command"
build_provider_env anthropic-api
test_case "actual isolated adapter emits between_tools and returns text without leaking parent credentials"
out="$(printf 'supplied evidence' | "${PROVIDER_ENV_ARRAY[@]}" "${argv[@]}")"
if [[ "$out" == 'fixture answer' ]] && "$real_python" - "$fixture" <<'PYASSERT'
import json, pathlib, sys
base = pathlib.Path(sys.argv[1])
payload = json.loads((base / 'request.json').read_text())
names = json.loads((base / 'env.json').read_text())
assert payload['thinking'] == {'type': 'between_tools'}
assert payload['output_config'] == {'effort': 'medium'}
assert payload['max_tokens'] == 4096
assert payload['messages'] == [{'role':'user','content':'supplied evidence'}]
assert 'ANTHROPIC_API_KEY' in names
assert 'OPENAI_API_KEY' not in names and 'CLAUDE_SDK_API_KEY' not in names
assert 'ANTHROPIC_AUTH_TOKEN' not in names and 'ANTHROPIC_BASE_URL' not in names
PYASSERT
then test_pass; else test_fail "isolated adapter lost request settings or credential isolation"; fi

test_case "automatic tier effort reaches the isolated adapter without an effort parameter"
printf '%s\n' '{"cost_mode":"budget","providers":{"anthropic-api":{"default":"claude-sonnet-5-5","reasoning_effort":"high"}},"tiers":{"budget":{"anthropic-api":{"capability":"default","reasoning":"auto"}}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
auto_command="$(get_agent_command anthropic-api probe researcher)"
read -r -a auto_argv <<< "$auto_command"
if validate_agent_command "$auto_command" &&
   printf 'supplied evidence' | "${PROVIDER_ENV_ARRAY[@]}" "${auto_argv[@]}" > "$TEST_TMP_DIR/auto-answer" &&
   [[ "$(cat "$TEST_TMP_DIR/auto-answer")" == 'fixture answer' ]] && "$real_python" - "$fixture" <<'PYASSERT'
import json, pathlib, sys
payload = json.loads((pathlib.Path(sys.argv[1]) / 'request.json').read_text())
assert 'output_config' not in payload
assert payload['thinking'] == {'type': 'adaptive'}
assert payload['messages'] == [{'role':'user','content':'supplied evidence'}]
PYASSERT
then test_pass; else test_fail "automatic tier effort was replaced or lost at the adapter boundary"; fi

test_case "automatic effort rejects explicit between_tools thinking before dispatch"
if OCTOPUS_ANTHROPIC_API_THINKING=between_tools get_agent_command anthropic-api probe researcher >/dev/null 2>&1; then
    test_fail "unknown automatic effort admitted between_tools thinking"
else test_pass; fi
printf '%s\n' '{"version":"3.0","providers":{}}' > "$OCTOPUS_PROVIDERS_CONFIG"

test_case "API context admission reserves output while allowing an explicit larger input budget"
if [[ "$(get_provider_context_limit anthropic-api probe researcher)" == 7392 ]] &&
   [[ "$(OCTOPUS_ANTHROPIC_API_CONTEXT_BUDGET=50000 get_provider_context_limit anthropic-api probe researcher)" == 45392 ]]; then
    test_pass
else
    test_fail "text-seat context allowance ignored output reserve or explicit input budget"
fi

test_case "dispatch plan records no tools, metered billing and the API output reserve"
export PROJECT_ROOT WORKSPACE_DIR="$TEST_TMP_DIR"
source "$PROJECT_ROOT/scripts/lib/cost.sh"
argv_json="$(octo_dispatch_command_argv_json "$command")"
plan="$(octo_dispatch_plan_create anthropic-api probe researcher "$argv_json" claude-sonnet-5-5)"
if [[ "$(jq -r '.provider' <<< "$plan")" == anthropic-api ]] &&
   [[ "$(jq -r '.tool_policy' <<< "$plan")" == none ]] &&
   [[ "$(jq -r '.budgets.output_reserve_tokens' <<< "$plan")" == 4096 ]] &&
   [[ "$(jq -r ' .billing_mode' <<< "$plan")" == api ]] &&
   ! grep -Fq inert-fixture <<< "$plan"; then
    test_pass
else
    test_fail "API dispatch plan lost its restrictions or exposed credentials"
fi

test_summary
