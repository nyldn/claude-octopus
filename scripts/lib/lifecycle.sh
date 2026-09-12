#!/usr/bin/env bash
# Host-scoped plugin installation state. Source-safe and Bash 3.2 compatible.

OCTO_LIFECYCLE_STATE_FILE="${OCTOPUS_INSTALL_STATE_FILE:-${HOME}/.claude-octopus/install-state.json}"
OCTO_LIFECYCLE_STABLE_ROOT="${OCTOPUS_STABLE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"

# shellcheck source=scripts/lib/install-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/install-root.sh"
# shellcheck source=scripts/lib/plugin-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/plugin-root.sh"
# shellcheck source=scripts/lib/hook-activation.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/hook-activation.sh"

octo_lifecycle_profile_valid() {
    case "${1:-}" in core|orchestration|full) return 0 ;; esac
    return 1
}

octo_lifecycle_profile() {
    octo_context_profile
}

octo_lifecycle_hook_profile() {
    octo_hook_profile
}

octo_lifecycle_host() {
    if [[ -n "${OCTOPUS_HOST:-}" ]]; then
        printf '%s\n' "$OCTOPUS_HOST"
    elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        printf 'claude\n'
    elif [[ -n "${CODEX_PLUGIN_ROOT:-}" || -n "${CODEX_HOME:-}" ]]; then
        printf 'codex\n'
    else
        printf 'standalone\n'
    fi
}

octo_lifecycle_plugin_root() {
    local host root=""
    host="$(octo_lifecycle_host)"
    case "$host" in
        claude) root="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_DIR:-}}" ;;
        codex) root="${CODEX_PLUGIN_ROOT:-${PLUGIN_DIR:-}}" ;;
        *) root="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${PLUGIN_DIR:-}}}" ;;
    esac
    if [[ -z "$root" ]]; then
        root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)"
    elif [[ -d "$root" ]]; then
        root="$(cd "$root" 2>/dev/null && pwd -P)"
    fi
    printf '%s\n' "$root"
}

octo_lifecycle_version() {
    local root="${1:-$(octo_lifecycle_plugin_root)}" manifest=""
    if [[ -r "$root/.claude-plugin/plugin.json" ]]; then
        manifest="$root/.claude-plugin/plugin.json"
    elif [[ -r "$root/.codex-plugin/plugin.json" ]]; then
        manifest="$root/.codex-plugin/plugin.json"
    fi
    if [[ -n "$manifest" ]] && command -v jq >/dev/null 2>&1; then
        jq -r '.version // "unknown"' "$manifest" 2>/dev/null || printf 'unknown\n'
    else
        printf 'unknown\n'
    fi
}

octo_lifecycle_snapshot() {
    command -v jq >/dev/null 2>&1 || return 3
    local host root version scope profile hooks
    host="$(octo_lifecycle_host)"
    root="$(octo_lifecycle_plugin_root)"
    version="$(octo_lifecycle_version "$root")"
    scope="${OCTOPUS_INSTALL_SCOPE:-user}"
    profile="$(octo_lifecycle_profile)"
    hooks="$(octo_lifecycle_hook_profile)"
    jq -cn --arg host "$host" --arg version "$version" --arg root "$root" \
        --arg stable "$OCTO_LIFECYCLE_STABLE_ROOT" --arg scope "$scope" \
        --arg profile "$profile" --arg hooks "$hooks" \
        '{host:$host,plugin_version:$version,plugin_root:$root,stable_root:$stable,
          install_scope:$scope,context_profile:$profile,hook_profile:$hooks}'
}

octo_lifecycle_state_valid() {
    [[ -f "$OCTO_LIFECYCLE_STATE_FILE" && ! -L "$OCTO_LIFECYCLE_STATE_FILE" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local host expected
    host="$(octo_lifecycle_host)"
    expected="$(octo_lifecycle_snapshot)" || return 1
    jq -se --arg host "$host" --argjson expected "$expected" '
        length == 1 and (.[0] |
        .schema == 2 and (.hosts | type == "object") and
        (.hosts[$host] | {
          host,plugin_version,plugin_root,stable_root,install_scope,context_profile,hook_profile
        }) == $expected)
    ' "$OCTO_LIFECYCLE_STATE_FILE" >/dev/null 2>&1
}

_octo_lifecycle_lock() {
    local lock="$1.lock" owner="$2" tries=0 candidate pid probe
    while ! mkdir "$lock" 2>/dev/null; do
        [[ -d "$lock" && ! -L "$lock" ]] || return 1
        # Removing the empty owner directory elects exactly one reclaimer.
        # Other waiters cannot remove a newly acquired lock after losing here.
        for candidate in "$lock/owner-$lock_host-"*; do
            [[ -d "$candidate" && ! -L "$candidate" ]] || continue
            pid="${candidate##*-}"
            case "$pid" in ''|0|*[!0-9]*) continue ;; esac
            probe="$(LC_ALL=C kill -0 "$pid" 2>&1)" && continue
            case "$probe" in
                *'No such process'*)
                    if rmdir "$candidate" 2>/dev/null; then rmdir "$lock" 2>/dev/null || true; fi ;;
            esac
        done
        tries=$((tries + 1))
        [[ "$tries" -lt 50 ]] || return 1
        sleep 0.02 2>/dev/null || return 1
    done
    mkdir "$lock/$owner" || { rmdir "$lock" 2>/dev/null || true; return 1; }
}

_octo_lifecycle_unlock() {
    local lock="$1" owner="$2" tmp="$3"
    [[ -z "$tmp" ]] || rm -f "$tmp"
    if [[ ! -L "$lock" ]] && rmdir "$lock/$owner" 2>/dev/null; then
        rmdir "$lock" 2>/dev/null || true
    fi
    return 0
}

octo_lifecycle_record_install() (
    # A subshell confines signal and EXIT traps to this transaction.
    command -v jq >/dev/null 2>&1 || return 3
    local expected host state_dir lock tmp="" current='{"schema":2,"hosts":{}}' updated rc=0
    local lock_pid lock_host owner
    expected="$(octo_lifecycle_snapshot)" || return $?
    host="$(jq -r '.host' <<<"$expected")"
    case "$host" in ''|*[!A-Za-z0-9._-]*) return 2 ;; esac
    [[ -d "$(jq -r '.plugin_root' <<<"$expected")" ]] || return 4
    [[ ! -L "$OCTO_LIFECYCLE_STATE_FILE" && ( ! -e "$OCTO_LIFECYCLE_STATE_FILE" || -f "$OCTO_LIFECYCLE_STATE_FILE" ) ]] || return 5
    state_dir="$(dirname "$OCTO_LIFECYCLE_STATE_FILE")"
    mkdir -p "$state_dir" || return 5
    lock="$OCTO_LIFECYCLE_STATE_FILE.lock"
    # $$ identifies the caller on Bash 3.2; the exec child reports this subshell.
    read -r lock_pid < <(exec sh -c 'echo "$PPID"') || return 6
    lock_host="$(hostname)" || return 6
    lock_host="${lock_host//[^A-Za-z0-9._-]/_}"
    owner="owner-$lock_host-$lock_pid"
    # Bash 3.2 unwinds function locals before EXIT when a signal exits the shell.
    # These variables survive that unwind and remain confined to this subshell.
    _octo_receipt_lock="$lock" _octo_receipt_owner="$owner" _octo_receipt_tmp=""
    trap '_octo_lifecycle_unlock "$_octo_receipt_lock" "$_octo_receipt_owner" "$_octo_receipt_tmp"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _octo_lifecycle_lock "$OCTO_LIFECYCLE_STATE_FILE" "$owner" || return 6
    [[ ! -L "$OCTO_LIFECYCLE_STATE_FILE" && ( ! -e "$OCTO_LIFECYCLE_STATE_FILE" || -f "$OCTO_LIFECYCLE_STATE_FILE" ) ]] || return 5

    if [[ -f "$OCTO_LIFECYCLE_STATE_FILE" ]]; then
        current="$(jq -sce '
            if length == 1 then .[0] else error("expected one install state") end |
            if .schema == 2 and (.hosts | type == "object") then .
            elif .schema == 1 and (.host | type == "string") then
              {schema:2,hosts:{(.host):del(.schema,.recorded,.host)}}
            else error("unrecognized install state") end
        ' "$OCTO_LIFECYCLE_STATE_FILE" 2>/dev/null)" || return 5
    fi
    updated="$(jq -cn --argjson state "$current" --argjson entry "$expected" \
        --arg host "$host" --arg recorded_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '$state | .schema = 2 | .hosts = (.hosts // {}) |
         .hosts[$host] = ($entry + {recorded_at:$recorded_at})')" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        tmp="$(mktemp "$state_dir/.install-state.XXXXXX")" || rc=$?
        _octo_receipt_tmp="$tmp"
    fi
    if [[ "$rc" -eq 0 ]]; then
        chmod 600 "$tmp" 2>/dev/null || true
        printf '%s\n' "$updated" > "$tmp" &&
            [[ ! -L "$OCTO_LIFECYCLE_STATE_FILE" && ( ! -e "$OCTO_LIFECYCLE_STATE_FILE" || -f "$OCTO_LIFECYCLE_STATE_FILE" ) ]] &&
            mv -f "$tmp" "$OCTO_LIFECYCLE_STATE_FILE" || rc=$?
        [[ "$rc" -eq 0 ]] && chmod 600 "$OCTO_LIFECYCLE_STATE_FILE" 2>/dev/null || true
    fi
    return "$rc"
)

octo_lifecycle_state_json() {
    command -v jq >/dev/null 2>&1 || return 3
    local host expected recorded='null' current=false
    host="$(octo_lifecycle_host)"
    expected="$(octo_lifecycle_snapshot)" || return $?
    if [[ -f "$OCTO_LIFECYCLE_STATE_FILE" && ! -L "$OCTO_LIFECYCLE_STATE_FILE" ]]; then
        recorded="$(jq -sc --arg host "$host" '
            if length == 1 and (.[0].hosts | type == "object")
            then .[0].hosts[$host] // null else null end
        ' "$OCTO_LIFECYCLE_STATE_FILE" 2>/dev/null)" || recorded=null
    fi
    octo_lifecycle_state_valid && current=true || true
    jq -cn --argjson expected "$expected" --argjson recorded "$recorded" \
        --argjson current "$current" --arg state_file "$OCTO_LIFECYCLE_STATE_FILE" \
        '{schema:2,current:$current,state_file:$state_file,expected:$expected,recorded:$recorded}'
}

octo_lifecycle_stable_root_status() {
    local root="${1:-$(octo_lifecycle_plugin_root)}" stable="$OCTO_LIFECYCLE_STABLE_ROOT"
    if ! octo_validate_install_root "$root" "$(octo_lifecycle_host)"; then
        printf 'invalid-target\n'; return 1
    fi
    if [[ -L "$stable" ]]; then
        local stable_real="" root_real=""
        stable_real="$(cd "$stable" 2>/dev/null && pwd -P)" || true
        root_real="$(cd "$root" 2>/dev/null && pwd -P)" || true
        if [[ -z "$stable_real" ]]; then printf 'broken\n'; return 1; fi
        if [[ -n "$root_real" && "$stable_real" == "$root_real" ]]; then printf 'ok\n'; return 0; fi
        printf 'mismatch\n'; return 1
    fi
    if [[ ! -e "$stable" ]]; then printf 'missing\n'; return 1; fi
    if [[ -d "$stable" && -x "$stable/scripts/orchestrate.sh" ]]; then
        octo_stable_shims_status "$root" "$stable"
        return $?
    fi
    printf 'invalid\n'; return 1
}

octo_lifecycle_handoff_id() {
    local project="${1:-$PWD}"
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$project" | shasum -a 256 | cut -c1-16
    elif command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$project" | sha256sum | cut -c1-16
    else
        printf '%s' "$project" | cksum | cut -d' ' -f1
    fi
}
