#!/usr/bin/env bash
# Tests for the OrcaRouter provider: registry capabilities, model resolution,
# model catalog entries, dispatch command, and API-key detection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OrcaRouter provider"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"

test_case "registry declares orcarouter with full provider capabilities"
if octo_provider_valid "orcarouter" &&
   octo_provider_has_capability "orcarouter" dispatch &&
   octo_provider_has_capability "orcarouter" health &&
   octo_provider_has_capability "orcarouter" detect &&
   octo_provider_has_capability "orcarouter" model-config &&
   octo_provider_has_capability "orcarouter" env; then
    test_pass
else
    test_fail "orcarouter registry capabilities incomplete"
fi

test_case "registry command and organization resolve for orcarouter"
if [[ "$(octo_provider_command "orcarouter")" == "orcarouter" ]] &&
   [[ "$(octo_provider_org "orcarouter")" == "orcarouter" ]]; then
    test_pass
else
    test_fail "orcarouter command/org metadata missing"
fi

MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
MODEL_CATALOG="$PROJECT_ROOT/scripts/lib/models.sh"

if bash -n "$MODEL_RESOLVER" "$MODEL_CATALOG"; then
    pass "orcarouter model scripts have valid bash syntax"
else
    fail "orcarouter model scripts have valid bash syntax" "syntax error"
fi

TEST_HOME="$TEST_TMP_DIR/orca-home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"
source "$MODEL_CATALOG"

test_case "bare orcarouter resolves to a namespaced OrcaRouter ID"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="orcarouter-default" resolve_octopus_model orcarouter orcarouter 2>/dev/null)" == "anthropic/claude-sonnet-4.6" ]]; then
    test_pass
else
    test_fail "expected anthropic/claude-sonnet-4.6"
fi

test_case "suffixed orcarouter agents keep a namespaced OrcaRouter ID"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="orcarouter-suffix" resolve_octopus_model orcarouter orcarouter-reviewer 2>/dev/null)" == "anthropic/claude-sonnet-4.6" ]]; then
    test_pass
else
    test_fail "suffixed OrcaRouter agent fell through to another provider default"
fi

test_case "model catalog includes the orcarouter fallback models"
if is_known_model "anthropic/claude-sonnet-4.6" &&
   is_known_model "anthropic/claude-opus-4.8" &&
   is_known_model "anthropic/claude-haiku-4.5" &&
   [[ "$(get_model_capability "anthropic/claude-sonnet-4.6" provider)" == "orcarouter" ]] &&
   [[ "$(get_model_capability "anthropic/claude-sonnet-4.6" context_k)" == "1000" ]] &&
   [[ "$(get_model_capability "anthropic/claude-opus-4.8" context_k)" == "1000" ]]; then
    test_pass
else
    test_fail "orcarouter models missing or mislabeled in catalog"
fi

# Dispatch: the command builder must emit the shell-function executor for the
# orcarouter agent type, the same shape openrouter uses.
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
test_case "get_agent_command emits orcarouter_execute"
cmd="$(get_agent_command orcarouter tangle implementer 2>/dev/null)" || cmd=""
if [[ "$cmd" == "orcarouter_execute" ]]; then
    test_pass
else
    test_fail "expected 'orcarouter_execute', got: '$cmd'"
fi


source "$PROJECT_ROOT/scripts/lib/perplexity.sh"
ORCAROUTER_CAPTURED_MODEL=""
orcarouter_execute_model() {
    ORCAROUTER_CAPTURED_MODEL="$1"
}
test_case "orcarouter execution enforces its model allowlist"
OCTOPUS_ORCAROUTER_MODEL="anthropic/claude-sonnet-4.6"
OCTOPUS_ORCAROUTER_ALLOWED_MODELS="anthropic/claude-haiku-4.5"
if orcarouter_execute "review this" review 2 >/dev/null 2>&1 &&
        [[ "$ORCAROUTER_CAPTURED_MODEL" == "anthropic/claude-haiku-4.5" ]]; then
    test_pass
else
    test_fail "blocked model reached execution: ${ORCAROUTER_CAPTURED_MODEL:-none}"
fi
unset OCTOPUS_ORCAROUTER_MODEL OCTOPUS_ORCAROUTER_ALLOWED_MODELS
source "$PROJECT_ROOT/scripts/lib/perplexity.sh"

test_case "orcarouter retry increment is safe under errexit"
if grep -Ec -- '\(\([[:space:]]*\+\+attempt[[:space:]]*\)\)' \
        "$PROJECT_ROOT/scripts/lib/perplexity.sh" >/dev/null &&
        ! grep -Eq -- '\(\([[:space:]]*attempt\+\+[[:space:]]*\)\)' \
            "$PROJECT_ROOT/scripts/lib/perplexity.sh"; then
    test_pass
else
    test_fail "OrcaRouter retry still uses a zero-valued post-increment"
fi

test_case "orcarouter execution fails when a successful response has no message content"
curl() {
    printf '%s' '{"choices":[{"message":{"content":""}}]}200'
}
ORCAROUTER_API_KEY="sk-orca-empty-response-test"
VERBOSE="false"
set +e
empty_response_output=$(orcarouter_execute_model \
    "anthropic/claude-sonnet-4.6" "review this" review 2 2>/dev/null)
empty_response_rc=$?
set -e
unset -f curl
unset ORCAROUTER_API_KEY
if [[ "$empty_response_rc" -ne 0 && "$empty_response_output" == *'"choices"'* ]]; then
    test_pass
else
    test_fail "empty OrcaRouter content returned status=$empty_response_rc"
fi

test_case "orcarouter execution removes its header file when interrupted"
interrupt_tmp="$TEST_TMP_DIR/orcarouter-interrupt"
mkdir -p "$interrupt_tmp"
TMPDIR="$interrupt_tmp" ORCAROUTER_API_KEY="sk-orca-interrupt-test" \
    bash -c '
        log() { :; }
        json_escape() { printf "%s" "$1"; }
        curl() {
            local header_file=""
            printf "%s\n" "$BASHPID" > "$TMPDIR/request.pid"
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == "-D" ]]; then
                    header_file="$2"
                    shift 2
                else
                    shift
                fi
            done
            printf "Retry-After: 2\r\n" > "$header_file"
            printf "%s" "{}429"
        }
        VERBOSE=false
        source "$1/scripts/lib/perplexity.sh"
        orcarouter_execute_model "anthropic/claude-sonnet-4.6" "review this" review 2
    ' _ "$PROJECT_ROOT" > "$interrupt_tmp/output" 2>&1 &
interrupt_pid=$!
header_created="false"
for _attempt in {1..100}; do
    if [[ -s "$interrupt_tmp/request.pid" ]] &&
            find "$interrupt_tmp" -maxdepth 1 -name 'octo-orca-headers.*' -print -quit | grep -q .; then
        header_created="true"
        break
    fi
    sleep 0.02
done
request_pid=""
[[ -s "$interrupt_tmp/request.pid" ]] && request_pid="$(<"$interrupt_tmp/request.pid")"
[[ -n "$request_pid" ]] && kill -TERM "$request_pid" 2>/dev/null || true
set +e
wait "$interrupt_pid" 2>/dev/null
interrupt_rc=$?
set -e
if [[ "$header_created" == "true" && "$interrupt_rc" -ne 0 ]] &&
        ! find "$interrupt_tmp" -maxdepth 1 -name 'octo-orca-headers.*' -print -quit | grep -q .; then
    test_pass
else
    test_fail "interrupted OrcaRouter call left a response-header file"
fi

# Detection: an ORCAROUTER_API_KEY alone must surface orcarouter in the
# provider inventory, mirroring the openrouter api-key detection.
test_case "detect_providers surfaces orcarouter with an API key"
stub_dir=$(mktemp -d "$TEST_TMP_DIR/orcarouter-detect.XXXXXX")
set +e
detected=$(env "HOME=$stub_dir" "PATH=$PATH" "ORCAROUTER_API_KEY=sk-orca-test" \
    "OCTO_ALLOWED_PROVIDERS=orcarouter" bash -c \
    'log(){ :; }; source "$1/scripts/lib/providers.sh"; detect_providers' \
    _ "$PROJECT_ROOT")
detected_rc=$?
set -e
rm -rf "$stub_dir"
if [[ "$detected_rc" -eq 0 && "$detected" == *"orcarouter:api-key"* ]]; then
    test_pass
else
    test_fail "orcarouter detection failed (status=$detected_rc): $detected"
fi

test_case "detect_providers resolves a profile-backed OrcaRouter key"
profile_home="$TEST_TMP_DIR/profile-backed-home"
mkdir -p "$profile_home"
printf '%s\n' 'ORCAROUTER_API_KEY=sk-orca-profile-test' > "$profile_home/.env"
set +e
profile_detected=$(env -u ORCAROUTER_API_KEY "HOME=$profile_home" "PATH=$PATH" \
    "OCTO_ALLOWED_PROVIDERS=orcarouter" bash -c \
    'log(){ :; }; source "$1/scripts/lib/providers.sh"; detect_providers' \
    _ "$PROJECT_ROOT")
profile_detected_rc=$?
set -e
if [[ "$profile_detected_rc" -eq 0 && "$profile_detected" == *"orcarouter:api-key"* ]]; then
    test_pass
else
    test_fail "profile-backed OrcaRouter key was not resolved"
fi

test_case "detect_providers resolves a legacy zshrc-backed OrcaRouter key"
zshrc_home="$TEST_TMP_DIR/zshrc-backed-home"
mkdir -p "$zshrc_home"
printf '%s\n' 'export ORCAROUTER_API_KEY=sk-orca-zshrc-test' > "$zshrc_home/.zshrc"
set +e
zshrc_detected=$(env -u ORCAROUTER_API_KEY "HOME=$zshrc_home" "PATH=$PATH" \
    "OCTO_ALLOWED_PROVIDERS=orcarouter" bash -c \
    'log(){ :; }; source "$1/scripts/lib/providers.sh"; detect_providers' \
    _ "$PROJECT_ROOT")
zshrc_detected_rc=$?
set -e
if [[ "$zshrc_detected_rc" -eq 0 && "$zshrc_detected" == *"orcarouter:api-key"* ]]; then
    test_pass
else
    test_fail "legacy zshrc-backed OrcaRouter key was not resolved"
fi

test_case "provider status resolves a legacy zshrc-backed OrcaRouter key"
set +e
zshrc_status=$(env -u ORCAROUTER_API_KEY "HOME=$zshrc_home" "PATH=$PATH" \
    "OCTO_ALLOWED_PROVIDERS=orcarouter" \
    bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh")
zshrc_status_rc=$?
set -e
if [[ "$zshrc_status_rc" -eq 0 && "$zshrc_status" == *"orcarouter:available"* ]]; then
    test_pass
else
    test_fail "provider status did not resolve the legacy OrcaRouter key"
fi

test_case "provider status does not advertise disabled OrcaRouter configuration"
disabled_workspace="$TEST_TMP_DIR/orcarouter-disabled"
mkdir -p "$disabled_workspace"
printf '%s\n' \
    'providers:' \
    '  orcarouter:' \
    '    enabled: false' \
    '    api_key_set: true' \
    > "$disabled_workspace/.providers-config"
set +e
disabled_status=$(env "HOME=$TEST_TMP_DIR" "PATH=$PATH" \
    "WORKSPACE_DIR=$disabled_workspace" \
    "ORCAROUTER_API_KEY=sk-orca-disabled-test" \
    "OCTO_ALLOWED_PROVIDERS=orcarouter" \
    bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh")
disabled_status_rc=$?
set -e
if [[ "$disabled_status_rc" -eq 0 && "$disabled_status" == *"orcarouter:missing"* ]]; then
    test_pass
else
    test_fail "disabled OrcaRouter configuration was advertised as available"
fi

test_case "OrcaRouter availability requires api_key_set in explicit configuration"
old_providers_config_file="${PROVIDERS_CONFIG_FILE:-}"
printf '%s\n' \
    'providers:' \
    '  orcarouter:' \
    '    enabled: true' \
    '    api_key_set: false' \
    > "$disabled_workspace/.providers-config"
PROVIDERS_CONFIG_FILE="$disabled_workspace/.providers-config"
ORCAROUTER_API_KEY="sk-orca-unconfigured-test"
if octo_api_key_provider_is_available "orcarouter" "ORCAROUTER_API_KEY"; then
    test_fail "api_key_set=false was ignored"
else
    test_pass
fi
unset ORCAROUTER_API_KEY

source "$PROJECT_ROOT/scripts/lib/council.sh"
test_case "Council does not seat disabled OrcaRouter configuration"
printf '%s\n' \
    'providers:' \
    '  orcarouter:' \
    '    enabled: false' \
    '    api_key_set: true' \
    > "$disabled_workspace/.providers-config"
COUNCIL_PROVIDERS="orcarouter"
ORCAROUTER_API_KEY="sk-orca-disabled-test"
council_detect_providers
if [[ "$(jq -r '.orcarouter' <<< "$COUNCIL_PROVIDER_STATUS_JSON")" == "missing" ]]; then
    test_pass
else
    test_fail "Council seated OrcaRouter despite enabled=false"
fi
PROVIDERS_CONFIG_FILE="$old_providers_config_file"
unset ORCAROUTER_API_KEY

test_case "OrcaRouter setup keeps the API key out of terminal output"
config_display="$PROJECT_ROOT/scripts/lib/config-display.sh"
if grep -Eq -- 'read -r -s -p .*OrcaRouter API key' "$config_display" &&
        grep -Ec -- 'export "ORCAROUTER_API_KEY=[$][{]orcarouter_key[}]"' \
            "$config_display" >/dev/null &&
        grep -Eq -- 'persist_provider_secret .*ORCAROUTER_API_KEY' "$config_display" &&
        ! grep -Eq -- 'keys_to_add=.*ORCAROUTER_API_KEY' "$config_display"; then
    test_pass
else
    test_fail "OrcaRouter setup still exposes or prints the raw API key"
fi

source "$config_display"
test_case "OrcaRouter secret persistence is private, atomic, and silent"
secret_env="$TEST_TMP_DIR/provider-secrets.env"
secret_output="$TEST_TMP_DIR/provider-secrets.out"
printf '%s\n' \
    'KEEP_ME=yes' \
    'export ORCAROUTER_API_KEY=older-exported-value' \
    'ORCAROUTER_API_KEY=old-value' \
    > "$secret_env"
chmod 644 "$secret_env"
umask_before=$(umask)
set +e
OCTOPUS_SECRET_ENV_FILE="$secret_env" \
    persist_provider_secret "ORCAROUTER_API_KEY" "sk-orca-replacement" \
    > "$secret_output" 2>&1
persist_rc=$?
set -e
umask_after=$(umask)
umask "$umask_before"
if stat -f '%Lp' "$secret_env" >/dev/null 2>&1; then
    secret_mode=$(stat -f '%Lp' "$secret_env")
else
    secret_mode=$(stat -c '%a' "$secret_env")
fi
secret_count=$(grep -Ec -- '^[[:space:]]*(export[[:space:]]+)?ORCAROUTER_API_KEY=' "$secret_env")
if [[ "$persist_rc" -eq 0 && ! -s "$secret_output" && \
        "$umask_before" == "$umask_after" && "$secret_mode" == "600" && \
        "$secret_count" -eq 1 ]] && \
        grep -Fxq -- 'KEEP_ME=yes' "$secret_env" && \
        grep -Fxq -- 'ORCAROUTER_API_KEY=sk-orca-replacement' "$secret_env"; then
    test_pass
else
    test_fail "secret persistence changed umask, permissions, content, or terminal output"
fi

test_case "OrcaRouter smoke selection and status require an API key"
smoke_file="$PROJECT_ROOT/scripts/lib/smoke.sh"
smoke_guard_count=$(grep -Ec -- 'PROVIDER_ORCAROUTER_ENABLED.*true.*PROVIDER_ORCAROUTER_API_KEY_SET.*true' "$smoke_file")
if [[ "$smoke_guard_count" -ge 3 ]]; then
    test_pass
else
    test_fail "only $smoke_guard_count OrcaRouter smoke paths require both flags"
fi

test_case "Council uses the shared OrcaRouter availability gate"
if grep -A8 -E '^[[:space:]]*orcarouter\)' "$PROJECT_ROOT/scripts/lib/council.sh" |
        grep -Ec -- 'octo_api_key_provider_is_available "orcarouter" "ORCAROUTER_API_KEY"' >/dev/null; then
    test_pass
else
    test_fail "Council bypasses the shared enabled-plus-key gate"
fi

test_summary
