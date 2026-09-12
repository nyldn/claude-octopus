#!/usr/bin/env bash
# Conservative repair for the Octopus-owned stable plugin root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
APPLY=false
OUTPUT=human
mode_seen=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            [[ -z "$mode_seen" || "$mode_seen" == apply ]] || { printf 'Choose either --apply or --dry-run\n' >&2; exit 2; }
            APPLY=true; mode_seen=apply
            ;;
        --dry-run)
            [[ -z "$mode_seen" || "$mode_seen" == dry-run ]] || { printf 'Choose either --apply or --dry-run\n' >&2; exit 2; }
            APPLY=false; mode_seen=dry-run
            ;;
        --json) OUTPUT=json ;;
        --help|-h)
            printf 'Usage: %s [--dry-run|--apply] [--json]\n' "$(basename "$0")"
            exit 0
            ;;
        *) printf 'Unknown repair option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { printf 'repair requires jq\n' >&2; exit 1; }
# shellcheck source=lib/lifecycle.sh
source "$SCRIPT_DIR/lib/lifecycle.sh"
# shellcheck source=lib/plugin-root.sh
source "$SCRIPT_DIR/lib/plugin-root.sh"

root="$(octo_lifecycle_plugin_root)"
stable="$OCTO_LIFECYCLE_STABLE_ROOT"
status="$(octo_lifecycle_stable_root_status "$root" 2>/dev/null || true)"
action=none
result=ready

case "$status" in
    ok|shim) ;;
    missing) action="create stable plugin root" ;;
    broken) action="replace broken stable plugin link" ;;
    mismatch) action="replace stale stable plugin link" ;;
    invalid) action="manual review required: stable path is not an Octopus link or shim"; result=blocked ;;
    *) action="manual review required: plugin root is unavailable"; result=blocked ;;
esac

if [[ "$APPLY" == true && "$result" == ready && "$status" != ok && "$status" != shim ]]; then
    if octo_ensure_stable_plugin_root "$root" "$stable" >/dev/null 2>&1; then
        status="$(octo_lifecycle_stable_root_status "$root" 2>/dev/null || true)"
        case "$status" in ok|shim) ;; *) result=failed ;; esac
    else
        result=failed
    fi
fi
if [[ "$APPLY" == true && "$result" == ready ]]; then
    octo_lifecycle_record_install >/dev/null 2>&1 || result=state-write-failed
fi

mode=dry-run
[[ "$APPLY" == true ]] && mode=apply
report="$(jq -cn --arg mode "$mode" --arg root "$root" --arg stable "$stable" \
    --arg status "$status" --arg action "$action" --arg result "$result" \
    '{schema:1,mode:$mode,plugin_root:$root,stable_root:$stable,status:$status,
      action:$action,result:$result}')"
if [[ "$OUTPUT" == json ]]; then
    printf '%s\n' "$report"
else
    printf 'Claude Octopus repair (%s)\n' "$mode"
    jq -r '"  plugin root: \(.plugin_root)\n  stable root: \(.stable_root)\n  status: \(.status)\n  action: \(.action)"' <<<"$report"
fi
[[ "$result" == ready ]]
