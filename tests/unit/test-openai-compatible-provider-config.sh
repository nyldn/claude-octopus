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
log() { :; }
get_agent_model() { printf '%s\n' 'deepseek-ai/DeepSeek-V4-Pro'; }
validate_model_name() { return 0; }
octopus_resolve_reasoning_level() { printf '%s\n' 'none'; }
octopus_resolve_reasoning_policy() { printf '%s\n' 'best_effort'; }
octopus_reasoning_cli_fragment() { printf '%s\n' ''; }

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
