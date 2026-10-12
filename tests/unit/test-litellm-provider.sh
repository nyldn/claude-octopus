#!/usr/bin/env bash
# LiteLLM uses the explicit-model, isolated tool-loop contract plus a self-hosted proxy URL.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/providers.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
test_suite "LiteLLM provider"
export PLUGIN_DIR="$PROJECT_ROOT"
export PROVIDER_CODEX_INSTALLED=false
export PROVIDER_CLAUDE_INSTALLED=false
TEST_HOME="$TEST_TMP_DIR/litellm-home"
mkdir -p "$TEST_HOME"
export OCTOPUS_PROVIDERS_CONFIG="$TEST_HOME/providers.json"
unset LITELLM_API_KEY LITELLM_BASE_URL LITELLM_MODEL OCTOPUS_LITELLM_MODEL OPENAI_COMPAT_MODEL LITELLM_ALLOWED_MODELS
log() { :; }
resolve_provider_env() { return 1; }
migrate_provider_config() { :; }

test_case "missing credentials and model fail local health"
if ! check_provider_health litellm 2>/dev/null &&
   ! LITELLM_API_KEY=fixture-key check_provider_health litellm 2>/dev/null; then
    test_pass
else
    test_fail "key-only or empty provider reported ready"
fi

test_case "model pins preserve resolution precedence"
if [[ "$(LITELLM_MODEL=primary OCTOPUS_LITELLM_MODEL=secondary OPENAI_COMPAT_MODEL=generic octo_litellm_model)" == primary ]] &&
   [[ "$(OCTOPUS_LITELLM_MODEL=secondary OPENAI_COMPAT_MODEL=generic octo_litellm_model)" == secondary ]] &&
   [[ "$(PWD=/tmp/octo-cwd OCTOPUS_LITELLM_MODEL=secondary get_agent_command litellm-agent review code-reviewer)" == *'--model secondary '* ]]; then
    test_pass
else
    test_fail "model precedence drifted"
fi

test_case "another gateway's OPENAI_COMPAT_MODEL does not configure LiteLLM"
if ! OPENAI_COMPAT_MODEL=generic octo_litellm_model >/dev/null &&
   ! PWD=/tmp/octo-cwd OPENAI_COMPAT_MODEL=generic get_agent_command litellm-agent review code-reviewer >/dev/null 2>&1 &&
   ! LITELLM_API_KEY=fixture-key OPENAI_COMPAT_MODEL=generic is_agent_available_v2 litellm-agent &&
   ! LITELLM_API_KEY=fixture-key OPENAI_COMPAT_MODEL=generic check_provider_health litellm 2>/dev/null &&
   [[ "$(LITELLM_API_KEY=fixture-key OPENAI_COMPAT_MODEL=generic OCTO_ALLOWED_PROVIDERS=litellm detect_providers 2>/dev/null)" != *"litellm:api-key"* ]]; then
    test_pass
else
    test_fail "OPENAI_COMPAT_MODEL leaked into LiteLLM model resolution"
fi

test_case "providers.json default resolves the provider id"
printf '%s\n' '{"providers":{"litellm":{"default":"gpt-4o-mini"}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
if [[ "$(octo_litellm_model)" == gpt-4o-mini ]]; then test_pass; else test_fail "configured default not resolved"; fi
rm -f "$OCTOPUS_PROVIDERS_CONFIG"

test_case "unsafe model ids fail closed"
bad=false
for model in 'bad;touch' '/tmp/model' 'two words' 'model\' 'model$(cmd)' 'modelA,modelB' ''; do
    if octo_litellm_model "$model" >/dev/null; then bad=true; fi
done
if [[ "$bad" == false ]]; then test_pass; else test_fail "unsafe model accepted"; fi

test_case "comma-bearing models cannot spoof a CSV allowlist entry"
if ! LITELLM_ALLOWED_MODELS=modelA,modelB,modelC octo_litellm_effective_model modelA,modelB >/dev/null &&
   ! LITELLM_MODEL=modelA,modelB LITELLM_ALLOWED_MODELS=modelA,modelB,modelC octo_litellm_effective_model >/dev/null &&
   ! PWD=/tmp/octo-cwd LITELLM_MODEL=modelA,modelB LITELLM_ALLOWED_MODELS=modelA,modelB,modelC \
        get_agent_command litellm-agent review code-reviewer >/dev/null 2>&1 &&
   ! LITELLM_API_KEY=fixture-key LITELLM_ALLOWED_MODELS=modelA,modelB,modelC \
        is_agent_available_v2 litellm-agent:modelA,modelB &&
   [[ "$(LITELLM_ALLOWED_MODELS=modelA,modelB,modelC octo_litellm_effective_model modelB)" == modelB ]]; then
    test_pass
else
    test_fail "a composite model crossed the allowlist admission boundary"
fi

test_case "LiteLLM family follows configured, exact and supplied effective models"
if [[ "$(LITELLM_MODEL=gpt-5.4 octo_agent_spec_model_family litellm-agent)" == openai ]] &&
   [[ "$(OCTOPUS_LITELLM_MODEL=deepseek-chat octo_agent_spec_model_family litellm)" == deepseek ]] &&
   [[ "$(LITELLM_MODEL=gpt-5.4 octo_agent_spec_model_family litellm-agent:deepseek-chat)" == deepseek ]] &&
   [[ "$(LITELLM_MODEL=gpt-5.4 octo_agent_spec_model_family litellm-agent gemini-3.5-flash)" == google ]] &&
   [[ "$(LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=gpt-5.4-mini octo_agent_spec_model_family litellm-agent)" == openai ]] &&
   [[ "$(LITELLM_MODEL=gpt-5.4 LITELLM_ALLOWED_MODELS=deepseek-chat octo_agent_spec_model_family litellm-agent:gpt-5.4)" == unknown ]] &&
   [[ "$(LITELLM_MODEL=unrecognized-model octo_agent_spec_model_family litellm-agent)" == unknown ]] &&
   [[ "$(octo_agent_spec_model_family litellm-agent)" == unknown ]]; then
    test_pass
else
    test_fail "transport or blocked exact pin was treated as model-family evidence"
fi

test_case "LiteLLM configured default supplies its model family"
printf '%s\n' '{"providers":{"litellm":{"default":"gpt-5.4"}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
family="$(octo_agent_spec_model_family litellm-agent)"
rm -f "$OCTOPUS_PROVIDERS_CONFIG"
if [[ "$family" == openai ]]; then test_pass; else test_fail "configured default family was lost"; fi

test_case "LiteLLM alias and exact seats canonicalize"
if [[ "$(octo_provider_canonical litellm)" == litellm ]] &&
   [[ "$(octo_agent_spec_canonicalize_exact litellm-agent:gpt-4o-mini)" == litellm-agent:gpt-4o-mini ]]; then
    test_pass
else
    test_fail "provider identity or exact seat changed"
fi

test_case "fleet diversity uses the effective LiteLLM model family"
if [[ "$(LITELLM_MODEL=gpt-5.6-sol octo_agent_spec_model_family litellm-agent)" == openai ]] &&
   [[ "$(LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=claude-sonnet-5 octo_agent_spec_model_family litellm-agent)" == anthropic ]] &&
   [[ "$(octo_agent_spec_model_family litellm-agent:gpt-5.6-sol)" == openai ]] &&
   [[ "$(octo_agent_spec_model_family litellm-agent)" == unknown ]] &&
   [[ "$(LITELLM_MODEL=unrecognized-model octo_agent_spec_model_family litellm-agent)" == unknown ]]; then
    test_pass
else
    test_fail "LiteLLM transport was counted as a separate model family"
fi

test_case "review disables tools and implementation retains them"
review=$(PWD=/tmp/octo-cwd LITELLM_MODEL=gpt-4o-mini get_agent_command litellm-agent review code-reviewer)
implementation=$(PWD=/tmp/octo-cwd LITELLM_MODEL=gpt-4o-mini get_agent_command litellm-agent implementation implementer)
if [[ "$review" == *'--provider litellm'* && "$review" == *'--tool-policy none'* && "$implementation" != *'--tool-policy none'* ]]; then
    test_pass
else
    test_fail "role tool policy was not preserved"
fi

test_case "unconfigured dispatch has no guessed model"
if PWD=/tmp/octo-cwd get_agent_command litellm-agent implementation implementer >/dev/null 2>&1; then
    test_fail "unconfigured provider dispatched"
else
    test_pass
fi

test_case "canonical LiteLLM quota marker blocks pinned and unpinned seats"
if (
    source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
    WORKSPACE_DIR="$TEST_TMP_DIR/litellm-quota"
    octo_quota_mark_dead litellm 0
    ! LITELLM_API_KEY=fixture-key LITELLM_MODEL=gpt-4o-mini is_agent_available_v2 litellm-agent &&
    ! LITELLM_API_KEY=fixture-key is_agent_available_v2 litellm-agent:gpt-4o-mini &&
    octo_quota_clear_dead litellm &&
    LITELLM_API_KEY=fixture-key LITELLM_MODEL=gpt-4o-mini is_agent_available_v2 litellm-agent &&
    LITELLM_API_KEY=fixture-key is_agent_available_v2 litellm-agent:gpt-4o-mini
); then
    test_pass
else
    test_fail "quota-dead LiteLLM stayed available or failed recovery"
fi

test_case "configured health and exact-seat availability share model validation"
if LITELLM_API_KEY=fixture-key LITELLM_MODEL=gpt-4o-mini check_provider_health litellm &&
   LITELLM_API_KEY=fixture-key is_agent_available_v2 litellm-agent:gpt-4o-mini &&
   ! LITELLM_API_KEY=fixture-key is_agent_available_v2 'litellm-agent:bad;touch'; then
    test_pass
else
    test_fail "health and availability disagreed"
fi

test_case "invalid restriction fallbacks fail dispatch and standalone readiness"
if ! PWD=/tmp/octo-cwd LITELLM_MODEL=good LITELLM_ALLOWED_MODELS='bad;touch' get_agent_command litellm-agent review code-reviewer >/dev/null 2>&1 &&
   PROJECT_ROOT="$PROJECT_ROOT" LITELLM_API_KEY=fixture-key LITELLM_MODEL=good LITELLM_ALLOWED_MODELS='bad;touch' OCTO_ALLOWED_PROVIDERS=litellm bash -c '
       source "$PROJECT_ROOT/scripts/lib/providers.sh"
       source "$PROJECT_ROOT/scripts/lib/preflight.sh"
       log() { :; }
       resolve_provider_env() { return 1; }
       ! check_provider_health litellm 2>/dev/null &&
       [[ "$(detect_providers)" != *"litellm:api-key"* ]] &&
       [[ "$(_octo_provider_static_readiness litellm)" != available\|* ]]
   '; then
    test_pass
else
    test_fail "a rejected fallback was advertised as ready"
fi

test_case "blocked exact seats are unavailable without substituting their model"
if ! LITELLM_API_KEY=fixture-key LITELLM_ALLOWED_MODELS=allowed is_agent_available_v2 litellm-agent:blocked &&
   ! PWD=/tmp/octo-cwd LITELLM_ALLOWED_MODELS=allowed get_agent_command litellm-agent:blocked review code-reviewer >/dev/null 2>&1 &&
   LITELLM_API_KEY=fixture-key LITELLM_ALLOWED_MODELS=allowed is_agent_available_v2 litellm-agent:allowed &&
   [[ "$(PWD=/tmp/octo-cwd LITELLM_ALLOWED_MODELS=allowed get_agent_command litellm-agent:allowed review code-reviewer)" == *'--model allowed '* ]]; then
    test_pass
else
    test_fail "exact-seat availability disagreed with dispatch restrictions"
fi

test_case "unpinned availability validates the effective allowlist fallback"
if LITELLM_API_KEY=fixture-key LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=allowed is_agent_available_v2 litellm-agent &&
   ! LITELLM_API_KEY=fixture-key LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS='bad;touch' is_agent_available_v2 litellm-agent &&
   ! LITELLM_API_KEY=fixture-key LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=claude-fable-5-1 is_agent_available_v2 litellm-agent; then
    test_pass
else
    test_fail "availability admitted a rejected fallback or blocked a valid one"
fi

test_case "a blocked exact primary seat selects its configured available fallback"
if (
    source "$PROJECT_ROOT/scripts/lib/agents.sh"
    export AGENTS_CONFIG="$TEST_HOME/agents.yaml"
    printf '%s\n' 'agents:' '  code-reviewer:' '    cli: litellm-agent:blocked' '    fallback_cli: codex' > "$AGENTS_CONFIG"
    export LITELLM_API_KEY=fixture-key LITELLM_ALLOWED_MODELS=allowed
    export PROVIDER_CODEX_INSTALLED=true PROVIDER_CODEX_AUTH_METHOD=api-key
    [[ "$(resolve_persona_spawn_target code-reviewer)" == codex ]]
); then
    test_pass
else
    test_fail "a blocked LiteLLM pin bypassed the configured primary-seat fallback"
fi

test_case "valid allowlist fallback is shared with dispatch and health"
if [[ "$(LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=gpt-5.4-mini octo_litellm_effective_model)" == gpt-5.4-mini ]] &&
   [[ "$(PWD=/tmp/octo-cwd LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=gpt-5.4-mini get_agent_command litellm-agent review code-reviewer)" == *'--model gpt-5.4-mini '* ]] &&
   LITELLM_API_KEY=fixture-key LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=gpt-5.4-mini check_provider_health litellm &&
   [[ "$(LITELLM_MODEL=pinned LITELLM_ALLOWED_MODELS=pinned octo_litellm_effective_model)" == pinned ]] &&
   ! LITELLM_MODEL=blocked LITELLM_ALLOWED_MODELS=claude-fable-5-1 octo_litellm_effective_model >/dev/null; then
    test_pass
else
    test_fail "allowlist fallback or explicit pin policy drifted"
fi

test_case "LiteLLM does not claim an unverified independent model check"
checker="$TEST_HOME/provider-checker.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" codex:available agy:available qwen:available openai-compatible:available litellm:available\n' > "$checker"
chmod +x "$checker"
fleet="$(OCTO_ALLOWED_PROVIDERS=codex,agy,qwen,openai-compatible,litellm OCTOPUS_PROVIDER_CHECKER="$checker" \
    LITELLM_MODEL=shared-model OPENAI_COMPAT_MODEL=shared-model \
    bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research deep fixture)"
if [[ "$fleet" == *'openai-compatible|Cross-Synthesis|'* && "$fleet" != *'litellm-agent|Independent Model Check|'* ]]; then
    test_pass
else
    test_fail "gateway diversity admission changed: $fleet"
fi

test_case "fleet ordering and family totals use the configured LiteLLM model"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" codex:available litellm:available\n' > "$checker"
same_fleet="$(OCTO_ALLOWED_PROVIDERS=codex,litellm,claude OCTOPUS_PROVIDER_CHECKER="$checker" \
    LITELLM_MODEL=gpt-5.4 bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research quick fixture \
    2> "$TEST_HOME/same-family.log")"
different_fleet="$(OCTO_ALLOWED_PROVIDERS=codex,litellm,claude OCTOPUS_PROVIDER_CHECKER="$checker" \
    LITELLM_MODEL=deepseek-chat bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research quick fixture \
    2> "$TEST_HOME/different-family.log")"
if [[ "$same_fleet" == *'claude-sonnet|Ecosystem Overview|'* && "$same_fleet" != *'litellm-agent|Ecosystem Overview|'* ]] &&
   [[ "$(cat "$TEST_HOME/same-family.log")" == *'families=2 '* ]] &&
   [[ "$different_fleet" == *'litellm-agent|Ecosystem Overview|'* ]] &&
   [[ "$(cat "$TEST_HOME/different-family.log")" == *'families=3 '* ]]; then
    test_pass
else
    test_fail "fleet claimed transport diversity instead of resolved model diversity"
fi

test_case "only the selected LiteLLM credential crosses the child boundary"
export LITELLM_API_KEY=litellm-fixture OPENAI_API_KEY=unrelated-openai-key CHEAPER_INFERENCE_API_KEY=unrelated-gateway-key
export LITELLM_SENTINEL=must-not-cross
build_provider_env litellm-agent:gpt-4o-mini
if "${PROVIDER_ENV_ARRAY[@]}" bash -c '[[ "$LITELLM_API_KEY" == litellm-fixture && -z "${OPENAI_API_KEY:-}" && -z "${CHEAPER_INFERENCE_API_KEY:-}" && -z "${LITELLM_SENTINEL:-}" ]]'; then
    test_pass
else
    test_fail "credential isolation failed"
fi
unset LITELLM_API_KEY OPENAI_API_KEY CHEAPER_INFERENCE_API_KEY LITELLM_SENTINEL

test_case "helper sends the LiteLLM model and credential to the correct endpoint"
if HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py" python3 - <<'PY'
import contextlib, importlib.util, io, json, os, sys
spec = importlib.util.spec_from_file_location("litellm_agent", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for name in ("OPENAI_COMPAT_BASE_URL", "OPENAI_COMPAT_API_KEY_ENV", "OPENAI_COMPAT_MODEL"):
    os.environ.pop(name, None)
os.environ["LITELLM_API_KEY"] = "litellm-fixture"
os.environ["LITELLM_MODEL"] = "gpt-4o-mini"
seen = []
class Response:
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"OK"}}]}'
def request(req, timeout):
    seen.append((req.full_url, req.get_header("Authorization"), json.loads(req.data)))
    return Response()
mod.open_credentialed_request = request
sys.argv = ["agent", "--provider", "litellm", "--tool-policy", "none", "--cwd", os.getcwd()]
sys.stdin = io.StringIO("Reply with OK.")
out = io.StringIO()
with contextlib.redirect_stdout(out):
    assert mod.main() == 0
url, auth, body = seen[0]
assert url == "http://localhost:4000/v1/chat/completions", url
assert auth == "Bearer litellm-fixture"
assert body["model"] == "gpt-4o-mini"
assert "tools" not in body
assert "OK" in out.getvalue()
PY
then test_pass; else test_fail "helper HTTP contract failed"; fi

test_case "helper does not take the LiteLLM model from OPENAI_COMPAT_MODEL"
if HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py" python3 - <<'PY'
import contextlib, importlib.util, io, os, sys
spec = importlib.util.spec_from_file_location("litellm_agent", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for name in ("LITELLM_MODEL", "OCTOPUS_LITELLM_MODEL"):
    os.environ.pop(name, None)
os.environ["LITELLM_API_KEY"] = "litellm-fixture"
os.environ["OPENAI_COMPAT_MODEL"] = "other-gateway-model"
def request(req, timeout):
    raise AssertionError("no request may be sent without a LiteLLM model")
mod.open_credentialed_request = request
sys.argv = ["agent", "--provider", "litellm", "--tool-policy", "none", "--cwd", os.getcwd()]
sys.stdin = io.StringIO("Reply with OK.")
err = io.StringIO()
with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
    assert mod.main() == 2
assert "LITELLM_MODEL" in err.getvalue() and "OPENAI_COMPAT_MODEL" not in err.getvalue(), err.getvalue()
PY
then test_pass; else test_fail "helper read another gateway's model setting"; fi

test_case "proxy URL normalizes to the /v1 root and keeps a path prefix"
if [[ "$(octo_litellm_base_url)" == http://localhost:4000/v1 ]] &&
   [[ "$(octo_litellm_base_url http://127.0.0.1:4000)" == http://127.0.0.1:4000/v1 ]] &&
   [[ "$(octo_litellm_base_url https://gw.example.com/v1/)" == https://gw.example.com/v1 ]] &&
   [[ "$(octo_litellm_base_url https://gw.example.com/litellm//)" == https://gw.example.com/litellm/v1 ]] &&
   [[ "$(LITELLM_BASE_URL=https://proxy.example.com:8443 octo_litellm_base_url)" == https://proxy.example.com:8443/v1 ]] &&
   [[ "$(octo_litellm_base_url https://litellm_proxy:4000)" == https://litellm_proxy:4000/v1 ]]; then
    test_pass
else
    test_fail "proxy URL normalization drifted"
fi

test_case "unsafe proxy URLs fail closed"
bad=false
for url in 'ftp://proxy:4000' 'proxy:4000' 'https://user:secret@proxy:4000' 'https://user:123@proxy' \
           'https://user@proxy:4000' 'https://proxy:4000/a b' 'https://proxy:4000/;touch' 'https://proxy:4000/$(cmd)' \
           'https:///v1' 'http://' 'http://-proxy:4000' 'http://_proxy:4000' 'http://proxy:port' \
           'http://proxy:4000/%2e' 'http://proxy:4000/~user' 'http://proxy:4000?x=1' 'http://proxy:4000#frag'; do
    if octo_litellm_base_url "$url" >/dev/null; then bad=true; fi
done
if [[ "$bad" == false ]]; then test_pass; else test_fail "unsafe proxy URL accepted"; fi

test_case "every proxy URL detection accepts also passes the dispatch validator"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
mismatch=""
for url in http://localhost:4000 https://litellm_proxy:4000 https://litellm_proxy:4000/v1/ http://10.0.0.5:4000 \
           https://gw.example.com/litellm/ https://proxy.example.com:8443/v1 http://litellm-proxy.internal_net:4000 \
           https://user:secret@proxy:4000 'http://proxy:4000/%2e' 'http://proxy:4000/~user' http://_proxy:4000 \
           http://proxy:port 'ftp://proxy:4000'; do
    accepted=false dispatched=false validated=false
    octo_litellm_base_url "$url" >/dev/null && accepted=true
    if command="$(PWD=/tmp/octo-cwd LITELLM_BASE_URL="$url" LITELLM_MODEL=gpt-4o-mini \
            get_agent_command litellm-agent review code-reviewer 2>/dev/null)"; then
        dispatched=true
        _validate_openai_compatible_agent_command "$command" && validated=true
    fi
    if [[ "$accepted" != "$dispatched" || "$dispatched" != "$validated" ]]; then
        mismatch+=" $url(accepted=$accepted dispatched=$dispatched validated=$validated)"
    fi
done
if [[ -z "$mismatch" ]] &&
   [[ "$(PWD=/tmp/octo-cwd LITELLM_BASE_URL=https://litellm_proxy:4000 LITELLM_MODEL=gpt-4o-mini \
        get_agent_command litellm-agent review code-reviewer)" == *'--base-url https://litellm_proxy:4000/v1 '* ]]; then
    test_pass
else
    test_fail "readiness and dispatch URL grammars disagree:$mismatch"
fi

test_case "project configuration cannot redirect an independently supplied key"
if (
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    mkdir -p "$TEST_HOME/untrusted-project"
    printf '%s\n' 'LITELLM_BASE_URL=https://attacker.example.com' > "$TEST_HOME/untrusted-project/.env"
    cd "$TEST_HOME/untrusted-project"
    unset LITELLM_BASE_URL
    export LITELLM_API_KEY=fixture-key LITELLM_MODEL=gpt-4o-mini
    [[ "$(octo_litellm_base_url)" == http://localhost:4000/v1 ]] &&
    [[ "$(get_agent_command litellm-agent review code-reviewer)" == *'--base-url http://localhost:4000/v1 '* ]] &&
    [[ "$(LITELLM_BASE_URL=https://env.example.com octo_litellm_base_url)" == https://env.example.com/v1 ]]
); then
    test_pass
else
    test_fail "project configuration changed the credential destination"
fi

test_case "remote HTTP is rejected by every LiteLLM admission path"
if (
    source "$PROJECT_ROOT/scripts/lib/preflight.sh"
    source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
    export LITELLM_API_KEY=fixture-key LITELLM_MODEL=gpt-4o-mini OCTO_ALLOWED_PROVIDERS=litellm
    export WORKSPACE_DIR="$TEST_HOME/http-rejection"
    for url in http://10.0.0.5:4000 http://litellm_proxy:4000 http://localhost.evil:4000 http://127.0.0.1.evil:4000; do
        export LITELLM_BASE_URL="$url"
        ! octo_litellm_base_url >/dev/null || exit 1
        ! get_agent_command litellm-agent review code-reviewer >/dev/null 2>&1 || exit 1
        ! check_provider_health litellm 2>/dev/null || exit 1
        ! is_agent_available_v2 litellm-agent || exit 1
        [[ "$(detect_providers)" != *"litellm:api-key"* ]] || exit 1
        [[ "$(_octo_provider_static_readiness litellm)" == degraded\|config-invalid\|* ]] || exit 1
        # Any curl call would expose the fixture credential; record it even in a subshell.
        curl() { touch "$TEST_HOME/http-probe-called"; return 1; }
        OCTOPUS_PREFLIGHT_PROBE=1 octo_provider_probe litellm || exit 1
        [[ ! -e "$TEST_HOME/http-probe-called" ]] || exit 1
    done
); then
    test_pass
else
    test_fail "remote HTTP was admitted or received a credentialed probe"
fi

test_case "dispatch passes the normalized proxy URL to the helper"
command="$(PWD=/tmp/octo-cwd LITELLM_BASE_URL=https://gw.example.com/litellm/ LITELLM_MODEL=claude-sonnet-4-6 \
    get_agent_command litellm-agent review code-reviewer)"
if [[ "$command" == *'--provider litellm --base-url https://gw.example.com/litellm/v1 --model claude-sonnet-4-6 '* ]]; then
    test_pass
else
    test_fail "unexpected command: $command"
fi

test_case "an invalid proxy URL blocks dispatch, health, detection and availability"
if ! PWD=/tmp/octo-cwd LITELLM_BASE_URL='https://user:secret@proxy' LITELLM_MODEL=good \
        get_agent_command litellm-agent review code-reviewer >/dev/null 2>&1 &&
   ! LITELLM_API_KEY=fixture-key LITELLM_BASE_URL='ftp://proxy' LITELLM_MODEL=good is_agent_available_v2 litellm-agent &&
   PROJECT_ROOT="$PROJECT_ROOT" LITELLM_API_KEY=fixture-key LITELLM_MODEL=good LITELLM_BASE_URL='ftp://proxy' OCTO_ALLOWED_PROVIDERS=litellm bash -c '
       source "$PROJECT_ROOT/scripts/lib/providers.sh"
       source "$PROJECT_ROOT/scripts/lib/preflight.sh"
       log() { :; }
       resolve_provider_env() { return 1; }
       ! check_provider_health litellm 2>/dev/null &&
       [[ "$(detect_providers)" != *"litellm:api-key"* ]] &&
       [[ "$(_octo_provider_static_readiness litellm)" != available\|* ]]
   '; then
    test_pass
else
    test_fail "an invalid proxy URL was admitted"
fi

test_case "helper normalizes a direct --base-url with a path prefix"
if HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py" python3 - <<'PY'
import contextlib, importlib.util, io, os, sys
spec = importlib.util.spec_from_file_location("litellm_agent", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
os.environ["LITELLM_API_KEY"] = "litellm-fixture"
seen = []
class Response:
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"OK"}}]}'
def request(req, timeout):
    seen.append(req.full_url)
    return Response()
mod.open_credentialed_request = request
sys.argv = ["agent", "--provider", "litellm", "--base-url", "https://gw.example.com/litellm/",
            "--model", "gpt-4.1-mini", "--tool-policy", "none", "--cwd", os.getcwd()]
sys.stdin = io.StringIO("Reply with OK.")
with contextlib.redirect_stdout(io.StringIO()):
    assert mod.main() == 0
assert seen[0] == "https://gw.example.com/litellm/v1/chat/completions", seen[0]
PY
then test_pass; else test_fail "helper did not normalize the proxy URL"; fi

test_summary
