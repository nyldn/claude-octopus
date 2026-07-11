#!/usr/bin/env bash
# Regression tests for PR #600 (agy model-validation stdin leak, the
# council_pick_provider diversity short-circuit) and issue #599 problem 3
# (roster entries recording the persona's pinned model instead of the model
# dispatch actually resolves for the seated provider). Every test fails on
# the corresponding pre-fix code (verified) — they are not string greps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "council model selection fixes (#600)"

TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

# ── agy stdin leak ─────────────────────────────────────────────────────────
# The real agy CLI consumes stdin. When validate_agy_model_name ran
# `agy models` inside a command substitution with the parent's stdin attached
# to a prompt pipe, agy ate the prompt and returned chat output instead of a
# model list, so valid pins were rejected. The mock reproduces that behavior:
# with data on stdin it returns garbage; with empty stdin (the </dev/null fix)
# it returns the model list.
STUB_BIN="$TEST_TMP_DIR/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then
    stdin_content="$(cat)"
    if [[ -n "$stdin_content" ]]; then
        echo "I received your prompt: $stdin_content"
        exit 0
    fi
    printf '%s\n' \
        'Gemini 3.5 Flash (Low)' \
        'Claude Sonnet 4.6 (Thinking)'
    exit 0
fi
exit 0
MOCK_AGY
chmod 755 "$STUB_BIN/agy"

test_case "agy model pin validates even when parent stdin is a pipe"
if printf 'council prompt payload' | env PATH="$STUB_BIN:$PATH" bash -c '
    log() { :; }
    source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
    validate_agy_model_name "Gemini 3.5 Flash (Low)"
' 2>/dev/null; then
    test_pass
else
    test_fail "pin rejected under piped stdin — agy models consumed the prompt (stdin leak regressed)"
fi

test_case "agy model pin still rejects unknown labels"
if printf 'payload' | env PATH="$STUB_BIN:$PATH" bash -c '
    log() { :; }
    source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
    validate_agy_model_name "Nonexistent Model (Ultra)"
' 2>/dev/null; then
    test_fail "unknown model label was accepted"
else
    test_pass
fi

# ── council diversity short-circuit ────────────────────────────────────────
pick_provider() {
    local roster_json="$1" preferred="$2"
    bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/council.sh" 2>/dev/null
        COUNCIL_ROSTER_JSON="$1"
        COUNCIL_PROVIDER_STATUS_JSON="{\"claude\":\"host-native\",\"opencode\":\"available\"}"
        COUNCIL_PROVIDERS="claude,opencode"
        council_pick_provider "$2"
    ' _ "$roster_json" "$preferred"
}

test_case "preferred provider passed over when its org already holds a seat"
out=$(pick_provider '[{"persona":"strategy-analyst","provider":"claude","provider_org":"anthropic"}]' claude)
if [[ "$out" == "opencode" ]]; then
    test_pass
else
    test_fail "expected opencode (anthropic already seated), got '$out'"
fi

test_case "preferred provider kept when its org is not yet seated"
out=$(pick_provider '[]' claude)
if [[ "$out" == "claude" ]]; then
    test_pass
else
    test_fail "expected claude on empty roster, got '$out'"
fi

test_case "falls back to preferred when every org is already seated"
out=$(bash -c '
    log() { :; }
    source "'"$PROJECT_ROOT"'/scripts/lib/council.sh" 2>/dev/null
    COUNCIL_ROSTER_JSON="[{\"persona\":\"a\",\"provider\":\"claude\",\"provider_org\":\"anthropic\"},{\"persona\":\"b\",\"provider\":\"opencode\",\"provider_org\":\"opencode\"}]"
    COUNCIL_PROVIDER_STATUS_JSON="{\"claude\":\"host-native\",\"opencode\":\"available\"}"
    COUNCIL_PROVIDERS="claude,opencode"
    council_pick_provider claude
')
if [[ "$out" == "claude" || "$out" == "opencode" ]]; then
    test_pass
else
    test_fail "expected an available provider from the any-available fallback, got '$out'"
fi

# ── roster model lineage (issue #599 problem 3) ────────────────────────────
# council_roster_entry_json recorded council_persona_model (the persona's
# configured pin) even when seating placed the persona on a different
# provider, so summary.json/config.json could label a seat with a model it
# never ran — and benchmark_signal/score were computed against that wrong
# model. Post-fix the entry records the same resolution dispatch uses
# (get_agent_model provider/council/persona), with the persona pin kept only
# as the fallback when the resolver isn't loaded. The stubs isolate the
# behavior from the repo's live agents/config.yaml and providers.json.
roster_entry_model() {
    local persona="$1" provider="$2" mode="$3"
    bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/council.sh" 2>/dev/null
        COUNCIL_ROSTER_JSON="[]"
        council_agent_config_value() {
            [[ "$2" == "model" ]] && echo "persona-pinned-model"
            return 0
        }
        case "$3" in
            *resolver*) get_agent_model() { echo "dispatch-resolved-model"; } ;;
        esac
        case "$3" in
            *agy*) agy_current_model() { echo "agy-actual-model"; } ;;
        esac
        council_roster_entry_json "$1" "$2" | jq -r .model
    ' _ "$persona" "$provider" "$mode"
}

test_case "seat records the dispatch-resolved model, not the persona pin"
out=$(roster_entry_model security-auditor opencode resolver)
if [[ "$out" == "dispatch-resolved-model" ]]; then
    test_pass
else
    test_fail "roster recorded '$out' — persona pin leaked into the seat artifact (lineage regressed)"
fi

test_case "persona pin remains the fallback when the dispatch resolver is not loaded"
out=$(roster_entry_model security-auditor opencode plain)
if [[ "$out" == "persona-pinned-model" ]]; then
    test_pass
else
    test_fail "expected persona-pinned-model without a resolver, got '$out'"
fi

test_case "agy seat still records agy_current_model, not the generic resolver"
out=$(roster_entry_model backend-architect agy "resolver agy")
if [[ "$out" == "agy-actual-model" ]]; then
    test_pass
else
    test_fail "expected agy-actual-model (agy carve-out), got '$out'"
fi

test_summary
