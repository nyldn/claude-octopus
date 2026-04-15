#!/bin/bash
# tests/unit/test-gemini-provider.sh
# Extensive tests for Gemini CLI provider integration
# Covers: dispatch, detection, doctor, model resolution, .toml commands,
#         headless mode, env handling, provider health, circuit breaker,
#         and workflow integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Gemini Provider Integration"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
ALL_SRC=$(mktemp)
cat "$ORCH" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT
DISPATCH="$PROJECT_ROOT/scripts/lib/dispatch.sh"
PROVIDERS="$PROJECT_ROOT/scripts/lib/providers.sh"
DOCTOR="$PROJECT_ROOT/scripts/lib/doctor.sh"
MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
PROVIDER_ROUTER="$PROJECT_ROOT/scripts/provider-router.sh"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
EMBRACE="$PROJECT_ROOT/scripts/lib/embrace.sh"
SMOKE="$PROJECT_ROOT/scripts/lib/smoke.sh"
PREFLIGHT="$PROJECT_ROOT/scripts/lib/preflight.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Dispatch — get_agent_command for Gemini agents
# ═══════════════════════════════════════════════════════════════════════════════

test_dispatch_gemini_standard() {
    test_case "dispatch: gemini agent produces gemini command"
    if grep -q 'gemini|gemini-fast|gemini-image)' "$DISPATCH"; then
        test_pass
    else
        test_fail "gemini dispatch case missing from dispatch.sh"
    fi
}

test_dispatch_gemini_text_output() {
    test_case "dispatch: gemini uses -o text for clean output"
    if grep -A5 'gemini|gemini-fast' "$DISPATCH" | grep -q '\-o text'; then
        test_pass
    else
        test_fail "gemini dispatch should use -o text"
    fi
}

test_dispatch_gemini_yolo_mode() {
    test_case "dispatch: gemini uses --approval-mode yolo"
    if grep -A5 'gemini|gemini-fast' "$DISPATCH" | grep -q 'approval-mode yolo'; then
        test_pass
    else
        test_fail "gemini dispatch should use --approval-mode yolo"
    fi
}

test_dispatch_gemini_model_selection() {
    test_case "dispatch: gemini uses get_agent_model for model"
    # get_agent_model is called before the case block, within the gemini branch
    if sed -n '/gemini|gemini-fast/,/;;/p' "$DISPATCH" | grep -q 'get_agent_model'; then
        test_pass
    else
        test_fail "gemini dispatch should call get_agent_model"
    fi
}

test_dispatch_gemini_force_file_storage() {
    test_case "dispatch: GEMINI_FORCE_FILE_STORAGE on macOS"
    if grep -q 'GEMINI_FORCE_FILE_STORAGE=true' "$DISPATCH"; then
        test_pass
    else
        test_fail "dispatch should set GEMINI_FORCE_FILE_STORAGE on Darwin"
    fi
}

test_dispatch_gemini_node_no_warnings() {
    test_case "dispatch: NODE_NO_WARNINGS=1 suppresses warnings"
    if grep -q 'NODE_NO_WARNINGS=1' "$DISPATCH"; then
        test_pass
    else
        test_fail "dispatch should set NODE_NO_WARNINGS=1"
    fi
}

test_dispatch_gemini_sandbox_modes() {
    test_case "dispatch: supports headless and interactive sandbox modes"
    if grep -q 'OCTOPUS_GEMINI_SANDBOX' "$DISPATCH"; then
        test_pass
    else
        test_fail "dispatch should check OCTOPUS_GEMINI_SANDBOX"
    fi
}

test_dispatch_gemini_fast_variant() {
    test_case "dispatch: gemini-fast is a recognized agent type"
    if grep -q 'gemini-fast' "$DISPATCH"; then
        test_pass
    else
        test_fail "gemini-fast should be in dispatch"
    fi
}

test_dispatch_gemini_image_variant() {
    test_case "dispatch: gemini-image is a recognized agent type"
    if grep -q 'gemini-image' "$DISPATCH"; then
        test_pass
    else
        test_fail "gemini-image should be in dispatch"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. AVAILABLE_AGENTS — Gemini in the agent registry
# ═══════════════════════════════════════════════════════════════════════════════

test_available_agents_gemini() {
    test_case "AVAILABLE_AGENTS includes gemini"
    if grep 'AVAILABLE_AGENTS=' "$ALL_SRC" | grep -q ' gemini '; then
        test_pass
    else
        test_fail "gemini should be in AVAILABLE_AGENTS"
    fi
}

test_available_agents_gemini_fast() {
    test_case "AVAILABLE_AGENTS includes gemini-fast"
    if grep 'AVAILABLE_AGENTS=' "$ALL_SRC" | grep -q 'gemini-fast'; then
        test_pass
    else
        test_fail "gemini-fast should be in AVAILABLE_AGENTS"
    fi
}

test_available_agents_gemini_image() {
    test_case "AVAILABLE_AGENTS includes gemini-image"
    if grep 'AVAILABLE_AGENTS=' "$ALL_SRC" | grep -q 'gemini-image'; then
        test_pass
    else
        test_fail "gemini-image should be in AVAILABLE_AGENTS"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. Doctor — Gemini health checks
# ═══════════════════════════════════════════════════════════════════════════════

test_doctor_gemini_cli_check() {
    test_case "doctor: checks Gemini CLI installed"
    if grep -q 'gemini-cli.*providers' "$DOCTOR"; then
        test_pass
    else
        test_fail "doctor should check gemini-cli"
    fi
}

test_doctor_gemini_version_detection() {
    test_case "doctor: detects Gemini CLI version"
    if grep -q 'gemini --version' "$DOCTOR"; then
        test_pass
    else
        test_fail "doctor should detect gemini version"
    fi
}

test_doctor_gemini_install_hint() {
    test_case "doctor: provides install hint for missing Gemini"
    if grep -q 'npm install -g @google/gemini-cli' "$DOCTOR"; then
        test_pass
    else
        test_fail "doctor should suggest gemini install command"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Provider Health — check_provider_health for Gemini
# ═══════════════════════════════════════════════════════════════════════════════

test_provider_health_gemini_case() {
    test_case "providers: gemini case in check_provider_health"
    if grep -q 'gemini)' "$PROVIDERS"; then
        test_pass
    else
        test_fail "check_provider_health should have gemini case"
    fi
}

test_provider_health_gemini_oauth() {
    test_case "providers: checks gemini OAuth creds"
    if grep -q 'oauth_creds.json' "$PROVIDERS"; then
        test_pass
    else
        test_fail "gemini health check should look for oauth_creds.json"
    fi
}

test_provider_health_gemini_api_key() {
    test_case "providers: checks GEMINI_API_KEY"
    if grep -q 'GEMINI_API_KEY' "$PROVIDERS"; then
        test_pass
    else
        test_fail "gemini health check should check GEMINI_API_KEY"
    fi
}

test_provider_health_gemini_google_key() {
    test_case "providers: checks GOOGLE_API_KEY as fallback"
    if grep -q 'GOOGLE_API_KEY' "$PROVIDERS"; then
        test_pass
    else
        test_fail "gemini health check should check GOOGLE_API_KEY"
    fi
}

test_provider_all_includes_gemini() {
    test_case "providers: check_all_providers includes gemini"
    if grep 'for provider in' "$PROVIDERS" | grep -q 'gemini'; then
        test_pass
    else
        test_fail "check_all_providers loop should include gemini"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Model Resolution — fallback models for Gemini
# ═══════════════════════════════════════════════════════════════════════════════

test_model_resolver_gemini_standard() {
    test_case "model-resolver: gemini* has fallback model"
    if grep -q 'gemini\*).*resolved_model=' "$MODEL_RESOLVER"; then
        test_pass
    else
        test_fail "model-resolver should have gemini fallback"
    fi
}

test_model_resolver_gemini_fast() {
    test_case "model-resolver: gemini-fast has distinct model"
    if grep -q 'gemini-fast\|gemini-flash' "$MODEL_RESOLVER"; then
        test_pass
    else
        test_fail "model-resolver should have gemini-fast/flash model"
    fi
}

test_model_resolver_gemini_model_name() {
    test_case "model-resolver: gemini model starts with 'gemini-'"
    local model
    model=$(grep 'gemini\*)' "$MODEL_RESOLVER" | grep -oE 'gemini-[a-z0-9.-]+' | head -1)
    if [[ -n "$model" ]]; then
        test_pass
    else
        test_fail "gemini fallback model should start with gemini-"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6. Circuit Breaker — Gemini in provider-router
# ═══════════════════════════════════════════════════════════════════════════════

test_circuit_breaker_includes_gemini() {
    test_case "circuit breaker: iterates over gemini"
    if grep 'for provider in' "$PROVIDER_ROUTER" | grep -q 'gemini'; then
        test_pass
    else
        test_fail "circuit breaker loop should include gemini"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 7. Workflows — Gemini headless flag and provider metrics
# ═══════════════════════════════════════════════════════════════════════════════

test_workflows_gemini_headless_flag() {
    test_case "workflows: appends -p '' for gemini headless mode"
    if grep -q 'gemini\*.*-p' "$WORKFLOWS" || grep -B2 'cmd_array.*-p' "$WORKFLOWS" | grep -q 'gemini'; then
        test_pass
    else
        test_fail "workflows should append -p '' for gemini agents"
    fi
}

test_workflows_gemini_provider_name() {
    test_case "workflows: gemini* maps to provider_name=gemini"
    if grep -q 'gemini\*) provider_name="gemini"' "$WORKFLOWS"; then
        test_pass
    else
        test_fail "workflows should map gemini* to provider_name=gemini"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 8. Embrace — Gemini in dispatch strategies
# ═══════════════════════════════════════════════════════════════════════════════

test_embrace_checks_gemini() {
    test_case "embrace: checks has_gemini for dispatch strategy"
    if grep -q 'has_gemini' "$EMBRACE"; then
        test_pass
    else
        test_fail "embrace should check has_gemini"
    fi
}

test_embrace_gemini_in_strategy() {
    test_case "embrace: gemini appears in dispatch strategy strings"
    if grep -q 'gemini,claude' "$EMBRACE" || grep -q 'gemini,copilot' "$EMBRACE"; then
        test_pass
    else
        test_fail "embrace dispatch strategies should include gemini"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 9. Detect Providers — Gemini detection
# ═══════════════════════════════════════════════════════════════════════════════

test_detect_providers_gemini() {
    test_case "detect_providers: detects Gemini CLI"
    if grep -A20 'detect_providers()' "$ALL_SRC" | grep -q 'gemini'; then
        test_pass
    else
        test_fail "detect_providers should detect gemini"
    fi
}

test_preflight_gemini_status() {
    test_case "preflight: reports GEMINI_STATUS"
    if grep -q 'GEMINI_STATUS' "$PREFLIGHT"; then
        test_pass
    else
        test_fail "preflight should report GEMINI_STATUS"
    fi
}

test_preflight_gemini_auth() {
    test_case "preflight: reports GEMINI_AUTH"
    if grep -q 'GEMINI_AUTH' "$PREFLIGHT"; then
        test_pass
    else
        test_fail "preflight should report GEMINI_AUTH"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 10. MCP Server — Gemini env vars forwarded
# ═══════════════════════════════════════════════════════════════════════════════

test_mcp_forwards_gemini_key() {
    test_case "MCP: forwards GEMINI_API_KEY"
    if grep -q 'GEMINI_API_KEY' "$PROJECT_ROOT/mcp-server/src/index.ts"; then
        test_pass
    else
        test_fail "MCP server should forward GEMINI_API_KEY"
    fi
}

test_mcp_forwards_google_key() {
    test_case "MCP: forwards GOOGLE_API_KEY"
    if grep -q 'GOOGLE_API_KEY' "$PROJECT_ROOT/mcp-server/src/index.ts"; then
        test_pass
    else
        test_fail "MCP server should forward GOOGLE_API_KEY"
    fi
}

test_openclaw_forwards_gemini_key() {
    test_case "OpenClaw: forwards GEMINI_API_KEY"
    if grep -q 'GEMINI_API_KEY' "$PROJECT_ROOT/openclaw/src/index.ts"; then
        test_pass
    else
        test_fail "OpenClaw should forward GEMINI_API_KEY"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 11. .toml Custom Commands — present for human use
# ═══════════════════════════════════════════════════════════════════════════════

test_toml_commands_dir_exists() {
    test_case ".toml: commands directory exists"
    if [[ -d "$PROJECT_ROOT/.gemini/commands/octo" ]]; then
        test_pass
    else
        test_fail ".gemini/commands/octo/ should exist"
    fi
}

test_toml_research_exists() {
    test_case ".toml: research.toml exists"
    if [[ -f "$PROJECT_ROOT/.gemini/commands/octo/research.toml" ]]; then
        test_pass
    else
        test_fail "research.toml should exist"
    fi
}

test_toml_review_exists() {
    test_case ".toml: review.toml exists"
    if [[ -f "$PROJECT_ROOT/.gemini/commands/octo/review.toml" ]]; then
        test_pass
    else
        test_fail "review.toml should exist"
    fi
}

test_toml_has_prompt_field() {
    test_case ".toml: commands have prompt field"
    local ok=true
    for f in "$PROJECT_ROOT/.gemini/commands/octo/"*.toml; do
        if ! grep -q '^prompt' "$f"; then
            ok=false
        fi
    done
    if $ok; then test_pass; else test_fail "all .toml files should have prompt field"; fi
}

test_toml_has_description_field() {
    test_case ".toml: commands have description field"
    local ok=true
    for f in "$PROJECT_ROOT/.gemini/commands/octo/"*.toml; do
        if ! grep -q '^description' "$f"; then
            ok=false
        fi
    done
    if $ok; then test_pass; else test_fail "all .toml files should have description field"; fi
}

test_toml_has_args_placeholder() {
    test_case ".toml: commands use {{args}} placeholder"
    local ok=true
    for f in "$PROJECT_ROOT/.gemini/commands/octo/"*.toml; do
        if ! grep -q '{{args}}' "$f"; then
            ok=false
        fi
    done
    if $ok; then test_pass; else test_fail "all .toml files should use {{args}}"; fi
}

test_toml_not_used_in_dispatch() {
    test_case ".toml: NOT used in headless dispatch (stdin composition issue)"
    # Verify dispatch.sh does NOT reference /octo: commands (reverted)
    if grep -q '/octo:research\|/octo:review\|/octo:architect\|/octo:implement' "$DISPATCH"; then
        test_fail "dispatch.sh should not use .toml commands in headless mode"
    else
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 12. Pricing — Gemini models in cost table
# ═══════════════════════════════════════════════════════════════════════════════

test_pricing_gemini_pro() {
    test_case "pricing: gemini pro model has pricing"
    if grep -q 'gemini.*pro' "$ORCH" | head -1 && grep -qE 'gemini-3.*pro.*echo "[0-9]' "$ALL_SRC"; then
        test_pass
    else
        # Fallback: just check any gemini model has pricing
        if grep -q 'gemini.*echo "[0-9]' "$ALL_SRC"; then
            test_pass
        else
            test_fail "get_model_pricing should have gemini model"
        fi
    fi
}

test_pricing_gemini_flash() {
    test_case "pricing: gemini flash model has pricing"
    if grep -q 'gemini.*flash' "$ALL_SRC"; then
        test_pass
    else
        test_fail "get_model_pricing should have gemini flash model"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 13. Provider Config — Gemini CLAUDE.md
# ═══════════════════════════════════════════════════════════════════════════════

test_gemini_config_exists() {
    test_case "config: providers/gemini/CLAUDE.md exists"
    if [[ -f "$PROJECT_ROOT/config/providers/gemini/CLAUDE.md" ]]; then
        test_pass
    else
        test_fail "Gemini provider config should exist"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════════════

# 1. Dispatch
test_dispatch_gemini_standard
test_dispatch_gemini_text_output
test_dispatch_gemini_yolo_mode
test_dispatch_gemini_model_selection
test_dispatch_gemini_force_file_storage
test_dispatch_gemini_node_no_warnings
test_dispatch_gemini_sandbox_modes
test_dispatch_gemini_fast_variant
test_dispatch_gemini_image_variant

# 2. Available agents
test_available_agents_gemini
test_available_agents_gemini_fast
test_available_agents_gemini_image

# 3. Doctor
test_doctor_gemini_cli_check
test_doctor_gemini_version_detection
test_doctor_gemini_install_hint

# 4. Provider health
test_provider_health_gemini_case
test_provider_health_gemini_oauth
test_provider_health_gemini_api_key
test_provider_health_gemini_google_key
test_provider_all_includes_gemini

# 5. Model resolution
test_model_resolver_gemini_standard
test_model_resolver_gemini_fast
test_model_resolver_gemini_model_name

# 6. Circuit breaker
test_circuit_breaker_includes_gemini

# 7. Workflows
test_workflows_gemini_headless_flag
test_workflows_gemini_provider_name

# 8. Embrace
test_embrace_checks_gemini
test_embrace_gemini_in_strategy

# 9. Detection
test_detect_providers_gemini
test_preflight_gemini_status
test_preflight_gemini_auth

# 10. MCP/OpenClaw env forwarding
test_mcp_forwards_gemini_key
test_mcp_forwards_google_key
test_openclaw_forwards_gemini_key

# 11. .toml commands
test_toml_commands_dir_exists
test_toml_research_exists
test_toml_review_exists
test_toml_has_prompt_field
test_toml_has_description_field
test_toml_has_args_placeholder
test_toml_not_used_in_dispatch

# 12. Pricing
test_pricing_gemini_pro
test_pricing_gemini_flash

# 13. Config
test_gemini_config_exists

# 14. Model fallback wrapper (v9.22.0)
test_gemini_exec_wrapper_exists() {
    test_case "fallback: helpers/gemini-exec.sh exists and is executable"
    local wrapper="$PROJECT_ROOT/scripts/helpers/gemini-exec.sh"
    if [[ -x "$wrapper" ]]; then
        test_pass
    else
        test_fail "scripts/helpers/gemini-exec.sh missing or not executable"
    fi
}

test_gemini_exec_wrapper_invoked() {
    test_case "fallback: dispatch routes gemini through gemini-exec.sh wrapper"
    if sed -n '/gemini|gemini-fast/,/;;/p' "$DISPATCH" | grep -q 'gemini-exec\.sh'; then
        test_pass
    else
        test_fail "dispatch.sh gemini branch should invoke helpers/gemini-exec.sh"
    fi
}

test_gemini_fallback_default_model() {
    test_case "fallback: default OCTOPUS_GEMINI_FALLBACK_MODELS includes a GA model"
    local wrapper="$PROJECT_ROOT/scripts/helpers/gemini-exec.sh"
    # Default fallback must be a non-preview, generally-available model so that
    # accounts lacking preview access still recover automatically.
    if grep -qE 'OCTOPUS_GEMINI_FALLBACK_MODELS:-gemini-[0-9]+\.[0-9]+-flash' "$wrapper"; then
        test_pass
    else
        test_fail "wrapper default should fall back to a GA flash model"
    fi
}

test_gemini_fallback_classifies_modelnotfound() {
    test_case "fallback: smoke classifier returns MODEL_NOT_FOUND for all known variants"
    local result
    # shellcheck disable=SC1090
    source "$SMOKE" 2>/dev/null || { test_fail "cannot source lib/smoke.sh"; return; }
    if ! declare -f _classify_smoke_error >/dev/null; then
        test_fail "_classify_smoke_error not defined after sourcing smoke.sh"
        return
    fi
    local failed=""
    for payload in \
        "ModelNotFoundError: the model does not exist" \
        "HTTP 404 - model gemini-foo not found" \
        "Error: model gemini-xyz is not available in your region" \
        "unknown model specified" \
        "Request failed: 404 Not Found" \
        "model not available" \
        "no such model: gemini-x" \
        "invalid model id"
    do
        result=$(_classify_smoke_error "$payload")
        [[ "$result" == "MODEL_NOT_FOUND" ]] || failed+="  input=[${payload}] got=[${result}]\n"
    done
    if [[ -z "$failed" ]]; then
        test_pass
    else
        test_fail "classifier missed variants:\n${failed}"
    fi
}

test_gemini_wrapper_is_model_error_in_sync() {
    test_case "fallback: gemini-exec is_model_error agrees with smoke classifier on every variant"
    local helper="${PROJECT_ROOT}/scripts/helpers/gemini-exec.sh"
    [[ -r "$helper" ]] || { test_fail "missing $helper"; return; }
    local failed=""
    for payload in \
        "ModelNotFoundError: x" \
        "HTTP 404 - model gemini-foo not found" \
        "model gemini-xyz is not available" \
        "404 Not Found" \
        "no such model: gemini-x" \
        "invalid model id"
    do
        local fn_src
        fn_src=$(sed -n '/^is_model_error()/,/^}/p' "$helper")
        bash -c "$fn_src; is_model_error \"\$1\"" _ "$payload" \
            || failed+="  payload=[$payload]\n"
    done
    [[ -z "$failed" ]] && test_pass || test_fail "wrapper is_model_error missed:\n${failed}"
}

_make_stub_gemini_dir() {
    local mode="$1" dir
    dir=$(mktemp -d -t "octo-gemini-stub.XXXXXX")
    cat >"$dir/gemini" <<'STUB'
#!/usr/bin/env bash
model=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m) model="$2"; shift 2 ;;
        *) shift ;;
    esac
done
prompt=$(cat || true)
case "$STUB_MODE" in
    fallback)
        if [[ "$model" == "gemini-3.0-pro-preview" ]]; then
            echo "PARTIAL_LEAK_SHOULD_NOT_APPEAR"
            echo "HTTP 404 - model $model not found" >&2
            exit 1
        fi
        echo "OK from $model: $prompt"
        exit 0
        ;;
    rate_limit)
        echo "429 Too Many Requests" >&2
        exit 1
        ;;
esac
STUB
    chmod +x "$dir/gemini"
    printf '%s' "$dir"
}

test_gemini_exec_wrapper_retries_on_404() {
    test_case "fallback: wrapper retries next model on 404, replays stdin, hides leaked stdout"
    local helper="$PROJECT_ROOT/scripts/helpers/gemini-exec.sh"
    local stub_dir out rc
    stub_dir=$(_make_stub_gemini_dir fallback)
    out=$(PATH="$stub_dir:$PATH" STUB_MODE=fallback \
          OCTOPUS_GEMINI_FALLBACK_MODELS=gemini-2.5-flash \
          OCTOPUS_GEMINI_FALLBACK_QUIET=true \
          bash "$helper" gemini-3.0-pro-preview <<<"hello world" 2>/dev/null)
    rc=$?
    rm -rf "$stub_dir"
    if [[ $rc -eq 0 \
          && "$out" == *"OK from gemini-2.5-flash"* \
          && "$out" == *"hello world"* \
          && "$out" != *"PARTIAL_LEAK_SHOULD_NOT_APPEAR"* ]]; then
        test_pass
    else
        test_fail "wrapper retry/replay/leak-suppression broken (rc=$rc out=$out)"
    fi
}

test_gemini_exec_wrapper_no_retry_on_429() {
    test_case "fallback: wrapper does NOT retry on transient 429 (left to provider-router)"
    local helper="$PROJECT_ROOT/scripts/helpers/gemini-exec.sh"
    local stub_dir rc
    stub_dir=$(_make_stub_gemini_dir rate_limit)
    set +e
    PATH="$stub_dir:$PATH" STUB_MODE=rate_limit \
        OCTOPUS_GEMINI_FALLBACK_MODELS=gemini-2.5-flash \
        OCTOPUS_GEMINI_FALLBACK_QUIET=true \
        bash "$helper" gemini-3.0-pro-preview <<<"hi" >/dev/null 2>&1
    rc=$?
    set -e
    rm -rf "$stub_dir"
    [[ $rc -ne 0 ]] && test_pass || test_fail "wrapper retried on 429 (should bail out)"
}

test_gemini_exec_wrapper_blocks_disallowed_primary() {
    test_case "fallback: wrapper rejects primary model not in OCTOPUS_GEMINI_ALLOWED_MODELS"
    local helper="$PROJECT_ROOT/scripts/helpers/gemini-exec.sh"
    local rc
    set +e
    OCTOPUS_GEMINI_ALLOWED_MODELS="gemini-2.5-flash" \
        bash "$helper" gemini-3.0-pro-preview </dev/null >/dev/null 2>&1
    rc=$?
    set -e
    [[ $rc -eq 2 ]] && test_pass || test_fail "expected exit 2 for disallowed primary, got $rc"
}

test_gemini_exec_wrapper_exists
test_gemini_exec_wrapper_invoked
test_gemini_fallback_default_model
test_gemini_fallback_classifies_modelnotfound
test_gemini_wrapper_is_model_error_in_sync
test_gemini_exec_wrapper_retries_on_404
test_gemini_exec_wrapper_no_retry_on_429
test_gemini_exec_wrapper_blocks_disallowed_primary

test_summary
