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
export PROVIDER_CODEX_INSTALLED=false
export PROVIDER_CLAUDE_INSTALLED=false
TEST_HOME="$TEST_TMP_DIR/api-route-home"
mkdir -p "$TEST_HOME"
export OCTOPUS_PROVIDERS_CONFIG="$TEST_HOME/providers.json"
unset API_ROUTE_API_KEY API_ROUTE_MODEL OCTOPUS_API_ROUTE_MODEL OPENAI_COMPAT_MODEL API_ROUTE_ALLOWED_MODELS
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
   [[ "$(PWD=/tmp/octo-cwd OCTOPUS_API_ROUTE_MODEL=secondary get_agent_command api-route-agent review code-reviewer)" == *'--model secondary '* ]] &&
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
for model in 'bad;touch' '/tmp/model' 'two words' 'model\' 'model$(cmd)' 'modelA,modelB' ''; do
    if octo_api_route_model "$model" >/dev/null; then bad=true; fi
done
if [[ "$bad" == false ]]; then test_pass; else test_fail "unsafe model accepted"; fi

test_case "comma-bearing models cannot spoof a CSV allowlist entry"
if ! API_ROUTE_ALLOWED_MODELS=modelA,modelB,modelC octo_api_route_effective_model modelA,modelB >/dev/null &&
   ! API_ROUTE_MODEL=modelA,modelB API_ROUTE_ALLOWED_MODELS=modelA,modelB,modelC octo_api_route_effective_model >/dev/null &&
   ! PWD=/tmp/octo-cwd API_ROUTE_MODEL=modelA,modelB API_ROUTE_ALLOWED_MODELS=modelA,modelB,modelC \
        get_agent_command api-route-agent review code-reviewer >/dev/null 2>&1 &&
   ! API_ROUTE_API_KEY=fixture-key API_ROUTE_ALLOWED_MODELS=modelA,modelB,modelC \
        is_agent_available_v2 api-route-agent:modelA,modelB &&
   [[ "$(API_ROUTE_ALLOWED_MODELS=modelA,modelB,modelC octo_api_route_effective_model modelB)" == modelB ]]; then
    test_pass
else
    test_fail "a composite model crossed the allowlist admission boundary"
fi

test_case "API Route family follows configured, exact and supplied effective models"
if [[ "$(API_ROUTE_MODEL=gpt-5.4 octo_agent_spec_model_family api-route-agent)" == openai ]] &&
   [[ "$(OCTOPUS_API_ROUTE_MODEL=deepseek-v4.1-flash octo_agent_spec_model_family apiroute)" == deepseek ]] &&
   [[ "$(API_ROUTE_MODEL=gpt-5.4 octo_agent_spec_model_family api-route-agent:deepseek-v4.1-flash)" == deepseek ]] &&
   [[ "$(API_ROUTE_MODEL=gpt-5.4 octo_agent_spec_model_family api-route-agent gemini-3.5-flash)" == google ]] &&
   [[ "$(API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=gpt-5.4-mini octo_agent_spec_model_family api-route-agent)" == openai ]] &&
   [[ "$(API_ROUTE_MODEL=gpt-5.4 API_ROUTE_ALLOWED_MODELS=deepseek-v4.1-flash octo_agent_spec_model_family api-route-agent:gpt-5.4)" == unknown ]] &&
   [[ "$(API_ROUTE_MODEL=unrecognized-model octo_agent_spec_model_family api-route-agent)" == unknown ]] &&
   [[ "$(octo_agent_spec_model_family api-route-agent)" == unknown ]]; then
    test_pass
else
    test_fail "transport or blocked exact pin was treated as model-family evidence"
fi

test_case "API Route configured default supplies its model family"
printf '%s\n' '{"providers":{"api-route":{"default":"gpt-5.4"}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
family="$(octo_agent_spec_model_family api-route-agent)"
rm -f "$OCTOPUS_PROVIDERS_CONFIG"
if [[ "$family" == openai ]]; then test_pass; else test_fail "configured default family was lost"; fi

test_case "API Route alias and exact seats canonicalize"
if [[ "$(octo_provider_canonical apiroute)" == api-route ]] &&
   [[ "$(octo_agent_spec_canonicalize_exact api-route-agent:deepseek-v4.1-flash)" == api-route-agent:deepseek-v4.1-flash ]]; then
    test_pass
else
    test_fail "provider identity or exact seat changed"
fi

test_case "fleet diversity uses the effective API Route model family"
if [[ "$(API_ROUTE_MODEL=gpt-5.6-sol octo_agent_spec_model_family api-route-agent)" == openai ]] &&
   [[ "$(API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=claude-sonnet-5 octo_agent_spec_model_family api-route-agent)" == anthropic ]] &&
   [[ "$(octo_agent_spec_model_family api-route-agent:gpt-5.6-sol)" == openai ]] &&
   [[ "$(octo_agent_spec_model_family api-route-agent)" == unknown ]] &&
   [[ "$(API_ROUTE_MODEL=unrecognized-model octo_agent_spec_model_family api-route-agent)" == unknown ]]; then
    test_pass
else
    test_fail "API Route transport was counted as a separate model family"
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

test_case "canonical API Route quota marker blocks pinned and unpinned seats"
if (
    source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
    WORKSPACE_DIR="$TEST_TMP_DIR/api-route-quota"
    octo_quota_mark_dead api-route 0
    ! API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=deepseek-v4.1-flash is_agent_available_v2 api-route-agent &&
    ! API_ROUTE_API_KEY=fixture-key is_agent_available_v2 api-route-agent:deepseek-v4.1-flash &&
    octo_quota_clear_dead api-route &&
    API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=deepseek-v4.1-flash is_agent_available_v2 api-route-agent &&
    API_ROUTE_API_KEY=fixture-key is_agent_available_v2 api-route-agent:deepseek-v4.1-flash
); then
    test_pass
else
    test_fail "quota-dead API Route stayed available or failed recovery"
fi

test_case "configured health and exact-seat availability share model validation"
if API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=deepseek-v4.1-flash check_provider_health api-route &&
   API_ROUTE_API_KEY=fixture-key is_agent_available_v2 api-route-agent:deepseek-v4.1-flash &&
   ! API_ROUTE_API_KEY=fixture-key is_agent_available_v2 'api-route-agent:bad;touch'; then
    test_pass
else
    test_fail "health and availability disagreed"
fi

test_case "invalid restriction fallbacks fail dispatch and standalone readiness"
if ! PWD=/tmp/octo-cwd API_ROUTE_MODEL=good API_ROUTE_ALLOWED_MODELS='bad;touch' get_agent_command api-route-agent review code-reviewer >/dev/null 2>&1 &&
   PROJECT_ROOT="$PROJECT_ROOT" API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=good API_ROUTE_ALLOWED_MODELS='bad;touch' OCTO_ALLOWED_PROVIDERS=api-route bash -c '
       source "$PROJECT_ROOT/scripts/lib/providers.sh"
       source "$PROJECT_ROOT/scripts/lib/preflight.sh"
       log() { :; }
       resolve_provider_env() { return 1; }
       ! check_provider_health api-route 2>/dev/null &&
       [[ "$(detect_providers)" != *"api-route:api-key"* ]] &&
       [[ "$(_octo_provider_static_readiness api-route)" != available\|* ]]
   '; then
    test_pass
else
    test_fail "a rejected fallback was advertised as ready"
fi

test_case "blocked exact seats are unavailable without substituting their model"
if ! API_ROUTE_API_KEY=fixture-key API_ROUTE_ALLOWED_MODELS=allowed is_agent_available_v2 api-route-agent:blocked &&
   ! PWD=/tmp/octo-cwd API_ROUTE_ALLOWED_MODELS=allowed get_agent_command api-route-agent:blocked review code-reviewer >/dev/null 2>&1 &&
   API_ROUTE_API_KEY=fixture-key API_ROUTE_ALLOWED_MODELS=allowed is_agent_available_v2 api-route-agent:allowed &&
   [[ "$(PWD=/tmp/octo-cwd API_ROUTE_ALLOWED_MODELS=allowed get_agent_command api-route-agent:allowed review code-reviewer)" == *'--model allowed '* ]]; then
    test_pass
else
    test_fail "exact-seat availability disagreed with dispatch restrictions"
fi

test_case "unpinned availability validates the effective allowlist fallback"
if API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=allowed is_agent_available_v2 api-route-agent &&
   ! API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS='bad;touch' is_agent_available_v2 api-route-agent &&
   ! API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=claude-fable-5-1 is_agent_available_v2 api-route-agent; then
    test_pass
else
    test_fail "availability admitted a rejected fallback or blocked a valid one"
fi

test_case "a blocked exact primary seat selects its configured available fallback"
if (
    source "$PROJECT_ROOT/scripts/lib/agents.sh"
    export AGENTS_CONFIG="$TEST_HOME/agents.yaml"
    printf '%s\n' 'agents:' '  code-reviewer:' '    cli: api-route-agent:blocked' '    fallback_cli: codex' > "$AGENTS_CONFIG"
    export API_ROUTE_API_KEY=fixture-key API_ROUTE_ALLOWED_MODELS=allowed
    export PROVIDER_CODEX_INSTALLED=true PROVIDER_CODEX_AUTH_METHOD=api-key
    [[ "$(resolve_persona_spawn_target code-reviewer)" == codex ]]
); then
    test_pass
else
    test_fail "a blocked API Route pin bypassed the configured primary-seat fallback"
fi

test_case "valid allowlist fallback is shared with dispatch and health"
if [[ "$(API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=gpt-5.4-mini octo_api_route_effective_model)" == gpt-5.4-mini ]] &&
   [[ "$(PWD=/tmp/octo-cwd API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=gpt-5.4-mini get_agent_command api-route-agent review code-reviewer)" == *'--model gpt-5.4-mini '* ]] &&
   API_ROUTE_API_KEY=fixture-key API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=gpt-5.4-mini check_provider_health api-route &&
   [[ "$(API_ROUTE_MODEL=pinned API_ROUTE_ALLOWED_MODELS=pinned octo_api_route_effective_model)" == pinned ]] &&
   ! API_ROUTE_MODEL=blocked API_ROUTE_ALLOWED_MODELS=claude-fable-5-1 octo_api_route_effective_model >/dev/null; then
    test_pass
else
    test_fail "allowlist fallback or explicit pin policy drifted"
fi

test_case "API Route does not claim an unverified independent model check"
checker="$TEST_HOME/provider-checker.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" codex:available agy:available qwen:available openai-compatible:available api-route:available\n' > "$checker"
chmod +x "$checker"
fleet="$(OCTO_ALLOWED_PROVIDERS=codex,agy,qwen,openai-compatible,api-route OCTOPUS_PROVIDER_CHECKER="$checker" \
    API_ROUTE_MODEL=shared-model OPENAI_COMPAT_MODEL=shared-model \
    bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research deep fixture)"
if [[ "$fleet" == *'openai-compatible|Cross-Synthesis|'* && "$fleet" != *'api-route-agent|Independent Model Check|'* ]]; then
    test_pass
else
    test_fail "gateway diversity admission changed: $fleet"
fi

test_case "fleet ordering and family totals use the configured API Route model"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" codex:available api-route:available\n' > "$checker"
same_fleet="$(OCTO_ALLOWED_PROVIDERS=codex,api-route,claude OCTOPUS_PROVIDER_CHECKER="$checker" \
    API_ROUTE_MODEL=gpt-5.4 bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research quick fixture \
    2> "$TEST_HOME/same-family.log")"
different_fleet="$(OCTO_ALLOWED_PROVIDERS=codex,api-route,claude OCTOPUS_PROVIDER_CHECKER="$checker" \
    API_ROUTE_MODEL=deepseek-v4.1-flash bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research quick fixture \
    2> "$TEST_HOME/different-family.log")"
if [[ "$same_fleet" == *'claude-sonnet|Ecosystem Overview|'* && "$same_fleet" != *'api-route-agent|Ecosystem Overview|'* ]] &&
   [[ "$(cat "$TEST_HOME/same-family.log")" == *'families=2 '* ]] &&
   [[ "$different_fleet" == *'api-route-agent|Ecosystem Overview|'* ]] &&
   [[ "$(cat "$TEST_HOME/different-family.log")" == *'families=3 '* ]]; then
    test_pass
else
    test_fail "fleet claimed transport diversity instead of resolved model diversity"
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
