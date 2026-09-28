#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "execution profile"
source "$ROOT/scripts/lib/execution-profile.sh"
TMP="$TEST_TMP_DIR/execution-profile"
mkdir -p "$TMP"
CFG="$TMP/providers.json"
cat > "$CFG" <<JSON
{
  "providers": {
    "codex": {"reasoning":"gpt-5.6-sol","reasoning_effort":"low","reasoning_policy":"best_effort"},
    "claude": {"reasoning_effort":"high","reasoning_policy":"strict"},
    "openai-compatible-agent": {"reasoning":{"default":"medium","policy":"strict"}},
    "openai-compatible": {"reasoning":{"default":"high","policy":"best_effort"},"reasoning_effort":"low","reasoning_policy":"strict"}
  },
  "routing": {
    "phases": {
      "research": {"provider":"gemini","model":"gemini-3.1-pro-preview","reasoning":"high","reasoningPolicy":"best_effort"}
    },
    "roles": {
      "implementer": {"provider":"openai-compatible-agent","model":"deepseek-ai/DeepSeek-V4-Pro","reasoning":"medium","reasoningPolicy":"strict"},
      "logic-reviewer": {"provider":"codex","model":"gpt-5.6","reasoning":"medium","reasoningPolicy":"strict"},
      "quick-checker": {"provider":"codex","model":"gpt-5.6-mini","reasoning":"low","reasoningPolicy":"strict"},
      "legacy-reviewer": "claude:sonnet"
    }
  }
}
JSON
export OCTOPUS_PROVIDERS_CONFIG="$CFG"
assert_eq() {
  local actual="$1" expected="$2" desc="${3:-expected $2}"
  test_case "$desc"
  if [[ "$actual" == "$expected" ]]; then
    test_pass
  else
    test_fail "expected=[$expected] got=[$actual]"
    return 0
  fi
}
assert_eq "$(octopus_profile_provider council logic-reviewer fallback)" codex
assert_eq "$(octopus_profile_model council logic-reviewer)" gpt-5.6
assert_eq "$(octopus_profile_provider council quick-checker fallback)" codex
assert_eq "$(octopus_profile_model council quick-checker)" gpt-5.6-mini
assert_eq "$(octopus_resolve_reasoning_level codex council quick-checker)" low
assert_eq "$(octopus_profile_provider build implementer fallback)" openai-compatible-agent
assert_eq "$(octopus_profile_model build implementer)" deepseek-ai/DeepSeek-V4-Pro
assert_eq "$(octopus_profile_provider review legacy-reviewer fallback)" claude
assert_eq "$(octopus_profile_model review legacy-reviewer)" sonnet
assert_eq "$(octopus_profile_provider research unknown fallback)" gemini
assert_eq "$(octopus_profile_model research unknown)" gemini-3.1-pro-preview
assert_eq "$(octopus_resolve_reasoning_level codex council logic-reviewer)" medium
assert_eq "$(octopus_resolve_reasoning_policy codex council logic-reviewer)" strict
assert_eq "$(octopus_resolve_reasoning_level codex "" "")" low "provider reasoning_effort beside the reasoning model slot"
assert_eq "$(octopus_resolve_reasoning_policy claude "" "")" strict "provider reasoning_policy"
assert_eq "$(octopus_resolve_reasoning_level openai-compatible-agent "" "")" medium "legacy provider reasoning object level"
assert_eq "$(octopus_resolve_reasoning_policy openai-compatible-agent "" "")" strict "legacy provider reasoning object policy"
assert_eq "$(octopus_resolve_reasoning_level openai-compatible "" "")" low "reasoning_effort outranks a legacy reasoning object"
assert_eq "$(octopus_resolve_reasoning_policy openai-compatible "" "")" strict "reasoning_policy outranks a legacy reasoning object"
assert_eq "$(octopus_reasoning_cli_fragment codex medium strict)" "-c model_reasoning_effort=\"medium\""
assert_eq "$(octopus_reasoning_cli_fragment claude high strict)" "--effort high"
assert_eq "$(octopus_reasoning_cli_fragment openai-compatible-agent medium strict)" "--reasoning-effort medium --reasoning-policy strict"
set +e
octopus_reasoning_cli_fragment gemini high strict >/dev/null 2>&1
rc=$?
set -e
assert_eq "$rc" 2
assert_eq "$(octopus_reasoning_cli_fragment gemini high best_effort)" ""
OCTOPUS_COUNCIL_LOGIC_REVIEWER_AGENT=codex:local-shell-override
assert_eq "$(octopus_explicit_provider_override council logic-reviewer)" codex:local-shell-override "unexported shell override remains visible"
unset OCTOPUS_COUNCIL_LOGIC_REVIEWER_AGENT
export OCTOPUS_LOGIC_REVIEWER_REASONING=high
assert_eq "$(octopus_resolve_reasoning_level codex council logic-reviewer)" high
unset OCTOPUS_LOGIC_REVIEWER_REASONING
export OCTOPUS_COUNCIL_LOGIC_REVIEWER_REASONING=low
assert_eq "$(octopus_resolve_reasoning_level codex council logic-reviewer)" low
unset OCTOPUS_COUNCIL_LOGIC_REVIEWER_REASONING
test_summary
