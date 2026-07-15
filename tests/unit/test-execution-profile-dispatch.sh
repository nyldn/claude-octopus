#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PLUGIN_DIR="$ROOT"
export OCTOPUS_PLATFORM=Linux
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
export OCTOPUS_REASONING_POLICY=strict
export OCTOPUS_CODEX_REASONING=medium
cmd=$(get_agent_command codex council logic-reviewer)
assert_contains "$cmd" "--model gpt-5.6"
assert_contains "$cmd" 'model_reasoning_effort="medium"'
unset OCTOPUS_CODEX_REASONING
export OCTOPUS_CLAUDE_REASONING=high
cmd=$(get_agent_command claude-sonnet review code-reviewer)
assert_contains "$cmd" "--model sonnet"
assert_contains "$cmd" "--effort high"
unset OCTOPUS_CLAUDE_REASONING
export OCTOPUS_OPENAI_COMPATIBLE_AGENT_REASONING=medium
cmd=$(get_agent_command openai-compatible-agent develop implementer)
assert_contains "$cmd" "--model deepseek-ai/DeepSeek-V4-Pro"
assert_contains "$cmd" "--reasoning-effort medium"
unset OCTOPUS_OPENAI_COMPATIBLE_AGENT_REASONING
export OCTOPUS_GEMINI_REASONING=high
set +e
get_agent_command gemini research researcher >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || { echo "FAIL strict Gemini reasoning should fail" >&2; exit 1; }
export OCTOPUS_REASONING_POLICY=best_effort
cmd=$(get_agent_command gemini research researcher)
assert_contains "$cmd" "gemini-exec.sh"
printf "PASS test-execution-profile-dispatch\n"
