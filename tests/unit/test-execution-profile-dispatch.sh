#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
assert_contains(){ [[ "$1" == *"$2"* ]] || { echo "FAIL missing [$2] in [$1]" >&2; exit 1; }; }
assert_not_contains(){ [[ "$1" != *"$2"* ]] || { echo "FAIL unexpected [$2] in [$1]" >&2; exit 1; }; }
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
printf "PASS test-execution-profile-dispatch\n"
