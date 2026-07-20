#!/usr/bin/env bash
# Antigravity CLI stdin-to-argument adapter.
#
# This intentionally stays a thin, env-driven adapter. It does NOT implement a
# model-fallback chain or an error classifier the way the Gemini adapter does:
# agy's model catalog and error strings are not verified here (agy may be
# unauthenticated on a given box), and forcing a specific --model pushes agy onto
# an exhaustible quota group. The only added robustness is provider-agnostic — a
# single replay-from-cached-stdin retry on a silent-empty success.
#
# Prompt delivery: current agy takes the prompt as --print's ARGUMENT VALUE and
# ignores stdin in print mode; with `--print` placed before other flags, agy
# reads the NEXT FLAG as the message. Empirically probed 2026-07-11: piping the
# prompt to `agy --print --sandbox ...` delivers no task at all — the seat then
# answers from its own instruction-file context instead of the council prompt.
# So this adapter still ACCEPTS the prompt on stdin (the dispatch contract),
# but hands it to agy as the --print value, with all other flags placed first.
set -euo pipefail

# Default to "default" → don't pass --model, so agy uses the model you picked in
# its own `/model` UI (e.g. Gemini 3.5 Flash Medium). The old default ("Claude
# Sonnet 4.6 (Thinking)") forced agy onto the Claude/GPT quota group, which can be
# exhausted → agy returns empty and the council seat silently fails. Override per
# run with OCTOPUS_AGY_MODEL if you want a specific model.
model="${OCTOPUS_AGY_MODEL:-default}"
print_timeout="${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}"

# agy (jetski) resolves its home/log/AppData config dir by expanding %USERPROFILE%.
# On Windows/Git Bash the orchestrator's spawn context can drop USERPROFILE from
# agy's environment, so agy crashes at startup (exit 1) with
# "%userprofile% is not defined" before it ever reads the prompt, so the council
# seat fails silently. Re-derive and export it from any available source so agy
# always starts. Gated to Windows shell environments (MSYS/MinGW/Cygwin) so a
# macOS/Linux host, where USERPROFILE is normally unset and unused, is never
# given a spurious one; exported only when a fallback actually resolved a value,
# so an empty USERPROFILE is never exported.
# Reproduce with: env -u USERPROFILE agy --print "say ok"
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        if [[ -z "${USERPROFILE:-}" ]]; then
            if [[ -n "${HOME:-}" ]] && command -v cygpath >/dev/null 2>&1; then
                USERPROFILE="$(cygpath -w "$HOME" 2>/dev/null)"
            fi
            if [[ -z "${USERPROFILE:-}" && -n "${HOMEDRIVE:-}" && -n "${HOMEPATH:-}" ]]; then
                USERPROFILE="${HOMEDRIVE}${HOMEPATH}"
            fi
            if [[ -z "${USERPROFILE:-}" && -n "${HOME:-}" ]]; then
                USERPROFILE="$HOME"
            fi
            if [[ -n "${USERPROFILE:-}" ]]; then
                export USERPROFILE
            fi
        fi
        ;;
esac

# --dangerously-skip-permissions: auto-approve agy's folder-trust + tool prompts so
# council seats don't block on a per-worktree trust prompt (already --sandbox'd).
# OCTOPUS_AGY_SANDBOX=off drops the sandbox restriction; the default keeps it on.
# Built incrementally so the sandbox toggle can't drift out of lockstep with the
# shared flags (this PR had to edit two duplicate array literals in step).
# NOTE: --print is deliberately NOT in this array — it must come LAST with the
# prompt as its value (see prompt-delivery note in the header).
cmd=(agy)
if [[ "${OCTOPUS_AGY_SANDBOX:-on}" != "off" ]]; then
    cmd+=(--sandbox)
fi
cmd+=(--dangerously-skip-permissions --print-timeout "$print_timeout")

# Model-pin guard adopted from #555: query-free, treats agy/default as "no pin".
case "$model" in
    ""|default|agy/default)
        ;;
    *)
        cmd+=(--model "$model")
        ;;
esac

# agy confines reads to its workspace; whitelist extra dirs (e.g. a /tmp staging
# dir) the prompt references. Comma-separated.
if [[ -n "${OCTOPUS_AGY_INCLUDE_DIRS:-}" ]]; then
    IFS=',' read -r -a _agy_dirs <<< "$OCTOPUS_AGY_INCLUDE_DIRS"
    for _d in "${_agy_dirs[@]}"; do
        [[ -n "$_d" ]] && cmd+=(--add-dir "$_d")
    done
fi

# The dispatch contract still delivers the prompt on OUR stdin; cache it so a
# retry can replay it (stdin is consumed once) and so it can be handed to agy as
# the --print argument. Buffer stdout to a file to preserve output fidelity.
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

# No prompt on stdin = nothing to dispatch. Fail loudly rather than invoking agy
# promptless — a promptless print-mode agy answers from its own instruction-file
# context, which is precisely the silent-degenerate-seat failure this adapter
# exists to prevent. Read the content once here: $(<file) strips trailing
# whitespace, so a whitespace-only payload would pass a byte-size (-s) check yet
# still hand agy an empty --print value — the stripped content, not the file
# size, is what must be non-empty.
prompt_content=""
[[ -n "$prompt_file" ]] && prompt_content="$(<"$prompt_file")"
if [[ -z "${prompt_content//[[:space:]]/}" ]]; then
    echo "agy-exec.sh: no prompt received on stdin; refusing to dispatch a promptless seat" >&2
    exit 2
fi

# Force-inline directive (default on; disable with OCTOPUS_AGY_FORCE_INLINE=0).
# agy is an agentic CLI: given a council/analysis prompt it writes its real answer
# to an internal "brain" artifact and returns only a "see the artifact" stub on
# stdout, or nothing at all when a tool it wants needs a permission headless mode
# cannot prompt for. Either way the council seat is silently empty, and the
# silent-empty retry below cannot help because it reproduces the same behaviour.
# This directive pins the full answer to the stdout response so the seat is captured.
AGY_INLINE_DIRECTIVE="CRITICAL OUTPUT RULES: Respond with your COMPLETE answer directly inline as plain text in THIS response. Do NOT create files. Do NOT write artifacts or brain documents. Do NOT use terminal, command, or file tools. Do NOT say 'see the artifact' or reference any external document. Write the full answer here now, from your own expertise.

"
# Oversized prompts are handed over as a file path (see the size ceiling below), so
# that branch needs a directive that permits reading exactly that one file. Reusing
# the blanket no-file-tools wording above would contradict its own instruction to
# read the prompt file.
AGY_INLINE_DIRECTIVE_FILE="CRITICAL OUTPUT RULES: Respond with your COMPLETE answer directly inline as plain text in THIS response. You may read ONLY the prompt file named below. Apart from reading that one file, do NOT create files, do NOT write artifacts or brain documents, and do NOT use terminal or command tools. Do NOT say 'see the artifact' or reference any external document. Write the full answer here now.

"
if [[ "${OCTOPUS_AGY_FORCE_INLINE:-1}" != "1" ]]; then
    AGY_INLINE_DIRECTIVE=""
    AGY_INLINE_DIRECTIVE_FILE=""
fi

# Silent prompt mutation is hard to diagnose from the outside: someone debugging an
# odd agy response should be able to see that the adapter modified the prompt.
if [[ -n "$AGY_INLINE_DIRECTIVE" && "${OCTOPUS_DEBUG:-false}" == "true" ]]; then
    echo "agy-exec.sh: prepending force-inline directive to prompt (disable with OCTOPUS_AGY_FORCE_INLINE=0)" >&2
fi

# Single-argument size ceiling: Linux caps one argv string at MAX_ARG_STRLEN
# (128 KiB). Oversized prompts stay in the cached temp file and agy is pointed
# at it via --add-dir with a read-this-file --print instruction, instead of
# failing the seat.
if (( ${#prompt_content} > 100000 )); then
    cmd+=(--add-dir "$(dirname "$prompt_file")")
    cmd+=(--print "${AGY_INLINE_DIRECTIVE_FILE}Read the file '${prompt_file}' and follow the instructions in it as your task prompt. Do not summarize the file; execute it.")
else
    cmd+=(--print "${AGY_INLINE_DIRECTIVE}${prompt_content}")
fi

run_agy() {
    : > "$stdout_file"
    "${cmd[@]}" > "$stdout_file" < /dev/null
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
