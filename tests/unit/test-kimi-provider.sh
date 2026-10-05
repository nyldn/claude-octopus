#!/bin/bash
# tests/unit/test-kimi-provider.sh
# Contract coverage for the Moonshot Kimi Code CLI provider:
#   1. dispatch routes through the stdin->-p shim (helpers/kimi-exec.sh).
#   2. config/env model selection reaches the shim through a reversible,
#      shell-safe environment encoding.
#   3. provider-routing isolates kimi by default, preserves KIMI_CODE_HOME,
#      and offers a full-env opt-in.
#   4. providers.json kimi model resolves and kimi-exec.sh emits --model;
#      "default" emits no --model.
#   5. kimi_execute propagates a non-zero exit even with stdout and isolates its
#      direct-call environment.
#   6. the Kimi request timeout still works without GNU/BSD timeout.
#   7. stderr-only authentication failures receive actionable guidance without
#      contaminating successful response output.
#   8. kimi_is_available requires the binary, a resolvable configured model,
#      and credentials on that model's provider. Ambient KIMI_API_KEY is
#      not a Kimi Code credential source.
#   9. standard dispatch validation and configured routing accept both Kimi
#      agent types and give them a stable display label.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
PLUGIN_DIR="$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true
source "$PROJECT_ROOT/scripts/lib/dispatch.sh" 2>/dev/null || true
source "$PROJECT_ROOT/scripts/lib/routing.sh" 2>/dev/null || true
source "$PROJECT_ROOT/scripts/lib/parallel.sh" 2>/dev/null || true

test_suite "Moonshot Kimi Code CLI Provider"

# Config probes execute through Kimi Code's own plugin runtime. The fixture
# below emulates only Kimi's offline doctor/provider commands; it never reaches
# the network and keeps credential values inside the child process.
export KIMI_TEST_NODE="$(command -v node)"
export KIMI_TEST_DRIVER="$PROJECT_ROOT/tests/fixtures/kimi-code-cli-mock.mjs"

_kimi_emit_test_runtime_env() {
    printf 'KIMI_TEST_NODE=%q\n' "$KIMI_TEST_NODE"
    printf 'KIMI_TEST_DRIVER=%q\n' "$KIMI_TEST_DRIVER"
    printf '%s\n' 'export KIMI_TEST_NODE KIMI_TEST_DRIVER'
}

# Stub log() — kimi.sh/model-resolver.sh call it outside orchestrate.sh.
log() { :; }

# Restore KIMI_API_KEY exactly as found — including "was not set at all",
# which a plain -n check would silently turn into "keep the fake test key".
_kimi_restore_key() {
    if [[ -n "$1" ]]; then export KIMI_API_KEY="$2"; else unset KIMI_API_KEY; fi
}

_kimi_mock_bin() {
    local dir="$1" body="$2"
    mkdir -p "$dir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        _kimi_emit_test_runtime_env
        cat <<'MOCK'
case "${1:-}" in
    __plugin_run_node)
        shift
        exec "${KIMI_TEST_NODE:?}" "$@"
        ;;
    doctor|provider)
        exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "$@"
        ;;
esac
MOCK
        printf '%s\n' "$body"
    } > "$dir/kimi"
    chmod +x "$dir/kimi"
}

_kimi_native_runtime_mock_bin() {
    local dir="$1" command_name
    mkdir -p "$dir"
    # Use a native shell to dispatch the inert command files below. Some env
    # implementations reject invocation under a different executable name.
    ln -s "$(command -v sh)" "$dir/kimi"
    for command_name in doctor provider; do
        {
            printf '%s\n' '#!/usr/bin/env bash'
            _kimi_emit_test_runtime_env
            cat <<'MOCK'
exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "${0##*/}" "$@"
MOCK
        } > "$dir/$command_name"
        chmod +x "$dir/$command_name"
    done
    {
        printf '%s\n' '#!/usr/bin/env bash'
        _kimi_emit_test_runtime_env
        cat <<'MOCK'
exec "${KIMI_TEST_NODE:?}" "$@"
MOCK
    } > "$dir/__plugin_run_node"
    chmod +x "$dir/__plugin_run_node"
}

_kimi_node_runtime_mock_bin() {
    local dir="$1" node_json driver_json
    mkdir -p "$dir"
    node_json="$("$KIMI_TEST_NODE" -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$KIMI_TEST_NODE")"
    driver_json="$("$KIMI_TEST_NODE" -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$KIMI_TEST_DRIVER")"
    {
        printf '%s\n' '#!/usr/bin/env node'
        printf 'const KIMI_TEST_NODE = %s;\n' "$node_json"
        printf 'const KIMI_TEST_DRIVER = %s;\n' "$driver_json"
        cat <<'MOCK'
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const args = process.argv.slice(2);
if (args[0] === '__plugin_run_node') {
  const entry = args[1];
  process.argv = [process.argv[0], entry, ...args.slice(2)];
  import(pathToFileURL(entry).href).catch(() => process.exit(1));
} else {
  const result = spawnSync(KIMI_TEST_NODE, [KIMI_TEST_DRIVER, ...args], {
    env: process.env,
    stdio: 'inherit',
  });
  process.exit(result.status ?? 1);
}
MOCK
    } > "$dir/kimi"
    chmod +x "$dir/kimi"
}

# Keep a deterministic Kimi runtime available for config-only tests that do
# not otherwise need a bespoke dispatch mock.
KIMI_TEST_CONFIG_BIN="$TEST_TMP_DIR/kimi-bin-config-runtime"
_kimi_mock_bin "$KIMI_TEST_CONFIG_BIN" 'exit 0'
PATH="$KIMI_TEST_CONFIG_BIN:$PATH"
export PATH

_kimi_fake_system_timeout_bins() {
    local dir="$1" timeout_name
    mkdir -p "$dir"
    for timeout_name in gtimeout timeout; do
        cat > "$dir/$timeout_name" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >> "${FAKE_TIMEOUT_USED:?}"
shift 3
"$@"
MOCK
        chmod +x "$dir/$timeout_name"
    done
}

# A mock that enforces the current standalone CLI's argument contract, so a
# permissive mock cannot green-light an invocation Kimi would reject.
#   unknown flags are rejected ("error: unknown option '<flag>'")
_kimi_strict_mock_bin() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/kimi" <<'MOCK'
#!/usr/bin/env bash
have_prompt=0; have_conflicting_mode=0
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
        -p|--prompt)        have_prompt=1; i=$((i+2)); continue ;;
        --auto|-y|--yolo|--plan) have_conflicting_mode=1 ;;
        --output-format)    i=$((i+2)); continue ;;
        -m|--model)         i=$((i+2)); continue ;;
        *) echo "error: unknown option '${args[$i]}'" >&2; exit 1 ;;
    esac
    i=$((i+1))
done
if [[ $have_prompt -eq 1 && $have_conflicting_mode -eq 1 ]]; then
    echo "error: Cannot combine --prompt with an interactive permission mode." >&2; exit 1
fi
[[ $have_prompt -eq 1 ]] || { echo "error: no prompt" >&2; exit 1; }
printf 'MOCK_KIMI_OK\n'
MOCK
    chmod +x "$dir/kimi"
}

# ── 1. dispatch routes through the shim ───────────────────────────────────────
test_kimi_dispatch_shim() {
    test_case "dispatch.sh routes kimi through helpers/kimi-exec.sh"
    if grep -q 'scripts/helpers/kimi-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh" && \
       grep -q 'kimi -p "$prompt"' "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh"; then
        test_pass
    else
        test_fail "kimi dispatch should use scripts/helpers/kimi-exec.sh"
    fi
}

# ── 2. dispatch wires config/env model to the shim ────────────────────────────
test_kimi_dispatch_wires_model() {
    test_case "dispatch kimi arm resolves and safely encodes OCTOPUS_KIMI_MODEL"
    local arm
    arm="$(sed -n '/kimi|kimi-research)/,/;;/p' "$PROJECT_ROOT/scripts/lib/dispatch.sh")"
    if [[ "$arm" == *"get_agent_model"* ]] && [[ "$arm" == *"env OCTOPUS_KIMI_MODEL_HEX="* ]]; then
        test_pass
    else
        test_fail "kimi arm should encode the resolved model before passing it to the shim"
    fi
}

test_kimi_rejects_read_only_roles() {
    test_case "Kimi dispatch rejects read-only roles and permits all six write roles"
    local review_rc=0 research_rc=0 role implementation_cmd=""
    (
        get_agent_model() { printf '%s\n' default; }
        get_agent_command kimi review code-reviewer 10 >/dev/null 2>&1
    ) || review_rc=$?
    (
        get_agent_model() { printf '%s\n' default; }
        get_agent_command kimi-research probe researcher 10 >/dev/null 2>&1
    ) || research_rc=$?
    if [[ "$review_rc" -eq 0 || "$research_rc" -eq 0 ]]; then
        test_fail "expected read-only rejection, got review=$review_rc research=$research_rc"
        return
    fi
    for role in implementer tdd-orchestrator debugger python-pro typescript-pro frontend-developer; do
        implementation_cmd="$({
            get_agent_model() { printf '%s\n' default; }
            get_agent_command kimi tangle "$role" 10
        } 2>/dev/null)"
        if [[ "$implementation_cmd" != *"scripts/helpers/kimi-exec.sh"* ]]; then
            test_fail "expected Kimi shim for write role '$role', got '$implementation_cmd'"
            return
        fi
    done
    test_pass
}

test_kimi_rejects_every_non_write_capable_role() {
    test_case "Kimi dispatch fails closed for readonly, mapped review, and unknown roles"
    local role rc
    for role in backend-architect design-feasibility-reviewer \
        implementation-logic-reviewer implementation-security-reviewer \
        implementation-architecture-reviewer implementation-cve-reviewer \
        implementation-diversity-reviewer unknown-role; do
        rc=0
        (
            get_agent_model() { printf '%s\n' default; }
            get_agent_command kimi spawn "$role" 10 >/dev/null 2>&1
        ) || rc=$?
        if [[ "$rc" -eq 0 ]]; then
            test_fail "expected Kimi to reject role '$role'"
            return
        fi
    done
    test_pass
}

test_kimi_is_excluded_from_consultative_fleets() {
    test_case "consultative fleets exclude Kimi before seat construction"
    local checker="$TEST_TMP_DIR/kimi-only-provider-checker.sh" fleet rc=0
    cat > "$checker" <<'MOCK'
#!/bin/bash
printf '%s\n' 'kimi:available'
MOCK
    chmod +x "$checker"
    fleet="$(OCTOPUS_PROVIDER_CHECKER="$checker" OCTO_ALLOWED_PROVIDERS="kimi" \
        bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research quick fixture 2>/dev/null)" || rc=$?
    if [[ "$rc" -ne 0 && "$fleet" != *'kimi|'* ]]; then
        test_pass
    else
        test_fail "Kimi-only read-only fleet must fail explicitly: rc=$rc fleet='$fleet'"
    fi
}

test_kimi_direct_execution_rejects_restricted_types() {
    test_case "direct Kimi execution rejects research and role-like agent types"
    local agent_type rc
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    for agent_type in kimi-research code-reviewer unknown-role; do
        rc=0
        kimi_execute "$agent_type" probe >/dev/null 2>&1 || rc=$?
        if [[ "$rc" -eq 0 ]]; then
            test_fail "direct Kimi execution accepted restricted type '$agent_type'"
            return
        fi
    done
    test_pass
}

# ── 3. provider-routing env isolation parity ──────────────────────────────────
test_kimi_env_isolation() {
    test_case "provider routing preserves a custom Kimi data root through env isolation"
    local old_home old_root had_root entry found=false
    old_home="$HOME"; old_root="${KIMI_CODE_HOME-}"; had_root="${KIMI_CODE_HOME+set}"
    HOME="$TEST_TMP_DIR/kimi-routing-home"
    KIMI_CODE_HOME="$TEST_TMP_DIR/kimi custom root"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    build_provider_env kimi-research
    for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
        [[ "$entry" == "KIMI_CODE_HOME=$KIMI_CODE_HOME" ]] && found=true
    done
    HOME="$old_home"
    if [[ "$had_root" == set ]]; then KIMI_CODE_HOME="$old_root"; else unset KIMI_CODE_HOME; fi
    if [[ "${PROVIDER_ENV_ARRAY[0]:-}" == env && "${PROVIDER_ENV_ARRAY[1]:-}" == -i && "$found" == true ]]; then
        test_pass
    else
        test_fail "kimi should retain KIMI_CODE_HOME exactly across env -i"
    fi
}

test_kimi_config_credentials() {
    test_case "readiness follows default model to provider api_key in config.toml"
    local tmp_bin old_path old_home old_root old_key had_root had_key auth rc rc_whitespace
    tmp_bin="$TEST_TMP_DIR/kimi-bin-config-auth"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"; old_root="${KIMI_CODE_HOME-}"; old_key="${KIMI_API_KEY-}"
    had_root="${KIMI_CODE_HOME+set}"; had_key="${KIMI_API_KEY+set}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-config-home"; unset KIMI_CODE_HOME
    unset KIMI_API_KEY
    mkdir -p "$HOME/.kimi-code"
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "kimi-code/k3"
[models."kimi-code/k3"]
provider = "managed:kimi-code"
model = "k3"
max_context_size = 1048576
[providers."managed:kimi-code"]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0; kimi_is_available >/dev/null 2>&1 || rc=$?
    auth="$(kimi_auth_method)"
    sed 's/fixture-not-a-secret/   /' "$HOME/.kimi-code/config.toml" > "$HOME/.kimi-code/config.next"
    mv "$HOME/.kimi-code/config.next" "$HOME/.kimi-code/config.toml"
    rc_whitespace=0
    kimi_is_available >/dev/null 2>&1 || rc_whitespace=$?
    PATH="$old_path"; HOME="$old_home"
    if [[ "$had_root" == set ]]; then KIMI_CODE_HOME="$old_root"; else unset KIMI_CODE_HOME; fi
    _kimi_restore_key "$had_key" "$old_key"
    if [[ "$rc" -eq 0 && "$auth" == "config:api-key" && "$rc_whitespace" -ne 0 ]]; then
        test_pass
    else
        test_fail "expected config-backed readiness and config:api-key, got rc=$rc auth=$auth whitespace=$rc_whitespace"
    fi
}

test_kimi_native_runtime_config_bridge() {
    test_case "config validation works with a native Kimi executable shape"
    local tmp_bin root old_path method rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-native-runtime"
    root="$TEST_TMP_DIR/kimi-native-runtime"
    _kimi_native_runtime_mock_bin "$tmp_bin"
    mkdir -p "$root"
    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    old_path="$PATH"
    PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0
    method="$(cd "$tmp_bin" && KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc=$?
    PATH="$old_path"
    if [[ "$rc" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected native-runtime config readiness, got rc=$rc method=$method"
    fi
}

test_kimi_node_runtime_config_bridge() {
    test_case "config validation works with the official Node launcher shape"
    local tmp_bin root old_path method rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-node-runtime"
    root="$TEST_TMP_DIR/kimi-node-runtime"
    _kimi_node_runtime_mock_bin "$tmp_bin"
    mkdir -p "$root"
    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "openai"
model = "gpt-5"
max_context_size = 400000
capabilities = ["tool_use", "audio_in"]
[providers.openai]
type = "openai"
[providers.openai.env]
OPENAI_API_KEY = "fixture-not-a-secret"
TOML
    old_path="$PATH"
    PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc=$?
    PATH="$old_path"
    if [[ "$rc" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected Node-runtime config readiness, got rc=$rc method=$method"
    fi
}

test_kimi_config_env_is_credential() {
    test_case "provider-local env supplies the selected provider credential"
    local tmp_bin old_path old_home auth rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-config-env"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-config-env-home"; unset KIMI_CODE_HOME KIMI_API_KEY
    mkdir -p "$HOME/.kimi-code"
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
[providers.kimi.env]
KIMI_API_KEY = "fixture-not-a-secret"
TOML
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0; kimi_is_available >/dev/null 2>&1 || rc=$?
    auth="$(kimi_auth_method)"
    PATH="$old_path"; HOME="$old_home"
    if [[ "$rc" -eq 0 && "$auth" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected provider-local env readiness, got rc=$rc auth=$auth"
    fi
}

test_kimi_rejects_incomplete_selected_records() {
    test_case "readiness rejects schema-invalid selected model and provider records"
    local root rc_missing_type rc_missing_model rc_missing_context
    local rc_missing_base_url rc_missing_api_key rc_invalid_type
    root="$TEST_TMP_DIR/kimi-incomplete-records"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_missing_type=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_missing_type=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_missing_model=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_missing_model=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_missing_context=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_missing_context=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
api_key = "fixture-not-a-secret"
TOML
    rc_missing_base_url=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_missing_base_url=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
TOML
    rc_missing_api_key=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_missing_api_key=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "openai"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_invalid_type=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_invalid_type=$?

    if [[ "$rc_missing_type" -ne 0 && "$rc_missing_model" -ne 0 && \
          "$rc_missing_context" -ne 0 && "$rc_missing_base_url" -eq 0 && \
          "$rc_missing_api_key" -ne 0 && "$rc_invalid_type" -eq 0 ]]; then
        test_pass
    else
        test_fail "expected required selected fields to fail while optional base_url and openai pass, got type=$rc_missing_type model=$rc_missing_model context=$rc_missing_context base-url=$rc_missing_base_url api-key=$rc_missing_api_key provider-type=$rc_invalid_type"
    fi
}

test_kimi_accepts_matching_provider_env_credentials() {
    test_case "provider-local env uses the credential key for the selected provider type"
    local root rc_unrelated rc_kimi rc_openai_wrong rc_openai
    root="$TEST_TMP_DIR/kimi-provider-env-key"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
[providers.kimi.env]
UNRELATED_API_KEY = "fixture-not-a-secret"
TOML
    rc_unrelated=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_unrelated=$?

    sed 's/UNRELATED_API_KEY/KIMI_API_KEY/' "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_kimi=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_kimi=$?

    sed 's/type = "kimi"/type = "openai"/' "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_openai_wrong=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_openai_wrong=$?

    sed 's/KIMI_API_KEY/OPENAI_API_KEY/' "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_openai=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_openai=$?

    if [[ "$rc_unrelated" -ne 0 && "$rc_kimi" -eq 0 &&
          "$rc_openai_wrong" -ne 0 && "$rc_openai" -eq 0 ]]; then
        test_pass
    else
        test_fail "expected only matching provider env keys to authenticate, got unrelated=$rc_unrelated kimi=$rc_kimi openai-wrong=$rc_openai_wrong openai=$rc_openai"
    fi
}

test_kimi_accepts_current_provider_types_and_capabilities() {
    test_case "current Kimi provider types and capability tags pass readiness"
    local root rc_openai rc_google method
    root="$TEST_TMP_DIR/kimi-current-config-vocabulary"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "provider"
model = "model"
max_context_size = 1048576
capabilities = ["tool_use", "audio_in"]
[providers.provider]
type = "openai"
[providers.provider.env]
OPENAI_API_KEY = "fixture-not-a-secret"
TOML
    rc_openai=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc_openai=$?

    sed 's/type = "openai"/type = "google-genai"/; s/OPENAI_API_KEY/GOOGLE_API_KEY/' \
        "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_google=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc_google=$?

    if [[ "$rc_openai" -eq 0 && "$rc_google" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected current vocabulary readiness, got openai=$rc_openai google=$rc_google method=$method"
    fi
}

test_kimi_accepts_current_v2_model_reference_shape() {
    test_case "current provider_id/name model records resolve and authenticate"
    local root rc method
    root="$TEST_TMP_DIR/kimi-current-v2-model-shape"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider_id = "openai"
name = "gpt-5"
protocol = "openai"
max_context_size = 400000
[providers.openai]
type = "openai"
api_key = "fixture-not-a-secret"
TOML
    rc=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc=$?
    if [[ "$rc" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected provider_id/name readiness, got rc=$rc method=$method"
    fi
}

test_kimi_model_level_auth_precedes_provider_auth() {
    test_case "model-level API key and OAuth credentials drive readiness before provider auth"
    local root api_rc=0 oauth_rc=0 api_method oauth_method
    root="$TEST_TMP_DIR/kimi-model-level-auth"
    mkdir -p "$root/credentials"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "openai"
model = "gpt-fixture"
max_context_size = 1048576
api_key = "PR987_MODEL_KEY_SENTINEL"
[providers.openai]
type = "openai"
base_url = "https://fixture.invalid/v1"
[providers.openai.oauth]
storage = "file"
key = "oauth/provider-session"
TOML
    api_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || api_rc=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "openai"
model = "gpt-fixture"
max_context_size = 1048576
[models.selected.oauth]
storage = "file"
key = "oauth/model-session"
[providers.openai]
type = "openai"
base_url = "https://fixture.invalid/v1"
api_key = "PR987_PROVIDER_KEY_SENTINEL"
TOML
    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/model-session.json"
    oauth_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || oauth_rc=$?

    if [[ "$api_rc" -eq 0 && "$api_method" == "config:api-key" && \
          "$oauth_rc" -eq 0 && "$oauth_method" == "kimi-session" && \
          "$api_method$oauth_method" != *PR987_* ]]; then
        test_pass
    else
        test_fail "expected model auth precedence without secret output, got api=$api_rc/$api_method oauth=$oauth_rc/$oauth_method"
    fi
}

test_kimi_effective_dispatch_model_drives_health() {
    test_case "health validates the effective Kimi dispatch alias and its OAuth file"
    local root old_model had_model default_method pinned_rc=0 issue health_rc=0 health
    root="$TEST_TMP_DIR/kimi-effective-health"
    mkdir -p "$root/credentials"
    old_model="${OCTOPUS_KIMI_MODEL-}"
    had_model="${OCTOPUS_KIMI_MODEL+set}"
    unset OCTOPUS_KIMI_MODEL
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "ready"
[models.ready]
provider = "ready-provider"
model = "k3"
max_context_size = 1048576
[models."Pinned OAuth"]
provider = "oauth-provider"
model = "k3"
max_context_size = 1048576
[providers.ready-provider]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
[providers.oauth-provider]
type = "kimi"
base_url = "https://fixture.invalid/v1"
[providers.oauth-provider.oauth]
storage = "file"
key = "oauth/missing-session"
TOML

    default_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)"
    KIMI_CODE_HOME="$root" OCTOPUS_KIMI_MODEL="Pinned OAuth" \
        kimi_configured_credential_method >/dev/null 2>&1 || pinned_rc=$?
    issue="$(KIMI_CODE_HOME="$root" OCTOPUS_KIMI_MODEL="Pinned OAuth" \
        kimi_credential_issue 2>/dev/null || true)"
    health="$(KIMI_CODE_HOME="$root" check_provider_health kimi "Pinned OAuth" 2>&1)" || health_rc=$?

    if [[ "$had_model" == set ]]; then OCTOPUS_KIMI_MODEL="$old_model"; else unset OCTOPUS_KIMI_MODEL; fi
    if [[ "$default_method" == "config:api-key" && "$pinned_rc" -ne 0 && \
          "$issue" == "oauth-invalid" && "$health_rc" -ne 0 && "$health" == *"/login"* ]]; then
        test_pass
    else
        test_fail "expected pinned OAuth failure before dispatch, got default=$default_method pinned=$pinned_rc issue=$issue health=$health_rc/$health"
    fi
}

test_kimi_dangling_default_rejects_credentialed_pin() {
    test_case "dangling default_model blocks a complete credentialed Kimi pin"
    local root helper_rc=0 health_rc=0 issue
    root="$PROJECT_ROOT/tests/fixtures/kimi-dangling-default"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    KIMI_CODE_HOME="$root" OCTOPUS_KIMI_MODEL="Pinned Complete" \
        kimi_configured_credential_method >/dev/null 2>&1 || helper_rc=$?
    KIMI_CODE_HOME="$root" check_provider_health kimi "Pinned Complete" \
        >/dev/null 2>&1 || health_rc=$?
    issue="$(KIMI_CODE_HOME="$root" OCTOPUS_KIMI_MODEL="Pinned Complete" \
        kimi_credential_issue 2>/dev/null || true)"

    if [[ "$helper_rc" -ne 0 && "$health_rc" -ne 0 && "$issue" == config-invalid ]]; then
        test_pass
    else
        test_fail "dangling default passed helper or health: helper=$helper_rc health=$health_rc issue=$issue"
    fi
}

test_kimi_routing_parser_accepts_multiline_quote_endings() {
    test_case "routing parser accepts Kimi-valid multiline strings ending in one or two quotes"
    local tmp_bin root suffix method rc failures=""
    tmp_bin="$TEST_TMP_DIR/kimi-bin-multiline-quotes"
    mkdir -p "$tmp_bin"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        _kimi_emit_test_runtime_env
        cat <<'MOCK'
case "${1:-}" in
    __plugin_run_node)
        shift
        exec "${KIMI_TEST_NODE:?}" "$@"
        ;;
    doctor)
        exit 0
        ;;
    provider)
        [[ "${2:-}" == list && "${3:-}" == --json ]] || exit 1
        printf '%s\n' '{"providers":{"kimi":{"type":"kimi","baseUrl":"https://fixture.invalid/v1","apiKey":"fixture-not-a-secret"}},"models":{"selected":{"provider":"kimi","model":"k3","maxContextSize":1048576}}}'
        ;;
    *) exit 1 ;;
esac
MOCK
    } > "$tmp_bin/kimi"
    chmod +x "$tmp_bin/kimi"

    for suffix in four five; do
        root="$TEST_TMP_DIR/kimi-multiline-$suffix"
        mkdir -p "$root"
        if [[ "$suffix" == four ]]; then
            printf '%s\n' 'default_model = "selected"' 'description = """ends with one quote""""' > "$root/config.toml"
        else
            printf '%s\n' 'default_model = "selected"' 'description = """ends with two quotes"""""' > "$root/config.toml"
        fi
        cat >> "$root/config.toml" <<'TOML'
[models.selected]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
        rc=0
        method="$(PATH="$tmp_bin:$PATH" KIMI_CODE_HOME="$root" \
            kimi_configured_credential_method 2>/dev/null)" || rc=$?
        [[ "$rc" -eq 0 && "$method" == "config:api-key" ]] || failures="$failures $suffix=$rc/$method"
    done

    if [[ -z "$failures" ]]; then
        test_pass
    else
        test_fail "Kimi-valid multiline quote endings were rejected:$failures"
    fi
}

test_kimi_whitespace_alias_dispatch_is_safe() {
    test_case "whitespace Kimi aliases survive validation, isolation, splitting, and shim argv"
    local tmp_bin capture marker old_path old_model had_model model cmd output="" rc=1 malicious_rc=0
    local word_count=0
    local command_valid=false
    local -a inner_cmd_array cmd_array
    tmp_bin="$TEST_TMP_DIR/kimi-bin-whitespace-alias"
    capture="$tmp_bin/argv"
    marker="$TEST_TMP_DIR/never-octopus-kimi"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/kimi" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${0%/*}/argv"
printf '%s\n' "whitespace alias dispatched"
MOCK
    chmod +x "$tmp_bin/kimi"
    old_path="$PATH"
    old_model="${OCTOPUS_KIMI_MODEL-}"
    had_model="${OCTOPUS_KIMI_MODEL+set}"
    PATH="$tmp_bin:$PATH"
    OCTOPUS_KIMI_MODEL="Team Model"
    export PATH OCTOPUS_KIMI_MODEL
    source "$PROJECT_ROOT/scripts/lib/utils.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"

    model="$(get_agent_model kimi 2>/dev/null || true)"
    cmd="$(get_agent_command kimi tangle implementer 2>/dev/null || true)"
    build_provider_env kimi
    if [[ -n "$cmd" ]]; then
        read -r -a inner_cmd_array <<< "$cmd"
        word_count=${#inner_cmd_array[@]}
        cmd_array=("${PROVIDER_ENV_ARRAY[@]}" "${inner_cmd_array[@]}")
        validate_agent_command "$cmd" && command_valid=true
        rc=0
        output="$(printf '%s' probe | "${cmd_array[@]}" 2>&1)" || rc=$?
    fi

    OCTOPUS_KIMI_MODEL="Team Model;touch $marker"
    get_agent_model kimi >/dev/null 2>&1 || malicious_rc=$?
    PATH="$old_path"
    if [[ "$had_model" == set ]]; then OCTOPUS_KIMI_MODEL="$old_model"; else unset OCTOPUS_KIMI_MODEL; fi

    if [[ "$model" == "Team Model" && -n "$cmd" && "$cmd" != *"Team Model"* && \
          "$word_count" -eq 3 && "${PROVIDER_ENV_ARRAY[0]:-}" == env && \
          "${PROVIDER_ENV_ARRAY[1]:-}" == -i && "$command_valid" == true && \
          "$rc" -eq 0 && "$output" == "whitespace alias dispatched" && \
          "$(grep -A1 -x -- '--model' "$capture" | tail -1)" == "Team Model" && \
          "$malicious_rc" -ne 0 && ! -e "$marker" ]]; then
        test_pass
    else
        test_fail "whitespace alias did not round-trip safely: model=$model words=$word_count rc=$rc malicious=$malicious_rc"
    fi
}

test_kimi_shim_validates_encoded_and_plaintext_models() {
    test_case "Kimi shim validates encoded and direct model names before array dispatch"
    local tmp_bin capture old_path encoded value rc failures=""
    tmp_bin="$TEST_TMP_DIR/kimi-bin-model-transport"
    capture="$tmp_bin/argv"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/kimi" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${0%/*}/argv"
printf '%s\n' "model transport dispatched"
MOCK
    chmod +x "$tmp_bin/kimi"
    old_path="$PATH"
    PATH="$tmp_bin:$PATH"

    for encoded in "" 00 0a 0a41 3b 20 09 64656661756c74; do
        rc=0
        OCTOPUS_KIMI_MODEL_HEX="$encoded" /bin/bash \
            "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || rc=$?
        [[ "$rc" -eq 64 ]] || failures="$failures hex-$encoded=$rc"
    done

    rc=0
    OCTOPUS_KIMI_MODEL_HEX=5465616d204d6f64656c OCTOPUS_KIMI_MODEL="Other Model" \
        /bin/bash "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -ne 0 ]] || \
       [[ "$(grep -A1 -x -- '--model' "$capture" | tail -1)" != "Team Model" ]]; then
        failures="$failures encoded-authority=$rc"
    fi

    for encoded in 5465616d204d6f64656c 5465616d094d6f64656c; do
        rc=0
        OCTOPUS_KIMI_MODEL_HEX="$encoded" /bin/bash \
            "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || rc=$?
        if [[ "$rc" -ne 0 ]] || ! grep -A1 -x -- '--model' "$capture" | tail -1 | \
            grep -q "^$([[ "$encoded" == *09* ]] && printf 'Team\tModel' || printf 'Team Model')$"; then
            failures="$failures valid-hex-$encoded=$rc"
        fi
    done

    for value in "" " " $'\t' $'A\nB' $'A\rB' ';' 'A|B' 'A&B' 'A$B' 'A`B' \
        "A'B" 'A"B' 'A(B)' 'A<B' 'A>B' 'A!B' 'A?B' 'A[B' 'A]B' 'A{B' 'A}B' \
        'A*B' 'A\B' '/absolute/model'; do
        rc=0
        OCTOPUS_KIMI_MODEL="$value" /bin/bash \
            "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || rc=$?
        [[ "$rc" -eq 64 ]] || failures="$failures plaintext-$(printf '%s' "$value" | od -An -v -tx1 | tr -d '[:space:]')=$rc"
    done

    for value in "Team Model" $'Team\tModel'; do
        rc=0
        OCTOPUS_KIMI_MODEL="$value" /bin/bash \
            "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || rc=$?
        if [[ "$rc" -ne 0 ]] || ! grep -A1 -x -- '--model' "$capture" | tail -1 | grep -Fqx "$value"; then
            failures="$failures valid-plaintext=$rc"
        fi
    done

    PATH="$old_path"
    if [[ -z "$failures" ]]; then
        test_pass
    else
        test_fail "Kimi model transport validation failures:$failures"
    fi
}

test_kimi_default_provider_and_flat_model_readiness() {
    test_case "default_provider inheritance and flat model credentials match Kimi runtime"
    local root inherited_rc=0 flat_key_rc=0 flat_oauth_rc=0 explicit_rc=0
    local inherited_method flat_key_method flat_oauth_method explicit_method
    root="$TEST_TMP_DIR/kimi-model-resolution-shapes"
    mkdir -p "$root/credentials"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    cat > "$root/config.toml" <<'TOML'
default_provider = "openai"
default_model = "selected"
[models.selected]
model = "gpt-fixture"
max_context_size = 1048576
[models.unselected]
model = "other-fixture"
max_context_size = 1048576
[providers.openai]
type = "openai"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    inherited_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || inherited_rc=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
model = "gpt-fixture"
protocol = "openai"
base_url = "https://fixture.invalid/v1"
api_key = "PR987_FLAT_KEY_SENTINEL"
max_context_size = 1048576
TOML
    flat_key_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || flat_key_rc=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
model = "gpt-fixture"
protocol = "openai"
base_url = "https://fixture.invalid/v1"
max_context_size = 1048576
[models.selected.oauth]
storage = "file"
key = "oauth/flat-session"
TOML
    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/flat-session.json"
    flat_oauth_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || flat_oauth_rc=$?

    cat > "$root/config.toml" <<'TOML'
default_provider = "unused"
default_model = "selected"
[models.selected]
provider = "openai"
model = "gpt-fixture"
max_context_size = 1048576
[providers.openai]
type = "openai"
api_key = "fixture-not-a-secret"
TOML
    explicit_method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || explicit_rc=$?

    if [[ "$inherited_rc" -eq 0 && "$inherited_method" == "config:api-key" && \
          "$flat_key_rc" -eq 0 && "$flat_key_method" == "config:api-key" && \
          "$flat_oauth_rc" -eq 0 && "$flat_oauth_method" == "kimi-session" && \
          "$explicit_rc" -eq 0 && "$explicit_method" == "config:api-key" && \
          "$flat_key_method$flat_oauth_method" != *PR987_* ]]; then
        test_pass
    else
        test_fail "expected inherited/flat/explicit readiness, got inherited=$inherited_rc/$inherited_method flat-key=$flat_key_rc/$flat_key_method flat-oauth=$flat_oauth_rc/$flat_oauth_method explicit=$explicit_rc/$explicit_method"
    fi
}

test_kimi_rejects_malformed_or_duplicate_toml() {
    test_case "readiness fails closed on malformed and duplicate TOML assignments"
    local root rc_bare rc_boolean rc_trailing rc_duplicate rc_document
    local rc_quoted_duplicate rc_table_duplicate rc_parser_missing parser_issue
    local broken_bin old_path
    root="$TEST_TMP_DIR/kimi-malformed-config"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = fixture-not-a-secret
TOML
    rc_bare=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_bare=$?

    sed 's/api_key = fixture-not-a-secret/api_key = false/' "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_boolean=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_boolean=$?

    sed 's/api_key = false/api_key = "fixture-not-a-secret" trailing/' "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_trailing=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_trailing=$?

    awk 'NR == 1 { print; print "default_model = \"custom\""; next } { print }' \
        "$root/config.toml" > "$root/config.next"
    mv "$root/config.next" "$root/config.toml"
    rc_duplicate=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_duplicate=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
this is not valid TOML
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_document=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_document=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
"default_model" = "other"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_quoted_duplicate=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_quoted_duplicate=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
[models."custom"]
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_table_duplicate=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_table_duplicate=$?

    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    broken_bin="$TEST_TMP_DIR/kimi-bin-no-plugin-runtime"
    mkdir -p "$broken_bin"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$broken_bin/kimi"
    chmod +x "$broken_bin/kimi"
    old_path="$PATH"
    PATH="$broken_bin:$PATH"
    rc_parser_missing=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_parser_missing=$?
    parser_issue="$(KIMI_CODE_HOME="$root" kimi_credential_issue 2>/dev/null || true)"
    PATH="$old_path"

    if [[ "$rc_bare" -ne 0 && "$rc_boolean" -ne 0 && "$rc_trailing" -ne 0 && "$rc_duplicate" -ne 0 ]]; then
        if [[ "$rc_document" -ne 0 && "$rc_quoted_duplicate" -ne 0 && \
              "$rc_table_duplicate" -ne 0 && "$rc_parser_missing" -ne 0 && \
              "$parser_issue" == "validator-unavailable" ]]; then
            test_pass
        else
            test_fail "expected full-document and parser fail-closed rejection, got document=$rc_document quoted=$rc_quoted_duplicate table=$rc_table_duplicate parser=$rc_parser_missing issue=$parser_issue"
        fi
    else
        test_fail "expected malformed config rejection, got bare=$rc_bare boolean=$rc_boolean trailing=$rc_trailing duplicate=$rc_duplicate"
    fi
}

test_kimi_validates_unselected_records() {
    test_case "readiness rejects a schema-invalid unselected record"
    local root rc issue readiness
    root="$TEST_TMP_DIR/kimi-invalid-unselected-record"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "selected"
model = "model"
max_context_size = 1048576
[providers.selected]
type = "kimi"
api_key = "fixture-not-a-secret"
[providers.unselected]
type = 42
TOML
    rc=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc=$?
    issue="$(KIMI_CODE_HOME="$root" kimi_credential_issue 2>/dev/null || true)"
    readiness="$(PROJECT_ROOT="$PROJECT_ROOT" KIMI_CODE_HOME="$root" /bin/bash -c '
        source "$PROJECT_ROOT/scripts/lib/preflight.sh"
        _octo_provider_static_readiness kimi
    ')"
    if [[ "$rc" -ne 0 && "$issue" == "config-invalid" && \
          "$readiness" == degraded\|config-invalid\|* ]]; then
        test_pass
    else
        test_fail "expected full-document rejection, got rc=$rc issue=$issue readiness=$readiness"
    fi
}

test_kimi_rejects_dangling_unselected_provider_reference() {
    test_case "readiness rejects an unselected model whose provider does not exist"
    local root rc rc_inherited issue
    root="$TEST_TMP_DIR/kimi-dangling-unselected-provider"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "selected"
model = "model"
max_context_size = 1048576
[models.unselected]
provider = "missing"
model = "other"
max_context_size = 1048576
[providers.selected]
type = "kimi"
api_key = "fixture-not-a-secret"
TOML
    rc=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc=$?
    cat > "$root/config.toml" <<'TOML'
default_provider = "missing"
default_model = "selected"
[models.selected]
provider = "selected"
model = "model"
max_context_size = 1048576
[models.unselected]
model = "other"
max_context_size = 1048576
[providers.selected]
type = "kimi"
api_key = "fixture-not-a-secret"
TOML
    rc_inherited=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_inherited=$?
    issue="$(KIMI_CODE_HOME="$root" kimi_credential_issue 2>/dev/null || true)"
    if [[ "$rc" -ne 0 && "$rc_inherited" -ne 0 && "$issue" == "config-invalid" ]]; then
        test_pass
    else
        test_fail "expected explicit/inherited dangling rejection, got explicit=$rc inherited=$rc_inherited issue=$issue"
    fi
}

test_kimi_rejects_mixed_provider_auth() {
    test_case "readiness rejects model or provider API keys mixed with OAuth"
    local root rc_direct rc_env rc_unselected rc_model issue
    root="$TEST_TMP_DIR/kimi-mixed-provider-auth"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "kimi"
model = "model"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
api_key = "fixture-not-a-secret"
[providers.kimi.oauth]
storage = "file"
key = "oauth/kimi-code"
TOML
    rc_direct=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_direct=$?
    sed '/api_key = /d' "$root/config.toml" > "$root/config.next"
    cat >> "$root/config.next" <<'TOML'
[providers.kimi.env]
KIMI_API_KEY = "fixture-not-a-secret"
TOML
    mv "$root/config.next" "$root/config.toml"
    rc_env=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_env=$?
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "selected"
model = "model"
max_context_size = 1048576
[providers.selected]
type = "kimi"
api_key = "fixture-not-a-secret"
[providers.unselected]
type = "openai"
api_key = "fixture-not-a-secret"
[providers.unselected.oauth]
storage = "file"
key = "oauth/other"
TOML
    rc_unselected=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_unselected=$?
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "kimi"
model = "model"
max_context_size = 1048576
api_key = "fixture-not-a-secret"
[models.selected.oauth]
storage = "file"
key = "oauth/model"
[providers.kimi]
type = "kimi"
TOML
    rc_model=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_model=$?
    issue="$(KIMI_CODE_HOME="$root" kimi_credential_issue 2>/dev/null || true)"
    if [[ "$rc_direct" -ne 0 && "$rc_env" -ne 0 && "$rc_unselected" -ne 0 && \
          "$rc_model" -ne 0 && "$issue" == "config-invalid" ]]; then
        test_pass
    else
        test_fail "expected mixed-auth rejection, got direct=$rc_direct env=$rc_env unselected=$rc_unselected model=$rc_model issue=$issue"
    fi
}

test_kimi_model_env_is_forwarded_and_drives_readiness() {
    test_case "documented KIMI_MODEL variables cross isolation and can provide readiness"
    local root entry expected_var found forwarded_count=0 found_extra=false method rc
    local -a expected_vars=(
        KIMI_MODEL_NAME KIMI_MODEL_API_KEY KIMI_MODEL_PROVIDER_TYPE
        KIMI_MODEL_BASE_URL KIMI_MODEL_MAX_CONTEXT_SIZE KIMI_MODEL_CAPABILITIES
        KIMI_MODEL_DISPLAY_NAME KIMI_MODEL_MAX_OUTPUT_SIZE KIMI_MODEL_REASONING_KEY
        KIMI_MODEL_THINKING_EFFORT KIMI_MODEL_ADAPTIVE_THINKING
        KIMI_MODEL_MAX_COMPLETION_TOKENS KIMI_MODEL_MAX_TOKENS
        KIMI_MODEL_TEMPERATURE KIMI_MODEL_TOP_P KIMI_MODEL_THINKING_KEEP
    )
    root="$TEST_TMP_DIR/kimi-model-env"
    mkdir -p "$root"
    export KIMI_CODE_HOME="$root"
    export KIMI_MODEL_NAME="fixture-model"
    export KIMI_MODEL_API_KEY="fixture-not-a-secret"
    export KIMI_MODEL_PROVIDER_TYPE="openai"
    export KIMI_MODEL_BASE_URL="https://fixture.invalid/v1"
    export KIMI_MODEL_MAX_CONTEXT_SIZE="262144"
    export KIMI_MODEL_CAPABILITIES="tool_use,thinking"
    export KIMI_MODEL_DISPLAY_NAME="Fixture"
    export KIMI_MODEL_MAX_OUTPUT_SIZE="4096"
    export KIMI_MODEL_REASONING_KEY="reasoning_content"
    export KIMI_MODEL_THINKING_EFFORT="high"
    export KIMI_MODEL_ADAPTIVE_THINKING="true"
    export KIMI_MODEL_MAX_COMPLETION_TOKENS="2048"
    export KIMI_MODEL_MAX_TOKENS="2048"
    export KIMI_MODEL_TEMPERATURE="0.3"
    export KIMI_MODEL_TOP_P="0.9"
    export KIMI_MODEL_THINKING_KEEP="all"
    KIMI_MODEL_UNDOCUMENTED_SECRET="must-not-cross"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    build_provider_env kimi
    for expected_var in "${expected_vars[@]}"; do
        found=false
        for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
            case "$entry" in "$expected_var="*) found=true; break ;; esac
        done
        [[ "$found" == true ]] && forwarded_count=$((forwarded_count + 1))
    done
    for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
        [[ "$entry" == KIMI_MODEL_UNDOCUMENTED_SECRET=* ]] && found_extra=true
    done
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0
    method="$(kimi_configured_credential_method 2>/dev/null)" || rc=$?
    for expected_var in "${expected_vars[@]}"; do unset "$expected_var"; done
    unset KIMI_MODEL_UNDOCUMENTED_SECRET KIMI_CODE_HOME
    if [[ "$forwarded_count" -eq "${#expected_vars[@]}" && "$found_extra" == false && \
          "$rc" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected exact env-model forwarding/readiness, got forwarded=$forwarded_count/${#expected_vars[@]} extra=$found_extra rc=$rc method=$method"
    fi
}

test_kimi_vertex_adc_fails_closed() {
    test_case "Vertex ADC is reported unsupported and its system credential path is isolated"
    local root entry forwarded=false issue base_url_issue readiness keyed_method keyed_rc
    root="$TEST_TMP_DIR/kimi-vertex-adc"
    mkdir -p "$root"
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "vertex"
model = "gemini-2.5-pro"
max_context_size = 1048576
[providers.vertex]
type = "vertexai"
[providers.vertex.env]
GOOGLE_CLOUD_PROJECT = "fixture-project"
GOOGLE_CLOUD_LOCATION = "us-central1"
TOML
    KIMI_CODE_HOME="$root"
    GOOGLE_APPLICATION_CREDENTIALS="$root/adc.json"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    build_provider_env kimi
    for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
        [[ "$entry" == GOOGLE_APPLICATION_CREDENTIALS=* ]] && forwarded=true
    done
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    issue="$(kimi_credential_issue 2>/dev/null || true)"
    readiness="$(PROJECT_ROOT="$PROJECT_ROOT" KIMI_CODE_HOME="$root" \
        GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS" /bin/bash -c '
            source "$PROJECT_ROOT/scripts/lib/preflight.sh"
            _octo_provider_static_readiness kimi
        ')"
    cat > "$root/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "vertex"
model = "gemini-2.5-pro"
max_context_size = 1048576
[providers.vertex]
type = "vertexai"
base_url = "https://us-central1-aiplatform.googleapis.com"
[providers.vertex.env]
GOOGLE_CLOUD_PROJECT = "fixture-project"
TOML
    base_url_issue="$(kimi_credential_issue 2>/dev/null || true)"
    printf '%s\n' 'VERTEXAI_API_KEY = "fixture-not-a-secret"' >> "$root/config.toml"
    keyed_rc=0
    keyed_method="$(kimi_configured_credential_method 2>/dev/null)" || keyed_rc=$?
    unset GOOGLE_APPLICATION_CREDENTIALS KIMI_CODE_HOME
    if [[ "$forwarded" == false && "$issue" == "vertex-adc-unsupported" && \
          "$base_url_issue" == "vertex-adc-unsupported" && \
          "$readiness" == degraded\|auth-unsupported\|*"VERTEXAI_API_KEY"* && \
          "$readiness" == *"GOOGLE_API_KEY"* && "$keyed_rc" -eq 0 && \
          "$keyed_method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected fail-closed ADC and provider-key fallback, got forwarded=$forwarded issue=$issue base_url_issue=$base_url_issue readiness=$readiness keyed=$keyed_rc/$keyed_method"
    fi
}

test_kimi_leading_dash_home_is_safe() {
    test_case "a relative KIMI_CODE_HOME beginning with a dash validates safely"
    local tmp_bin case_parent old_path old_pwd method rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-leading-dash"
    case_parent="$TEST_TMP_DIR/kimi-leading-dash"
    mkdir -p "$tmp_bin" "$case_parent/-kimi-home"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        _kimi_emit_test_runtime_env
        cat <<'MOCK'
case "${1:-}" in
    __plugin_run_node)
        shift
        exec "${KIMI_TEST_NODE:?}" "$@"
        ;;
    doctor)
        [[ "${3:-}" != -* ]] || exit 2
        exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "$@"
        ;;
    provider)
        exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "$@"
        ;;
esac
exit 1
MOCK
    } > "$tmp_bin/kimi"
    chmod +x "$tmp_bin/kimi"
    cat > "$case_parent/-kimi-home/config.toml" <<'TOML'
default_model = "selected"
[models.selected]
provider = "kimi"
model = "model"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
api_key = "fixture-not-a-secret"
TOML
    old_path="$PATH"; old_pwd="$PWD"
    PATH="$tmp_bin:$PATH"
    cd "$case_parent"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0
    method="$(KIMI_CODE_HOME=-kimi-home kimi_configured_credential_method 2>/dev/null)" || rc=$?
    cd "$old_pwd"; PATH="$old_path"
    if [[ "$rc" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected safe leading-dash home, got rc=$rc method=$method"
    fi
}

test_kimi_fixture_and_docs_are_current() {
    test_case "Kimi tests need no Python and setup text has no stale keyring/MOONSHOT advice"
    if [[ -f "$PROJECT_ROOT/tests/fixtures/kimi-code-cli-mock.mjs" ]] && \
       [[ ! -e "$PROJECT_ROOT/tests/fixtures/kimi-code-cli-mock.py" ]] && \
       ! grep -q 'MOONSHOT_API_KEY' "$PROJECT_ROOT/CHANGELOG.md" && \
       ! grep -qi 'keyring.*migrat\|migrat.*keyring' "$PROJECT_ROOT/commands/model-config.md"; then
        test_pass
    else
        test_fail "expected Node-only fixture and current /login/provider credential guidance"
    fi
}

test_kimi_accepts_unrelated_array_tables() {
    test_case "readiness tolerates valid repeated array tables outside the selected records"
    local root method rc
    root="$TEST_TMP_DIR/kimi-array-tables"
    mkdir -p "$root"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
[[hooks]]
event = "PreToolUse"
command = "true"
[[hooks]]
event = "PostToolUse"
command = "true"
TOML
    rc=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc=$?
    if [[ "$rc" -eq 0 && "$method" == "config:api-key" ]]; then
        test_pass
    else
        test_fail "expected valid unrelated array tables to remain supported, got rc=$rc method=$method"
    fi
}

test_kimi_custom_root_oauth() {
    test_case "KIMI_CODE_HOME relocates config and its referenced OAuth credential"
    local tmp_bin old_path old_home old_root had_root auth rc_nested rc_flat
    tmp_bin="$TEST_TMP_DIR/kimi-bin-custom-root"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"; old_root="${KIMI_CODE_HOME-}"; had_root="${KIMI_CODE_HOME+set}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-unused-home"
    KIMI_CODE_HOME="$TEST_TMP_DIR/kimi-custom-root"
    unset KIMI_API_KEY
    mkdir -p "$KIMI_CODE_HOME/credentials/oauth"
    cat > "$KIMI_CODE_HOME/config.toml" <<'TOML'
default_model = "kimi-code/k3"
[models."kimi-code/k3"]
provider = "managed:kimi-code"
model = "k3"
max_context_size = 1048576
[providers."managed:kimi-code"]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
[providers."managed:kimi-code".oauth]
storage = "file"
key = "oauth/kimi-code"
TOML
    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$KIMI_CODE_HOME/credentials/oauth/kimi-code.json"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc_nested=0; kimi_is_available >/dev/null 2>&1 || rc_nested=$?
    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$KIMI_CODE_HOME/credentials/kimi-code.json"
    rc_flat=0; kimi_is_available >/dev/null 2>&1 || rc_flat=$?
    auth="$(kimi_auth_method)"
    PATH="$old_path"; HOME="$old_home"
    if [[ "$had_root" == set ]]; then KIMI_CODE_HOME="$old_root"; else unset KIMI_CODE_HOME; fi
    if [[ "$rc_nested" -ne 0 && "$rc_flat" -eq 0 && "$auth" == "kimi-session" ]]; then
        test_pass
    else
        test_fail "expected nested OAuth rejection and flat custom-root readiness, got nested=$rc_nested flat=$rc_flat auth=$auth"
    fi
}

test_kimi_oauth_requires_usable_json_object() {
    test_case "OAuth readiness requires a readable usable token object without exposing it"
    local root rc_unreadable rc_invalid rc_array rc_empty rc_partial rc_whitespace
    local rc_bad_expiry rc_valid method issue_invalid
    root="$TEST_TMP_DIR/kimi-oauth-validation"
    mkdir -p "$root/credentials"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "managed:kimi-code"
model = "k3"
max_context_size = 1048576
[providers."managed:kimi-code"]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
[providers."managed:kimi-code".oauth]
storage = "file"
key = "oauth/kimi-code"
TOML

    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/kimi-code.json"
    chmod 000 "$root/credentials/kimi-code.json"
    rc_unreadable=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_unreadable=$?
    chmod 600 "$root/credentials/kimi-code.json"
    printf '%s\n' 'not-json' > "$root/credentials/kimi-code.json"
    rc_invalid=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_invalid=$?
    issue_invalid="$(KIMI_CODE_HOME="$root" kimi_credential_issue 2>/dev/null || true)"
    printf '%s\n' '[]' > "$root/credentials/kimi-code.json"
    rc_array=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_array=$?
    printf '%s\n' '{}' > "$root/credentials/kimi-code.json"
    rc_empty=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_empty=$?
    printf '%s\n' '{"access_token":"PR987_TOKEN_SENTINEL"}' > "$root/credentials/kimi-code.json"
    rc_partial=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_partial=$?
    printf '%s\n' '{"access_token":"   ","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/kimi-code.json"
    rc_whitespace=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_whitespace=$?
    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":"not-a-number","scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/kimi-code.json"
    rc_bad_expiry=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_bad_expiry=$?
    printf '%s\n' '{"access_token":"PR987_TOKEN_SENTINEL","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/kimi-code.json"
    rc_valid=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc_valid=$?

    if [[ "$rc_unreadable" -ne 0 && "$rc_invalid" -ne 0 && \
          "$issue_invalid" == "oauth-invalid" && "$rc_array" -ne 0 && \
          "$rc_empty" -ne 0 && "$rc_partial" -ne 0 && \
          "$rc_whitespace" -ne 0 && "$rc_bad_expiry" -ne 0 && "$rc_valid" -eq 0 && \
          "$method" == "kimi-session" && \
          "$method" != *PR987_TOKEN_SENTINEL* ]]; then
        test_pass
    else
        test_fail "expected OAuth object validation, got unreadable=$rc_unreadable invalid=$rc_invalid issue=$issue_invalid array=$rc_array empty=$rc_empty partial=$rc_partial whitespace=$rc_whitespace expiry=$rc_bad_expiry valid=$rc_valid method=$method"
    fi
}

test_kimi_keyring_reference_requires_flat_file() {
    test_case "a legacy keyring OAuth declaration needs a usable flat credential file"
    local root rc_missing rc_file method issue readiness health health_rc
    root="$TEST_TMP_DIR/kimi-keyring-oauth"
    mkdir -p "$root/credentials"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
[providers.kimi.oauth]
storage = "keyring"
key = "oauth/kimi-code"
TOML
    rc_missing=0
    KIMI_CODE_HOME="$root" kimi_configured_credential_method >/dev/null 2>&1 || rc_missing=$?
    issue="$(KIMI_CODE_HOME="$root" kimi_credential_issue 2>/dev/null || true)"
    readiness="$(PROJECT_ROOT="$PROJECT_ROOT" KIMI_CODE_HOME="$root" \
        /bin/bash -c '
            source "$PROJECT_ROOT/scripts/lib/preflight.sh"
            _octo_provider_static_readiness kimi
        ')"
    health_rc=0
    health="$(PROJECT_ROOT="$PROJECT_ROOT" KIMI_CODE_HOME="$root" \
        /bin/bash -c '
            source "$PROJECT_ROOT/scripts/lib/providers.sh"
            check_provider_health kimi
        ' 2>&1)" || health_rc=$?
    printf '%s\n' '{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_at":4102444800,"scope":"fixture","token_type":"Bearer","expires_in":3600}' > "$root/credentials/kimi-code.json"
    rc_file=0
    method="$(KIMI_CODE_HOME="$root" kimi_configured_credential_method 2>/dev/null)" || rc_file=$?
    if [[ "$rc_missing" -ne 0 && "$issue" == "keyring-migration-required" && \
          "$readiness" == degraded\|auth-migration-required\|*"/login"* && \
          "$readiness" != *"launch"* && \
          "$health_rc" -ne 0 && "$health" == *"/login"* && \
          "$health" != *"launch"* && \
          "$rc_file" -eq 0 && "$method" == "kimi-session" ]]; then
        test_pass
    else
        test_fail "expected actionable keyring migration state, got missing=$rc_missing issue=$issue readiness=$readiness health_rc=$health_rc health=$health file=$rc_file method=$method"
    fi
}

test_kimi_ambient_key_is_not_auth() {
    test_case "ambient KIMI_API_KEY alone is not reported as Kimi Code readiness"
    local tmp_bin old_path old_home old_key had_key rc auth
    tmp_bin="$TEST_TMP_DIR/kimi-bin-ambient-only"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"; old_key="${KIMI_API_KEY-}"; had_key="${KIMI_API_KEY+set}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-ambient-home"; unset KIMI_CODE_HOME
    mkdir -p "$HOME/.kimi-code"
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
TOML
    KIMI_API_KEY="ambient-fixture-value"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh"
    rc=0; kimi_is_available >/dev/null 2>&1 || rc=$?
    auth="$(kimi_auth_method)"
    PATH="$old_path"; HOME="$old_home"; _kimi_restore_key "$had_key" "$old_key"
    if [[ "$rc" -ne 0 && "$auth" == "none" ]]; then
        test_pass
    else
        test_fail "expected ambient-only auth rejection, got rc=$rc auth=$auth"
    fi
}

test_kimi_static_preflight_uses_config() {
    test_case "static preflight reports config readiness and an actionable auth failure"
    local tmp_bin home output missing
    tmp_bin="$TEST_TMP_DIR/kimi-bin-preflight"; home="$TEST_TMP_DIR/kimi-preflight-home"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    mkdir -p "$home/.kimi-code"
    cat > "$home/.kimi-code/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    output="$(HOME="$home" PATH="$tmp_bin:$PATH" OCTO_ALLOWED_PROVIDERS=kimi /bin/bash -c '
        unset KIMI_CODE_HOME KIMI_API_KEY
        source "'$PROJECT_ROOT'/scripts/lib/preflight.sh"
        _octo_provider_static_readiness kimi
    ')"
    sed 's/fixture-not-a-secret//g' "$home/.kimi-code/config.toml" > "$home/.kimi-code/config.next"
    mv "$home/.kimi-code/config.next" "$home/.kimi-code/config.toml"
    missing="$(HOME="$home" PATH="$tmp_bin:$PATH" OCTO_ALLOWED_PROVIDERS=kimi /bin/bash -c '
        unset KIMI_CODE_HOME
        KIMI_API_KEY=ambient-fixture-value
        source "'$PROJECT_ROOT'/scripts/lib/preflight.sh"
        _octo_provider_static_readiness kimi
    ')"
    if [[ "$output" == "available|ready|" ]] && \
       [[ "$missing" == degraded\|auth-missing\|*"$home/.kimi-code/config.toml"* ]] && \
       [[ "$missing" == *"Shell-only API keys are not read automatically"* ]] && \
       [[ "$missing" != *ambient-fixture-value* ]]; then
        test_pass
    else
        test_fail "unexpected ready='$output' missing='$missing'"
    fi
}

test_kimi_real_health_uses_custom_root() {
    test_case "real Kimi health check consumes config from KIMI_CODE_HOME"
    local tmp_bin root output rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-health"; root="$TEST_TMP_DIR/kimi-health-root"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    mkdir -p "$root"
    cat > "$root/config.toml" <<'TOML'
default_model = "custom"
[models.custom]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc=0
    output="$(HOME="$TEST_TMP_DIR/kimi-health-home" KIMI_CODE_HOME="$root" \
        PATH="$tmp_bin:$PATH" /bin/bash -c '
            unset KIMI_API_KEY
            source "'$PROJECT_ROOT'/scripts/lib/providers.sh"
            check_provider_health kimi
        ' 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 && -z "$output" ]]; then
        test_pass
    else
        test_fail "expected silent healthy result, got rc=$rc output=$output"
    fi
}

test_kimi_install_and_model_display() {
    test_case "real dependency check and model display provide Kimi guidance"
    local dep_output legacy_output legacy_bin model_output model_home
    model_home="$TEST_TMP_DIR/kimi-model-display"
    dep_output="$(HOME="$TEST_TMP_DIR/kimi-deps-home" PATH="/usr/bin:/bin" \
        /bin/bash "$PROJECT_ROOT/scripts/install-deps.sh" check 2>&1 || true)"
    model_output="$(HOME="$model_home" OCTOPUS_KIMI_MODEL="kimi-code/k3" \
        /bin/bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" list 2>&1)"
    legacy_bin="$TEST_TMP_DIR/kimi-legacy-bin"
    _kimi_mock_bin "$legacy_bin" '[[ "${1:-}" == "--version" ]] && printf "%s\n" "kimi, version 1.49.0"'
    legacy_output="$(HOME="$TEST_TMP_DIR/kimi-legacy-home" PATH="$legacy_bin:/usr/bin:/bin" \
        /bin/bash "$PROJECT_ROOT/scripts/install-deps.sh" check 2>&1 || true)"
    if [[ "$dep_output" == *"code.kimi.com/kimi-code/install.sh"* ]] && \
       [[ "$dep_output" == *"run kimi and enter /login"* ]] && \
       [[ "$legacy_output" == *"Legacy kimi-cli detected"* ]] && \
       [[ "$legacy_output" == *"code.kimi.com/kimi-code/install.sh"* ]] && \
       [[ "$legacy_output" == *"kimi migrate"* ]] && \
       [[ "$legacy_output" == *"OAuth is not migrated"* ]] && \
       [[ "$model_output" == *"OCTOPUS_KIMI_MODEL=kimi-code/k3"* ]]; then
        test_pass
    else
        test_fail "Kimi dependency or model-display guidance missing"
    fi
}

test_kimi_user_guidance_contracts() {
    test_case "install, model-config, provider, and generated-doc sources teach Kimi setup"
    if grep -q 'code.kimi.com/kimi-code/install.sh' "$PROJECT_ROOT/scripts/install-deps.sh" && \
       grep -q 'OCTOPUS_KIMI_MODEL' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" && \
       grep -q 'printf "kimi:%s' "$PROJECT_ROOT/commands/model-config.md" && \
       grep -q 'Kimi Code integration' "$PROJECT_ROOT/docs/PROVIDERS.md" && \
       grep -q "Kimi Code's own runtime" "$PROJECT_ROOT/docs/PROVIDERS.md" && \
       grep -q 'enter `/login`' "$PROJECT_ROOT/docs/PROVIDERS.md" && \
       ! grep -q 'bundled Python runtime' "$PROJECT_ROOT/docs/PROVIDERS.md" && \
       grep -q 'Kimi Code CLI' "$PROJECT_ROOT/scripts/sync-readme.py"; then
        test_pass
    else
        test_fail "Kimi install/config/provider/generated-doc guidance is incomplete"
    fi
}

# ── 4. config-file model resolves and reaches the shim as --model ─────────────
test_kimi_config_runtime_model() {
    test_case "providers.json kimi model resolves and kimi-exec.sh emits --model"
    local tmp_bin capture config_home old_path old_home resolved
    tmp_bin="$TEST_TMP_DIR/kimi-bin"; capture="$TEST_TMP_DIR/kimi-argv.txt"; config_home="$TEST_TMP_DIR/kimi-home"
    mkdir -p "$config_home/.claude-octopus/config"
    _kimi_mock_bin "$tmp_bin" 'printf "%s\n" "$@" > "${KIMI_ARG_CAPTURE:?}"; exit 0'
    cat > "$config_home/.claude-octopus/config/providers.json" <<'JSON'
{"providers":{"kimi":{"default":"kimi-k2.5"}}}
JSON
    old_path="$PATH"; old_home="$HOME"
    PATH="$tmp_bin:$PATH"; export KIMI_ARG_CAPTURE="$capture"
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true

    HOME="$config_home"
    resolved="$(resolve_octopus_model kimi kimi "" "" 2>/dev/null || true)"
    HOME="$old_home"
    if [[ "$resolved" != "kimi-k2.5" ]]; then
        PATH="$old_path"; unset KIMI_ARG_CAPTURE
        test_fail "config providers.json kimi model should resolve to kimi-k2.5, got: '$resolved'"
        return
    fi

    OCTOPUS_KIMI_MODEL="kimi-k2.5" bash "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || true
    PATH="$old_path"; unset KIMI_ARG_CAPTURE
    if grep -Fxq -- '--model' "$capture" && grep -Fxq -- 'kimi-k2.5' "$capture"; then
        test_pass
    else
        test_fail "kimi-exec.sh should pass the resolved model as --model; argv: $(tr '\n' ' ' < "$capture" 2>/dev/null)"
    fi
}

# ── 5. "default" model => no --model flag ─────────────────────────────────────
test_kimi_default_no_model() {
    test_case "OCTOPUS_KIMI_MODEL=default is not passed to kimi --model"
    local tmp_bin capture old_path
    tmp_bin="$TEST_TMP_DIR/kimi-bin-def"; capture="$TEST_TMP_DIR/kimi-argv-def.txt"
    _kimi_mock_bin "$tmp_bin" 'printf "%s\n" "$@" > "${KIMI_ARG_CAPTURE:?}"; exit 0'
    old_path="$PATH"; PATH="$tmp_bin:$PATH"; export KIMI_ARG_CAPTURE="$capture"
    OCTOPUS_KIMI_MODEL="default" bash "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" <<<"probe" >/dev/null 2>&1 || true
    PATH="$old_path"; unset KIMI_ARG_CAPTURE
    if grep -q -- '--model' "$capture"; then
        test_fail "default should not be passed to kimi --model; argv: $(tr '\n' ' ' < "$capture" 2>/dev/null)"
    else
        test_pass
    fi
}

# ── 6. empty stdin is rejected before exec ────────────────────────────────────
test_kimi_shim_requires_prompt() {
    test_case "kimi-exec.sh rejects empty stdin with exit 64"
    local rc=0
    printf '' | bash "$PROJECT_ROOT/scripts/helpers/kimi-exec.sh" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq 64 ]]; then test_pass; else test_fail "expected exit 64, got $rc"; fi
}

# ── 7. non-zero exit propagates even with stdout ──────────────────────────────
test_kimi_exit_propagation() {
    test_case "kimi_execute returns non-zero when kimi exits non-zero (even with stdout)"
    local tmp_bin old_path rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-fail"
    _kimi_mock_bin "$tmp_bin" 'printf "partial answer before crash\n"; exit 3'
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true
    rc=0
    kimi_execute kimi "probe" >/dev/null 2>&1 || rc=$?
    PATH="$old_path"
    if [[ "$rc" -ne 0 ]]; then
        test_pass
    else
        test_fail "kimi_execute masked a non-zero exit (returned 0) despite kimi exiting 3"
    fi
}

test_kimi_direct_env_isolation() {
    test_case "kimi_execute removes unrelated parent secrets by default"
    local tmp_bin old_path output rc=0
    tmp_bin="$TEST_TMP_DIR/kimi-bin-direct-env"
    _kimi_mock_bin "$tmp_bin" 'printf "%s\n" "${UNRELATED_KIMI_SECRET-unset}"'
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true
    output="$(UNRELATED_KIMI_SECRET=must-not-cross kimi_execute kimi "probe" 2>/dev/null)" || rc=$?
    PATH="$old_path"
    if [[ "$rc" -eq 0 && "$output" == "unset" ]]; then
        test_pass
    else
        test_fail "expected isolated direct execution, got rc=$rc output='$output'"
    fi
}

test_kimi_stderr_auth_classification() {
    test_case "kimi_execute classifies stderr-only auth failures"
    local tmp_bin old_path output rc=0
    tmp_bin="$TEST_TMP_DIR/kimi-bin-auth-stderr"
    _kimi_mock_bin "$tmp_bin" 'printf "Login required: token expired\n" >&2; exit 1'
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true
    log() { printf '[%s] %s\n' "$1" "${*:2}" >&2; }

    output="$(kimi_execute kimi "probe" 2>&1)" || rc=$?
    log() { :; }
    PATH="$old_path"

    if [[ "$rc" -ne 0 && "$output" == *"kimi: auth failure"* && "$output" != *"kimi: exit 1"* ]]; then
        test_pass
    else
        test_fail "expected stderr-only auth guidance, got rc=$rc output='$output'"
    fi
}

test_kimi_success_stderr_is_not_response() {
    test_case "kimi_execute discards successful stderr instead of exposing it as response or diagnostics"
    local tmp_bin old_path output_file stderr_file rc=0 response stdout_response call_output
    tmp_bin="$TEST_TMP_DIR/kimi-bin-success-stderr"
    output_file="$TEST_TMP_DIR/kimi-success.out"
    stderr_file="$TEST_TMP_DIR/kimi-success.err"
    _kimi_mock_bin "$tmp_bin" 'printf "provider diagnostic\n" >&2; printf "answer\n"; exit 0'
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true

    stdout_response="$(kimi_execute kimi "probe" 2>"$stderr_file")" || rc=$?
    call_output="$(kimi_execute kimi "probe" "$output_file" 2>"$stderr_file")" || rc=$?
    PATH="$old_path"
    response="$(< "$output_file")"

    if [[ "$rc" -eq 0 && "$stdout_response" == "answer" && -z "$call_output" &&
          "$response" == "answer" && "$response" != *"provider diagnostic"* &&
          ! -s "$stderr_file" ]]; then
        test_pass
    else
        test_fail "expected successful stderr to be discarded in both output modes, got rc=$rc stdout='$stdout_response' file-call-stdout='$call_output' response='$response' caller-stderr-bytes=$(wc -c < "$stderr_file" | tr -d ' ')"
    fi
}

test_kimi_interruption_cleans_private_captures() {
    test_case "kimi_execute removes private captures before preserving default TERM semantics"
    local case_dir="$TEST_TMP_DIR/kimi-interrupt-default"
    local tmp_bin="$case_dir/bin" harness="$case_dir/harness.sh"
    local started_file="$case_dir/kimi.pid" harness_pid="" kimi_pid="" rc=0
    local leaks="" kimi_alive=false attempt
    mkdir -p "$case_dir"
    _kimi_mock_bin "$tmp_bin" 'printf "%s\n" "$$" > "${KIMI_STARTED:?}"; trap "" TERM; exec /bin/sleep 30'
    cat > "$harness" <<'EOF'
#!/bin/bash
set -u
source "$PROJECT_ROOT/scripts/lib/kimi.sh"
log() { :; }
command() {
    if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
        return 1
    fi
    builtin command "$@"
}
OCTOPUS_ALLOW_FULL_KIMI_ENV=true OCTOPUS_KIMI_TIMEOUT=30 kimi_execute kimi "probe" >/dev/null 2>&1
EOF
    chmod +x "$harness"

    TMPDIR="$case_dir" PATH="$tmp_bin:$PATH" PROJECT_ROOT="$PROJECT_ROOT" \
        KIMI_STARTED="$started_file" /bin/bash "$harness" &
    harness_pid=$!
    for ((attempt=0; attempt<100; attempt++)); do
        [[ -s "$started_file" ]] && break
        sleep 0.05
    done
    if [[ -s "$started_file" ]]; then
        kimi_pid="$(< "$started_file")"
        kill -TERM "$harness_pid"
    else
        kill -KILL "$harness_pid" 2>/dev/null || true
    fi
    set +e
    wait "$harness_pid"
    rc=$?
    set -e
    sleep 0.2

    if [[ -n "$kimi_pid" ]] && kill -0 "$kimi_pid" 2>/dev/null; then
        local process_stat
        process_stat="$(/bin/ps -o stat= -p "$kimi_pid" 2>/dev/null | tr -d '[:space:]')"
        [[ -n "$process_stat" && "$process_stat" != Z* ]] && kimi_alive=true
    fi
    leaks="$(find "$case_dir" -maxdepth 1 \( -name 'octo-kimi-response.*' -o -name 'octo-kimi-error.*' -o -name 'octo-timeout.*' \) -print)"
    if [[ "$kimi_alive" == true ]]; then kill -KILL "$kimi_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 143 && -n "$kimi_pid" && "$kimi_alive" == false && -z "$leaks" ]]; then
        test_pass
    else
        test_fail "expected TERM rc=143, dead Kimi, and no private temp files; got rc=$rc pid=${kimi_pid:-missing}/$kimi_alive leaks='${leaks:-none}'"
    fi
}

test_kimi_interruption_restores_caller_trap() {
    test_case "kimi_execute restores a returning caller TERM trap and returns 143"
    local case_dir="$TEST_TMP_DIR/kimi-interrupt-trap"
    local tmp_bin="$case_dir/bin" harness="$case_dir/harness.sh"
    local started_file="$case_dir/kimi.pid" trap_hits="$case_dir/trap-hits"
    local before="$case_dir/trap-before" after="$case_dir/trap-after"
    local harness_pid="" kimi_pid="" rc=0 hit_count=0 leaks="" kimi_alive=false attempt
    mkdir -p "$case_dir"
    _kimi_mock_bin "$tmp_bin" 'printf "%s\n" "$$" > "${KIMI_STARTED:?}"; exec /bin/sleep 30'
    cat > "$harness" <<'EOF'
#!/bin/bash
set -u
source "$PROJECT_ROOT/scripts/lib/kimi.sh"
log() { :; }
command() {
    if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
        return 1
    fi
    builtin command "$@"
}
trap 'printf "TERM\n" >> "$TRAP_HITS"' TERM
trap -p TERM > "$TRAP_BEFORE"
set +e
OCTOPUS_ALLOW_FULL_KIMI_ENV=true OCTOPUS_KIMI_TIMEOUT=30 kimi_execute kimi "probe" >/dev/null 2>&1
rc=$?
set -e
trap -p TERM > "$TRAP_AFTER"
kill -TERM "$$"
exit "$rc"
EOF
    chmod +x "$harness"

    TMPDIR="$case_dir" PATH="$tmp_bin:$PATH" PROJECT_ROOT="$PROJECT_ROOT" KIMI_STARTED="$started_file" \
        TRAP_HITS="$trap_hits" TRAP_BEFORE="$before" TRAP_AFTER="$after" /bin/bash "$harness" &
    harness_pid=$!
    for ((attempt=0; attempt<100; attempt++)); do
        [[ -s "$started_file" ]] && break
        sleep 0.05
    done
    if [[ -s "$started_file" ]]; then
        kimi_pid="$(< "$started_file")"
        kill -TERM "$harness_pid"
    else
        kill -KILL "$harness_pid" 2>/dev/null || true
    fi
    set +e
    wait "$harness_pid"
    rc=$?
    set -e
    [[ -f "$trap_hits" ]] && hit_count="$(wc -l < "$trap_hits" | tr -d ' ')"
    sleep 0.2
    if [[ -n "$kimi_pid" ]] && kill -0 "$kimi_pid" 2>/dev/null; then
        local process_stat
        process_stat="$(/bin/ps -o stat= -p "$kimi_pid" 2>/dev/null | tr -d '[:space:]')"
        [[ -n "$process_stat" && "$process_stat" != Z* ]] && kimi_alive=true
    fi
    leaks="$(find "$case_dir" -maxdepth 1 \( -name 'octo-kimi-response.*' -o -name 'octo-kimi-error.*' -o -name 'octo-timeout.*' \) -print)"
    if [[ "$kimi_alive" == true ]]; then kill -KILL "$kimi_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 143 && "$hit_count" -eq 2 && -s "$before" && -s "$after" ]] &&
       cmp -s "$before" "$after" && [[ "$kimi_alive" == false && -z "$leaks" ]]; then
        test_pass
    else
        test_fail "expected rc=143, restored trap invoked twice, dead Kimi, and no temp files; got rc=$rc hits=$hit_count pid=${kimi_pid:-missing}/$kimi_alive leaks='${leaks:-none}'"
    fi
}

test_kimi_interruption_bypasses_system_timeout() {
    local timeout_name signal_name expected_status case_dir bin_dir harness
    local started_file completed_file used_file harness_rc leaks kimi_pid process_stat
    local kimi_alive

    for timeout_name in gtimeout timeout; do
        for signal_name in INT TERM; do
            expected_status=130
            [[ "$signal_name" == "TERM" ]] && expected_status=143
            test_case "kimi_execute uses the portable supervisor for $signal_name when $timeout_name is available"

            case_dir="$TEST_TMP_DIR/kimi-system-timeout-${timeout_name}-${signal_name}"
            bin_dir="$case_dir/bin"
            harness="$case_dir/harness.sh"
            started_file="$case_dir/kimi.pid"
            completed_file="$case_dir/kimi.completed"
            used_file="$case_dir/system-timeout.used"
            mkdir -p "$case_dir"
            _kimi_mock_bin "$bin_dir" 'printf "%s\n" "$$" > "${KIMI_STARTED:?}"; trap "" TERM; /bin/sleep 2; : > "${KIMI_COMPLETED:?}"; printf "late response\n"'
            _kimi_fake_system_timeout_bins "$bin_dir"
            cat > "$harness" <<'EOF'
#!/bin/bash
set -u
source "$PROJECT_ROOT/scripts/lib/kimi.sh"
log() { :; }
if [[ "$TIMEOUT_NAME" == "timeout" ]]; then
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "gtimeout" ]]; then
            return 1
        fi
        builtin command "$@"
    }
fi
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
run_with_timeout 2 /usr/bin/true >/dev/null 2>&1 || exit 90
[[ -s "$FAKE_TIMEOUT_USED" ]] || exit 91
rm -f "$FAKE_TIMEOUT_USED"
(
    _attempt=0
    while [[ "$_attempt" -lt 200 ]]; do
        [[ -s "$KIMI_STARTED" ]] && break
        sleep 0.01
        _attempt=$((_attempt + 1))
    done
    [[ -s "$KIMI_STARTED" ]] && kill -"$SIGNAL_NAME" "$$"
) &
OCTOPUS_ALLOW_FULL_KIMI_ENV=true OCTOPUS_KIMI_TIMEOUT=30 kimi_execute kimi "probe" >/dev/null 2>&1
EOF
            chmod +x "$harness"

            set +e
            TMPDIR="$case_dir" PATH="$bin_dir:/usr/bin:/bin" PROJECT_ROOT="$PROJECT_ROOT" \
                TIMEOUT_NAME="$timeout_name" SIGNAL_NAME="$signal_name" \
                KIMI_STARTED="$started_file" KIMI_COMPLETED="$completed_file" \
                FAKE_TIMEOUT_USED="$used_file" \
                /bin/bash "$harness" >/dev/null 2>&1
            harness_rc=$?
            set -e

            kimi_pid=""
            [[ -s "$started_file" ]] && kimi_pid="$(< "$started_file")"
            kimi_alive=false
            if [[ "$kimi_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$kimi_pid" 2>/dev/null; then
                process_stat="$(/bin/ps -o stat= -p "$kimi_pid" 2>/dev/null | tr -d '[:space:]')"
                [[ -n "$process_stat" && "$process_stat" != Z* ]] && kimi_alive=true
            fi
            leaks="$(find "$case_dir" -maxdepth 1 \( -name 'octo-kimi-response.*' -o -name 'octo-kimi-error.*' \) -print)"
            if [[ "$kimi_alive" == true ]]; then
                kill -KILL "$kimi_pid" 2>/dev/null || true
            fi

            if [[ "$harness_rc" -eq "$expected_status" && -n "$kimi_pid" &&
                  "$kimi_alive" == false && -z "$leaks" && ! -e "$used_file" &&
                  ! -e "$completed_file" ]]; then
                test_pass
            else
                test_fail "expected rc=$expected_status, killed provider, clean captures, and unused $timeout_name; got rc=$harness_rc pid=${kimi_pid:-missing}/$kimi_alive completed=$([[ -e "$completed_file" ]] && echo yes || echo no) leaks='${leaks:-none}' timeout-used=$([[ -e "$used_file" ]] && echo yes || echo no)"
            fi
        done
    done
}

# ── 8. request timeout uses the shared portable watchdog ─────────────────────
test_kimi_portable_timeout() {
    test_case "kimi_execute enforces its timeout without GNU/BSD timeout"
    local tmp_bin started_file old_path rc started_ms elapsed_ms
    tmp_bin="$TEST_TMP_DIR/kimi-bin-timeout"
    started_file="$TEST_TMP_DIR/kimi-timeout-started"
    _kimi_mock_bin "$tmp_bin" 'printf "started\n" > "${KIMI_TIMEOUT_STARTED:?}"; /bin/sleep 4; printf "late response\n"'
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    export KIMI_TIMEOUT_STARTED="$started_file"

    # Force the shared timeout implementation down its macOS-compatible
    # watchdog path while leaving the rest of PATH available to that watchdog.
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }

    started_ms="$("$KIMI_TEST_NODE" -e 'process.stdout.write(String(process.hrtime.bigint() / 1000000n))')"
    rc=0
    OCTOPUS_ALLOW_FULL_KIMI_ENV=true OCTOPUS_KIMI_TIMEOUT=1 kimi_execute kimi "probe" >/dev/null 2>&1 || rc=$?
    elapsed_ms=$(( $("$KIMI_TEST_NODE" -e 'process.stdout.write(String(process.hrtime.bigint() / 1000000n))') - started_ms ))

    unset -f command
    unset KIMI_TIMEOUT_STARTED
    PATH="$old_path"
    if [[ -s "$started_file" && "$rc" -ne 0 && "$elapsed_ms" -lt 3000 ]]; then
        test_pass
    else
        test_fail "expected a started, bounded non-zero result, got rc=$rc after ${elapsed_ms}ms"
    fi
}

# ── 9. an explicit model pin is sufficient model selection ───────────────────
test_kimi_pin_drives_readiness() {
    test_case "OCTOPUS_KIMI_MODEL selects a configured alias without default_model"
    local tmp_bin old_path old_home old_key had_key rc_pin_only rc_default
    tmp_bin="$TEST_TMP_DIR/kimi-bin-pin"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"; old_key="${KIMI_API_KEY-}"; had_key="${KIMI_API_KEY+set}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-pin-home"; mkdir -p "$HOME/.kimi-code"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true
    unset KIMI_API_KEY

    # Kimi's --model contract selects this alias directly; default_model is
    # consulted only when --model is omitted.
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
[models."Pinned Complete"]
provider = "kimi"
model = "kimi-k2.5"
max_context_size = 262144
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_pin_only=0; OCTOPUS_KIMI_MODEL="Pinned Complete" kimi_is_available >/dev/null 2>&1 || rc_pin_only=$?

    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "kimi-k2.5"
[models."kimi-k2.5"]
provider = "kimi"
model = "kimi-k2.5"
max_context_size = 262144
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_default=0; kimi_is_available >/dev/null 2>&1 || rc_default=$?

    PATH="$old_path"; HOME="$old_home"; _kimi_restore_key "$had_key" "$old_key"
    if [[ "$rc_pin_only" -eq 0 && "$rc_default" -eq 0 ]]; then
        test_pass
    else
        test_fail "expected pin-only=0 ($rc_pin_only) and default_model=0 ($rc_default)"
    fi
}

test_kimi_unknown_pin_is_not_a_model() {
    test_case "kimi_has_model rejects an explicit alias absent from config.models"
    local tmp_bin old_path old_home rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-unknown-pin"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-unknown-pin-home"
    mkdir -p "$HOME/.kimi-code"
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "known"
[models.known]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
api_key = "fixture-not-a-secret"
TOML
    rc=0
    OCTOPUS_KIMI_MODEL=missing kimi_has_model >/dev/null 2>&1 || rc=$?
    PATH="$old_path"; HOME="$old_home"
    if [[ "$rc" -ne 0 ]]; then
        test_pass
    else
        test_fail "unknown explicit alias was reported as a configured model"
    fi
}

test_kimi_readiness_env_isolation() {
    test_case "Kimi readiness strips unrelated provider credentials"
    local tmp_bin marker old_path root rc
    tmp_bin="$TEST_TMP_DIR/kimi-bin-readiness-env"
    marker="$TEST_TMP_DIR/kimi-readiness-env-leak"
    root="$TEST_TMP_DIR/kimi-readiness-env-root"
    mkdir -p "$tmp_bin" "$root"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        _kimi_emit_test_runtime_env
        printf 'KIMI_LEAK_MARKER=%q\n' "$marker"
        printf '%s\n' 'export KIMI_LEAK_MARKER'
        cat <<'MOCK'
if [[ -n "${UNRELATED_PROVIDER_SECRET:-}" ]]; then
    printf 'leaked\n' > "${KIMI_LEAK_MARKER:?}"
fi
case "${1:-}" in
    __plugin_run_node) shift; exec "${KIMI_TEST_NODE:?}" "$@" ;;
    doctor|provider) exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "$@" ;;
esac
exit 1
MOCK
    } > "$tmp_bin/kimi"
    chmod +x "$tmp_bin/kimi"
    cat > "$root/config.toml" <<'TOML'
default_model = "ready"
[models.ready]
provider = "kimi"
model = "k3"
max_context_size = 1048576
[providers.kimi]
type = "kimi"
api_key = "fixture-not-a-secret"
TOML
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    rc=0
    KIMI_CODE_HOME="$root" KIMI_LEAK_MARKER="$marker" \
        UNRELATED_PROVIDER_SECRET="must-not-leak" \
        kimi_configured_credential_method >/dev/null 2>&1 || rc=$?
    PATH="$old_path"
    if [[ "$rc" -eq 0 && ! -e "$marker" ]]; then
        test_pass
    else
        test_fail "readiness leaked an unrelated credential or failed: rc=$rc marker=$([[ -e "$marker" ]] && echo yes || echo no)"
    fi
}

test_kimi_readiness_timeout() {
    test_case "Kimi readiness bounds the plugin runner and its descendants"
    local tmp_bin started child_pid_file old_path rc started_ms elapsed_ms child_pid child_alive=false
    tmp_bin="$TEST_TMP_DIR/kimi-bin-readiness-timeout"
    started="$TEST_TMP_DIR/kimi-readiness-timeout-started"
    child_pid_file="$TEST_TMP_DIR/kimi-readiness-timeout-child"
    mkdir -p "$tmp_bin"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'KIMI_TIMEOUT_STARTED=%q\n' "$started"
        printf 'KIMI_TIMEOUT_CHILD=%q\n' "$child_pid_file"
        printf '%s\n' 'export KIMI_TIMEOUT_STARTED KIMI_TIMEOUT_CHILD'
        cat <<'MOCK'
if [[ "${1:-}" == __plugin_run_node ]]; then
    /bin/sleep 30 &
    printf '%s\n' "$!" > "${KIMI_TIMEOUT_CHILD:?}"
    printf 'started\n' > "${KIMI_TIMEOUT_STARTED:?}"
    wait
fi
exit 1
MOCK
    } > "$tmp_bin/kimi"
    chmod +x "$tmp_bin/kimi"
    old_path="$PATH"; PATH="$tmp_bin:$PATH"
    started_ms="$("$KIMI_TEST_NODE" -e 'process.stdout.write(String(Date.now()))')"
    rc=0
    KIMI_TIMEOUT_STARTED="$started" KIMI_TIMEOUT_CHILD="$child_pid_file" \
        OCTOPUS_KIMI_HEALTH_TIMEOUT=1 _kimi_run_config_check self-test \
        >/dev/null 2>&1 || rc=$?
    elapsed_ms=$(( $("$KIMI_TEST_NODE" -e 'process.stdout.write(String(Date.now()))') - started_ms ))
    PATH="$old_path"
    child_pid=""; [[ -s "$child_pid_file" ]] && child_pid="$(< "$child_pid_file")"
    if [[ "$child_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$child_pid" 2>/dev/null; then
        child_alive=true
        kill -KILL "$child_pid" 2>/dev/null || true
    fi
    if [[ "$rc" -ne 0 && -s "$started" && "$elapsed_ms" -lt 3000 && "$child_alive" == false ]]; then
        test_pass
    else
        test_fail "expected bounded process-tree failure, got rc=$rc elapsed=${elapsed_ms}ms child=${child_pid:-missing}/$child_alive"
    fi
}

# ── 9b. default_model must have a value, not just a key ──────────────────────
test_kimi_empty_default_model() {
    test_case "default_model with an empty value is not readiness"
    local tmp_bin old_path old_home old_key had_key rc_empty rc_bare rc_set
    tmp_bin="$TEST_TMP_DIR/kimi-bin-empty"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"; old_key="${KIMI_API_KEY-}"; had_key="${KIMI_API_KEY+set}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-empty-model-home"; mkdir -p "$HOME/.kimi-code"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true
    unset KIMI_API_KEY

    printf 'default_model = ""\n' > "$HOME/.kimi-code/config.toml"
    rc_empty=0; kimi_is_available >/dev/null 2>&1 || rc_empty=$?
    printf 'default_model =\n' > "$HOME/.kimi-code/config.toml"
    rc_bare=0; kimi_is_available >/dev/null 2>&1 || rc_bare=$?
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "kimi-k2.5"
[models."kimi-k2.5"]
provider = "kimi"
model = "kimi-k2.5"
max_context_size = 262144
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_set=0; kimi_is_available >/dev/null 2>&1 || rc_set=$?

    PATH="$old_path"; HOME="$old_home"; _kimi_restore_key "$had_key" "$old_key"
    if [[ "$rc_empty" -ne 0 && "$rc_bare" -ne 0 && "$rc_set" -eq 0 ]]; then
        test_pass
    else
        test_fail "expected empty!=0 ($rc_empty) bare!=0 ($rc_bare) set=0 ($rc_set)"
    fi
}

# ── 9c. the dispatch command is one the real CLI would accept ────────────────
test_kimi_dispatch_command_is_valid() {
    test_case "dispatch's kimi command survives the real CLI's argument contract"
    local tmp_bin old_path out rc cmd
    tmp_bin="$TEST_TMP_DIR/kimi-bin-strict"
    _kimi_strict_mock_bin "$tmp_bin"
    old_path="$PATH"; PATH="$tmp_bin:$PATH"

    # Take the command dispatch.sh actually builds, strip any env prefix, and
    # run it exactly as spawn.sh would: flags as argv, prompt on stdin.
    PLUGIN_DIR="$PROJECT_ROOT"
    cmd="$(get_agent_command kimi tangle implementer 2>/dev/null)"
    cmd="${cmd#env *MODEL=* }"
    # `|| rc=$?` not `; rc=$?` — the suite runs under `set -e`, which would
    # abort on a failing assignment and make this test unable to fail at all.
    rc=0
    # shellcheck disable=SC2086
    out="$(printf 'probe' | bash $cmd 2>&1)" || rc=$?
    PATH="$old_path"

    if [[ "$rc" -eq 0 && "$out" == *MOCK_KIMI_OK* ]]; then
        test_pass
    else
        test_fail "dispatch command rejected by the CLI argument contract: rc=$rc out=$out"
    fi
}

# ── 10. availability requires binary AND auth AND a configured model ──────────
test_kimi_detection() {
    test_case "kimi_is_available requires the kimi binary, auth, and a model"
    local tmp_bin old_path old_home old_key had_key rc_ready rc_nomodel rc_noauth
    tmp_bin="$TEST_TMP_DIR/kimi-bin-det"
    _kimi_mock_bin "$tmp_bin" 'exit 0'
    old_path="$PATH"; old_home="$HOME"; old_key="${KIMI_API_KEY-}"; had_key="${KIMI_API_KEY+set}"
    PATH="$tmp_bin:$PATH"; HOME="$TEST_TMP_DIR/kimi-empty-home"; mkdir -p "$HOME"
    source "$PROJECT_ROOT/scripts/lib/kimi.sh" 2>/dev/null || true

    printf 'default_model = "kimi-k2.5"\n' > "$HOME/.kimi-code-config-probe"
    mkdir -p "$HOME/.kimi-code"
    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "kimi-k2.5"
[models."kimi-k2.5"]
provider = "kimi"
model = "kimi-k2.5"
max_context_size = 262144
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = "fixture-not-a-secret"
TOML
    rc_ready=0; kimi_is_available >/dev/null 2>&1 || rc_ready=$?

    rm -f "$HOME/.kimi-code/config.toml"
    rc_nomodel=0; OCTOPUS_KIMI_MODEL="" kimi_is_available >/dev/null 2>&1 || rc_nomodel=$?

    cat > "$HOME/.kimi-code/config.toml" <<'TOML'
default_model = "kimi-k2.5"
[models."kimi-k2.5"]
provider = "kimi"
model = "kimi-k2.5"
max_context_size = 262144
[providers.kimi]
type = "kimi"
base_url = "https://fixture.invalid/v1"
api_key = ""
TOML
    rc_noauth=0; kimi_is_available >/dev/null 2>&1 || rc_noauth=$?

    PATH="$old_path"; HOME="$old_home"; _kimi_restore_key "$had_key" "$old_key"
    if [[ "$rc_ready" -eq 0 && "$rc_nomodel" -ne 0 && "$rc_noauth" -ne 0 ]]; then
        test_pass
    else
        test_fail "expected available=0 ($rc_ready), no-model!=0 ($rc_nomodel), no-auth!=0 ($rc_noauth)"
    fi
}

test_kimi_agent_validation() {
    test_case "kimi agent types pass the standard dispatch allowlist"
    local AVAILABLE_AGENTS agent
    AVAILABLE_AGENTS="$(sed -n 's/^AVAILABLE_AGENTS="\([^"]*\)".*/\1/p' "$PROJECT_ROOT/scripts/orchestrate.sh")"

    for agent in kimi kimi-research; do
        if ! validate_agent_type "$agent"; then
            test_fail "expected $agent to pass validate_agent_type"
            return
        fi
    done
    test_pass
}

test_kimi_configured_provider_resolution() {
    test_case "configured kimi providers resolve to labeled agent types"
    local AVAILABLE_AGENTS provider agent label
    AVAILABLE_AGENTS="$(sed -n 's/^AVAILABLE_AGENTS="\([^"]*\)".*/\1/p' "$PROJECT_ROOT/scripts/orchestrate.sh")"

    for provider in kimi kimi-research; do
        agent="$(resolve_provider_to_agent "$provider")" || {
            test_fail "expected configured provider $provider to resolve"
            return
        }
        label="$(agent_display_label "$agent")" || {
            test_fail "expected $agent to have a display label"
            return
        }
        if [[ "$agent" != "$provider" || "$label" != "Kimi" ]]; then
            test_fail "expected $provider|Kimi, got $agent|$label"
            return
        fi
    done
    test_pass
}

test_kimi_dispatch_shim
test_kimi_dispatch_wires_model
test_kimi_rejects_read_only_roles
test_kimi_rejects_every_non_write_capable_role
test_kimi_is_excluded_from_consultative_fleets
test_kimi_direct_execution_rejects_restricted_types
test_kimi_env_isolation
test_kimi_config_credentials
test_kimi_native_runtime_config_bridge
test_kimi_node_runtime_config_bridge
test_kimi_config_env_is_credential
test_kimi_rejects_incomplete_selected_records
test_kimi_accepts_matching_provider_env_credentials
test_kimi_accepts_current_provider_types_and_capabilities
test_kimi_accepts_current_v2_model_reference_shape
test_kimi_model_level_auth_precedes_provider_auth
test_kimi_effective_dispatch_model_drives_health
test_kimi_dangling_default_rejects_credentialed_pin
test_kimi_routing_parser_accepts_multiline_quote_endings
test_kimi_whitespace_alias_dispatch_is_safe
test_kimi_shim_validates_encoded_and_plaintext_models
test_kimi_default_provider_and_flat_model_readiness
test_kimi_rejects_malformed_or_duplicate_toml
test_kimi_validates_unselected_records
test_kimi_rejects_dangling_unselected_provider_reference
test_kimi_rejects_mixed_provider_auth
test_kimi_model_env_is_forwarded_and_drives_readiness
test_kimi_vertex_adc_fails_closed
test_kimi_leading_dash_home_is_safe
test_kimi_fixture_and_docs_are_current
test_kimi_accepts_unrelated_array_tables
test_kimi_custom_root_oauth
test_kimi_oauth_requires_usable_json_object
test_kimi_keyring_reference_requires_flat_file
test_kimi_ambient_key_is_not_auth
test_kimi_static_preflight_uses_config
test_kimi_real_health_uses_custom_root
test_kimi_install_and_model_display
test_kimi_user_guidance_contracts
test_kimi_config_runtime_model
test_kimi_default_no_model
test_kimi_shim_requires_prompt
test_kimi_exit_propagation
test_kimi_direct_env_isolation
test_kimi_stderr_auth_classification
test_kimi_success_stderr_is_not_response
test_kimi_interruption_cleans_private_captures
test_kimi_interruption_restores_caller_trap
test_kimi_interruption_bypasses_system_timeout
test_kimi_portable_timeout
test_kimi_pin_drives_readiness
test_kimi_unknown_pin_is_not_a_model
test_kimi_readiness_env_isolation
test_kimi_readiness_timeout
test_kimi_empty_default_model
test_kimi_dispatch_command_is_valid
test_kimi_detection
test_kimi_agent_validation
test_kimi_configured_provider_resolution

test_summary
