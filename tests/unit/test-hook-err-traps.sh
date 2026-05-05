#!/usr/bin/env bash
# tests/unit/test-hook-err-traps.sh
# Regression test for issue #313 — "No stderr output" silent hook failures.
#
# Enforces:
#   1. Every hook that uses `set -e` also installs an EXIT trap that emits
#      diagnostic stderr on non-zero exit.
#   2. Every hook exits 0 under a minimal valid UserPromptSubmit-ish input
#      (no silent pre-existing failures in the ``careful-check / freeze-check /
#      quality-gate`` grep pipelines).
#   3. A deliberately broken copy of a hook emits readable stderr (trap fires).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Hook ERR/EXIT trap hygiene (issue #313)"

VALID_STDIN='{"hook_event_name":"UserPromptSubmit","session_id":"test","cwd":"/tmp","prompt":"test","transcript_path":"/dev/null"}'
HOOK_TIMEOUT_SECONDS="${HOOK_TIMEOUT_SECONDS:-5}"

run_hook_with_deadline() {
    local hook="$1"
    local err_out="$2"
    local out_out="${3:-/dev/null}"
    local home_dir code

    home_dir=$(mktemp -d "$TEST_TMP_DIR/hook-home-$(basename "$hook" .sh).XXXXXX")
    code=0
    VALID_STDIN_ENV="$VALID_STDIN" \
    HOOK_PATH="$hook" \
    ERR_OUT="$err_out" \
    OUT_OUT="$out_out" \
    HOME_DIR="$home_dir" \
    PROJECT_ROOT_ENV="$PROJECT_ROOT" \
    CLAUDE_SESSION_ID_ENV="test-session" \
    HOOK_TIMEOUT_SECONDS_ENV="$HOOK_TIMEOUT_SECONDS" \
    python3 <<'PY' || code=$?
import os
import subprocess
import sys

hook = os.environ["HOOK_PATH"]
payload = os.environ["VALID_STDIN_ENV"] + "\n"
timeout = float(os.environ["HOOK_TIMEOUT_SECONDS_ENV"])

env = os.environ.copy()
env["HOME"] = os.environ["HOME_DIR"]
env["CLAUDE_PLUGIN_ROOT"] = os.environ["PROJECT_ROOT_ENV"]
env["CLAUDE_SESSION_ID"] = os.environ["CLAUDE_SESSION_ID_ENV"]

with open(os.environ["OUT_OUT"], "wb") as stdout, open(os.environ["ERR_OUT"], "wb") as stderr:
    try:
        result = subprocess.run(
            ["bash", hook],
            input=payload.encode(),
            stdout=stdout,
            stderr=stderr,
            env=env,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        stderr.write(f"hook timed out after {timeout:g}s\n".encode())
        sys.exit(124)

sys.exit(result.returncode)
PY
    rm -rf "$home_dir"
    return "$code"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Every hook using `set -e` has the trap
# ═══════════════════════════════════════════════════════════════════════════════

test_all_set_e_hooks_have_exit_trap() {
    test_case "all hooks using 'set -e' also register an EXIT trap"
    local missing=()
    for hook in "$PROJECT_ROOT"/hooks/*.sh; do
        if grep -qE '^set -[eu]' "$hook" 2>/dev/null; then
            if ! grep -qE 'trap _octo_hook_(err|exit)' "$hook" 2>/dev/null; then
                missing+=("$(basename "$hook")")
            fi
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        test_pass
    else
        test_fail "hooks missing trap: ${missing[*]}"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Every hook exits 0 under a minimal valid UserPromptSubmit payload
# (detects pre-existing silent failures like the careful-check/freeze-check/quality-gate bugs)
# ═══════════════════════════════════════════════════════════════════════════════

test_all_hooks_exit_clean_on_valid_input() {
    test_case "no event-registered hook exits non-zero on minimal UserPromptSubmit stdin"
    local failing=()
    # Only test hooks actually registered in hooks.json — statusline-resolver /
    # octopus-statusline live in hooks/ but are standalone runners, not event
    # hooks, and would legitimately block on statusline-specific input.
    local registered
    registered=$(jq -r '.. | objects | .command? | select(.) | select(type=="string")' \
        "$PROJECT_ROOT/.claude-plugin/hooks.json" 2>/dev/null \
        | grep -oE '[a-z][a-z0-9-]+\.sh' | sort -u)
    for hook_name in $registered; do
        local hook="$PROJECT_ROOT/hooks/$hook_name"
        [[ ! -f "$hook" ]] && continue
        local err_out code err
        err_out=$(mktemp)
        # `|| code=$?` both suppresses the framework's set -e and captures the
        # real exit code. Without it, a non-zero hook aborts the test before
        # test_fail runs — CI shows "FAIL" with no detail.
        code=0
        run_hook_with_deadline "$hook" "$err_out" >/dev/null || code=$?
        err=$(<"$err_out")
        rm -f "$err_out"
        if [[ $code -ne 0 ]]; then
            # Truncate stderr to avoid log overflow; embed for diagnosis
            local short_err="${err:0:120}"
            failing+=("$hook_name:exit=$code:stderr='$short_err'")
        fi
    done
    if [[ ${#failing[@]} -eq 0 ]]; then
        test_pass
    else
        test_fail "hooks failing on valid stdin: ${failing[*]}"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Trap semantics — a deliberately broken hook must emit readable stderr
# ═══════════════════════════════════════════════════════════════════════════════

test_trap_emits_stderr_on_forced_failure() {
    test_case "EXIT trap emits diagnostic stderr when hook exits non-zero"
    # Copy a real hook, inject a `false` AFTER the trap line, verify stderr
    local src="$PROJECT_ROOT/hooks/user-prompt-submit.sh"
    local tmp
    tmp=$(mktemp)
    # Insert `false` after the `trap _octo_hook_exit EXIT` line
    awk '{print} /^trap _octo_hook_exit EXIT$/ && !done {print "false"; done=1}' "$src" > "$tmp"
    local err_out code err
    err_out=$(mktemp)
    # `|| code=$?` both suppresses set -e and captures the real exit code.
    code=0
    run_hook_with_deadline "$tmp" "$err_out" >/dev/null || code=$?
    err=$(<"$err_out")
    rm -f "$tmp" "$err_out"
    # Match on the stable "[hook:...] exit" pattern; the copied file has a random basename
    if [[ $code -ne 0 && "$err" == *"[hook:"*"] exit"* ]]; then
        test_pass
    else
        test_fail "expected exit!=0 with '[hook:...] exit' stderr, got exit=$code stderr='$err'"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Trap does NOT over-fire — normal clean exit produces no trap output
# ═══════════════════════════════════════════════════════════════════════════════

test_trap_silent_on_clean_exit() {
    test_case "EXIT trap stays silent when hook exits 0"
    local hook="$PROJECT_ROOT/hooks/user-prompt-submit.sh"
    local err_out err
    err_out=$(mktemp)
    run_hook_with_deadline "$hook" "$err_out" >/dev/null
    err=$(<"$err_out")
    rm -f "$err_out"
    if [[ "$err" != *"[hook:"* ]]; then
        test_pass
    else
        test_fail "trap over-fired on clean exit: stderr='$err'"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Specific regressions — the 3 pre-existing silent failures
# ═══════════════════════════════════════════════════════════════════════════════

test_careful_check_no_silent_fail_on_non_tool_input() {
    test_case "careful-check.sh exits 0 on UserPromptSubmit stdin (was silent fail before #313 fix)"
    local err_out code
    err_out=$(mktemp)
    local code=0
    run_hook_with_deadline "$PROJECT_ROOT/hooks/careful-check.sh" "$err_out" >/dev/null || code=$?
    local err=$(<"$err_out")
    rm -f "$err_out"
    if [[ $code -eq 0 ]]; then test_pass; else test_fail "exit=$code stderr='${err:0:120}'"; fi
}

test_freeze_check_no_silent_fail_on_non_tool_input() {
    test_case "freeze-check.sh exits 0 on UserPromptSubmit stdin (was silent fail before #313 fix)"
    local err_out code err
    err_out=$(mktemp)
    code=0
    run_hook_with_deadline "$PROJECT_ROOT/hooks/freeze-check.sh" "$err_out" >/dev/null || code=$?
    err=$(<"$err_out")
    rm -f "$err_out"
    if [[ $code -eq 0 ]]; then test_pass; else test_fail "exit=$code stderr='${err:0:120}'"; fi
}

test_quality_gate_no_silent_fail_on_missing_validation() {
    test_case "quality-gate.sh exits 0 when no tangle-validation-*.md exists (was silent fail before #313 fix)"
    # Explicitly simulate a fresh environment (no ~/.claude-octopus/results/)
    # — this was the exact failure path that CI hit but local repro missed.
    local err_out code err
    err_out=$(mktemp)
    code=0
    run_hook_with_deadline "$PROJECT_ROOT/hooks/quality-gate.sh" "$err_out" >/dev/null || code=$?
    err=$(<"$err_out")
    rm -f "$err_out"
    if [[ $code -eq 0 ]]; then test_pass; else test_fail "exit=$code stderr='${err:0:120}'"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_all_set_e_hooks_have_exit_trap
test_all_hooks_exit_clean_on_valid_input
test_trap_emits_stderr_on_forced_failure
test_trap_silent_on_clean_exit
test_careful_check_no_silent_fail_on_non_tool_input
test_freeze_check_no_silent_fail_on_non_tool_input
test_quality_gate_no_silent_fail_on_missing_validation

test_summary
