#!/usr/bin/env bash
# Cursor Agent CLI provider execution (v9.23.0)
# NOTE: no top-level `set -e*` — sourced libs must not alter parent shell options
# (per upstream cfaf6871 fix(#269)). orchestrate.sh already sets `set -eo pipefail`.

# Internal log helper — proxies to orchestrate.sh's log() if available, otherwise
# prints level-prefixed messages to stderr so this file is safe to source standalone.
_cursor_log() {
    if declare -f log >/dev/null 2>&1; then
        log "$@"
    else
        echo "[${1}] ${*:2}" >&2
    fi
}
# Uses `agent -p` headless mode with --trust to skip workspace prompts.
# Auth: CURSOR_API_KEY or a Cursor session (`agent login`).
# Models: Cursor's service-owned catalog (`agent models`); default `auto`.
# Execution mode: read-only (`--mode ask`) unless the role writes code — see
# cursor_agent_mode_for_role / OCTOPUS_CURSOR_AGENT_MODE below.
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

_cursor_agent_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if ! declare -f run_with_timeout >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${_cursor_agent_lib_dir}/heartbeat.sh" 2>/dev/null || true
fi

# Cursor Agent CLI binary identity check
#
# Version format: CalVer (YYYY.MM.DD-hash), e.g. "2026.04.14-ee4b43a"
# Detection regex: ^20[0-9]{2}\.  (year 20xx followed by dot)
#
# Why this pattern (not semver): the binary name "agent" is generic and could
# collide with other tools. Cursor's calendar-versioning is distinctive enough
# to disambiguate; semver-style "1.x.y" outputs are intentionally rejected.
#
# If Cursor changes versioning scheme, update both this regex and the
# corresponding checks in: preflight.sh, embrace.sh, build-fleet.sh,
# model-resolver.sh (is_agent_available_v2 cursor-agent case).
_cursor_agent_run_with_timeout() {
    local timeout_secs="$1"
    shift

    if ! declare -f run_with_timeout >/dev/null 2>&1; then
        _cursor_log ERROR "cursor-agent: shared timeout supervisor unavailable"
        return 1
    fi
    # Always use the shared private-process-group path. A short-lived Cursor
    # command can leave descendants holding stdout after its main PID exits;
    # the portable supervisor contains and reaps that complete process group.
    run_with_timeout --portable-supervisor "$timeout_secs" "$@"
}

_is_cursor_agent_binary() {
    local version_output probe_timeout
    command -v agent &>/dev/null || return 1
    # Wrap with timeout: an unrelated `agent` binary on PATH could hang on stdin
    # or spawn an interactive session, blocking every caller (cursor_agent_is_available,
    # preflight, doctor, smoke, build-fleet). Redirect stdin to /dev/null too.
    probe_timeout="${OCTOPUS_CURSOR_AGENT_PROBE_TIMEOUT:-3}"
    # MCP can forward OpenCode's key before provider-child filtering runs.
    version_output=$(unset MISTRAL_API_KEY || exit 1
        _cursor_agent_run_with_timeout "$probe_timeout" agent --version </dev/null) || return 1
    # Cursor Agent versions look like: 2026.04.14-ee4b43a
    [[ "$version_output" =~ ^20[0-9]{2}\. ]] && return 0
    return 1
}

# ── Authentication ────────────────────────────────────────────────────────────
# Precedence:
#   1. CURSOR_API_KEY in the environment                     → "env:CURSOR_API_KEY"
#   2. Cursor session created by `agent login`               → "cursor-session"
#      a. an "authInfo" block in ~/.cursor/cli-config.json (cheap, offline)
#      b. the block can be absent while the CLI is still authenticated
#         (observed on build 2026.06.24 until the CLI persisted its session);
#         `agent status --format json` → {"isAuthenticated":true} is then the
#         only reliable signal
# `agent status` is network-bound (3-12s observed), so it gets its own bound
# (OCTOPUS_CURSOR_AGENT_STATUS_TIMEOUT, default 15s) and its yes/no verdict is
# cached per process and on disk (OCTOPUS_CURSOR_AGENT_AUTH_CACHE_TTL, default
# 600s; negative results expire after OCTOPUS_CURSOR_AGENT_AUTH_NEGATIVE_TTL,
# default 60s, so a fresh `agent login` shows up quickly; TTL 0 disables the
# file cache). Doctor, preflight, smoke, and fleet builders therefore pay the
# probe once per window instead of once per process. The JSON carries account
# identity (email, userId) and is never echoed or cached; only the boolean is.
#
# NOTE: ~/.cursor/agent-cli-state.json is a statsig migration flag
# ({"hasClearedLegacyStatsigFields":true}), NOT auth state — verified on
# Cursor Agent CLI build 2026.04.17-787b533.

_CURSOR_AGENT_SESSION_AUTH_CACHE=""

_cursor_agent_config_has_auth_info() {
    grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null
}

# On-disk verdict cache: two lines (epoch seconds, yes|no). Never credentials.
# Kept in the user's cache directory, never in the workspace: a workspace may be
# a repository checkout, where a committed symlink could redirect the write.
# Reads refuse symlinks and writes replace the file atomically via rename, which
# never follows a link that appears between the check and the replace.
_cursor_agent_auth_cache_file() {
    printf '%s\n' "${OCTOPUS_CURSOR_AGENT_AUTH_CACHE_FILE:-${XDG_CACHE_HOME:-${HOME}/.cache}/claude-octopus/cursor-agent-auth-verdict}"
}

_cursor_agent_auth_cache_ttl() {
    local ttl="${OCTOPUS_CURSOR_AGENT_AUTH_CACHE_TTL:-600}"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=600
    printf '%s\n' "$ttl"
}

# Prints a fresh cached verdict (yes|no) or returns 1.
_cursor_agent_auth_cache_read() {
    local ttl file stamp state now age max_age
    ttl="$(_cursor_agent_auth_cache_ttl)"
    [[ "$ttl" -gt 0 ]] || return 1
    file="$(_cursor_agent_auth_cache_file)"
    [[ -L "$file" ]] && return 1
    [[ -f "$file" ]] || return 1
    { read -r stamp && read -r state; } < "$file" 2>/dev/null || return 1
    [[ "$stamp" =~ ^[0-9]+$ ]] || return 1
    case "$state" in
        yes) max_age="$ttl" ;;
        no)  max_age="${OCTOPUS_CURSOR_AGENT_AUTH_NEGATIVE_TTL:-60}"
             [[ "$max_age" =~ ^[0-9]+$ ]] || max_age=60 ;;
        *)   return 1 ;;
    esac
    now="$(date +%s)"
    age=$((now - stamp))
    (( age >= 0 && age < max_age )) || return 1
    printf '%s\n' "$state"
}

_cursor_agent_auth_cache_write() {
    local file dir tmp
    [[ "$(_cursor_agent_auth_cache_ttl)" -gt 0 ]] || return 0
    file="$(_cursor_agent_auth_cache_file)"
    if [[ -L "$file" ]]; then
        _cursor_log WARN "cursor-agent: refusing to write the auth verdict through a symlink: $file"
        return 0
    fi
    dir="$(dirname "$file")"
    mkdir -p "$dir" 2>/dev/null || return 0
    tmp="$(mktemp "${dir}/.cursor-agent-auth-verdict.XXXXXX" 2>/dev/null)" || return 0
    if printf '%s\n%s\n' "$(date +%s)" "$1" > "$tmp" 2>/dev/null \
        && chmod 600 "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$file" 2>/dev/null; then
        return 0
    fi
    /bin/rm -f "$tmp" 2>/dev/null || true
    return 0
}

_cursor_agent_session_probe() {
    local status_timeout status_output cached
    if [[ -n "$_CURSOR_AGENT_SESSION_AUTH_CACHE" ]]; then
        [[ "$_CURSOR_AGENT_SESSION_AUTH_CACHE" == "yes" ]]
        return $?
    fi
    if cached="$(_cursor_agent_auth_cache_read)"; then
        _CURSOR_AGENT_SESSION_AUTH_CACHE="$cached"
        [[ "$cached" == "yes" ]]
        return $?
    fi
    status_timeout="${OCTOPUS_CURSOR_AGENT_STATUS_TIMEOUT:-15}"
    # Keep whatever was printed even on a non-zero exit; the verdict is the
    # boolean, not the exit status.
    status_output=$(unset MISTRAL_API_KEY || exit 1
        _cursor_agent_run_with_timeout "$status_timeout" agent status --format json </dev/null 2>/dev/null) || true
    if grep -Ec '"isAuthenticated"[[:space:]]*:[[:space:]]*true' >/dev/null <<< "$status_output"; then
        _CURSOR_AGENT_SESSION_AUTH_CACHE="yes"
        _cursor_agent_auth_cache_write yes
        return 0
    fi
    _CURSOR_AGENT_SESSION_AUTH_CACHE="no"
    _cursor_agent_auth_cache_write no
    return 1
}

# Session auth only (ignores CURSOR_API_KEY). Cheap file check first, then the
# bounded status probe. Requires a verified Cursor binary before probing; pass
# "verified" as $1 when the caller has already run _is_cursor_agent_binary.
cursor_agent_session_authenticated() {
    _cursor_agent_config_has_auth_info && return 0
    if [[ "${1:-}" != "verified" ]]; then
        _is_cursor_agent_binary || return 1
    fi
    _cursor_agent_session_probe
}

# Any accepted credential: env key or session.
cursor_agent_is_authenticated() {
    [[ -n "${CURSOR_API_KEY:-}" ]] && return 0
    cursor_agent_session_authenticated "${1:-}"
}

# Check if Cursor Agent CLI is available and authenticated
# Returns 0 if ready, 1 if not
cursor_agent_is_available() {
    command -v agent &>/dev/null || return 1
    # Verify binary identity — `agent` is a generic name
    _is_cursor_agent_binary || return 1
    cursor_agent_is_authenticated verified
}

# Get the auth method currently in use (for doctor/setup reporting)
# Returns: "env:CURSOR_API_KEY", "cursor-session", or "none"
cursor_agent_auth_method() {
    if [[ -n "${CURSOR_API_KEY:-}" ]]; then
        echo "env:CURSOR_API_KEY"
    elif cursor_agent_session_authenticated; then
        echo "cursor-session"
    else
        echo "none"
    fi
}

# ── Execution mode ────────────────────────────────────────────────────────────
# `agent -p` has full tool access (write + shell) in the working directory.
# Every seat that only reads must opt down explicitly:
#   ask   → --mode ask   (Q&A, read-only)                  default for research/review/council
#   plan  → --mode plan  (read-only planning, no edits)    planners and architects
#   agent → --force      (unattended full tool access)     implementer roles only
# Mirrors OCTOPUS_CODEX_SANDBOX / OCTOPUS_COMMANDCODE_PERMISSION_MODE.
cursor_agent_mode_for_role() {
    case "${1:-}" in
        implementer|developer|implementer-heavy) echo "agent" ;;
        planner|architect|strategist) echo "plan" ;;
        *) echo "ask" ;;
    esac
}

# Apply the OCTOPUS_CURSOR_AGENT_MODE override to the role-derived default.
# An invalid value logs an error and keeps the role default (fails safe).
cursor_agent_resolve_mode() {
    local role="${1:-}" mode
    mode="$(cursor_agent_mode_for_role "$role")"
    if [[ -n "${OCTOPUS_CURSOR_AGENT_MODE:-}" ]]; then
        case "$OCTOPUS_CURSOR_AGENT_MODE" in
            ask|plan|agent) mode="$OCTOPUS_CURSOR_AGENT_MODE" ;;
            *)
                _cursor_log ERROR "Invalid OCTOPUS_CURSOR_AGENT_MODE value: '${OCTOPUS_CURSOR_AGENT_MODE}'. Allowed: ask, plan, agent"
                _cursor_log ERROR "Falling back to role-derived default (${mode})."
                ;;
        esac
    fi
    echo "$mode"
}

# Emit the argv fragment for a resolved mode. Agent mode uses --force so
# unattended implementers may run tools without stopping for approval.
cursor_agent_mode_flag() {
    case "${1:-ask}" in
        ask|plan) printf -- '--mode %s' "$1" ;;
        agent) printf '%s' '--force' ;;
        *) printf '' ;;
    esac
}

# Execute a prompt via Cursor Agent CLI headless mode
# Args: $1=agent_type (e.g. cursor-agent), $2=prompt, $3=output_file (optional),
#       $4=role (optional; drives the read-only/plan/agent mode contract)
cursor_agent_execute() {
    local agent_type="$1"
    local prompt="$2"
    local output_file="${3:-}"
    local role="${4:-}"

    if ! command -v agent &>/dev/null; then
        _cursor_log ERROR "cursor-agent: CLI not found — install: curl -fsSL https://cursor.com/install | bash"
        return 1
    fi
    if ! _is_cursor_agent_binary; then
        _cursor_log ERROR "cursor-agent: 'agent' binary on PATH is not Cursor Agent CLI"
        return 1
    fi

    local timeout="${OCTOPUS_CURSOR_AGENT_TIMEOUT:-120}"

    [[ "${VERBOSE:-}" == "true" ]] && _cursor_log DEBUG "cursor_agent_execute: type=$agent_type, timeout=${timeout}s, auth=$(cursor_agent_auth_method)" || true

    # Note: --model is set by dispatch.sh via get_agent_command(), not here
    local -a mode_args=()
    local cursor_mode
    cursor_mode="$(cursor_agent_resolve_mode "$role")"
    case "$cursor_mode" in
        ask|plan) mode_args=(--mode "$cursor_mode") ;;
        agent) mode_args=(--force) ;;
    esac
    local response exit_code
    response=$(printf '%s' "$prompt" | _cursor_agent_run_with_timeout "$timeout" agent -p "" --trust --output-format text "${mode_args[@]+"${mode_args[@]}"}" 2>&1) && exit_code=0 || exit_code=$?

    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            _cursor_log WARN "cursor-agent: Timed out after ${timeout}s"
            return 1
        fi
        # Check for auth errors
        if printf '%s' "$response" | grep -ciE 'unauthorized|forbidden|(^|[^0-9])(401|403)([^0-9]|$)|authentication[[:space:]]+(failed|required)|not[[:space:]]+authorized|invalid[[:space:]]+token|expired[[:space:]]+token|token[[:space:]]+expired|please[[:space:]]+(re)?login|login[[:space:]]+required' >/dev/null; then
            _cursor_log ERROR "cursor-agent: Auth failure — run: agent login (or set CURSOR_API_KEY)"
            return 1
        fi
        _cursor_log WARN "cursor-agent: Exit code $exit_code"
        # Still return output if we got some (non-zero exit can include useful output)
    fi

    if [[ -z "$response" ]]; then
        _cursor_log WARN "cursor-agent: Empty response"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        printf '%s\n' "$response" > "$output_file"
    else
        printf '%s\n' "$response"
    fi

    if [[ $exit_code -ne 0 ]]; then
        return "$exit_code"
    fi

    return 0
}
