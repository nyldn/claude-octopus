#!/usr/bin/env bash
# Inspect active, stable, and cached plugin roots without changing them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
OUTPUT=human
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json|json) OUTPUT=json ;;
        --help|-h) printf 'Usage: %s [--json]\n' "$(basename "$0")"; exit 0 ;;
        *) printf 'Unknown cache-check option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
command -v jq >/dev/null 2>&1 || { printf 'cache-check requires jq\n' >&2; exit 1; }

# shellcheck source=lib/cache-hygiene.sh
source "$SCRIPT_DIR/lib/cache-hygiene.sh"
# shellcheck source=lib/lifecycle.sh
source "$SCRIPT_DIR/lib/lifecycle.sh"

checks='[]'
failures=0
add_check() {
    local host="$1" version="$2" role="$3" status="$4" root="$5" detail="$6"
    checks="$(jq -cn --argjson checks "$checks" --arg host "$host" --arg version "$version" \
        --arg role "$role" --arg status "$status" --arg root "$root" --arg detail "$detail" \
        '$checks + [{host:$host,version:$version,role:$role,status:$status,root:$root,detail:$detail}]')"
    [[ "$status" != fail ]] || failures=$((failures + 1))
}

CACHE_VALID_STATUS=pass
CACHE_VALID_DETAIL="manifest and referenced paths are present"
validate_plugin_root() {
    if octo_validate_install_root "$1" "$2"; then CACHE_VALID_STATUS=pass
    else CACHE_VALID_STATUS=fail; fi
    CACHE_VALID_DETAIL="$OCTO_ROOT_VALID_DETAIL"
}

check_host_cache() {
    local host="$1" cache_root="$2" active_root="$3" version path newest="" role status detail
    local active_real="" path_real="" active_seen=false
    [[ -n "$active_root" && -d "$active_root" ]] && active_real="$(cd "$active_root" 2>/dev/null && pwd -P)" || true
    if [[ ! -d "$cache_root" ]]; then
        add_check "$host" "" cache info "$cache_root" "cache directory is absent"
    else
        newest="$(octo_cache_versions "$cache_root" | tail -1)"
        if [[ -z "$newest" ]]; then
            add_check "$host" "" cache info "$cache_root" "cache directory has no versions"
        fi
    fi
    while IFS= read -r version; do
        [[ -n "$version" ]] || continue
        path="$cache_root/$version"
        [[ -d "$path" ]] || continue
        path_real="$(cd "$path" 2>/dev/null && pwd -P)" || path_real=""
        role=stale
        [[ "$version" == "$newest" ]] && role=newest
        if [[ -n "$active_real" && "$path_real" == "$active_real" ]]; then role=active; active_seen=true; fi
        validate_plugin_root "$path" "$host"
        status="$CACHE_VALID_STATUS"; detail="$CACHE_VALID_DETAIL"
        if [[ "$status" == fail && "$role" == stale ]]; then status=warn; fi
        add_check "$host" "$version" "$role" "$status" "$path" "$detail"
    done < <(octo_cache_versions "$cache_root")
    if [[ -n "$active_root" && "$active_seen" == false ]]; then
        validate_plugin_root "$active_root" "$host"
        add_check "$host" "$(octo_lifecycle_version "$active_root")" active "$CACHE_VALID_STATUS" \
            "$active_root" "$CACHE_VALID_DETAIL; active root is outside the host cache"
    fi
}

claude_cache="${OCTOPUS_CLAUDE_CACHE_DIR:-${HOME}/.claude/plugins/cache/nyldn-plugins/octo}"
codex_cache="${OCTOPUS_CODEX_CACHE_DIR:-${CODEX_HOME:-${HOME}/.codex}/plugins/cache/nyldn-plugins/claude-octopus}"
check_host_cache claude "$claude_cache" "${CLAUDE_PLUGIN_ROOT:-}"
check_host_cache codex "$codex_cache" "${CODEX_PLUGIN_ROOT:-}"

stable="$OCTO_LIFECYCLE_STABLE_ROOT"
loaded_root="$(octo_lifecycle_plugin_root)"
validate_plugin_root "$loaded_root" "$(octo_lifecycle_host)"
add_check "$(octo_lifecycle_host)" "$(octo_lifecycle_version "$loaded_root")" loaded \
    "$CACHE_VALID_STATUS" "$loaded_root" "$CACHE_VALID_DETAIL"
stable_status="$(octo_lifecycle_stable_root_status "$loaded_root" 2>/dev/null || true)"
case "$stable_status" in
    ok|shim) add_check "$(octo_lifecycle_host)" "$(octo_lifecycle_version "$stable")" stable pass "$stable" "stable root resolves to the loaded plugin" ;;
    missing) add_check "$(octo_lifecycle_host)" "" stable info "$stable" "stable root is absent" ;;
    *) add_check "$(octo_lifecycle_host)" "" stable fail "$stable" "stable root is $stable_status" ;;
esac

report="$(jq -cn --argjson checks "$checks" --argjson failures "$failures" \
    '{schema:1,failures:$failures,checks:$checks}')"
if [[ "$OUTPUT" == json ]]; then
    printf '%s\n' "$report"
else
    printf 'Claude Octopus plugin cache check\n'
    jq -r '.checks[] | "  \(.host)\t\(.version // "-")\t\(.role)\t\(.status)\t\(.detail)"' <<<"$report"
fi
[[ "$failures" -eq 0 ]]
