#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "compound init model resolution"

export PLUGIN_DIR="$PROJECT_ROOT"
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
export OCTOPUS_STATE_DIR="$TEST_TMP_DIR/state"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export OCTOPUS_REVIEWER_FLIP=codex OCTOPUS_ROUTING_POLICY=off
mkdir -p "$WORKSPACE_DIR"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/agent-utils.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
# Disable only persistent caching; exercise the real provider and model resolvers.
octo_model_cache_file() { return 1; }
SUPPORTS_SONNET_5=true
SUPPORTS_OPUS_5=true
unset OCTOPUS_CODEX_MODEL OCTOPUS_CLAUDE_MODEL OCTOPUS_OPUS_MODEL CLAUDE_MODEL
printf '%s\n' '{"routing":{"roles":{},"phases":{}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
INIT_BLOCK="$(awk '/^    init-workflow\)/ {active=1; next} active && /^[[:space:]]*;;$/ {exit} active {print}' "$PROJECT_ROOT/scripts/orchestrate.sh")"
bundle() { ( eval "$INIT_BLOCK" ); }

assert_models() {
    local description="$1" expression="$2" data="$3"
    test_case "$description"
    if jq -e "$expression" <<< "$data" >/dev/null; then test_pass; else test_fail "incorrect summary: $data"; fi
}
assert_models "default summary distinguishes research, implementation and synthesis" \
    '.models.researcher == "default" and .models.implementer == "gpt-5.6-sol" and .models.reviewer == "gpt-5.6-sol" and .models.synthesizer == "claude-sonnet-5"' "$(bundle tangle)"

printf '%s\n' '{"routing":{"roles":{"implementer":{"provider":"claude","model":"claude-opus-5"}}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
assert_models "configured role provider and model reach the summary" \
    '.models.implementer == "claude-opus-5"' "$(bundle tangle)"

printf '%s\n' '{"routing":{"phases":{"tangle":{"provider":"codex","model":"gpt-5.6-terra"}}}}' > "$OCTOPUS_PROVIDERS_CONFIG"
assert_models "phase routing uses the requested workflow" \
    '.models.implementer == "gpt-5.6-terra" and .models.synthesizer == "gpt-5.6-terra"' "$(bundle tangle)"
assert_models "environment model pin wins over configuration" \
    '.models.implementer == "gpt-5.6-luna"' "$(OCTOPUS_CODEX_MODEL=gpt-5.6-luna bundle tangle)"
assert_models "unresolvable provider is reported as unknown" \
    '.models.implementer == "unknown"' "$(OCTOPUS_TANGLE_CODING_AGENT=unregistered-provider bundle tangle)"
assert_models "develop alias honors Tangle coding and reasoning overrides" \
    '.models.implementer == "claude-opus-5" and .models.researcher == "claude-sonnet-5"' \
    "$(OCTOPUS_TANGLE_CODING_AGENT=claude-opus OCTOPUS_TANGLE_REASONING_AGENT=claude-sonnet bundle develop)"
test_summary
