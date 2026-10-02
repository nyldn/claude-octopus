#!/usr/bin/env bash
# xAI Grok CLI stdin→argv/file shim. octo pipes prompts via stdin (spawn.sh contract);
# grok's `-p/--single` takes the prompt as an argv argument, so read stdin and
# re-pass it. Model via OCTOPUS_GROK_MODEL (default: grok's own default).
# OCTOPUS_GROK_ARGV_MAX: byte limit for inline prompts (default: 100000).
# Larger prompts use --prompt-file; 0 always uses a file. Non-integers use the default.
# OCTOPUS_GROK_APPROVE=0 disables headless approval and sandbox flags (default: 1).
# OCTOPUS_GROK_SANDBOX: off|workspace|read-only|strict (default: read-only).
# Dispatch selects workspace for write-capable implementation calls; explicit
# overrides win. Invalid profiles warn once and fall back to read-only here.
set -euo pipefail
prompt=""
if [[ ! -t 0 ]]; then
    # Unlike command substitution, read preserves trailing newlines.
    IFS= read -r -d '' prompt || true
fi
if [[ -z "${prompt//[[:space:]]/}" ]]; then
    # Standalone shim (exec'd by dispatch.sh) — matches vibe-exec.sh / agy-exec.sh
    # which also use raw echo>&2 for startup validation (no shared logger in scope).
    echo "grok-exec: no prompt provided on stdin" >&2
    exit 64
fi
model="${OCTOPUS_GROK_MODEL:-default}"
workdir="${OCTOPUS_GROK_CWD:-$PWD}"
argv_max="${OCTOPUS_GROK_ARGV_MAX:-100000}"
[[ "$argv_max" =~ ^[0-9]+$ ]] || argv_max=100000
prompt_bytes="$(printf '%s' "$prompt" | wc -c)"
prompt_file=""
if (( 10#$argv_max == 0 || prompt_bytes > 10#$argv_max )); then
    prompt_file="$(mktemp "${TMPDIR:-/tmp}/octo-grok-prompt.XXXXXX")"
    trap 'rm -f "$prompt_file"' EXIT
    trap '[[ -z "${grok_pid:-}" ]] || kill -TERM "$grok_pid" 2>/dev/null || true; exit 143' TERM
    trap '[[ -z "${grok_pid:-}" ]] || kill -INT "$grok_pid" 2>/dev/null || true; exit 130' INT
    printf '%s' "$prompt" > "$prompt_file"
    cmd=(grok --prompt-file "$prompt_file" --output-format plain --cwd "$workdir" --disable-web-search)
else
    # Preserve the inline path's existing command-substitution newline handling.
    prompt="$(printf '%s' "$prompt")"
    cmd=(grok -p "$prompt" --output-format plain --cwd "$workdir" --disable-web-search)
fi
if [[ "${OCTOPUS_GROK_APPROVE:-1}" != "0" ]]; then
    sandbox="${OCTOPUS_GROK_SANDBOX:-read-only}"
    case "$sandbox" in
        off|workspace|read-only|strict) ;;
        *)
            echo "grok-exec: invalid OCTOPUS_GROK_SANDBOX '$sandbox'; using read-only" >&2
            sandbox="read-only"
            ;;
    esac
    cmd+=(--always-approve --sandbox "$sandbox")
fi
if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
fi
if [[ -n "$prompt_file" ]]; then
    # Wait as a parent so EXIT can remove the file, including after cancellation.
    "${cmd[@]}" &
    grok_pid=$!
    rc=0
    wait "$grok_pid" || rc=$?
    exit "$rc"
fi
exec "${cmd[@]}"
