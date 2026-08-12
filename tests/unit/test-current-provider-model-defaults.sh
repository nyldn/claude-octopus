#!/usr/bin/env bash
# Regression coverage for issue #800: provider-owned defaults and explicit pins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Current provider model defaults (#800)"
export "TMPDIR=${TEST_TMP_DIR}/runtime"
export "USER=octo-issue800-$$"
export "CLAUDE_CODE_SESSION=issue800-$$"
mkdir -p "$TMPDIR"

log() { :; }
PLUGIN_DIR="$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/copilot.sh"

empty_home="$TEST_TMP_DIR/home"
mkdir -p "$empty_home"

test_case "Copilot delegates its unpinned model choice to CLI auto selection"
copilot_model="$(HOME="$empty_home" resolve_octopus_model copilot copilot "" "")"
if [[ "$copilot_model" == "auto" ]]; then
    test_pass
else
    test_fail "expected Copilot auto model selection, got: $copilot_model"
fi

test_case "Copilot dispatch forwards an explicit OCTOPUS_COPILOT_MODEL pin"
copilot_command="$(HOME="$empty_home" OCTOPUS_COPILOT_MODEL="gpt-5.4" get_agent_command copilot probe researcher)"
if [[ "$copilot_command" == *"OCTOPUS_COPILOT_MODEL=gpt-5.4"* ]] &&
   [[ "$copilot_command" == *"copilot-exec.sh"* ]]; then
    test_pass
else
    test_fail "Copilot model pin did not reach its shim: $copilot_command"
fi

test_case "Copilot shim passes its resolved model to the CLI"
fake_bin="$TEST_TMP_DIR/bin"
capture="$TEST_TMP_DIR/copilot-argv"
mkdir -p "$fake_bin"
cat > "$fake_bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$OCTOPUS_TEST_CAPTURE"
EOF
chmod +x "$fake_bin/copilot"
printf 'fixture prompt' | PATH="$fake_bin:/usr/bin:/bin" \
    OCTOPUS_TEST_CAPTURE="$capture" \
    OCTOPUS_COPILOT_MODEL="gpt-5.4" \
    "$PROJECT_ROOT/scripts/helpers/copilot-exec.sh"
if grep -Fxq -- '--model' "$capture" && grep -Fxq -- 'gpt-5.4' "$capture" &&
   grep -Fxq -- '-s' "$capture"; then
    test_pass
else
    test_fail "Copilot shim omitted the model argument: $(tr '\n' ' ' < "$capture")"
fi

test_case "Copilot shim can deny every model tool for untrusted review diffs"
printf 'fixture review prompt' | PATH="$fake_bin:/usr/bin:/bin" \
    OCTOPUS_TEST_CAPTURE="$capture" \
    OCTOPUS_COPILOT_MODEL="auto" \
    OCTOPUS_COPILOT_TOOL_POLICY="none" \
    "$PROJECT_ROOT/scripts/helpers/copilot-exec.sh"
if grep -Fxq -- '--deny-tool=shell,write,read,url,memory' "$capture" &&
   grep -Fxq -- '--available-tools=' "$capture" &&
   grep -Fxq -- '--no-ask-user' "$capture" &&
   grep -Fxq -- '--disable-builtin-mcps' "$capture"; then
    test_pass
else
    test_fail "Copilot no-tools review policy was not forwarded: $(tr '\n' ' ' < "$capture")"
fi

test_case "Copilot availability fails closed when required CLI flags are absent"
mkdir -p "$empty_home/.copilot"
printf '{}\n' > "$empty_home/.copilot/config.json"
cat > "$fake_bin/copilot" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' "${OCTOPUS_TEST_COPILOT_HELP:-}"
    exit 0
fi
exit 0
EOF
chmod +x "$fake_bin/copilot"
required_help='--prompt --model --silent --no-ask-user --disable-builtin-mcps'
if PATH="$fake_bin:/usr/bin:/bin" HOME="$empty_home" OCTOPUS_TEST_COPILOT_HELP='--prompt --no-ask-user' copilot_is_available; then
    test_fail "an outdated Copilot CLI missing --model was admitted"
elif PATH="$fake_bin:/usr/bin:/bin" HOME="$empty_home" \
    OCTOPUS_TEST_COPILOT_HELP='--prompt-file --model-file --silent-mode --no-ask-user-help --disable-builtin-mcps-config' \
    copilot_is_available; then
    test_fail "suffixed Copilot option names were mistaken for required exact flags"
elif PATH="$fake_bin:/usr/bin:/bin" HOME="$empty_home" OCTOPUS_TEST_COPILOT_HELP="$required_help" copilot_is_available; then
    test_pass
else
    test_fail "a Copilot CLI with every required capability was rejected"
fi

test_case "Ollama selects an already-installed local model instead of a stale pin"
ollama_model="$({
    curl() { printf '%s\n' '{"models":[{"name":"qwen3-coder:30b"},{"name":"local-second:latest"}]}'; }
    HOME="$empty_home" resolve_octopus_model ollama ollama installed ""
})"
if [[ "$ollama_model" == "qwen3-coder:30b" ]]; then
    test_pass
else
    test_fail "expected first installed Ollama model, got: $ollama_model"
fi

test_case "Ollama fails closed when no local model is installed"
if {
    curl() { printf '%s\n' '{"models":[]}'; }
    HOME="$empty_home" resolve_octopus_model ollama ollama empty ""
} >/dev/null 2>&1; then
    test_fail "Ollama guessed or pulled a model despite an empty local inventory"
else
    test_pass
fi

test_case "Ollama sed fallback selects the first model when jq and python3 are unavailable"
fallback_model="$({
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "jq" || "${2:-}" == "python3" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    curl() { printf '%s\n' '{"models":[{"name":"first-local:latest"},{"name":"second-local:latest"}]}'; }
    ollama_default_model
})"
if [[ "$fallback_model" == "first-local:latest" ]]; then
    test_pass
else
    test_fail "sed fallback did not select the first installed model: $fallback_model"
fi

test_case "OpenRouter DeepSeek uses the current V4 Pro route"
deepseek_model="$(HOME="$empty_home" resolve_octopus_model openrouter openrouter-deepseek "" "")"
deepseek_command="$(HOME="$empty_home" get_agent_command openrouter-deepseek probe researcher)"
if [[ "$deepseek_model" == "deepseek/deepseek-v4-pro" ]] && is_known_model "$deepseek_model" &&
   [[ "$deepseek_command" == *"deepseek/deepseek-v4-pro"* ]]; then
    test_pass
else
    test_fail "expected cataloged current DeepSeek V4 Pro, got model=$deepseek_model command=$deepseek_command"
fi

test_case "Copilot auto selector has provider metadata"
if [[ "$(get_model_capability auto provider)" == "copilot" ]]; then
    test_pass
else
    test_fail "Copilot auto selector is missing from the model catalog"
fi

test_case "Generic OpenAI-compatible routing requires an explicit model"
if HOME="$empty_home" env -u OPENAI_COMPAT_MODEL \
    bash -c 'source "$1/scripts/lib/utils.sh"; log(){ :; }; source "$1/scripts/lib/model-resolver.sh"; resolve_octopus_model openai-compatible-agent openai-compatible-agent "" ""' _ "$PROJECT_ROOT" \
    >/dev/null 2>&1; then
    test_fail "generic OpenAI-compatible routing silently guessed a model"
else
    test_pass
fi

test_summary
