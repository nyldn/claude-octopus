#!/usr/bin/env bash
# xAI Grok CLI stdin→argv/file shim. octo pipes prompts via stdin (spawn.sh contract);
# grok's `-p/--single` takes the prompt as an argv argument, so read stdin and
# re-pass it. Model via OCTOPUS_GROK_MODEL (default: grok's own default).
# OCTOPUS_GROK_ARGV_MAX: byte limit for inline prompts (default: 100000).
# Larger prompts use --prompt-file; 0 always uses a file. Limits above 100000
# or invalid limits use 100000 to stay below Linux's per-argument ceiling.
# OCTOPUS_GROK_APPROVE=0 disables headless approval and sandbox flags (default: 1).
# OCTOPUS_GROK_SANDBOX: off|workspace|read-only|strict (default: read-only).
# Dispatch selects workspace for write-capable implementation calls; explicit
# overrides win. Invalid profiles warn once and fall back to read-only here.
# OCTOPUS_GROK_TOOL_POLICY: read-only|full (standalone default: read-only).
# Dispatch fixes the tool ceiling per role; a sandbox override cannot raise it.
set -euo pipefail
prompt_file="$(mktemp "${TMPDIR:-/tmp}/octo-grok-prompt.XXXXXX")"
trap 'rm -f "$prompt_file"' EXIT
# Cancellation owns only the direct child. Background commands can inherit an
# ignored INT, so both signals use TERM, then bounded escalation and reaping.
grok_cancel() {
    local status="$1" attempt
    trap '' TERM INT
    grok_pid="${grok_pid:-${!:-}}"
    if [[ -n "$grok_pid" ]]; then
        kill -TERM "$grok_pid" 2>/dev/null || true
        for attempt in {1..20}; do
            kill -0 "$grok_pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$grok_pid" 2>/dev/null; then
            kill -KILL "$grok_pid" 2>/dev/null || true
        fi
        wait "$grok_pid" 2>/dev/null || true
    fi
    exit "$status"
}
trap 'grok_cancel 143' TERM
trap 'grok_cancel 130' INT
[[ -t 0 ]] || cat > "$prompt_file"
if ! LC_ALL=C grep -q '[^[:space:]]' "$prompt_file"; then
    # Standalone shim (exec'd by dispatch.sh) — matches vibe-exec.sh / agy-exec.sh
    # which also use raw echo>&2 for startup validation (no shared logger in scope).
    echo "grok-exec: no prompt provided on stdin" >&2
    exit 64
fi
model="${OCTOPUS_GROK_MODEL:-default}"
workdir="${OCTOPUS_GROK_CWD:-$PWD}"
argv_max="${OCTOPUS_GROK_ARGV_MAX:-100000}"
[[ "$argv_max" =~ ^[0-9]{1,6}$ ]] || argv_max=100000
(( 10#$argv_max <= 100000 )) || argv_max=100000
prompt_bytes="$(wc -c < "$prompt_file")"
use_file=false
if (( 10#$argv_max == 0 || prompt_bytes > 10#$argv_max )); then
    use_file=true
    cmd=(grok --prompt-file "$prompt_file" --output-format plain --cwd "$workdir" --disable-web-search)
else
    # Preserve the inline path's existing command-substitution newline handling.
    prompt="$(cat "$prompt_file")"
    cmd=(grok -p "$prompt" --output-format plain --cwd "$workdir" --disable-web-search)
fi
case "${OCTOPUS_GROK_TOOL_POLICY:-read-only}" in
    full) ;;
    read-only)
        # read-only sandbox profiles permit temp writes. Remove executable and
        # mutation tools instead, and deny externally configured MCP tools.
        help="$(grok --help 2>/dev/null)" || exit 64
        if [[ "$help" != *'--tools <'* || "$help" != *'--deny <'* || "$help" != *'--no-subagents'* ]]; then
            echo "grok-exec: CLI lacks required read-only tool controls" >&2
            exit 64
        fi
        cmd+=(--tools 'read_file,grep,list_dir' --deny 'MCPTool(*)' --no-subagents)
        ;;
    *)
        echo "grok-exec: invalid OCTOPUS_GROK_TOOL_POLICY" >&2
        exit 64
        ;;
esac
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
if [[ "$use_file" == true ]]; then
    # Wait as a parent so EXIT can remove the file, including after cancellation.
    "${cmd[@]}" &
    grok_pid=$!
    rc=0
    wait "$grok_pid" || rc=$?
    exit "$rc"
fi
rm -f "$prompt_file"
trap - EXIT TERM INT
exec "${cmd[@]}"
