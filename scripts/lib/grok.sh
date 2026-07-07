#!/usr/bin/env bash
# xAI Grok CLI provider (standalone `grok` binary — NOT cursor-agent's grok-4-20).
# Added by octo-grok-patch.sh. No top-level set -e*: sourced libs must not alter
# parent shell options (orchestrate.sh already sets `set -eo pipefail`).
# Auth: $XAI_API_KEY or ~/.grok/auth.json (grok login session).
# Headless: grok -p "<prompt>" --output-format plain  (single-turn, prints+exits).

_grok_log(){ if declare -f log >/dev/null 2>&1; then log "$@"; else echo "[${1}] ${*:2}" >&2; fi; }

_grok_run_with_timeout(){
    local t="$1"; shift
    if command -v gtimeout &>/dev/null; then gtimeout "$t" "$@"; return $?; fi
    if command -v timeout  &>/dev/null; then timeout  "$t" "$@"; return $?; fi
    "$@"
}

# `grok` is an unambiguous binary name — no identity regex needed (unlike cursor's `agent`).
_is_grok_binary(){ command -v grok &>/dev/null; }

grok_is_available(){
    command -v grok &>/dev/null || return 1
    # Recover XAI_API_KEY from the shell profile in non-interactive runs (mirrors
    # codex/vibe) so fleet, health, and discovery agree on availability.
    if [[ -z "${XAI_API_KEY:-}" ]] && declare -f resolve_provider_env >/dev/null 2>&1; then
        resolve_provider_env "XAI_API_KEY" 2>/dev/null || true
    fi
    [[ -n "${XAI_API_KEY:-}" ]] && return 0
    [[ -f "${HOME}/.grok/auth.json" ]] && return 0
    return 1
}

grok_auth_method(){
    if   [[ -n "${XAI_API_KEY:-}" ]];        then echo "env:XAI_API_KEY"
    elif [[ -f "${HOME}/.grok/auth.json" ]]; then echo "grok-session"
    else echo "none"; fi
}

# grok_execute AGENT_TYPE PROMPT [OUTFILE] — single-turn headless dispatch.
grok_execute(){
    local agent_type="$1" prompt="$2" output_file="${3:-}"
    [[ -z "$prompt" && ! -t 0 ]] && prompt="$(cat)"
    command -v grok &>/dev/null || { _grok_log ERROR "grok: CLI not found"; return 1; }
    local timeout="${OCTOPUS_GROK_TIMEOUT:-150}"
    local workdir="${OCTOPUS_GROK_CWD:-$PWD}"
    local model="${OCTOPUS_GROK_MODEL:-default}"
    local -a cmd=(grok -p "$prompt" --output-format plain --cwd "$workdir" --disable-web-search)
    [[ -n "$model" && "$model" != "default" ]] && cmd+=(--model "$model")
    local response exit_code
    response=$(_grok_run_with_timeout "$timeout" "${cmd[@]}" 2>/dev/null) && exit_code=0 || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        [[ $exit_code -eq 124 ]] && { _grok_log WARN "grok: timed out after ${timeout}s"; return 1; }
        if printf '%s' "$response" | grep -ciE 'unauthorized|forbidden|(401|403)|not authorized|invalid token|expired token|please .?login|login required' >/dev/null; then
            _grok_log ERROR "grok: auth failure — run: grok login (or set XAI_API_KEY)"; return 1
        fi
        # A non-zero exit is a failure even when grok emitted partial stdout. Do not
        # let an aborted/errored run masquerade as a successful response, or debate and
        # council verdicts that treat any non-empty output as success get corrupted.
        _grok_log WARN "grok: exit $exit_code"; return 1
    fi
    [[ -z "$response" ]] && { _grok_log WARN "grok: empty response"; return 1; }
    if [[ -n "$output_file" ]]; then printf '%s\n' "$response" > "$output_file"; else printf '%s\n' "$response"; fi
    return 0
}
