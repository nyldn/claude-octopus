#!/usr/bin/env bash
# Antigravity CLI stdin adapter.
#
# This intentionally stays a thin, env-driven adapter. It does NOT implement a
# model-fallback chain or an error classifier the way the Gemini adapter does:
# agy's model catalog and error strings are not verified here (agy may be
# unauthenticated on a given box), and forcing a specific --model pushes agy onto
# an exhaustible quota group. The only added robustness is provider-agnostic — a
# single replay-from-cached-stdin retry on a silent-empty success.
set -euo pipefail

# Default to "default" → don't pass --model, so agy uses the model you picked in
# its own `/model` UI (e.g. Gemini 3.5 Flash Medium). The old default ("Claude
# Sonnet 4.6 (Thinking)") forced agy onto the Claude/GPT quota group, which can be
# exhausted → agy returns empty and the council seat silently fails. Override per
# run with OCTOPUS_AGY_MODEL if you want a specific model.
model="${OCTOPUS_AGY_MODEL:-default}"
print_timeout="${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}"

# --dangerously-skip-permissions: auto-approve agy's folder-trust + tool prompts so
# council seats don't block on a per-worktree trust prompt (already --sandbox'd).
# OCTOPUS_AGY_SANDBOX=off drops the sandbox restriction (mirror of the Gemini
# OCTOPUS_GEMINI_SANDBOX switch); the default keeps it on.
cmd=(agy --print --sandbox --dangerously-skip-permissions --print-timeout "$print_timeout")
if [[ "${OCTOPUS_AGY_SANDBOX:-on}" == "off" ]]; then
    cmd=(agy --print --dangerously-skip-permissions --print-timeout "$print_timeout")
fi

if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
fi

# agy confines reads to its workspace; whitelist extra dirs (e.g. a /tmp staging
# dir) the prompt references. Comma-separated, mirrors OCTOPUS_GEMINI_INCLUDE_DIRS.
if [[ -n "${OCTOPUS_AGY_INCLUDE_DIRS:-}" ]]; then
    IFS=',' read -r -a _agy_dirs <<< "$OCTOPUS_AGY_INCLUDE_DIRS"
    for _d in "${_agy_dirs[@]}"; do
        [[ -n "$_d" ]] && cmd+=(--add-dir "$_d")
    done
fi

# agy --print reads the prompt from stdin; cache it so a retry can replay it
# (stdin is consumed once). Buffer stdout to a file to preserve output fidelity.
prompt_file=""
stdout_file=$(mktemp -t "octo-agy-stdout.XXXXXX")
trap 'rm -f "${prompt_file:-}" "${stdout_file:-}"' EXIT
# INT/TERM must actually terminate (bash otherwise resumes after the handler);
# the EXIT trap still runs the cleanup on the way out.
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ ! -t 0 ]]; then
    prompt_file=$(mktemp -t "octo-agy-prompt.XXXXXX")
    cat > "$prompt_file"
fi

run_agy() {
    : > "$stdout_file"
    if [[ -n "$prompt_file" ]]; then
        "${cmd[@]}" < "$prompt_file" > "$stdout_file"
    else
        "${cmd[@]}" > "$stdout_file"
    fi
}

set +e
run_agy
rc=$?
# Retry once on a silent-empty success (a documented agy failure mode), replaying
# the cached prompt. Keyed on emptiness, not on any provider error string.
content=$(<"$stdout_file")
if [[ $rc -eq 0 && -z "${content//[$' \t\r\n']/}" && -n "$prompt_file" && "${OCTOPUS_AGY_NO_RETRY:-}" != "1" ]]; then
    run_agy
    rc=$?
fi
set -e

cat "$stdout_file"
exit "$rc"
