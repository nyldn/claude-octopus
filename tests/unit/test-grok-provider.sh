#!/bin/bash
# tests/unit/test-grok-provider.sh
# Contract coverage for the xAI Grok CLI provider (#542 follow-ups):
#   1. dispatch routes through the stdin->-p shim (helpers/grok-exec.sh).
#   2. config/env model selection is wired to runtime (get_agent_model +
#      OCTOPUS_GROK_MODEL env prefix) so providers.json picks reach the shim.
#   3. providers.json grok model resolves and grok-exec.sh emits --model;
#      "default" emits no --model.
#   4. provider-routing isolates grok by default (env -i) with a full-env opt-in,
#      matching codex/gemini/agy.
#   5. grok_execute propagates a non-zero exit even when stdout is non-empty.
#   6. grok_is_available requires the binary AND auth.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "xAI Grok CLI Provider"

# Stub log() — grok.sh/model-resolver.sh call it outside orchestrate.sh.
log() { :; }

# ── 1. dispatch routes through the shim ───────────────────────────────────────
test_grok_dispatch_shim() {
    test_case "dispatch.sh routes grok through helpers/grok-exec.sh"
    if grep -q 'scripts/helpers/grok-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh" && \
       grep -q 'grok -p "$prompt"' "$PROJECT_ROOT/scripts/helpers/grok-exec.sh"; then
        test_pass
    else
        test_fail "grok dispatch should use scripts/helpers/grok-exec.sh"
    fi
}

# ── 2. dispatch wires config/env model to the shim ────────────────────────────
test_grok_dispatch_wires_model() {
    test_case "dispatch grok arm resolves model and env-prefixes OCTOPUS_GROK_MODEL"
    local arm
    arm="$(sed -n '/grok|grok-research)/,/;;/p' "$PROJECT_ROOT/scripts/lib/dispatch.sh")"
    if [[ "$arm" == *"get_agent_model"* ]] && [[ "$arm" == *"env OCTOPUS_GROK_MODEL="* ]]; then
        test_pass
    else
        test_fail "grok arm should call get_agent_model and pass OCTOPUS_GROK_MODEL to the shim"
    fi
}

# ── 3. provider-routing env isolation parity ──────────────────────────────────
test_grok_env_isolation() {
    test_case "provider routing isolates grok by default with full-env opt-in"
    local block
    block="$(sed -n '/grok\*)/,/;;/p' "$PROJECT_ROOT/scripts/lib/provider-routing.sh")"
    if [[ "$block" == *"OCTOPUS_ALLOW_FULL_GROK_ENV"* ]] && \
       [[ "$block" == *"PROVIDER_ENV_ARRAY=(env -i"* ]] && \
       [[ "$block" == *"XAI_API_KEY"* ]] && \
       [[ "$block" == *"PROVIDER_ENV_ARRAY=()"* ]]; then
        test_pass
    else
        test_fail "grok should isolate by default (env -i + XAI_API_KEY) and honor OCTOPUS_ALLOW_FULL_GROK_ENV=true"
    fi
}

# ── 4. config-file model resolves and reaches the shim as --model ─────────────
test_grok_config_runtime_model() {
    test_case "providers.json grok model resolves and grok-exec.sh emits --model"
    local tmp_bin capture config_home old_path old_home resolved
    tmp_bin="$TEST_TMP_DIR/grok-bin"; capture="$TEST_TMP_DIR/grok-argv.txt"; config_home="$TEST_TMP_DIR/grok-home"
    mkdir -p "$tmp_bin" "$config_home/.claude-octopus/config"
    cat > "$tmp_bin/grok" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${GROK_ARG_CAPTURE:?}"
exit 0
MOCK
    chmod +x "$tmp_bin/grok"
    cat > "$config_home/.claude-octopus/config/providers.json" <<'JSON'
{"providers":{"grok":{"default":"grok-4-fast"}}}
JSON
    old_path="$PATH"; old_home="$HOME"
    PATH="$tmp_bin:$PATH"; export GROK_ARG_CAPTURE="$capture"
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true

    HOME="$config_home"
    resolved="$(resolve_octopus_model grok grok "" "" 2>/dev/null || true)"
    HOME="$old_home"
    if [[ "$resolved" != "grok-4-fast" ]]; then
        PATH="$old_path"; unset GROK_ARG_CAPTURE
        test_fail "config providers.json grok model should resolve to grok-4-fast, got: '$resolved'"
        return
    fi

    OCTOPUS_GROK_MODEL="grok-4-fast" bash "$PROJECT_ROOT/scripts/helpers/grok-exec.sh" <<<"probe" >/dev/null 2>&1 || true
    PATH="$old_path"; unset GROK_ARG_CAPTURE
    if grep -Fxq -- '--model' "$capture" && grep -Fxq -- 'grok-4-fast' "$capture"; then
        test_pass
    else
        test_fail "grok-exec.sh should pass the resolved model as --model; argv: $(tr '\n' ' ' < "$capture" 2>/dev/null)"
    fi
}

# ── 5. "default" model => no --model flag ─────────────────────────────────────
test_grok_default_no_model() {
    test_case "OCTOPUS_GROK_MODEL=default is not passed to grok --model"
    local tmp_bin capture old_path
    tmp_bin="$TEST_TMP_DIR/grok-bin-def"; capture="$TEST_TMP_DIR/grok-argv-def.txt"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/grok" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${GROK_ARG_CAPTURE:?}"
exit 0
MOCK
    chmod +x "$tmp_bin/grok"
    old_path="$PATH"; PATH="$tmp_bin:$PATH"; export GROK_ARG_CAPTURE="$capture"
    OCTOPUS_GROK_MODEL="default" bash "$PROJECT_ROOT/scripts/helpers/grok-exec.sh" <<<"probe" >/dev/null 2>&1 || true
    PATH="$old_path"; unset GROK_ARG_CAPTURE
    if grep -q -- '--model' "$capture"; then
        test_fail "default should not be passed to grok --model; argv: $(tr '\n' ' ' < "$capture" 2>/dev/null)"
    else
        test_pass
    fi
}

# ── 6. non-zero exit propagates even with stdout ──────────────────────────────
test_grok_exit_propagation() {
    test_case "grok_execute returns non-zero when grok exits non-zero (even with stdout)"
    local tmp_bin old_path rc
    tmp_bin="$TEST_TMP_DIR/grok-bin-fail"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/grok" <<'MOCK'
#!/usr/bin/env bash
printf 'partial answer before crash\n'   # non-empty stdout
exit 3
MOCK
    chmod +x "$tmp_bin/grok"
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/grok.sh" 2>/dev/null || true
    rc=0
    grok_execute grok "probe" >/dev/null 2>&1 || rc=$?
    PATH="$old_path"
    if [[ "$rc" -ne 0 ]]; then
        test_pass
    else
        test_fail "grok_execute masked a non-zero exit (returned 0) despite grok exiting 3"
    fi
}

# ── 7. availability requires binary AND auth ──────────────────────────────────
test_grok_detection() {
    test_case "grok_is_available requires the grok binary and auth"
    local tmp_bin old_path old_home old_key rc_auth rc_noauth
    tmp_bin="$TEST_TMP_DIR/grok-bin-det"
    mkdir -p "$tmp_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp_bin/grok"; chmod +x "$tmp_bin/grok"
    old_path="$PATH"; old_home="$HOME"; old_key="${XAI_API_KEY:-}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/grok-empty-home"; mkdir -p "$HOME"
    source "$PROJECT_ROOT/scripts/lib/grok.sh" 2>/dev/null || true

    XAI_API_KEY="xai-test-key"
    rc_auth=0; grok_is_available >/dev/null 2>&1 || rc_auth=$?
    unset XAI_API_KEY
    rc_noauth=0; grok_is_available >/dev/null 2>&1 || rc_noauth=$?

    PATH="$old_path"; HOME="$old_home"; [[ -n "$old_key" ]] && export XAI_API_KEY="$old_key"
    if [[ "$rc_auth" -eq 0 && "$rc_noauth" -ne 0 ]]; then
        test_pass
    else
        test_fail "grok_is_available should be true with XAI_API_KEY ($rc_auth) and false without auth ($rc_noauth)"
    fi
}

test_grok_dispatch_shim
test_grok_dispatch_wires_model
test_grok_env_isolation
test_grok_config_runtime_model
test_grok_default_no_model
test_grok_exit_propagation
test_grok_detection

test_summary
