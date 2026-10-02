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
#   7. large prompts use a private prompt file, cleaned up on exit or signals.
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
    arm="$(sed -n '/grok|grok-research)/,/kimi|kimi-research)/p' "$PROJECT_ROOT/scripts/lib/dispatch.sh")"
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

# Exercise the real shim with a stub that saves the prompt before cleanup.
# NUL-delimited argv captures also catch argument ordering and splitting bugs.
check_grok_prompt_transport() {
    local limit="$1" size="$2" transport="$3" stub_rc="${4:-0}" signal="${5:-}"
    local fixture input capture prompt_path rc expected_rc
    fixture="$TEST_TMP_DIR/grok-transport-$RANDOM"
    input="$fixture/input"; capture="$fixture/argv"
    mkdir -p "$fixture/bin" "$fixture/tmp"
    {
        printf '%*s' "$((size - 8))" '' | tr ' ' x
        printf '\303\251\nend\n\n'  # Eight bytes, including UTF-8 and trailing newlines.
    } > "$input"
    cat > "$fixture/bin/grok" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" > "${GROK_TEST_DIR:?}/argv"
for arg in "$@"; do
    printf '%s' "$arg" | wc -c >> "$GROK_TEST_DIR/lengths"
done
if [[ "$1" == --prompt-file ]]; then
    printf '%s' "$2" > "$GROK_TEST_DIR/path"
    cp "$2" "$GROK_TEST_DIR/received"
    # GNU and BSD stat spell their mode query differently.
    stat -c '%a' "$2" > "$GROK_TEST_DIR/mode" 2>/dev/null ||
        stat -f '%Lp' "$2" > "$GROK_TEST_DIR/mode"
    if [[ -n "${GROK_TEST_SIGNAL:-}" ]]; then
        kill -s "$GROK_TEST_SIGNAL" "$PPID"
    fi
fi
exit "${GROK_TEST_RC:-0}"
MOCK
    chmod +x "$fixture/bin/grok"
    rc=0
    env "PATH=$fixture/bin:$PATH" "TMPDIR=$fixture/tmp" \
        "OCTOPUS_GROK_ARGV_MAX=$limit" "OCTOPUS_GROK_MODEL=grok-4-fast" \
        "OCTOPUS_GROK_CWD=$fixture/work dir" "GROK_TEST_DIR=$fixture" \
        "GROK_TEST_RC=$stub_rc" "GROK_TEST_SIGNAL=$signal" \
        bash "$PROJECT_ROOT/scripts/helpers/grok-exec.sh" < "$input" \
        > "$fixture/stdout" 2> "$fixture/stderr" || rc=$?
    expected_rc="$stub_rc"
    case "$signal" in
        TERM) expected_rc=143 ;;
        INT) expected_rc=130 ;;
    esac
    if [[ "$rc" -ne "$expected_rc" ]]; then
        test_fail "expected exit $expected_rc, got $rc: $(cat "$fixture/stderr")"
        return 1
    fi
    if [[ "$transport" == --prompt-file ]]; then
        prompt_path="$(cat "$fixture/path" 2>/dev/null || true)"
        if [[ "$prompt_path" != "$fixture/tmp/"* || -e "$prompt_path" ]] ||
           ! cmp -s "$input" "$fixture/received" ||
           [[ "$(cat "$fixture/mode" 2>/dev/null || true)" != 600 ]] ||
           ! awk '$1 > 100000 { exit 1 }' "$fixture/lengths"; then
            test_fail "prompt file must preserve bytes, use mode 0600 in TMPDIR, leave short argv, and be removed"
            return 1
        fi
        printf '%s\0' --prompt-file "$prompt_path" > "$fixture/expected"
    else
        # The legacy inline path strips trailing newlines via command substitution.
        printf '%s\0' -p "$(cat "$input")" > "$fixture/expected"
    fi
    printf '%s\0' --output-format plain --cwd "$fixture/work dir" \
        --disable-web-search --model grok-4-fast >> "$fixture/expected"
    if ! cmp -s "$fixture/expected" "$capture"; then
        test_fail "prompt transport and all other argv must match byte-for-byte"
        return 1
    fi
}

test_grok_prompt_transport() {
    test_case "prompts below and at the byte threshold use -p; above it uses a file"
    if check_grok_prompt_transport 1024 1023 -p &&
       check_grok_prompt_transport 1024 1024 -p &&
       check_grok_prompt_transport 1024 1025 --prompt-file; then
        test_pass
    fi

    test_case "200 KB prompt uses a byte-identical private file and removes it on success"
    if check_grok_prompt_transport 100000 200000 --prompt-file; then test_pass; fi

    test_case "prompt file is removed on failure and grok exit 3 propagates"
    if check_grok_prompt_transport 100000 200000 --prompt-file 3; then test_pass; fi

    test_case "OCTOPUS_GROK_ARGV_MAX=0 forces a file for a tiny prompt"
    if check_grok_prompt_transport 0 8 --prompt-file; then test_pass; fi

    test_case "non-integer OCTOPUS_GROK_ARGV_MAX falls back to 100000 bytes"
    if check_grok_prompt_transport invalid 99999 -p &&
       check_grok_prompt_transport invalid 100001 --prompt-file; then test_pass; fi

    local signal
    for signal in TERM INT; do
        test_case "prompt file is removed when the shim receives $signal"
        if check_grok_prompt_transport 0 8 --prompt-file 0 "$signal"; then test_pass; fi
    done
}
# Capture complete argv, including argument boundaries and ordering. No provider
# is contacted; dispatch also runs through its real isolated environment.
test_grok_headless_approval() {
    local tmp_bin="$TEST_TMP_DIR/grok-approval-bin" capture="$TEST_TMP_DIR/approval-argv"
    local expected="$TEST_TMP_DIR/approval-expected" errors="$TEST_TMP_DIR/approval-stderr"
    local workdir="$TEST_TMP_DIR/work dir" profile rc
    mkdir -p "$tmp_bin" "$workdir"
    cat > "$tmp_bin/grok" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@"
MOCK
    chmod +x "$tmp_bin/grok"
    local -a base=(-p 'run a shell command' --output-format plain --cwd "$workdir" --disable-web-search)

    for profile in default workspace strict off read-only bogus; do
        test_case "headless approval: sandbox $profile preserves complete argv"
        local sandbox="$profile" warning_lines=0
        [[ "$profile" == default || "$profile" == bogus ]] && sandbox=read-only
        [[ "$profile" == bogus ]] && warning_lines=1
        printf '%s\0' "${base[@]}" --always-approve --sandbox "$sandbox" > "$expected"
        rc=0
        env -u OCTOPUS_GROK_APPROVE -u OCTOPUS_GROK_MODEL \
            "PATH=$tmp_bin:$PATH" "OCTOPUS_GROK_CWD=$workdir" \
            "OCTOPUS_GROK_SANDBOX=${profile/default/}" \
            bash "$PROJECT_ROOT/scripts/helpers/grok-exec.sh" <<< 'run a shell command' > "$capture" 2> "$errors" || rc=$?
        if [[ "$rc" -eq 0 && "$(wc -l < "$errors")" -eq "$warning_lines" ]] && \
           cmp -s "$expected" "$capture" && \
           { [[ "$profile" != bogus ]] || grep -q 'bogus.*read-only' "$errors"; }; then
            test_pass
        else
            test_fail "expected approval with $sandbox and $warning_lines warning(s), rc=$rc"
        fi
    done

    test_case "approval opt-out restores original argv; approval flags precede --model when enabled"
    local approve
    rc=0
    for approve in 0 1; do
        local -a flags=()
        [[ "$approve" == 1 ]] && flags=(--always-approve --sandbox strict)
        printf '%s\0' "${base[@]}" "${flags[@]}" --model grok-4-fast > "$expected"
        env "PATH=$tmp_bin:$PATH" "OCTOPUS_GROK_CWD=$workdir" \
            "OCTOPUS_GROK_APPROVE=$approve" OCTOPUS_GROK_SANDBOX=strict OCTOPUS_GROK_MODEL=grok-4-fast \
            bash "$PROJECT_ROOT/scripts/helpers/grok-exec.sh" <<< 'run a shell command' > "$capture" 2> "$errors" || rc=1
        cmp -s "$expected" "$capture" && [[ ! -s "$errors" ]] || rc=1
    done
    if [[ "$rc" -eq 0 ]]; then test_pass; else test_fail "approval toggle changed original args or model ordering"; fi
}

test_grok_dispatch_sandbox() {
    local scenario phase role codex_sandbox override expected_sandbox fixture_model approve cmd rc
    local capture="$TEST_TMP_DIR/dispatch-argv" expected="$TEST_TMP_DIR/dispatch-expected"
    while IFS='|' read -r scenario phase role codex_sandbox override expected_sandbox fixture_model approve; do
        test_case "dispatch sandbox: $scenario"
        rc=0
        (
            export "PLUGIN_DIR=$PROJECT_ROOT" "PATH=$TEST_TMP_DIR/grok-approval-bin:$PATH"
            export "OCTOPUS_CODEX_SANDBOX=$codex_sandbox" "OCTOPUS_GROK_SANDBOX=$override"
            export "OCTOPUS_GROK_APPROVE=$approve" OCTOPUS_ALLOW_FULL_GROK_ENV=false
            source "$PROJECT_ROOT/scripts/lib/utils.sh"
            source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
            source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
            get_agent_model() { printf '%s\n' "$fixture_model"; }
            cmd="$(get_agent_command grok "$phase" "$role")" || exit 1
            # Assert transport even for opt-out, which intentionally retains old argv.
            [[ " $cmd " == *" OCTOPUS_GROK_SANDBOX=$expected_sandbox "* ]] || exit 1
            validate_agent_command "$cmd" || exit 1
            # Keep the assignment prefix bound to the immediate shim executable.
            local injected="${cmd% "$PROJECT_ROOT/scripts/helpers/grok-exec.sh"} echo pwned $PROJECT_ROOT/scripts/helpers/grok-exec.sh"
            if validate_agent_command "$injected" >/dev/null 2>&1; then exit 1; fi
            octo_dispatch_command_to_argv "$cmd" || exit 1
            build_provider_env grok
            "${PROVIDER_ENV_ARRAY[@]}" "${OCTO_COMMAND_ARGV[@]}" <<< probe
        ) > "$capture" 2> "$TEST_TMP_DIR/dispatch-stderr" || rc=$?
        local -a args=(-p probe --output-format plain --cwd "$PWD" --disable-web-search)
        [[ "$approve" != 0 ]] && args+=(--always-approve --sandbox "$expected_sandbox")
        [[ "$fixture_model" != default ]] && args+=(--model "$fixture_model")
        printf '%s\0' "${args[@]}" > "$expected"
        if [[ "$rc" -eq 0 ]] && cmp -s "$expected" "$capture"; then
            test_pass
        else
            test_fail "expected validated, isolated dispatch with $expected_sandbox (rc=$rc): $(cat "$TEST_TMP_DIR/dispatch-stderr")"
        fi
    done <<'CASES'
review|review|code-reviewer|||read-only|default|1
review during implementation|tangle|code-reviewer|||read-only|grok-4-fast|1
consult|consult|implementer|danger-full-access||read-only|default|1
council|council|implementer|danger-full-access||read-only|grok-4-fast|1
design review|ceremony|implementer|danger-full-access||read-only|default|1
implementation default|tangle|implementer|||workspace|default|1
implementation full access|develop|implementer|danger-full-access||workspace|grok-4-fast|1
Codex read-only override|tangle|implementer|read-only||read-only|default|1
Grok explicit override|review|code-reviewer||strict|strict|grok-4-fast|1
approval opt-out survives isolation|tangle|implementer|||workspace|default|0
unknown context|||||read-only|default|1
CASES
}

test_grok_dispatch_shim
test_grok_dispatch_wires_model
test_grok_env_isolation
test_grok_config_runtime_model
test_grok_default_no_model
test_grok_exit_propagation
test_grok_detection
test_grok_prompt_transport

test_grok_headless_approval
test_grok_dispatch_sandbox

test_summary
