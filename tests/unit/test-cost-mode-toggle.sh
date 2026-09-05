#!/usr/bin/env bash
# Regression coverage for persistent cost-mode selection and quick toggle commands.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Cost mode quick toggles"

# Host configuration must not override the isolated providers.json fixture.
unset OCTOPUS_COST_MODE

MODEL_CONFIG="$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"
MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
PLUGIN_MANIFEST="$PROJECT_ROOT/.claude-plugin/plugin.json"
TEST_HOME="$TEST_TMP_DIR/home"
CONFIG_FILE="$TEST_HOME/.claude-octopus/config/providers.json"
mkdir -p "$TEST_HOME"

run_model_config() {
    env "HOME=${TEST_HOME}" "USER=octo-cost-mode-test" \
        "CLAUDE_CODE_SESSION=cost-mode-test" "$MODEL_CONFIG" "$@"
}

run_model_config_with_path() {
    local command_path="$1"
    shift
    env "HOME=${TEST_HOME}" "USER=octo-cost-mode-test" \
        "CLAUDE_CODE_SESSION=cost-mode-test" \
        "PATH=${command_path}" "OCTOPUS_TEST_REAL_JQ=$(command -v jq)" \
        "$MODEL_CONFIG" "$@"
}

resolve_codex_model() {
    local env_mode="${1:-}"
    env "HOME=${TEST_HOME}" "USER=octo-cost-mode-test" \
        "CLAUDE_CODE_SESSION=cost-mode-test-${RANDOM}" \
        "OCTOPUS_COST_MODE=${env_mode}" bash -c '
            if [[ -z "$OCTOPUS_COST_MODE" ]]; then
                unset OCTOPUS_COST_MODE
            fi
            log() { :; }
            source "$1"
            resolve_octopus_model codex codex
        ' _ "$MODEL_RESOLVER"
}

test_case "three quick commands are registered for Claude and generated for Cursor"
missing=""
for mode in budget standard premium; do
    command_file="$PROJECT_ROOT/commands/${mode}-mode.md"
    cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo-${mode}-mode.md"
    [[ -f "$command_file" ]] || missing+="missing $command_file"$'\n'
    [[ -f "$cursor_file" ]] || missing+="missing $cursor_file"$'\n'
    jq -e --arg path "./commands/${mode}-mode.md" '.commands | index($path) != null' \
        "$PLUGIN_MANIFEST" >/dev/null 2>&1 || missing+="manifest omits ${mode}-mode"$'\n'
    if [[ -f "$command_file" ]] && {
       ! grep -q "octo-model-config.sh" "$command_file" ||
       ! grep -q "\"\$helper\" cost-mode ${mode}" "$command_file";
    }; then
        missing+="${mode}-mode does not invoke the shared helper for ${mode}"$'\n'
    fi
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "$missing"
fi

test_case "quick commands cannot mask a failed mode write with status output"
masked_commands=""
for mode in budget standard premium; do
    command_file="$PROJECT_ROOT/commands/${mode}-mode.md"
    if ! grep -Eq "cost-mode ${mode}[[:space:]]*&&" "$command_file"; then
        masked_commands+="${mode}-mode does not fail before status when persistence fails"$'\n'
    fi
done
if [[ -z "$masked_commands" ]]; then
    test_pass
else
    test_fail "$masked_commands"
fi

test_case "cost-mode persists budget selection in providers.json"
if run_model_config cost-mode budget >/dev/null &&
   [[ "$(jq -r '.cost_mode' "$CONFIG_FILE")" == "budget" ]]; then
    test_pass
else
    test_fail "cost-mode budget did not persist .cost_mode=budget"
fi

test_case "cost-mode status reports the persisted source"
status_output="$(run_model_config cost-mode status 2>&1 || true)"
if [[ "$status_output" == *"budget"* && "$status_output" == *"providers.json"* ]]; then
    test_pass
else
    test_fail "status did not report persisted budget mode and source: $status_output"
fi

test_case "invalid cost mode fails without changing the saved selection"
before="$(jq -r '.cost_mode // "missing"' "$CONFIG_FILE" 2>/dev/null || printf 'missing\n')"
if run_model_config cost-mode unlimited >/dev/null 2>&1; then
    test_fail "invalid mode unexpectedly succeeded"
elif [[ "$(jq -r '.cost_mode // "missing"' "$CONFIG_FILE" 2>/dev/null || printf 'missing\n')" != "$before" ]]; then
    test_fail "invalid mode changed the persisted selection"
else
    test_pass
fi

test_case "tier command configures a provider target for a named mode"
if run_model_config tier budget codex gpt-5.6-luna >/dev/null &&
   [[ "$(jq -r '.tiers.budget.codex' "$CONFIG_FILE")" == "gpt-5.6-luna" ]]; then
    test_pass
else
    test_fail "tier budget codex did not persist the configured model"
fi

test_case "resolver uses the persisted budget mode when no env override exists"
if [[ "$(resolve_codex_model)" == "gpt-5.6-luna" ]]; then
    test_pass
else
    test_fail "resolver ignored persisted budget mode"
fi

test_case "standard mode applies the configurable standard tier"
if run_model_config tier standard codex gpt-5.6-terra >/dev/null &&
   run_model_config cost-mode standard >/dev/null &&
   [[ "$(resolve_codex_model)" == "gpt-5.6-terra" ]]; then
    test_pass
else
    test_fail "standard mode bypassed the configured standard tier"
fi

test_case "environment mode remains higher priority than persisted mode"
if run_model_config tier premium codex gpt-5.5 >/dev/null &&
   run_model_config cost-mode budget >/dev/null &&
   [[ "$(resolve_codex_model premium)" == "gpt-5.5" ]]; then
    test_pass
else
    test_fail "OCTOPUS_COST_MODE did not override the persisted mode"
fi

test_case "changing cost mode in one process cannot reuse a stale model cache entry"
cache_results="$(
    env "HOME=${TEST_HOME}" "USER=octo-cost-mode-test" \
        "CLAUDE_CODE_SESSION=cost-mode-cache-test" bash -c '
            log() { :; }
            source "$1"
            OCTOPUS_COST_MODE=budget
            budget_model="$(resolve_octopus_model codex codex)"
            OCTOPUS_COST_MODE=premium
            premium_model="$(resolve_octopus_model codex codex)"
            printf "%s|%s\n" "$budget_model" "$premium_model"
        ' _ "$MODEL_RESOLVER"
)"
if [[ "$cache_results" == "gpt-5.6-luna|gpt-5.5" ]]; then
    test_pass
else
    test_fail "cost-mode cache key reused the wrong model: $cache_results"
fi

test_case "resetting a provider removes stale mappings from every cost tier"
if run_model_config reset codex >/dev/null; then
    stale_tiers="$(jq -r '[.tiers | to_entries[] | select(.value.codex != null) | .key] | join(",")' "$CONFIG_FILE")"
    reset_failures=""
    for mode in budget standard premium; do
        resolved="$(resolve_codex_model "$mode")"
        case "$resolved" in
            gpt-5.6-luna|gpt-5.6-terra|gpt-5.5)
                reset_failures+="${mode} resolved stale model ${resolved}"$'\n'
                ;;
            "")
                reset_failures+="${mode} did not fall through to a default model"$'\n'
                ;;
        esac
    done
    if [[ -z "$stale_tiers" && -z "$reset_failures" ]]; then
        test_pass
    else
        test_fail "stale tiers=${stale_tiers:-none}${reset_failures:+; ${reset_failures}}"
    fi
else
    test_fail "reset codex failed"
fi

test_case "provider reset propagates a failed configuration rewrite"
fake_bin="$TEST_TMP_DIR/failing-jq-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/jq" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--arg" && "${2:-}" == "p" ]]; then
    exit 42
fi
exec "$OCTOPUS_TEST_REAL_JQ" "$@"
EOF
chmod +x "$fake_bin/jq"
set +e
reset_output="$(run_model_config_with_path "$fake_bin:$PATH" reset codex 2>&1)"
reset_rc=$?
set -e
if (( reset_rc == 0 )); then
    test_fail "reset reported success after jq failed"
elif [[ "$reset_output" == *"Failed to rewrite configuration while resetting provider: codex"* ]]; then
    test_pass
else
    test_fail "reset failed outside the intended rewrite path: $reset_output"
fi

test_case "model configuration helper remains valid Bash"
if bash -n "$MODEL_CONFIG" "$MODEL_RESOLVER"; then
    test_pass
else
    test_fail "cost-mode implementation contains a Bash syntax error"
fi

test_summary
