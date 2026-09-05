#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/execution-profile.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

TEST_TMP_DIR="/tmp/octopus-tests-$$"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT
export HOME="$TEST_TMP_DIR/home"
mkdir -p "$HOME/.claude-octopus/config"
export PLUGIN_DIR="$PROJECT_ROOT"
export PWD="$TEST_TMP_DIR/project"
mkdir -p "$PWD"
log() {
  local level="$1"
  shift
  [[ "$level" == ERROR ]] && printf '[%s] %s\n' "$level" "$*" >&2
  return 0
}
get_agent_model() { printf '%s\n' 'deepseek-ai/DeepSeek-V4-Pro'; }
validate_model_name() { return 0; }
octopus_resolve_reasoning_level() { printf '%s\n' 'none'; }
octopus_resolve_reasoning_policy() { printf '%s\n' 'best_effort'; }
octopus_reasoning_cli_fragment() { printf '%s\n' ''; }

test_suite "OpenAI-compatible provider configuration"

write_config() {
  cat > "$HOME/.claude-octopus/config/providers.json"
}

test_case "provider definition supplies endpoint and credential env"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"https://api.example.com/v1","api_key_env":"DEEPSEEK_API_KEY"}}}
JSON
export DEEPSEEK_API_KEY="test-secret"
unset OPENAI_COMPAT_BASE_URL OPENAI_COMPAT_API_KEY_ENV || true
cmd=$(get_agent_command openai-compatible-agent tangle implementer)
if [[ "$cmd" == *"--base-url https://api.example.com/v1"* && "$cmd" == *"--api-key-env DEEPSEEK_API_KEY"* && "$cmd" == *"--model deepseek-ai/DeepSeek-V4-Pro"* && "$cmd" != *"test-secret"* ]]; then
  test_pass
else
  test_fail "dispatch did not use provider definition safely: $cmd"
fi

test_case "missing endpoint fails before helper launch"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","api_key_env":"DEEPSEEK_API_KEY"}}}
JSON
unset OPENAI_COMPAT_BASE_URL || true
if get_agent_command openai-compatible-agent tangle implementer >/dev/null 2>&1; then
  test_fail "incomplete provider configuration was accepted"
else
  test_pass
fi

test_case "missing configured credential fails before helper launch"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"https://api.example.com/v1","api_key_env":"MISSING_PROVIDER_KEY"}}}
JSON
unset MISSING_PROVIDER_KEY || true
if get_agent_command openai-compatible-agent tangle implementer >/dev/null 2>&1; then
  test_fail "missing credential was accepted"
else
  test_pass
fi

test_case "credentialed public HTTP endpoint is rejected before helper launch"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"http://api.example.com/v1","api_key_env":"DEEPSEEK_API_KEY"}}}
JSON
export DEEPSEEK_API_KEY="test-secret"
http_error="$TEST_TMP_DIR/public-http.err"
if get_agent_command openai-compatible-agent tangle implementer >/dev/null 2>"$http_error"; then
  test_fail "credentialed public HTTP endpoint was accepted"
elif grep -Fc "requires HTTPS for non-loopback endpoints" "$http_error" >/dev/null; then
  test_pass
else
  test_fail "credentialed public HTTP endpoint failed for an unexpected reason"
fi

test_case "loopback HTTP endpoints remain available for local development"
loopback_ok=true
for loopback_url in http://localhost:8000/v1 http://127.0.0.1:8000/v1; do
  printf '%s\n' '{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"'"$loopback_url"'","api_key_env":"DEEPSEEK_API_KEY"}}}' > "$HOME/.claude-octopus/config/providers.json"
  cmd=$(get_agent_command openai-compatible-agent tangle implementer)
  [[ "$cmd" == *"--base-url $loopback_url"* ]] || loopback_ok=false
done
if [[ "$loopback_ok" == true ]]; then
  test_pass
else
  test_fail "a loopback OpenAI-compatible endpoint was rejected"
fi

test_case "lookalike loopback authority cannot bypass HTTPS"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"http://localhost:8000@api.example.com/v1","api_key_env":"DEEPSEEK_API_KEY"}}}
JSON
lookalike_error="$TEST_TMP_DIR/lookalike-http.err"
if get_agent_command openai-compatible-agent tangle implementer >/dev/null 2>"$lookalike_error"; then
  test_fail "lookalike loopback authority was accepted"
elif grep -Fc "requires HTTPS for non-loopback endpoints" "$lookalike_error" >/dev/null; then
  test_pass
else
  test_fail "lookalike loopback authority failed for an unexpected reason"
fi

test_case "legacy environment fallback remains supported"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro"}}}
JSON
export OPENAI_COMPAT_BASE_URL="https://legacy.example.com/v1"
export OPENAI_COMPAT_API_KEY_ENV="LEGACY_PROVIDER_KEY"
export LEGACY_PROVIDER_KEY="legacy-secret"
cmd=$(get_agent_command openai-compatible-agent tangle implementer)
if [[ "$cmd" == *"--base-url https://legacy.example.com/v1"* && "$cmd" == *"--api-key-env LEGACY_PROVIDER_KEY"* ]]; then
  test_pass
else
  test_fail "legacy env fallback did not resolve: $cmd"
fi

test_case "invalid credential env name is rejected"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"https://api.example.com/v1","api_key_env":"BAD-NAME"}}}
JSON
if get_agent_command openai-compatible-agent tangle implementer >/dev/null 2>&1; then
  test_fail "invalid credential env name was accepted"
else
  test_pass
fi


test_case "OpenAI-compatible aliases share the canonical provider definition"
write_config <<'JSON'
{"providers":{"openai-compatible-agent":{"default":"deepseek-ai/DeepSeek-V4-Pro","base_url":"https://api.example.com/v1","api_key_env":"DEEPSEEK_API_KEY"}}}
JSON
export DEEPSEEK_API_KEY="test-secret"
unset OPENAI_COMPAT_BASE_URL OPENAI_COMPAT_API_KEY_ENV || true
cmd=$(get_agent_command openai-tools tangle implementer)
if [[ "$cmd" == *"--base-url https://api.example.com/v1"* && "$cmd" == *"--api-key-env DEEPSEEK_API_KEY"* ]]; then
  test_pass
else
  test_fail "alias did not use canonical provider definition: $cmd"
fi

test_summary
