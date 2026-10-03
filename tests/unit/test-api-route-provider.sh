#!/usr/bin/env bash
# API Route uses the existing explicit-model, isolated tool-loop contract.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/providers.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
test_suite "API Route provider"
export PLUGIN_DIR="$PROJECT_ROOT"
PROVIDER_CODEX_INSTALLED=false
PROVIDER_CLAUDE_INSTALLED=false
TEST_HOME="$TEST_TMP_DIR/api-route-home"
mkdir -p "$TEST_HOME"
export OCTOPUS_PROVIDERS_CONFIG="$TEST_HOME/providers.json"
unset API_ROUTE_API_KEY API_ROUTE_MODEL OCTOPUS_API_ROUTE_MODEL OPENAI_COMPAT_MODEL
log() { :; }
resolve_provider_env() { return 1; }
migrate_provider_config() { :; }

test_case "missing credentials and model fail local health"
if ! check_provider_health api-route 2>/dev/null &&
   ! API_ROUTE_API_KEY=fixture-key check_provider_health api-route 2>/dev/null; then
    test_pass
else
    test_fail "key-only or empty provider reported ready"
fi

test_case "model pins preserve resolution precedence"
if [[ "$(API_ROUTE_MODEL=primary OCTOPUS_API_ROUTE_MODEL=secondary OPENAI_COMPAT_MODEL=generic octo_api_route_model)" == primary ]] &&
   [[ "$(OCTOPUS_API_ROUTE_MODEL=secondary OPENAI_COMPAT_MODEL=generic octo_api_route_model)" == secondary ]] &&
   [[ "$(OPENAI_COMPAT_MODEL=generic octo_api_route_model)" == generic ]]; then
    test_pass
else
    test_fail "model precedence drifted"
fi

test_case "providers.json default supports the hyphenated provider id"
printf '%s\n' '{"providers":{"api-route":{"default":"deepseek-v4.1-flash"}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
if [[ "$(octo_api_route_model)" == deepseek-v4.1-flash ]]; then test_pass; else test_fail "configured default not resolved"; fi
rm -f "$OCTOPUS_PROVIDERS_CONFIG"

test_case "unsafe model ids fail closed"
bad=false
for model in 'bad;touch' '/tmp/model' 'two words' 'model\' 'model$(cmd)' ''; do
    if octo_api_route_model "$model" >/dev/null; then bad=true; fi
done
if [[ "$bad" == false ]]; then test_pass; else test_fail "unsafe model accepted"; fi

test_case "API Route alias and exact seats canonicalize"
if [[ "$(octo_provider_canonical apiroute)" == api-route ]] &&
   [[ "$(octo_agent_spec_canonicalize_exact api-route-agent:deepseek-v4.1-flash)" == api-route-agent:deepseek-v4.1-flash ]]; then
    test_pass
else
    test_fail "provider identity or exact seat changed"
fi

test_case "review disables tools and implementation retains them"
review=$(PWD=/tmp/octo-cwd API_ROUTE_MODEL=deepseek-v4.1-flash get_agent_command api-route-agent review code-reviewer)
implementation=$(PWD=/tmp/octo-cwd API_ROUTE_MODEL=deepseek-v4.1-flash get_agent_command api-route-agent implementation implementer)
if [[ "$review" == *'--provider api-route'* && "$review" == *'--tool-policy none'* && "$implementation" != *'--tool-policy none'* ]]; then
    test_pass
else
    test_fail "role tool policy was not preserved"
fi

test_case "unconfigured dispatch has no guessed model"
if PWD=/tmp/octo-cwd get_agent_command api-route-agent implementation implementer >/dev/null 2>&1; then
    test_fail "unconfigured provider dispatched"
else
    test_pass
fi

test_case "configured health and exact-seat availability share model validation"
if API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=deepseek-v4.1-flash check_provider_health api-route &&
   API_ROUTE_API_KEY=fixture-key is_agent_available_v2 api-route-agent:deepseek-v4.1-flash &&
   ! API_ROUTE_API_KEY=fixture-key is_agent_available_v2 'api-route-agent:bad;touch'; then
    test_pass
else
    test_fail "health and availability disagreed"
fi

test_case "only the selected API Route credential crosses the child boundary"
export API_ROUTE_API_KEY=api-route-fixture OPENAI_API_KEY=unrelated-openai-key CHEAPER_INFERENCE_API_KEY=unrelated-gateway-key
export API_ROUTE_SENTINEL=must-not-cross
build_provider_env api-route-agent:deepseek-v4.1-flash
if "${PROVIDER_ENV_ARRAY[@]}" bash -c '[[ "$API_ROUTE_API_KEY" == api-route-fixture && -z "${OPENAI_API_KEY:-}" && -z "${CHEAPER_INFERENCE_API_KEY:-}" && -z "${API_ROUTE_SENTINEL:-}" ]]'; then
    test_pass
else
    test_fail "credential isolation failed"
fi
unset API_ROUTE_API_KEY OPENAI_API_KEY CHEAPER_INFERENCE_API_KEY API_ROUTE_SENTINEL

test_case "helper sends the API Route model and credential to the correct endpoint"
if HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py" python3 - <<'PY'
import contextlib, importlib.util, io, json, os, sys
spec = importlib.util.spec_from_file_location("api_route_agent", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for name in ("OPENAI_COMPAT_BASE_URL", "OPENAI_COMPAT_API_KEY_ENV", "OPENAI_COMPAT_MODEL"):
    os.environ.pop(name, None)
os.environ["API_ROUTE_API_KEY"] = "api-route-fixture"
os.environ["API_ROUTE_MODEL"] = "deepseek-v4.1-flash"
seen = []
class Response:
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"OK"}}]}'
def request(req, timeout):
    seen.append((req.full_url, req.get_header("Authorization"), json.loads(req.data)))
    return Response()
mod.open_credentialed_request = request
sys.argv = ["agent", "--provider", "api-route", "--tool-policy", "none", "--cwd", os.getcwd()]
sys.stdin = io.StringIO("Reply with OK.")
out = io.StringIO()
with contextlib.redirect_stdout(out):
    assert mod.main() == 0
url, auth, body = seen[0]
assert url == "https://global.api-route.com/v1/chat/completions", url
assert auth == "Bearer api-route-fixture"
assert body["model"] == "deepseek-v4.1-flash"
assert "tools" not in body
assert "OK" in out.getvalue()
PY
then test_pass; else test_fail "helper HTTP contract failed"; fi

test_summary
