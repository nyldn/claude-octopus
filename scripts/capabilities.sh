#!/usr/bin/env bash
# Local provider capability report backed by Provider Registry readiness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
OUTPUT=human

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json|json) OUTPUT=json ;;
        --help|-h)
            printf 'Usage: %s [--json]\n' "$(basename "$0")"
            exit 0
            ;;
        *) printf 'Unknown capabilities option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { printf 'capabilities requires jq\n' >&2; exit 1; }
# shellcheck source=lib/lifecycle.sh
source "$SCRIPT_DIR/lib/lifecycle.sh"
log() { :; }
# shellcheck source=lib/preflight.sh
source "$SCRIPT_DIR/lib/preflight.sh"

providers_json="$({
    for provider in $(octo_provider_ids detect); do
        readiness="$(octo_provider_readiness_result "$provider" static 2>/dev/null)"
        organization="$(octo_provider_org "$provider" 2>/dev/null || true)"
        command_name="$(octo_provider_command "$provider" 2>/dev/null || true)"
        capabilities="$(octo_provider_field "$provider" capabilities 2>/dev/null || true)"
        jq -cn --argjson readiness "$readiness" --arg id "$provider" \
            --arg organization "$organization" --arg command "$command_name" \
            --arg capabilities "$capabilities" \
            '$readiness + {id:$id,organization:$organization,command:$command,
             capabilities:($capabilities | split(",") | map(select(length > 0)))} |
             del(.provider,.check_kind,.checked_at,.duration_ms)'
    done
} | jq -s '.')"

report="$(jq -cn --arg host "$(octo_lifecycle_host)" \
    --arg context_profile "$(octo_lifecycle_profile)" \
    --arg hook_profile "$(octo_lifecycle_hook_profile)" \
    --argjson providers "$providers_json" \
    '{schema:1,check_kind:"static",host:$host,context_profile:$context_profile,
      hook_profile:$hook_profile,providers:$providers}')"

if [[ "$OUTPUT" == json ]]; then
    printf '%s\n' "$report"
    exit 0
fi

printf 'Claude Octopus capabilities\n'
printf '  host: %s\n  context profile: %s\n  hook profile: %s\n' \
    "$(jq -r '.host' <<<"$report")" "$(jq -r '.context_profile' <<<"$report")" \
    "$(jq -r '.hook_profile' <<<"$report")"
printf '%-18s %-11s %s\n' provider status capabilities
jq -r '.providers[] | [.id,.status,(.capabilities | join(","))] | @tsv' <<<"$report" |
    while IFS=$'\t' read -r provider status capabilities; do
        printf '%-18s %-11s %s\n' "$provider" "$status" "$capabilities"
    done
