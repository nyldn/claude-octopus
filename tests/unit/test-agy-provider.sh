#!/bin/bash
# tests/unit/test-agy-provider.sh
# Tests Antigravity CLI (agy) provider configuration and integration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Antigravity CLI Provider"

test_agy_config_exists() {
    test_case "Provider config file exists at config/providers/agy/CLAUDE.md"

    if [[ -f "$PROJECT_ROOT/config/providers/agy/CLAUDE.md" ]]; then
        test_pass
    else
        test_fail "missing config/providers/agy/CLAUDE.md"
    fi
}

test_agy_available_agent() {
    test_case "AVAILABLE_AGENTS includes agy aliases"

    if grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q ' agy ' && \
       grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q 'agy-research' && \
       grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q 'antigravity'; then
        test_pass
    else
        test_fail "agy, agy-research, and antigravity should be available agents"
    fi
}

test_agy_model_config_provider() {
    test_case "model configuration accepts the canonical agy provider key"

    if (
        source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
        octo_model_config_provider_valid agy
    ) >/dev/null 2>&1; then
        test_pass
    else
        test_fail "agy should be accepted by set/reset model configuration"
    fi
}

test_agy_dispatch_native_flags() {
    test_case "dispatch.sh uses native agy helper"

    # The adapter builds flags incrementally from a bare `agy` and appends
    # --print LAST with the prompt as its argument — current agy ignores stdin
    # in print mode, and a leading --print would eat the next flag as the
    # message.
    if grep -q 'scripts/helpers/agy-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh" && \
       grep -q 'cmd=(agy)' "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" && \
       grep -q -- '--print "${AGY_INLINE_DIRECTIVE}${prompt_content}"' "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"; then
        test_pass
    else
        test_fail "agy dispatch should use scripts/helpers/agy-exec.sh with the prompt as --print's argument"
    fi
}


test_agy_print_receives_prompt_argument() {
    test_case "agy-exec passes the stdin prompt as --print's argument"

    local tmp_bin="$TEST_TMP_DIR/agy-prompt-arg-bin"
    local capture="$TEST_TMP_DIR/agy-prompt-argv.txt"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${AGY_ARG_CAPTURE:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    local old_path="$PATH"
    PATH="$tmp_bin:$PATH"
    AGY_ARG_CAPTURE="$capture"
    export AGY_ARG_CAPTURE

    # OCTOPUS_AGY_FORCE_INLINE=0 disables the force-inline directive, so --print's
    # argument is the untouched prompt. This keeps the original prompt-as-argument
    # assertion exact while also covering the opt-out path.
    printf 'hello agy prompt' | OCTOPUS_AGY_FORCE_INLINE=0 bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" >/dev/null

    PATH="$old_path"
    unset AGY_ARG_CAPTURE

    # The prompt must be the argv element following --print; --sandbox must
    # still be present as a real flag (the old invocation consumed it as the
    # prompt, leaving the sandbox off).
    local print_next
    print_next="$(grep -Fx -A1 -- '--print' "$capture" | tail -1)"
    if [[ "$print_next" == "hello agy prompt" ]] && grep -Fxq -- '--sandbox' "$capture" && \
       ! grep -Fq 'CRITICAL OUTPUT RULES' "$capture"; then
        test_pass
    else
        test_fail "expected argv '--print' followed by the unmodified stdin prompt plus a real --sandbox flag, and no directive under OCTOPUS_AGY_FORCE_INLINE=0; got: $(tr '\n' '|' < "$capture")"
    fi
}

test_agy_review_sized_prompt_dispatches_promptly() {
    test_case "agy-exec dispatches a review-sized prompt without preprocessing stall"

    local tmp_bin="$TEST_TMP_DIR/agy-large-prompt-bin"
    local capture="$TEST_TMP_DIR/agy-large-prompt.txt"
    local prompt_file="$TEST_TMP_DIR/agy-large-prompt.input"
    local stdout_file="$TEST_TMP_DIR/agy-large-prompt.stdout"
    local prompt='x '
    local i adapter_pid launched=false
    mkdir -p "$tmp_bin"
    rm -f "$capture" "$stdout_file"

    # Double a mixed content/whitespace fragment to a realistic 128 KiB review
    # prompt. The old Bash 3.2 `${value//[[:space:]]/}` emptiness check becomes
    # pathologically slow on this input before the real CLI is ever launched.
    for ((i = 0; i < 16; i++)); do
        prompt="${prompt}${prompt}"
    done
    printf '%s' "$prompt" > "$prompt_file"

    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
while (( $# > 0 )); do
    if [[ "$1" == "--print" && $# -ge 2 ]]; then
        prompt_arg="$2"
        prompt_path="$(printf '%s\n' "$prompt_arg" | sed -n "s/.*Read the file '\([^']*\)'.*/\1/p")"
        if [[ -n "$prompt_path" && -r "$prompt_path" ]]; then
            cat "$prompt_path" > "${AGY_ARG_CAPTURE:?}"
        else
            printf '%s' "$prompt_arg" > "${AGY_ARG_CAPTURE:?}"
        fi
        printf '%s\n' 'mock-response'
        exit 0
    fi
    shift
done
exit 2
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    AGY_ARG_CAPTURE="$capture" \
    OCTOPUS_AGY_FORCE_INLINE=0 \
    PATH="$tmp_bin:$PATH" \
        bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" \
        < "$prompt_file" > "$stdout_file" 2>/dev/null &
    adapter_pid=$!

    # Poll for at most two seconds. On the regression path no agy child exists,
    # so terminating the adapter PID is sufficient and avoids leaking a stalled
    # process into the rest of the suite.
    for ((i = 0; i < 20; i++)); do
        if [[ -s "$capture" ]]; then
            launched=true
            break
        fi
        sleep 0.1
    done

    if [[ "$launched" != "true" ]]; then
        kill -TERM "$adapter_pid" 2>/dev/null || true
        sleep 0.1
        kill -KILL "$adapter_pid" 2>/dev/null || true
        wait "$adapter_pid" 2>/dev/null || true
        test_fail "agy was not launched within 2 seconds for a 128 KiB prompt"
        return
    fi

    local adapter_rc=0
    wait "$adapter_pid" || adapter_rc=$?
    if [[ "$adapter_rc" -eq 0 ]] && cmp -s "$prompt_file" "$capture" && \
       grep -Fxq 'mock-response' "$stdout_file"; then
        test_pass
    else
        test_fail "large prompt dispatch failed or did not preserve the prompt (rc=$adapter_rc)"
    fi
}

test_agy_review_sized_silent_output_retries_promptly() {
    test_case "agy-exec retries a review-sized whitespace-only response without preprocessing stall"

    local tmp_bin="$TEST_TMP_DIR/agy-large-empty-bin"
    local calls="$TEST_TMP_DIR/agy-large-empty.calls"
    local stdout_file="$TEST_TMP_DIR/agy-large-empty.stdout"
    local adapter_pid i retried=false
    mkdir -p "$tmp_bin"
    rm -f "$calls" "$stdout_file"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
count=0
[[ -f "${AGY_CALL_CAPTURE:?}" ]] && count="$(cat "$AGY_CALL_CAPTURE")"
count=$((count + 1))
printf '%s\n' "$count" > "$AGY_CALL_CAPTURE"
if [[ "$count" -eq 1 ]]; then
    head -c 131072 /dev/zero | tr '\0' ' '
else
    printf '%s\n' 'mock-response-after-retry'
fi
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    printf 'review prompt' \
        | AGY_CALL_CAPTURE="$calls" OCTOPUS_AGY_FORCE_INLINE=0 PATH="$tmp_bin:$PATH" \
          bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" > "$stdout_file" 2>/dev/null &
    adapter_pid=$!

    for ((i = 0; i < 20; i++)); do
        if [[ -f "$calls" ]] && [[ "$(cat "$calls")" == "2" ]]; then
            retried=true
            break
        fi
        sleep 0.1
    done

    if [[ "$retried" != "true" ]]; then
        kill -TERM "$adapter_pid" 2>/dev/null || true
        sleep 0.1
        kill -KILL "$adapter_pid" 2>/dev/null || true
        wait "$adapter_pid" 2>/dev/null || true
        test_fail "agy whitespace-only output retry did not start within 2 seconds"
        return
    fi

    local adapter_rc=0
    wait "$adapter_pid" || adapter_rc=$?
    if [[ "$adapter_rc" -eq 0 ]] && grep -Fxq 'mock-response-after-retry' "$stdout_file"; then
        test_pass
    else
        test_fail "agy whitespace-only output retry failed (rc=$adapter_rc)"
    fi
}

test_agy_force_inline_directive_prepended_by_default() {
    test_case "agy-exec prepends the force-inline directive by default"

    local tmp_bin="$TEST_TMP_DIR/agy-inline-bin"
    local capture="$TEST_TMP_DIR/agy-inline-argv.txt"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${AGY_ARG_CAPTURE:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    local old_path="$PATH"
    PATH="$tmp_bin:$PATH"
    AGY_ARG_CAPTURE="$capture"
    export AGY_ARG_CAPTURE

    printf 'hello agy prompt' | bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" >/dev/null

    PATH="$old_path"
    unset AGY_ARG_CAPTURE

    # agy writes its real answer to a brain artifact and returns a stub unless it is
    # told to answer inline, so the directive must reach agy ahead of the prompt --
    # and the prompt itself must survive intact behind it.
    if grep -Fq 'CRITICAL OUTPUT RULES' "$capture" && grep -Fq 'hello agy prompt' "$capture"; then
        test_pass
    else
        test_fail "expected the force-inline directive prepended to the prompt; got: $(tr '\n' '|' < "$capture")"
    fi
}

test_agy_file_prompt_directive_permits_reading_prompt_file() {
    test_case "oversized-prompt directive permits reading the adapter's prompt file"

    # The >100000 branch hands agy a file path to read. A blanket "do not use file
    # tools" directive would contradict that instruction, so this branch must use
    # the file-permitting variant while still forbidding artifacts.
    local helper="$PROJECT_ROOT/scripts/helpers/agy-exec.sh"
    if grep -q -- '--print "${AGY_INLINE_DIRECTIVE_FILE}Read the file' "$helper" && \
       grep -q 'You may read ONLY the prompt file named below' "$helper" && \
       grep -q 'AGY_INLINE_DIRECTIVE_FILE=""' "$helper"; then
        test_pass
    else
        test_fail "the oversized-prompt branch should use AGY_INLINE_DIRECTIVE_FILE, which permits reading the supplied prompt file and is cleared by the opt-out"
    fi
}

test_agy_oversize_payload_skips_gracefully() {
    test_case "agy-exec refuses an over-ceiling payload as a structured oversize skip, not an OOM"

    local tmp_bin="$TEST_TMP_DIR/agy-oversize-bin"
    local marker="$TEST_TMP_DIR/agy-oversize.called"
    local err="$TEST_TMP_DIR/agy-oversize.err"
    mkdir -p "$tmp_bin"
    rm -f "$marker"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
echo called > "${AGY_CALLED_MARKER:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    # A tiny ceiling + a payload above it: agy must NOT be invoked (a multi-MB
    # prompt OOM-kills headless agy), the exit is 0 (route around, don't fail the
    # council), stdout is empty, and stderr carries a marker the dispatch
    # classifier recognizes as a provider oversize rejection -> skipped:oversize.
    local out rc
    out="$(printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
        | AGY_CALLED_MARKER="$marker" OCTOPUS_AGY_MAX_PAYLOAD_BYTES=10 \
          PATH="$tmp_bin:$PATH" bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>"$err")"
    rc=$?

    if [[ $rc -eq 0 ]] && [[ -z "$out" ]] && [[ ! -f "$marker" ]] &&
       grep -qiE 'input is too large' "$err"; then
        test_pass
    else
        test_fail "oversize skip wrong: rc=$rc out=[$out] agy_called=$([[ -f "$marker" ]] && echo yes || echo no) stderr=[$(tr '\n' ' ' < "$err")]"
    fi
}

test_agy_oversize_ceiling_is_configurable() {
    test_case "OCTOPUS_AGY_MAX_PAYLOAD_BYTES raises the ceiling so the same prompt dispatches"

    local tmp_bin="$TEST_TMP_DIR/agy-ceiling-bin"
    local marker="$TEST_TMP_DIR/agy-ceiling.called"
    mkdir -p "$tmp_bin"
    rm -f "$marker"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
echo called > "${AGY_CALLED_MARKER:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    # The exact prompt refused at a 10-byte ceiling must dispatch once the ceiling
    # is raised above its size — proving the threshold is env-driven, not fixed.
    local out rc
    out="$(printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
        | AGY_CALLED_MARKER="$marker" OCTOPUS_AGY_MAX_PAYLOAD_BYTES=100000 \
          PATH="$tmp_bin:$PATH" bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>/dev/null)"
    rc=$?

    if [[ $rc -eq 0 ]] && [[ -f "$marker" ]] && [[ "$out" == *"mock-response"* ]]; then
        test_pass
    else
        test_fail "raised ceiling should dispatch: rc=$rc agy_called=$([[ -f "$marker" ]] && echo yes || echo no) out=[$out]"
    fi
}

test_agy_oversize_uses_documented_default_ceiling() {
    test_case "the 1 MiB default ceiling applies when OCTOPUS_AGY_MAX_PAYLOAD_BYTES is unset"

    local tmp_bin="$TEST_TMP_DIR/agy-default-bin"
    local marker="$TEST_TMP_DIR/agy-default.called"
    local err="$TEST_TMP_DIR/agy-default.err"
    mkdir -p "$tmp_bin"
    rm -f "$marker"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
echo called > "${AGY_CALLED_MARKER:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    # 1,048,577 bytes = 1 byte over the documented 1 MiB default. With no env
    # override, a broken default/fallback would dispatch instead of refusing — the
    # two override-based tests could not catch that. `unset` is scoped to the
    # subshell so it cannot leak into sibling tests.
    local out rc
    out="$( { unset OCTOPUS_AGY_MAX_PAYLOAD_BYTES
             head -c 1048577 /dev/zero | tr '\0' 'x' \
               | AGY_CALLED_MARKER="$marker" PATH="$tmp_bin:$PATH" \
                 bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>"$err"; } )"
    rc=$?

    if [[ $rc -eq 0 ]] && [[ -z "$out" ]] && [[ ! -f "$marker" ]] &&
       grep -qiE 'input is too large' "$err"; then
        test_pass
    else
        test_fail "default ceiling not enforced: rc=$rc out=[$out] agy_called=$([[ -f "$marker" ]] && echo yes || echo no) stderr=[$(tr '\n' ' ' < "$err")]"
    fi
}

test_agy_oversize_default_ceiling_dispatches_at_the_limit() {
    test_case "a payload at exactly the 1 MiB default (unset env) dispatches, not refused"

    local tmp_bin="$TEST_TMP_DIR/agy-atlimit-bin"
    local marker="$TEST_TMP_DIR/agy-atlimit.called"
    mkdir -p "$tmp_bin"
    rm -f "$marker"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
echo called > "${AGY_CALLED_MARKER:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    # Exactly 1,048,576 bytes = the documented default. The refusal is strictly
    # greater-than, so this must DISPATCH. Pairs with the 1-byte-over rejection test:
    # together they pin the boundary, so a default that is too LOW (would refuse here)
    # is also caught, not just one that is too high.
    local out rc
    out="$( { unset OCTOPUS_AGY_MAX_PAYLOAD_BYTES
             head -c 1048576 /dev/zero | tr '\0' 'x' \
               | AGY_CALLED_MARKER="$marker" PATH="$tmp_bin:$PATH" \
                 bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>/dev/null; } )"
    rc=$?

    if [[ $rc -eq 0 ]] && [[ -f "$marker" ]] && [[ "$out" == *"mock-response"* ]]; then
        test_pass
    else
        test_fail "at-limit payload should dispatch: rc=$rc agy_called=$([[ -f "$marker" ]] && echo yes || echo no) out=[$out]"
    fi
}

test_agy_pty_fallback_salvages_tty_error() {
    test_case "agy-exec retries under a pseudo-terminal when agy dies demanding a TTY"
    command -v script >/dev/null 2>&1 || { test_skip "script (PTY allocator) not available"; return 0; }

    local tmp_bin="$TEST_TMP_DIR/agy-pty-bin"
    mkdir -p "$tmp_bin"
    # Mimic agy's bubbletea failure: die 'could not open TTY' with NO controlling
    # terminal, but produce a real answer once a PTY is present.
cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [ -t 1 ] || [ -t 0 ]; then
    expected=$'review this diff\npreserve a '\''quoted'\'' token'
    actual="${!#}"
    if [[ "$actual" != "$expected" ]]; then
        printf 'prompt corrupted: <%s>\n' "$actual" >&2
        exit 3
    fi
    printf 'reviewed\nVERDICT: APPROVE\n'
    exit 0
fi
echo "bubbletea: could not open TTY" >&2
exit 1
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    local out rc=0 err="$TEST_TMP_DIR/agy-pty.err"
    out="$(printf '%s' $'review this diff\npreserve a '\''quoted'\'' token' | OCTOPUS_AGY_FORCE_INLINE=0 \
        PATH="$tmp_bin:$PATH" bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>"$err")" || rc=$?

    # Salvaged: real verdict returned, exit 0, PTY path announced, and the answer is
    # byte-clean (no caret-notation ^D echo leaked from the pseudo-terminal).
    if [[ $rc -eq 0 ]] && [[ "$out" == *"VERDICT: APPROVE"* ]] &&
       ! printf '%s' "$out" | grep -q '\^D' &&
       grep -q 'pseudo-terminal' "$err"; then
        test_pass
    else
        test_fail "PTY fallback did not salvage: rc=$rc out=[$(printf '%s' "$out" | tr '\n' '|')] fired=$(grep -q pseudo-terminal "$err" && echo yes || echo no)"
    fi
}

test_agy_pty_fallback_opt_out() {
    test_case "OCTOPUS_AGY_NO_PTY_FALLBACK=1 disables the pseudo-terminal retry"

    local tmp_bin="$TEST_TMP_DIR/agy-pty-off-bin"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [ -t 1 ] || [ -t 0 ]; then printf 'VERDICT: APPROVE\n'; exit 0; fi
echo "bubbletea: could not open TTY" >&2
exit 1
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    local out rc=0 err="$TEST_TMP_DIR/agy-pty-off.err"
    out="$(printf 'review this diff' | OCTOPUS_AGY_NO_PTY_FALLBACK=1 OCTOPUS_AGY_FORCE_INLINE=0 \
        PATH="$tmp_bin:$PATH" bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>"$err")" || rc=$?

    # With the fallback off, the TTY failure propagates: non-zero exit, no salvage.
    if [[ $rc -ne 0 ]] && [[ "$out" != *"VERDICT: APPROVE"* ]] &&
       ! grep -q 'pseudo-terminal' "$err"; then
        test_pass
    else
        test_fail "opt-out still retried: rc=$rc out=[$(printf '%s' "$out" | tr '\n' '|')]"
    fi
}

test_agy_print_timeout_gets_a_unit() {
    test_case "a bare-number OCTOPUS_AGY_PRINT_TIMEOUT is unit-suffixed for agy's Go duration"

    local tmp_bin="$TEST_TMP_DIR/agy-timeout-bin"
    local capture="$TEST_TMP_DIR/agy-timeout-argv.txt"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${AGY_ARG_CAPTURE:?}"
echo "mock-response"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    # agy rejects a bare integer: `--print-timeout 600` -> "missing unit in duration".
    # The adapter must pass 600s so the seat isn't taken down (exit 2).
    printf 'hi' | OCTOPUS_AGY_PRINT_TIMEOUT=600 OCTOPUS_AGY_FORCE_INLINE=0 \
        AGY_ARG_CAPTURE="$capture" PATH="$tmp_bin:$PATH" \
        bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" >/dev/null

    local next
    next="$(grep -Fx -A1 -- '--print-timeout' "$capture" | tail -1)"
    if [[ "$next" == "600s" ]]; then
        test_pass
    else
        test_fail "expected argv '--print-timeout' followed by '600s', got: $(tr '\n' '|' < "$capture")"
    fi
}

test_agy_dynamic_model_validation() {
    test_case "explicit agy model pins validate against agy models"

    local tmp_bin="$TEST_TMP_DIR/agy-dynamic-model-bin"
    local capture="$TEST_TMP_DIR/agy-argv.txt"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then
    printf '%s\t%s\n' \
        'gemini-3.5-flash-low' 'Gemini 3.5 Flash (Low)' \
        'gemini-3.5-flash-medium' 'Gemini 3.5 Flash (Medium)' \
        'claude-sonnet-4-6' 'Claude Sonnet 4.6 (Thinking)'
    exit 0
fi
printf '%s\n' "$@" > "${AGY_ARG_CAPTURE:?}"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    local old_path="$PATH"
    local old_home="$HOME"
    local had_log=0
    PATH="$tmp_bin:$PATH"
    AGY_ARG_CAPTURE="$capture"
    export AGY_ARG_CAPTURE

    if declare -F log >/dev/null 2>&1; then
        had_log=1
        eval "$(declare -f log | sed '1s/^log/__octo_saved_log/')"
    fi

    restore_agy_dynamic_model_env() {
        PATH="$old_path"
        HOME="$old_home"
        unset AGY_ARG_CAPTURE
        unset -f log 2>/dev/null || true
        if [[ "$had_log" == "1" ]] && declare -F __octo_saved_log >/dev/null 2>&1; then
            eval "$(declare -f __octo_saved_log | sed '1s/^__octo_saved_log/log/')"
            unset -f __octo_saved_log 2>/dev/null || true
        fi
    }

    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"

    if ! validate_agy_model_name 'Gemini 3.5 Flash (Low)'; then
        restore_agy_dynamic_model_env
        test_fail "real agy labels from agy models should be accepted"
        return
    fi
    if ! validate_agy_model_name 'gemini-3.5-flash-low'; then
        restore_agy_dynamic_model_env
        test_fail "real agy model IDs from tab-separated agy models output should be accepted"
        return
    fi
    if validate_agy_model_name 'gemini-3.5-flash' >/dev/null 2>&1; then
        restore_agy_dynamic_model_env
        test_fail "partial agy model IDs must be rejected"
        return
    fi
    if validate_model_name 'Gemini 3.5 Flash (Low)'; then
        restore_agy_dynamic_model_env
        test_fail "generic model validator should remain strict for shell-token providers"
        return
    fi
    if validate_agy_model_name 'Gemini 9 Unknown (Low)' >/dev/null 2>&1; then
        restore_agy_dynamic_model_env
        test_fail "agy labels absent from agy models should be rejected"
        return
    fi

    local resolved=""
    OCTOPUS_AGY_MODEL='Gemini 3.5 Flash (Low)'
    if ! resolved="$(resolve_octopus_model agy agy tangle decomposer)"; then
        unset OCTOPUS_AGY_MODEL
        restore_agy_dynamic_model_env
        test_fail "resolver failed for explicit agy label"
        return
    fi
    unset OCTOPUS_AGY_MODEL
    if [[ "$resolved" != 'Gemini 3.5 Flash (Low)' ]]; then
        restore_agy_dynamic_model_env
        test_fail "resolver should return explicit agy labels validated from agy models"
        return
    fi

    OCTOPUS_AGY_MODEL='Gemini 3.5 Flash (Low)'
    if ! resolved="$(resolve_octopus_model agy-research agy tangle decomposer)"; then
        unset OCTOPUS_AGY_MODEL
        restore_agy_dynamic_model_env
        test_fail "resolver failed for explicit agy-research label"
        return
    fi
    unset OCTOPUS_AGY_MODEL
    if [[ "$resolved" != 'Gemini 3.5 Flash (Low)' ]]; then
        restore_agy_dynamic_model_env
        test_fail "agy-research should use agy-specific env validation"
        return
    fi

    local config_dir="$TEST_TMP_DIR/agy-config-home"
    mkdir -p "$config_dir/.claude-octopus/config"
    cat > "$config_dir/.claude-octopus/config/providers.json" <<'JSON'
{"providers":{"agy":{"default":"gemini-3.5-flash-medium"}}}
JSON
    HOME="$config_dir"
    if ! resolved="$(resolve_octopus_model agy-research agy tangle decomposer)"; then
        HOME="$old_home"
        restore_agy_dynamic_model_env
        test_fail "resolver failed for config-resolved agy-research label"
        return
    fi
    HOME="$old_home"
    if [[ "$resolved" != 'gemini-3.5-flash-medium' ]]; then
        restore_agy_dynamic_model_env
        test_fail "config-resolved agy-research IDs should use agy-specific provider lookups"
        return
    fi

    HOME="$config_dir"
    source "$PROJECT_ROOT/scripts/lib/preflight.sh"
    local preflight_status=""
    preflight_status="$(_preflight_agy_model_status 2>/dev/null || true)"
    HOME="$old_home"
    if [[ "$preflight_status" != "ok" ]]; then
        restore_agy_dynamic_model_env
        test_fail "preflight should admit an installed agy provider with a valid configured model ID"
        return
    fi
    printf '%s\n' '{"providers":{"agy":{"default":"gemini-9-unknown"}}}' \
        > "$config_dir/.claude-octopus/config/providers.json"
    HOME="$config_dir"
    preflight_status="$(_preflight_agy_model_status 2>/dev/null || true)"
    HOME="$old_home"
    if [[ "$preflight_status" != "model-invalid" ]]; then
        restore_agy_dynamic_model_env
        test_fail "preflight should mark agy unavailable when its configured model is absent from the live catalog"
        return
    fi

    # The adapter refuses promptless dispatch (a promptless print-mode agy
    # answers from its own instruction-file context — the degenerate-seat
    # failure), so every invocation must pipe a prompt. Whitespace-only stdin
    # must count as promptless too: $(<file) strips trailing whitespace, so a
    # byte-size check alone would pass '\n' through as an empty --print value.
    : > "$capture"
    local ws_rc=0
    printf '\n  \n' | bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>/dev/null || ws_rc=$?
    if [[ "$ws_rc" -ne 2 || -s "$capture" ]]; then
        restore_agy_dynamic_model_env
        test_fail "whitespace-only stdin should be refused as promptless (rc=$ws_rc)"
        return
    fi

    printf 'ping' | OCTOPUS_AGY_MODEL='agy/default' bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"
    if grep -q -- '--model' "$capture"; then
        restore_agy_dynamic_model_env
        test_fail "agy/default should not be passed to agy --model"
        return
    fi

    printf 'ping' | OCTOPUS_AGY_MODEL='Gemini 3.5 Flash (Low)' bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"
    # 'ping' appearing in argv is the discriminating check for prompt-as-argument
    # delivery: pre-fix, the prompt went to stdin (which agy ignores) and never
    # reached argv, so this fails on the pre-fix adapter.
    if grep -Fxq -- '--model' "$capture" && grep -Fxq -- 'Gemini 3.5 Flash (Low)' "$capture" && \
       grep -Fxq -- '--print' "$capture" && grep -Fxq -- 'ping' "$capture"; then
        restore_agy_dynamic_model_env
        test_pass
    else
        restore_agy_dynamic_model_env
        test_fail "explicit agy model labels should be one --model argument and the prompt must reach argv via --print"
    fi
}

test_agy_catalog_lookup_timeout() {
    test_case "agy model validation bounds a stalled catalog lookup"

    local tmp_bin="$TEST_TMP_DIR/agy-stalled-catalog-bin"
    local old_path="$PATH"
    local catalog_timeout_secs=1
    local timeout_upper_ms=$((catalog_timeout_secs * 1000 + 1500))
    local started_ms elapsed_ms lookup_rc=0 stalled_pid="" process_alive="no"
    local started_marker="$TEST_TMP_DIR/agy-stalled.started"
    local completed_marker="$TEST_TMP_DIR/agy-stalled.completed"
    local pid_marker="$TEST_TMP_DIR/agy-stalled.pid"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then
    : > "${AGY_STALLED_STARTED:?}"
    printf '%s\n' "$$" > "${AGY_STALLED_PID:?}"
    sleep 6
    : > "${AGY_STALLED_COMPLETED:?}"
    printf '%s\t%s\n' 'gemini-3.5-flash-low' 'Gemini 3.5 Flash (Low)'
fi
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    PATH="$tmp_bin:$PATH"
    export AGY_STALLED_STARTED="$started_marker"
    export AGY_STALLED_COMPLETED="$completed_marker"
    export AGY_STALLED_PID="$pid_marker"
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
    started_ms="$(python3 -c 'import time; print(int(time.monotonic() * 1000))')"
    (
        unset OCTOPUS_AGY_MODEL_STRICT
        OCTOPUS_AGY_MODELS_TIMEOUT="$catalog_timeout_secs" \
            validate_agy_model_name 'gemini-3.5-flash-low'
    ) >/dev/null 2>&1 || lookup_rc=$?
    elapsed_ms=$(( $(python3 -c 'import time; print(int(time.monotonic() * 1000))') - started_ms ))
    stalled_pid="$(cat "$pid_marker" 2>/dev/null || true)"
    if [[ -n "$stalled_pid" ]] && kill -0 "$stalled_pid" 2>/dev/null; then
        process_alive="yes"
    fi
    PATH="$old_path"
    unset AGY_STALLED_STARTED AGY_STALLED_COMPLETED AGY_STALLED_PID

    # The invariant under test is the BOUND: the stalled lookup must be killed by
    # the 1s timeout and never complete the mock's 6s sleep. A stalled (unreachable)
    # catalog is a "cannot validate" case, so it now fails OPEN (rc=0) — the pin is
    # trusted and agy rejects a genuinely bad model at dispatch. (OCTOPUS_AGY_MODEL_STRICT=1
    # would fail closed; the default path is asserted here.)
    if [[ "$lookup_rc" -eq 0 && -f "$started_marker" && ! -e "$completed_marker" \
          && "$process_alive" == "no" && "$elapsed_ms" -ge 700 \
          && "$elapsed_ms" -lt "$timeout_upper_ms" ]]; then
        test_pass
    else
        test_fail "stalled agy catalog was not bounded or did not fail open: rc=$lookup_rc elapsed=${elapsed_ms}ms upper=${timeout_upper_ms}ms started=$([[ -f "$started_marker" ]] && echo yes || echo no) completed=$([[ -f "$completed_marker" ]] && echo yes || echo no) process_alive=$process_alive"
    fi
}
test_agy_command_validation() {
    test_case "command validator allows agy dispatch"

    if grep -q 'scripts/helpers/agy-exec.sh' "$PROJECT_ROOT/scripts/lib/utils.sh"; then
        test_pass
    else
        test_fail "utils.sh should allow agy command dispatch"
    fi
}

test_agy_dispatch_not_gemini_wrapper() {
    test_case "agy dispatch does not use Gemini-specific flags"

    local agy_block
    agy_block="$(sed -n '/agy|agy-research|antigravity)/,/;;/p' "$PROJECT_ROOT/scripts/lib/dispatch.sh")"$'\n'"$(cat "$PROJECT_ROOT/scripts/helpers/agy-exec.sh")"

    if [[ "$agy_block" != *"gemini-exec.sh"* ]] && \
       [[ "$agy_block" != *"-o text"* ]] && \
       [[ "$agy_block" != *"--approval-mode yolo"* ]]; then
        test_pass
    else
        test_fail "agy should not be wrapped as Gemini CLI"
    fi
}

test_agy_provider_detection() {
    test_case "provider detection includes agy"

    if grep -q 'octo_provider_allowed agy' "$PROJECT_ROOT/scripts/lib/providers.sh" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/scripts/lib/providers.sh" && \
       grep -q 'agy:cli' "$PROJECT_ROOT/scripts/lib/providers.sh"; then
        test_pass
    else
        test_fail "providers.sh should detect agy"
    fi
}

test_agy_inherits_environment() {
    test_case "provider routing isolates agy by default with full-env opt-in"

    local agy_block
    agy_block="$(sed -n '/agy\*|antigravity)/,/;;/p' "$PROJECT_ROOT/scripts/lib/provider-routing.sh")"

    if [[ "$agy_block" == *"OCTOPUS_ALLOW_FULL_AGY_ENV"* ]] && \
       [[ "$agy_block" == *"PROVIDER_ENV_ARRAY=(env -i"* ]] && \
       [[ "$agy_block" == *"AGY_AUTH_TOKEN"* ]] && \
       [[ "$agy_block" == *"AGY_CONFIG"* ]] && \
       [[ "$agy_block" == *"ANTIGRAVITY_API_KEY"* ]] && \
       [[ "$agy_block" == *"PROVIDER_ENV_ARRAY=()"* ]]; then
        test_pass
    else
        test_fail "agy should isolate by default and support OCTOPUS_ALLOW_FULL_AGY_ENV=true"
    fi
}

test_agy_spawn_bypasses_timeout_wrapper() {
    test_case "spawn enforces timeout wrapper for agy"

    if grep -q 'octopus_capture_provider_output' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q 'run_with_timeout "$timeout_secs"' "$PROJECT_ROOT/scripts/lib/heartbeat.sh"; then
        test_pass
    else
        test_fail "spawn capture should wrap every provider, including agy, in run_with_timeout"
    fi
}

test_agy_sync_bypasses_timeout_wrapper() {
    test_case "sync dispatch enforces timeout wrapper for agy"

    if grep -q 'agent_type.*agy' "$PROJECT_ROOT/scripts/lib/agent-sync.sh" && \
       sed -n '/^run_agent_sync() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/agent-sync.sh" | grep -q 'run_with_timeout'; then
        test_pass
    else
        test_fail "agent-sync.sh should wrap agy in run_with_timeout"
    fi
}

test_agy_spawn_cli_uses_sync_dispatch() {
    test_case "orchestrate spawn routes direct and persona-resolved agy through sync dispatch"

    if grep -q 'Antigravity CLI print mode does not emit output from background jobs' "$PROJECT_ROOT/scripts/orchestrate.sh" && \
       grep -q 'run_agent_sync "\$_spawn_target" "\$2" "\$TIMEOUT" "\${_spawn_role:-none}" "spawn"' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "orchestrate.sh spawn should run agy synchronously"
    fi
}

test_agy_check_providers() {
    test_case "check-providers reports agy"

    if grep -q 'provider_status "agy"' "$PROJECT_ROOT/scripts/helpers/check-providers.sh"; then
        test_pass
    else
        test_fail "check-providers.sh should report agy status"
    fi
}

test_agy_doctor_provider_check() {
    test_case "doctor reports agy provider status"

    if [[ -x "$PROJECT_ROOT/scripts/doctor.sh" ]] && \
       grep -q 'agy-cli' "$PROJECT_ROOT/scripts/lib/doctor.sh" && \
       grep -q 'OCTO_AGY_MIN_VERSION' "$PROJECT_ROOT/scripts/lib/provider-versions.sh" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/skills/skill-doctor/SKILL.md"; then
        test_pass
    else
        test_fail "doctor should expose agy provider diagnostics and user-facing guidance"
    fi
}

test_agy_doctor_live_probe() {
    test_case "doctor providers --live validates AGY catalog, model, and print dispatch"

    local tmp_bin="$TEST_TMP_DIR/agy-doctor-live-bin"
    local tmp_home="$TEST_TMP_DIR/agy-doctor-live-home"
    local output
    mkdir -p "$tmp_bin" "$tmp_home"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        printf '%s\n' 'agy version 1.1.12'
        exit 0
        ;;
    models)
        printf '%s\t%s\n' 'gemini-test' 'Gemini Test'
        exit 0
        ;;
esac
while (( $# > 0 )); do
    if [[ "$1" == "--print" && $# -ge 2 ]]; then
        printf '%s\n' 'OCTOPUS_AGY_HEALTH_OK'
        printf '%s\n' 'LOCAL_PROVIDER_DISPATCH_WORKS'
        exit 0
    fi
    shift
done
exit 2
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    output="$(
        HOME="$tmp_home" \
        OCTO_ROOT="$PROJECT_ROOT" \
        OCTOPUS_AGY_MODEL='gemini-test' \
        PATH="$tmp_bin:$PATH" \
            bash "$PROJECT_ROOT/scripts/doctor.sh" providers --live --json
    )"

    if jq -e '
        ([.[] | select(.name == "agy-live-catalog" and .status == "pass")] | length) == 1 and
        ([.[] | select(.name == "agy-live-model" and .status == "pass")] | length) == 1 and
        ([.[] | select(.name == "agy-live-dispatch" and .status == "pass")] | length) == 1
    ' <<< "$output" >/dev/null; then
        test_pass
    else
        test_fail "live doctor did not report all AGY stages as passing: $output"
    fi
}

test_agy_doctor_auth_remediation() {
    test_case "AGY live doctor gives the real browser and macOS keychain auth path"

    local tmp_bin="$TEST_TMP_DIR/agy-doctor-auth-bin"
    local tmp_home="$TEST_TMP_DIR/agy-doctor-auth-home"
    local output detail marker="$TEST_TMP_DIR/agy-doctor-auth-dispatched"
    mkdir -p "$tmp_bin" "$tmp_home"
    rm -f "$marker"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        printf '%s\n' 'agy version 1.1.12'
        exit 0
        ;;
    models)
        printf '%s\n' 'keyring authentication unavailable' >&2
        exit 1
        ;;
esac
printf '%s\n' called > "${AGY_DISPATCH_MARKER:?}"
exit 2
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    output="$(
        export HOME="$tmp_home"
        export OCTO_ROOT="$PROJECT_ROOT"
        export AGY_DISPATCH_MARKER="$marker"
        export PATH="$tmp_bin:$PATH"
        export OPENAI_API_KEY=''
        export CURSOR_API_KEY=''
        source "$PROJECT_ROOT/scripts/lib/doctor.sh"
        DOCTOR_LIVE_PROBE=true
        DOCTOR_AGY_LIVE_AUTH_STATUS=not-run
        DOCTOR_RESULTS_NAME=()
        DOCTOR_RESULTS_CAT=()
        DOCTOR_RESULTS_STATUS=()
        DOCTOR_RESULTS_MSG=()
        DOCTOR_RESULTS_DETAIL=()
        doctor_check_providers
        doctor_check_auth
        doctor_output_json
    )"
    detail="$(jq -r '.[] | select(.name == "agy-live-catalog") | .detail' <<< "$output")"

    if jq -e '.[] | select(.name == "agy-live-catalog" and .status == "warn")' \
        <<< "$output" >/dev/null && \
       [[ "$detail" == *"plain 'agy'"* ]] && \
       [[ "$detail" == *"Keychain Access"* ]] && \
       [[ "$detail" != *"agy login"* ]] && \
       ! jq -e '.[] | select(.name == "agy-auth" and .status == "pass")' \
           <<< "$output" >/dev/null && \
       jq -e '.[] | select(.name == "any-provider-auth" and .status == "fail")' \
           <<< "$output" >/dev/null && \
       [[ ! -e "$marker" ]]; then
        test_pass
    else
        test_fail "AGY auth remediation was inaccurate or dispatch ran after catalog failure: $output"
    fi
}

test_agy_doctor_version_probe_is_bounded() {
    test_case "AGY live doctor bounds a stalled version lookup"

    local tmp_bin="$TEST_TMP_DIR/agy-doctor-version-bin"
    local tmp_home="$TEST_TMP_DIR/agy-doctor-version-home"
    local output started elapsed
    mkdir -p "$tmp_bin" "$tmp_home"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        sleep 5
        exit 0
        ;;
    models)
        printf '%s\t%s\n' 'gemini-test' 'Gemini Test'
        exit 0
        ;;
esac
while (( $# > 0 )); do
    if [[ "$1" == "--print" && $# -ge 2 ]]; then
        printf '%s\n' 'OCTOPUS_AGY_HEALTH_OK'
        printf '%s\n' 'LOCAL_PROVIDER_DISPATCH_WORKS'
        exit 0
    fi
    shift
done
exit 2
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    # Keep the wall-clock assertion scoped to the mocked AGY provider. Host
    # CLIs can add unrelated live/auth work to the full doctor invocation.
    started=$(date +%s)
    output="$(
        HOME="$tmp_home" \
        OCTO_ROOT="$PROJECT_ROOT" \
        OCTOPUS_AGY_MODEL='gemini-test' \
        OCTOPUS_AGY_HEALTH_TIMEOUT=1 \
        PATH="$tmp_bin:/usr/bin:/bin" \
            bash "$PROJECT_ROOT/scripts/doctor.sh" providers --live --json
    )"
    elapsed=$(( $(date +%s) - started ))

    if [[ "$elapsed" -le 4 ]] && \
       jq -e '.[] | select(.name == "agy-live-dispatch" and .status == "pass")' \
           <<< "$output" >/dev/null; then
        test_pass
    else
        test_fail "stalled agy --version was not bounded (elapsed=${elapsed}s): $output"
    fi
}

test_agy_auth_guidance_uses_real_cli_flow() {
    test_case "user-facing AGY auth guidance never advertises a nonexistent login subcommand"

    local stale
    stale="$(grep -R -n --include='*.sh' --include='*.md' 'agy login' \
        "$PROJECT_ROOT/.claude/skills" \
        "$PROJECT_ROOT/.cursor-plugin/commands" \
        "$PROJECT_ROOT/skills" \
        "$PROJECT_ROOT/commands" \
        "$PROJECT_ROOT/scripts" \
        "$PROJECT_ROOT/docs" 2>/dev/null || true)"

    if [[ -z "$stale" ]] && \
       grep -q "Launch plain .*agy.*browser sign-in" "$PROJECT_ROOT/docs/TROUBLESHOOTING.md" && \
       grep -q "Keychain Access" "$PROJECT_ROOT/docs/TROUBLESHOOTING.md"; then
        test_pass
    else
        test_fail "stale AGY login guidance remains or the real browser/keychain flow is missing: $stale"
    fi
}

test_agy_setup_visibility() {
    test_case "setup command shows Antigravity provider"

    if grep -q 'printf "agy:%s' "$PROJECT_ROOT/commands/setup.md" && \
       grep -q 'Antigravity CLI (agy)' "$PROJECT_ROOT/commands/setup.md"; then
        test_pass
    else
        test_fail "setup should detect and offer Antigravity CLI"
    fi
}

test_agy_status_visibility() {
    test_case "status dashboard shows Antigravity provider"

    if grep -q 'PROVIDER_AGY_INSTALLED' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'Antigravity:' "$PROJECT_ROOT/scripts/lib/smoke.sh"; then
        test_pass
    else
        test_fail "status should show Antigravity provider"
    fi
}

test_agy_fleet_scoring() {
    test_case "smoke fleet scoring can select agy"

    source "$PROJECT_ROOT/scripts/lib/provider-policy.sh"
    local scorer_block select_block routing_providers
    scorer_block="$(sed -n '/score_provider()/,/^}/p' "$PROJECT_ROOT/scripts/lib/smoke.sh")"
    select_block="$(sed -n '/select_provider()/,/^}/p' "$PROJECT_ROOT/scripts/lib/smoke.sh")"
    routing_providers="$(octo_smoke_routing_providers)"

    if [[ "$scorer_block" == *"agy)"* ]] &&        [[ "$scorer_block" == *"PROVIDER_AGY_INSTALLED"* ]] &&        [[ " $routing_providers " == *" agy "* ]] &&        [[ "$select_block" == *"octo_smoke_routing_providers"* ]] &&        [[ "$select_block" == *'echo "agy"'* ]]; then
        test_pass
    else
        test_fail "score_provider/select_provider should include agy through shared smoke policy"
    fi
}

test_agy_smoke_defaults() {
    test_case "smoke defaults keep agy and opencode priorities distinct"

    if grep -q 'PROVIDER_AGY_TIER="subscription"' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'PROVIDER_AGY_TIER="${PROVIDER_AGY_TIER:-subscription}"' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'PROVIDER_AGY_COST_TIER="${PROVIDER_AGY_COST_TIER:-bundled}"' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       ! grep -q 'PROVIDER_AGY_TIER="${OCTOPUS_AGY_MODEL' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'PROVIDER_OPENCODE_PRIORITY="${PROVIDER_OPENCODE_PRIORITY:-5}"' "$PROJECT_ROOT/scripts/lib/smoke.sh"; then
        test_pass
    else
        test_fail "smoke defaults should use agy subscription tier and opencode priority 5"
    fi
}

test_agy_preflight_visibility() {
    test_case "provider detection emits and caches valid and invalid Antigravity models"

    local fixture_bin="$TEST_TMP_DIR/agy-preflight-bin"
    local fixture_home="$TEST_TMP_DIR/agy-preflight-home"
    local valid_workspace="$TEST_TMP_DIR/agy-preflight-valid"
    local invalid_workspace="$TEST_TMP_DIR/agy-preflight-invalid"
    local jq_path valid_output invalid_output
    mkdir -p "$fixture_bin" "$fixture_home" "$valid_workspace" "$invalid_workspace"
    jq_path="$(command -v jq)"
    ln -s "$jq_path" "$fixture_bin/jq"
    cat > "$fixture_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then
    printf '%s\t%s\n' \
        'gemini-3.5-flash-low' 'Gemini 3.5 Flash (Low)' \
        'claude-sonnet-4-6' 'Claude Sonnet 4.6 (Thinking)'
fi
MOCK_AGY
    chmod +x "$fixture_bin/agy"

    run_agy_detection_fixture() {
        local model="$1"
        local workspace="$2"
        (
            PATH="$fixture_bin:/usr/bin:/bin"
            HOME="$fixture_home"
            WORKSPACE_DIR="$workspace"
            OCTOPUS_AGY_MODEL="$model"
            export PATH HOME WORKSPACE_DIR OCTOPUS_AGY_MODEL
            check_claude_version() {
                printf '%s\n' \
                    'CLAUDE_CODE_STATUS=ok' \
                    'CLAUDE_CODE_VERSION=2.1.229' \
                    'CLAUDE_CODE_MINIMUM=2.1.0'
            }
            _is_cursor_agent_binary() { return 1; }
            source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
            source "$PROJECT_ROOT/scripts/lib/preflight.sh"
            cmd_detect_providers
        )
    }

    valid_output="$(run_agy_detection_fixture 'gemini-3.5-flash-low' "$valid_workspace" 2>/dev/null)"
    invalid_output="$(run_agy_detection_fixture 'gemini-9-unknown' "$invalid_workspace" 2>/dev/null)"
    unset -f run_agy_detection_fixture

    if grep -q '^AGY_STATUS=ok$' <<< "$valid_output" &&
       grep -q '^AGY_STATUS=ok$' "$valid_workspace/.provider-cache" &&
       grep -q '^AGY_STATUS=model-invalid$' <<< "$invalid_output" &&
       grep -q '^AGY_STATUS=model-invalid$' "$invalid_workspace/.provider-cache"; then
        test_pass
    else
        test_fail "provider detection output/cache did not preserve AGY model status"
    fi
}

test_agy_fleet_builder() {
    test_case "runtime admission seats agy in the fleet"

    local fixture_home="$TEST_TMP_DIR/agy-admission-home"
    local fixture_bin="$TEST_TMP_DIR/agy-admission-bin"
    local status fleet
    mkdir -p "$fixture_home" "$fixture_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture_bin/agy"
    chmod +x "$fixture_bin/agy"
    status=$(env \
        "HOME=$fixture_home" \
        "PATH=$fixture_bin:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=agy" \
        bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null)
    fleet=$(env \
        "HOME=$fixture_home" \
        "PATH=$fixture_bin:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=agy" \
        "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" research quick fixture 2>/dev/null)

    if grep -q '^agy:available$' <<< "$status" && grep -q '^agy|' <<< "$fleet"; then
        test_pass
    else
        test_fail "AGY admission or fleet seating failed: status=$status fleet=$fleet"
    fi
}

test_agy_allowlist_alias() {
    test_case "provider allowlist accepts agy and antigravity"

    source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
    local agy_ok=false alias_ok=false
    local had_allowlist=false previous_allowlist=""
    if [[ ${OCTO_ALLOWED_PROVIDERS+x} ]]; then had_allowlist=true; previous_allowlist="$OCTO_ALLOWED_PROVIDERS"; fi
    OCTO_ALLOWED_PROVIDERS=agy
    octo_provider_allowed agy && agy_ok=true
    OCTO_ALLOWED_PROVIDERS=antigravity
    octo_provider_allowed agy && alias_ok=true
    if [[ "$had_allowlist" == true ]]; then OCTO_ALLOWED_PROVIDERS="$previous_allowlist"; else unset OCTO_ALLOWED_PROVIDERS; fi

    if [[ "$agy_ok" == true && "$alias_ok" == true ]]; then
        test_pass
    else
        test_fail "provider allowlist should accept agy and antigravity behaviorally"
    fi
}

test_agy_routing_resolver() {
    test_case "routing resolver accepts agy debate participants"

    if grep -q 'agy|agy-research|antigravity' "$PROJECT_ROOT/scripts/lib/routing.sh" && \
       grep -q 'Antigravity' "$PROJECT_ROOT/scripts/lib/routing.sh"; then
        test_pass
    else
        test_fail "routing.sh should resolve agy debate participants"
    fi
}

test_agy_external_output_wrapped() {
    test_case "agy output is wrapped as untrusted external CLI output"

    if grep -q 'agy.*antigravity' "$PROJECT_ROOT/scripts/lib/validation.sh"; then
        test_pass
    else
        test_fail "validation.sh should wrap agy output"
    fi
}

test_agy_issue_reference() {
    test_case "agy provider config references issue #423"

    if grep -q '#423' "$PROJECT_ROOT/config/providers/agy/CLAUDE.md"; then
        test_pass
    else
        test_fail "provider config should reference #423"
    fi
}

test_agy_docs_cost_and_marker() {
    test_case "docs show agy cost controls and distinct provider marker"

    if grep -q 'OCTOPUS_AGY_MODEL' "$PROJECT_ROOT/CLAUDE.md" && \
       grep -q 'Four providers cost nothing extra' "$PROJECT_ROOT/README.md" && \
       grep -q '🧭 Antigravity CLI (`agy`)' "$PROJECT_ROOT/README.md" && \
       ! grep -q '🟢 Antigravity CLI (`agy`)' "$PROJECT_ROOT/README.md"; then
        test_pass
    else
        test_fail "docs should document agy cost/model behavior and use a distinct provider marker"
    fi
}

test_agy_slash_command_visibility() {
    test_case "commands and skills include agy in provider-facing prompts"

    if grep -q 'Codex and Antigravity' "$PROJECT_ROOT/commands/security.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/plan.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/review.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/factory.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/auto.md" && \
       grep -q 'checkCommandAvailable.*agy' "$PROJECT_ROOT/commands/multi.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/commands/brainstorm.md" && \
       grep -q 'Antigravity (agy)' "$PROJECT_ROOT/commands/model-config.md" && \
       grep -q 'claude,codex,agy' "$PROJECT_ROOT/commands/council.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/commands/debate.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-discover/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-develop/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-define/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-deliver/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/SECURITY.md" && \
       grep -q 'up to 10 external AI integrations' "$PROJECT_ROOT/PRODUCT.md" && \
       grep -q 'Four providers can cost nothing extra' "$PROJECT_ROOT/PRODUCT.md" && \
       grep -q 'codex agy' "$PROJECT_ROOT/tests/test-fleet-diversity.sh" && \
       grep -q 'codex, agy' "$PROJECT_ROOT/tests/unit/test-research-fanout-static.sh"; then
        test_pass
    else
        test_fail "provider-facing commands, skills, and docs should expose agy alongside other external providers"
    fi
}

test_agy_slash_command_no_stale_three_provider_copy() {
    test_case "commands, skills, and docs avoid stale Codex/Gemini-only multi-LLM copy"

    local stale
    stale=$(grep -R -nE 'Claude \+ Codex \+ Gemini|Codex \+ Gemini \+ Claude|Codex \+ Gemini|Codex/Gemini|Codex and Gemini|all three AI|all three providers|three-model|four-way debate|four-way debates|configure Codex and Gemini|2/3 providers|Providers: 🔴 Codex \| 🟡 Gemini \| 🔵 Claude|Providers: Codex \| Gemini \| Claude|\(🔴 🟡 🔵\)' \
        "$PROJECT_ROOT/commands" "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/docs" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/.claude-plugin/README.md" "$PROJECT_ROOT/SECURITY.md" "$PROJECT_ROOT/PRODUCT.md" "$PROJECT_ROOT/tests/test-fleet-diversity.sh" "$PROJECT_ROOT/tests/unit/test-research-fanout-static.sh" \
        | grep -v 'commands/resume.md' \
        | grep -v 'commands/extract.md:.*Extract all 8 features' \
        | grep -v 'docs/superpowers/specs/' \
        | grep -v 'docs/superpowers/plans/' \
        | grep -v 'docs/COMMAND-REFERENCE.md:.*transcripts' || true)

    if [[ -z "$stale" ]]; then
        test_pass
    else
        test_fail "stale provider copy remains: $stale"
    fi
}

test_agy_debate_skill_uses_runtime_advisors() {
    test_case "debate skill uses runtime advisor routing instead of hardcoded Gemini"

    local debate_files=(
        "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md"
        "$PROJECT_ROOT/skills/skill-debate/SKILL.md"
    )
    local stale
    stale=$(grep -nE 'ADVISORS="gemini,codex"|Consult Gemini|gemini -p|r001_gemini|GEMINI_RESPONSE|Gemini/Codex CLI|Codex/Gemini|codex exec --skip-git-repo-check|when available when available' "${debate_files[@]}" || true)

    if [[ -z "$stale" ]] && \
       grep -q 'orchestrate.sh" spawn "$advisor"' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'claude\*|codex\*|gemini\*|agy\*' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'orchestrate.sh" spawn "$advisor"' "$PROJECT_ROOT/skills/skill-debate/SKILL.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/skills/skill-debate/SKILL.md" && \
       grep -q 'claude\*|codex\*|gemini\*|agy\*' "$PROJECT_ROOT/skills/skill-debate/SKILL.md"; then
        test_pass
    else
        test_fail "debate skill should dispatch runtime advisors through orchestrate.sh and include agy fallback; stale copy: $stale"
    fi
}

test_user_facing_docs_route_external_provider_dispatch() {
    test_case "user-facing commands and skills route external provider dispatch through Octopus"

    local stale
    stale=$(grep -R -nE 'codex exec --skip-git-repo-check|gemini -p "" -o text|ADVISORS="gemini,codex"|GEMINI_RESPONSE|r001_gemini|Gemini/Codex CLI|Codex/Gemini' \
        "$PROJECT_ROOT/commands" \
        "$PROJECT_ROOT/.claude/skills" \
        "$PROJECT_ROOT/.cursor-plugin/commands" \
        "$PROJECT_ROOT/skills" \
        | grep -v 'codex --full-auto' \
        | grep -v 'codex -q' \
        | grep -v 'codex -y' \
        | grep -v 'gemini -y' || true)

    if [[ -z "$stale" ]]; then
        test_pass
    else
        test_fail "direct provider dispatch remains in user-facing docs: $stale"
    fi
}

test_provider_aware_commands_show_core_provider_status() {
    test_case "provider-aware slash commands show Codex, Antigravity, and Perplexity status"

    local missing=""
    local commands=(
        auto
        brainstorm
        embrace
        factory
        plan
        review
    )

    local command
    for command in "${commands[@]}"; do
        local claude_file="$PROJECT_ROOT/commands/${command}.md"
        local cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo-${command}.md"
        if [[ ! -f "$cursor_file" && "$command" == "auto" ]]; then
            cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo.md"
        fi

        for file in "$claude_file" "$cursor_file"; do
            if [[ ! -f "$file" ]]; then
                missing+="${file}: file missing"$'\n'
                continue
            fi

            grep -q 'Codex CLI: \[Available ✓ / Not installed ✗\]' "$file" || missing+="${file}: missing Codex status"$'\n'
            grep -q 'Antigravity CLI: \[Available ✓ / Not installed ✗\]' "$file" || missing+="${file}: missing Antigravity status"$'\n'
            grep -q 'Perplexity: \[Configured ✓ / Not configured ✗\]' "$file" || missing+="${file}: missing Perplexity status"$'\n'
        done
    done

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "provider-aware slash command banners must show core provider statuses: $missing"
    fi
}

test_review_command_generates_antigravity_banner() {
    test_case "review command renders Antigravity status from provider probe"

    local missing=""
    local files=(
        "$PROJECT_ROOT/commands/review.md"
        "$PROJECT_ROOT/.cursor-plugin/commands/octo-review.md"
    )

    local file
    for file in "${files[@]}"; do
        grep -q 'Do not hand-write or summarize this banner' "$file" || missing+="${file}: missing generated-banner instruction"$'\n'
        grep -q 'agy_status="$(status_cli agy)"' "$file" || missing+="${file}: missing agy status assignment"$'\n'
        grep -q '🧭 Antigravity CLI: ${agy_status}' "$file" || missing+="${file}: missing rendered Antigravity status line"$'\n'
    done

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "review command must render Antigravity in the provider banner: $missing"
    fi
}

test_provider_aware_commands_generate_antigravity_banners() {
    test_case "provider-aware commands generate Antigravity-visible banners"

    local missing=""
    local commands=(
        auto
        brainstorm
        embrace
        factory
        plan
        review
    )

    local command
    for command in "${commands[@]}"; do
        local claude_file="$PROJECT_ROOT/commands/${command}.md"
        local cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo-${command}.md"
        for file in "$claude_file" "$cursor_file"; do
            grep -q 'Do not hand-write or summarize this' "$file" || missing+="${file}: missing generated-banner instruction"$'\n'
            grep -q 'agy_status="$(status_cli agy)"' "$file" || missing+="${file}: missing agy status assignment"$'\n'
            grep -q 'Antigravity.*${agy_status}' "$file" || missing+="${file}: missing rendered Antigravity status line"$'\n'
        done
    done

    for file in "$PROJECT_ROOT/commands/setup.md" "$PROJECT_ROOT/.cursor-plugin/commands/octo-setup.md"; do
        grep -q 'Do not hand-write or summarize this provider block' "$file" || missing+="${file}: missing generated setup table instruction"$'\n'
        grep -q 'agy_status="$(status_installed agy)"' "$file" || missing+="${file}: missing setup agy status assignment"$'\n'
        grep -q '🧭 Antigravity:    ${agy_status}' "$file" || missing+="${file}: missing setup Antigravity status line"$'\n'
    done

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "provider-aware commands must generate Antigravity-visible banners: $missing"
    fi
}

test_provider_workflow_review_regressions() {
    test_case "provider workflow snippets avoid Round 2 review regressions"

    local missing=""
    local brainstorm_files=(
        "$PROJECT_ROOT/commands/brainstorm.md"
        "$PROJECT_ROOT/.cursor-plugin/commands/octo-brainstorm.md"
    )

    local file
    for file in "${brainstorm_files[@]}"; do
        grep -q 'ORCH_HELP="$("$ORCH" 2>&1 || true)"' "$file" || missing+="${file}: missing pipefail-safe orchestrator probe"$'\n'
        grep -q 'trap '\''rm -rf "$RUN_DIR"'\'' EXIT' "$file" || missing+="${file}: missing tempdir cleanup trap"$'\n'
        grep -q 'claude\*|codex\*|gemini\*|agy\*' "$file" || missing+="${file}: missing claude advisor allowlist"$'\n'
    done

    grep -q 'CLAUDE_PLUGIN_ROOT:-' "$PROJECT_ROOT/commands/setup.md" || missing+="commands/setup.md: setup root not plugin-anchored"$'\n'
    grep -q 'CLAUDE_PLUGIN_ROOT:-' "$PROJECT_ROOT/.cursor-plugin/commands/octo-setup.md" || missing+=".cursor-plugin/commands/octo-setup.md: setup root not plugin-anchored"$'\n'

    if grep -R -n '\${agy_status}' "$PROJECT_ROOT/.claude/skills/flow-deliver" "$PROJECT_ROOT/skills/flow-deliver" >/dev/null 2>&1; then
        missing+="flow-deliver: stale agy_status placeholder remains"$'\n'
    fi

    if grep -R -n -- '--rounds 3' "$PROJECT_ROOT/.claude/skills/flow-define" "$PROJECT_ROOT/skills/flow-define" >/dev/null 2>&1; then
        missing+="flow-define: restored debate should not use --rounds 3"$'\n'
    fi

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "provider workflow review regressions remain: $missing"
    fi
}

test_agy_config_exists
test_agy_available_agent
test_agy_model_config_provider
test_agy_dispatch_native_flags
test_agy_print_timeout_gets_a_unit
test_agy_print_receives_prompt_argument
test_agy_review_sized_prompt_dispatches_promptly
test_agy_review_sized_silent_output_retries_promptly
test_agy_force_inline_directive_prepended_by_default
test_agy_file_prompt_directive_permits_reading_prompt_file
test_agy_oversize_payload_skips_gracefully
test_agy_oversize_ceiling_is_configurable
test_agy_oversize_uses_documented_default_ceiling
test_agy_oversize_default_ceiling_dispatches_at_the_limit
test_agy_pty_fallback_salvages_tty_error
test_agy_pty_fallback_opt_out
test_agy_dynamic_model_validation
test_agy_catalog_lookup_timeout
test_agy_command_validation
test_agy_dispatch_not_gemini_wrapper
test_agy_provider_detection
test_agy_inherits_environment
test_agy_spawn_bypasses_timeout_wrapper
test_agy_sync_bypasses_timeout_wrapper
test_agy_spawn_cli_uses_sync_dispatch
test_agy_check_providers
test_agy_doctor_provider_check
test_agy_doctor_live_probe
test_agy_doctor_auth_remediation
test_agy_doctor_version_probe_is_bounded
test_agy_auth_guidance_uses_real_cli_flow
test_agy_setup_visibility
test_agy_status_visibility
test_agy_fleet_scoring
test_agy_smoke_defaults
test_agy_preflight_visibility
test_agy_fleet_builder
test_agy_allowlist_alias
test_agy_routing_resolver
test_agy_external_output_wrapped
test_agy_issue_reference
test_agy_docs_cost_and_marker
test_agy_slash_command_visibility
test_agy_slash_command_no_stale_three_provider_copy
test_agy_debate_skill_uses_runtime_advisors
test_user_facing_docs_route_external_provider_dispatch
test_provider_aware_commands_show_core_provider_status
test_review_command_generates_antigravity_banner
test_provider_aware_commands_generate_antigravity_banners
test_provider_workflow_review_regressions

test_summary
