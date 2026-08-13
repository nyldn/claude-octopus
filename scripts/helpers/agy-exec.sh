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
# agy's --print-timeout is a Go duration and REQUIRES a unit: a bare integer fails hard
# with `invalid value "600" for flag -print-timeout: missing unit in duration "600"`
# (exit 2), taking the whole seat down. Treat a plain number as seconds so a caller can
# pass either "600" or a unit-suffixed value ("600s", "5m0s").
case "$print_timeout" in
    ''|*[!0-9]*) ;;                          # empty or already unit-suffixed — leave as-is
    *) print_timeout="${print_timeout}s" ;;  # bare integer → seconds
esac

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
                # `|| true` keeps set -e from killing the shim on a failed
                # conversion, so the HOMEDRIVE+HOMEPATH and HOME fallbacks
                # below still get their turn.
                USERPROFILE="$(cygpath -w "$HOME" 2>/dev/null || true)"
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
stderr_file=$(mktemp -t "octo-agy-stderr.XXXXXX")
trap 'rm -f "${prompt_file:-}" "${stdout_file:-}" "${stderr_file:-}"' EXIT
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
# Match for any non-whitespace byte instead of deleting every whitespace match.
# Bash 3.2's global parameter substitution becomes superlinear on review-sized
# prompts with many spaces and can stall for minutes before `agy` is launched.
if [[ ! "$prompt_content" =~ [^[:space:]] ]]; then
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
# Raw stderr echo rather than `log`: this file is a standalone shim exec'd
# directly by dispatch.sh, like the sibling Gemini and Grok shims, and does
# not source the logging library by design.
if [[ -n "$AGY_INLINE_DIRECTIVE" && "${OCTOPUS_DEBUG:-false}" == "true" ]]; then
    echo "agy-exec.sh: prepending force-inline directive to prompt (disable with OCTOPUS_AGY_FORCE_INLINE=0)" >&2
fi

# Byte length regardless of locale: MAX_ARG_STRLEN is a byte limit, and a
# multibyte UTF-8 prompt has more bytes than ${#var} chars would suggest.
byte_length() {
    local LC_ALL=C
    printf '%s' "${#1}"
}

# Hard payload ceiling. The argv-size fallback below hands agy an OVERSIZED prompt
# as a file to read, which sidesteps MAX_ARG_STRLEN but not agy itself: a
# multi-megabyte prompt is loaded whole into agy's context and OOM-kills the
# headless process (or is rejected by the backend for context length). Either way
# the seat dies opaquely — an exit-code failure or a silent-empty result the retry
# can't fix, and #2077's finished-but-timed-out salvage can't recover because no
# verdict was ever written. Above this ceiling, refuse to dispatch and emit a
# provider-rejection marker the dispatch classifier already recognizes
# ("input is too large" -> classify_agent_output -> skipped:oversize), so the
# council records a STRUCTURED oversize skip and keeps its other seats instead of
# crashing on this one. Exit 0 (not an error), matching how agent-sync.sh routes
# around provider oversize rejections (#410): a too-big prompt is an input-size
# mismatch to skip, not a hard run failure. Measured on prompt_content — the exact
# bytes agy would read from the file — not the argv the inline branch would build.
# Tunable; default 1 MiB (~250k tokens), already far larger than any real review.
max_payload_bytes="${OCTOPUS_AGY_MAX_PAYLOAD_BYTES:-1048576}"
# Validate and normalize the ceiling. Reject non-digits, strip leading zeros (so a
# padded value keeps its true magnitude and `08` isn't read as octal by `10#`), then
# accept anything up to INT64_MAX and reject only genuine overflow. Bash arithmetic
# is signed 64-bit and WRAPS on overflow, which could flip a huge ceiling negative and
# make `prompt_bytes > x` always true (refusing every seat); so a value with more than
# 19 digits, or a 19-digit value above 9223372036854775807, falls back to the default.
# For equal-length all-digit strings a lexical `>` is the numeric comparison, which lets
# us range-check without triggering the very overflow we're guarding against.
case "$max_payload_bytes" in
    ''|*[!0-9]*) max_payload_bytes=1048576 ;;
    *)
        _mpb="${max_payload_bytes#"${max_payload_bytes%%[!0]*}"}"; [[ -n "$_mpb" ]] || _mpb=0
        if (( ${#_mpb} > 19 )) || { (( ${#_mpb} == 19 )) && [[ "$_mpb" > "9223372036854775807" ]]; }; then
            max_payload_bytes=1048576
        else
            max_payload_bytes=$((10#$_mpb))
        fi
        ;;
esac
prompt_bytes="$(byte_length "$prompt_content")"
if (( prompt_bytes > max_payload_bytes )); then
    echo "agy-exec.sh: prompt input is too large (${prompt_bytes} bytes > OCTOPUS_AGY_MAX_PAYLOAD_BYTES=${max_payload_bytes}); refusing to dispatch to avoid exhausting agy memory" >&2
    exit 0
fi

# Single-argument size ceiling: Linux caps one argv string at MAX_ARG_STRLEN
# (128 KiB). Oversized prompts stay in the cached temp file and agy is pointed
# at it via --add-dir with a read-this-file --print instruction, instead of
# failing the seat. The ceiling is measured on the FULL --print argument the
# inline branch would build (directive + prompt), not the prompt alone, so the
# prepended directive can never push a near-ceiling prompt past the limit.
if (( $(byte_length "${AGY_INLINE_DIRECTIVE}${prompt_content}") > 100000 )); then
    cmd+=(--add-dir "$(dirname "$prompt_file")")
    cmd+=(--print "${AGY_INLINE_DIRECTIVE_FILE}Read the file '${prompt_file}' and follow the instructions in it as your task prompt. Do not summarize the file; execute it.")
else
    cmd+=(--print "${AGY_INLINE_DIRECTIVE}${prompt_content}")
fi

run_agy() {
    : > "$stdout_file"
    : > "$stderr_file"
    "${cmd[@]}" > "$stdout_file" 2> "$stderr_file" < /dev/null
}

# agy is a bubbletea TUI app. In --print mode it is headless, but when it must render
# an INTERACTIVE screen anyway — a folder-trust prompt on a brand-new worktree, or an
# auth/login flow — it opens /dev/tty and, in a session with no controlling terminal,
# dies with "bubbletea: could not open TTY" before producing any answer. Detect that
# specific failure so we only pay the pseudo-TTY cost when it actually happens.
_agy_quota_error() {
    # agy's quota refusal ("Individual quota reached ... Resets in NNNhNNm") is
    # account-wide, not per-model: gemini-3.6-flash-low and gpt-oss-120b-medium
    # return the same window. It also returns instantly — far faster than the
    # quota-watcher's 2s poll — so the watcher never sees it and the seat keeps
    # reporting `available` to check-providers.sh. Detect it here and mark the
    # provider dead directly, the same way lib/perplexity.sh handles its 401.
    LC_ALL=C grep -ciE 'individual quota reached|quota reached\.|upgrade your subscription' \
        "$stderr_file" "$stdout_file" >/dev/null 2>&1
}

_agy_quota_reset_window() {
    # -h: two input files, so without it grep prefixes the match with a temp path.
    LC_ALL=C grep -hoiE 'resets in [0-9]+h[0-9]+m([0-9]+s)?' "$stderr_file" "$stdout_file" 2>/dev/null | head -1
}

# Convert agy's "Resets in 156h13m[45s]" into seconds, so the quota-dead marker
# expires when the quota actually resets. Without this the marker inherits the
# generic 1h default and a ~156h window is re-tried roughly 156 times, each retry
# dispatching into the same instant failure. Echoes nothing when unparseable, and
# the caller then falls back to the default TTL.
_agy_reset_window_seconds() {
    local w h m s
    w="$(_agy_quota_reset_window)"
    [[ -n "$w" ]] || return 0
    h="$(printf '%s\n' "$w" | LC_ALL=C sed -nE 's/.*[^0-9]([0-9]+)h.*/\1/p')"
    m="$(printf '%s\n' "$w" | LC_ALL=C sed -nE 's/.*h([0-9]+)m.*/\1/p')"
    s="$(printf '%s\n' "$w" | LC_ALL=C sed -nE 's/.*m([0-9]+)s.*/\1/p')"
    [[ "$h" =~ ^[0-9]+$ ]] || h=0
    [[ "$m" =~ ^[0-9]+$ ]] || m=0
    [[ "$s" =~ ^[0-9]+$ ]] || s=0
    (( h == 0 && m == 0 && s == 0 )) && return 0
    printf '%s\n' "$(( h * 3600 + m * 60 + s ))"
}

_agy_tty_error() {
    # Match only TTY-specific phrasing. A bare "bubbletea" would also catch unrelated
    # TUI failures a pseudo-terminal can't fix; the real error ("bubbletea: could not
    # open TTY") is already covered by the "could not open tty" alternative. Count
    # matches rather than `grep -q`: -q exits on first match and can SIGPIPE an upstream
    # writer under pipefail, which the repo's portability lint forbids.
    LC_ALL=C grep -ciE 'could not open( a)? tty|open /dev/tty|inappropriate ioctl|/dev/tty.*(no such device|not a)' \
        "$stderr_file" "$stdout_file" >/dev/null 2>&1
}

# PTY-fallback: re-run agy under a pseudo-terminal via `script` so a TUI it insists on
# rendering (already auto-dismissed by --dangerously-skip-permissions) has a TTY to draw
# on. Only invoked on a confirmed TTY error — a blanket wrap would fire on EVERY
# autonomous dispatch (which never has a TTY) and leak the PTY's control-char echo (^D,
# CR) into the answer. Opt out with OCTOPUS_AGY_NO_PTY_FALLBACK=1.
run_agy_pty() {
    # Bail BEFORE truncating the captures: agy's original stderr (the TTY error the
    # caller matched on) must survive if we can't actually run the fallback.
    command -v script >/dev/null 2>&1 || return 127
    : > "$stdout_file"
    : > "$stderr_file"
    if [[ "$(uname -s 2>/dev/null)" == Darwin* || "$(uname -s 2>/dev/null)" == *BSD ]]; then
        # BSD script: trailing command args preserve argv (safe for a large --print value).
        script -q /dev/null "${cmd[@]}" > "$stdout_file" 2> "$stderr_file" < /dev/null
    else
        # util-linux script: the command must be one -c string and may be
        # interpreted by /bin/sh rather than Bash. Quote every argument with
        # POSIX single-quote syntax; Bash printf %q can emit $'...' for
        # multiline values, which is not portable to /bin/sh.
        local _q="" _a _escaped
        for _a in "${cmd[@]}"; do
            _escaped="${_a//\'/\'\\\'\'}"
            _q+="'${_escaped}' "
        done
        script -qec "$_q" /dev/null > "$stdout_file" 2> "$stderr_file" < /dev/null
    fi
    local _rc=$?
    # Clean the pseudo-terminal's echo artifacts so the captured answer is byte-clean
    # for the council response parser. Feeding /dev/null as stdin makes the line
    # discipline echo the EOF as caret-notation "^D" (literal ^ + D) followed by
    # backspaces to erase it — plus trailing carriage returns. Drop CR/BS/EOT, then
    # strip any leading run of caret-notation control sequences (^@..^_ ^?) left on the
    # first line. A real answer never starts with those.
    LC_ALL=C tr -d '\r\010\004' < "$stdout_file" \
        | LC_ALL=C sed -E '1s/^(\^[]@-_?])+//' > "${stdout_file}.clean" 2>/dev/null \
        && mv -f "${stdout_file}.clean" "$stdout_file"
    return "$_rc"
}

set +e
run_agy
rc=$?
# Retry once on a silent-empty success (a documented agy failure mode), replaying
# the cached prompt. Keyed on emptiness, not on any provider error string.
content=$(<"$stdout_file")
if [[ $rc -eq 0 && ! "$content" =~ [^[:space:]] && -n "$prompt_file" && "${OCTOPUS_AGY_NO_RETRY:-}" != "1" ]]; then
    run_agy
    rc=$?
fi
# Hardening (not a live-bug fix): if agy died demanding a TTY, retry once under a
# pseudo-terminal so a first-touch folder-trust TUI on a fresh worktree can't sink an
# autonomous council seat. Gated on the real error so the working headless path is
# untouched.
if [[ "${OCTOPUS_AGY_NO_PTY_FALLBACK:-}" != "1" ]] && (( rc != 0 )) \
        && command -v script >/dev/null 2>&1 && _agy_tty_error; then
    echo "agy-exec.sh: agy demanded a TTY; retrying once under a pseudo-terminal (disable with OCTOPUS_AGY_NO_PTY_FALLBACK=1)" >&2
    run_agy_pty
    rc=$?
fi
set -e

# Terminal quota refusal: record it so preflight (check-providers.sh) and
# is_agent_available report agy as `degraded` instead of `available` for the rest
# of the run, rather than seating it again into the same instant failure. Emit a
# quota-watcher-matchable keyword too, so consumers that scan output agree with
# the marker file. Mirrors the perplexity 401 path in lib/perplexity.sh.
if (( rc != 0 )) && _agy_quota_error; then
    _agy_reset_window="$(_agy_quota_reset_window)"
    echo "agy-exec.sh: agy TerminalQuotaError (Individual quota reached${_agy_reset_window:+; ${_agy_reset_window}}) — marking agy unavailable for this session" >&2
    if ! declare -f octo_quota_mark_dead >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/quota-watcher.sh" 2>/dev/null || true
    fi
    # Expire the marker when the quota actually resets, not on the generic
    # default. An unparseable window yields an empty ttl and mark_dead falls back.
    _agy_reset_ttl="$(_agy_reset_window_seconds)"
    declare -f octo_quota_mark_dead >/dev/null 2>&1 && octo_quota_mark_dead "agy" "${_agy_reset_ttl}" || true
fi

# Surface agy's own stderr (folder-trust notes, diagnostics) that used to flow straight
# through, now that we capture it to detect the TTY error.
[[ -s "$stderr_file" ]] && cat "$stderr_file" >&2
cat "$stdout_file"
exit "$rc"
