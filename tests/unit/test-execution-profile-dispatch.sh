#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "execution profile dispatch"
export PLUGIN_DIR="$ROOT"
export OCTOPUS_PLATFORM=Linux
export OPENAI_COMPAT_BASE_URL=https://example.invalid/v1
export OPENAI_API_KEY=test-key
export _BARE_OPT=""
log(){ :; }
migrate_provider_config(){ :; }
resolve_octopus_model(){ echo model; }
get_agent_model(){ case "$1" in codex*) echo gpt-5.6;; claude*) echo sonnet;; openai-*) echo deepseek-ai/DeepSeek-V4-Pro;; *) echo model;; esac; }
validate_model_name(){ return 0; }
source "$ROOT/scripts/lib/execution-profile.sh"
source "$ROOT/scripts/lib/dispatch.sh"
get_agent_model(){ case "$1" in codex*) echo gpt-5.6;; claude*) echo sonnet;; openai-*) echo deepseek-ai/DeepSeek-V4-Pro;; *) echo model;; esac; }
validate_model_name(){ return 0; }
assert_contains() {
  local haystack="$1" needle="$2"
  test_case "contains: $needle"
  if [[ "$haystack" == *"$needle"* ]]; then test_pass; else test_fail "missing [$needle] in [$haystack]"; return 0; fi
}
assert_not_contains() {
  local haystack="$1" needle="$2"
  test_case "does not contain: $needle"
  if [[ "$haystack" != *"$needle"* ]]; then test_pass; else test_fail "unexpected [$needle] in [$haystack]"; return 0; fi
}
export OCTOPUS_REASONING_POLICY=strict
export OCTOPUS_CODEX_REASONING=medium
cmd=$(get_agent_command codex council logic-reviewer)
assert_contains "$cmd" "--model gpt-5.6"
assert_contains "$cmd" 'model_reasoning_effort="medium"'
unset OCTOPUS_CODEX_REASONING
export OCTOPUS_CLAUDE_REASONING=high
export SUPPORTS_EFFORT_COMMAND=true
export SUPPORTS_EFFORT_CLI_FLAG=true
cmd=$(get_agent_command claude-sonnet review code-reviewer)
assert_contains "$cmd" "--model sonnet"
assert_contains "$cmd" "--effort high"
export SUPPORTS_EFFORT_COMMAND=false
cmd=$(get_agent_command claude-sonnet review code-reviewer)
assert_not_contains "$cmd" "--effort"
export SUPPORTS_EFFORT_COMMAND=true
unset OCTOPUS_CLAUDE_REASONING
export OCTOPUS_OPENAI_COMPATIBLE_AGENT_REASONING=medium
cmd=$(get_agent_command openai-compatible-agent develop implementer)
assert_contains "$cmd" "--model deepseek-ai/DeepSeek-V4-Pro"
assert_contains "$cmd" "--reasoning-effort medium"
unset OCTOPUS_OPENAI_COMPATIBLE_AGENT_REASONING
# Legacy Gemini identifiers are canonicalized to the AGY Google seat. AGY
# selects its own model/reasoning policy, so Octopus emits only the wrapper.
cmd=$(get_agent_command gemini research researcher)
assert_contains "$cmd" "agy-exec.sh"
# Workflow roles are prose ("Technical implementation analysis"); the resolver
# must sanitize them into valid env-var names instead of aborting dispatch.
cmd=$(get_agent_command codex probe "Technical implementation analysis")
assert_contains "$cmd" "--model gpt-5.6"
export OCTOPUS_PROBE_TECHNICAL_IMPLEMENTATION_ANALYSIS_REASONING=medium
cmd=$(get_agent_command codex probe "Technical implementation analysis")
assert_contains "$cmd" 'model_reasoning_effort="medium"'
unset OCTOPUS_PROBE_TECHNICAL_IMPLEMENTATION_ANALYSIS_REASONING
# providers.<p>.reasoning is the v3.0 model slot, so provider-level effort
# lives in reasoning_effort/reasoning_policy beside it.
unset OCTOPUS_REASONING_POLICY
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
cat > "$OCTOPUS_PROVIDERS_CONFIG" <<'JSON'
{
  "version": "3.0",
  "providers": {
    "codex": {"default": "gpt-5.6-sol", "reasoning": "gpt-5.6-sol", "reasoning_effort": "medium"},
    "openai-compatible-agent": {"reasoning_effort": "low", "reasoning_policy": "strict"}
  }
}
JSON
cmd=$(get_agent_command codex review code-reviewer)
assert_contains "$cmd" 'model_reasoning_effort="medium"'
cmd=$(get_agent_command openai-compatible-agent develop implementer)
assert_contains "$cmd" "--reasoning-effort low --reasoning-policy strict"
cat > "$OCTOPUS_PROVIDERS_CONFIG" <<'JSON'
{
  "version": "3.0",
  "providers": {
    "codex": {"reasoning": {"default": "high", "policy": "best_effort"}}
  }
}
JSON
cmd=$(get_agent_command codex review code-reviewer)
assert_contains "$cmd" 'model_reasoning_effort="high"'
unset OCTOPUS_PROVIDERS_CONFIG
test_summary
