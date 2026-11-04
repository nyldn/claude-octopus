#!/usr/bin/env bash
set -euo pipefail

# /octo:preflight — shared provider readiness dashboard.
# Static mode is the default and performs no network calls. Pass --live to run
# the registry-selected health handlers under a strict timeout.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK_VERSIONS="${SCRIPT_DIR}/check-versions.sh"
CHECK_OLLAMA_MODELS="${SCRIPT_DIR}/check-ollama-models.sh"

log() { :; }
source "${SCRIPT_DIR}/../lib/preflight.sh"

CHECK_KIND="static"
OUTPUT_MODE="human"
for arg in "$@"; do
    case "$arg" in
        --live) CHECK_KIND="live" ;;
        --json) OUTPUT_MODE="json" ;;
        --exit-code) OUTPUT_MODE="exit-code" ;;
        *) echo "Unknown preflight option: $arg" >&2; exit 2 ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: /octo:preflight requires jq. Install jq and retry." >&2
    exit 1
fi

# A pinned council roster (OCTOPUS_COUNCIL_DEFAULT_PROVIDERS) is checked
# instead of every registered provider.
roster="" roster_rc=0 sandbox=""
if declare -F octo_preflight_roster >/dev/null 2>&1; then
    roster="$(octo_preflight_roster)" || roster_rc=$?
fi
if [[ "$roster_rc" -ne 0 ]]; then
    echo "ERROR: OCTOPUS_COUNCIL_DEFAULT_PROVIDERS is not a valid council roster: ${OCTOPUS_COUNCIL_DEFAULT_PROVIDERS:-}" >&2
    exit 2
fi
roster_json='null'
[[ -z "$roster" ]] || roster_json="$(printf '%s\n' "$roster" | jq -R . | jq -cs .)"
if declare -F octo_preflight_sandbox >/dev/null 2>&1; then
    sandbox="$(octo_preflight_sandbox)"
fi

# Roster seats the registry cannot detect are listed as not checked rather than
# unready; the council checks them when it dispatches.
roster_unchecked=""
if [[ -n "$roster" ]] && declare -F octo_preflight_seat_checkable >/dev/null 2>&1; then
    for seat in $roster; do
        octo_preflight_seat_checkable "$seat" || roster_unchecked="${roster_unchecked}${roster_unchecked:+ }${seat}"
    done
fi
roster_unchecked_json="$(printf '%s\n' $roster_unchecked | jq -R 'select(length > 0)' | jq -cs .)"

# Unchecked seats are listed separately, never counted as ready or degraded.
roster_checked=""
for seat in $roster; do
    [[ " $roster_unchecked " == *" $seat "* ]] || roster_checked="${roster_checked}${roster_checked:+ }${seat}"
done
if [[ -n "$roster" && -z "$roster_checked" ]]; then
    results_json='[]'
else
    results_json="$({ octo_provider_readiness_all "$CHECK_KIND" "$roster_checked"; } | jq -s '.')"
fi
providers_ready="$(jq '[.[] | select(.status == "available")] | length' <<<"$results_json")"
providers_degraded="$(jq '[.[] | select(.status != "available")] | length' <<<"$results_json")"

if [[ "$OUTPUT_MODE" == "exit-code" ]]; then
    exit 0
fi

versions_json='{"any_below_floor":false,"results":[]}'
if [[ -f "$CHECK_VERSIONS" ]]; then
    versions_json="$(bash "$CHECK_VERSIONS" --json 2>/dev/null || printf '%s' '{"any_below_floor":false,"results":[]}')"
fi

ollama_json='{"reachable":false,"models":[],"check_kind":"static"}'
if [[ "$CHECK_KIND" == "live" && -f "$CHECK_OLLAMA_MODELS" ]]; then
    ollama_json="$(bash "$CHECK_OLLAMA_MODELS" --json 2>/dev/null || printf '%s' '{"reachable":false,"models":[],"check_kind":"live"}')"
fi

if [[ "$OUTPUT_MODE" == "json" ]]; then
    jq -n \
        --argjson providers_ready "$providers_ready" \
        --argjson providers_degraded "$providers_degraded" \
        --argjson results "$results_json" \
        --argjson versions "$versions_json" \
        --argjson ollama_models "$ollama_json" \
        --arg check_kind "$CHECK_KIND" \
        --argjson roster "$roster_json" \
        --argjson roster_unchecked "$roster_unchecked_json" \
        --arg sandbox "$sandbox" \
        '{providers_ready:$providers_ready,
          providers_degraded:$providers_degraded,
          check_kind:$check_kind,
          roster:$roster,
          roster_unchecked:$roster_unchecked,
          sandbox:(if $sandbox == "" then null else $sandbox end),
          results:$results,
          versions:$versions,
          ollama_models:$ollama_models}'
    exit 0
fi

echo ""
echo "🐙 Octopus Provider Readiness (${CHECK_KIND})"
echo "────────────────────────────────────"
if [[ -n "$roster" ]]; then
    echo "  Council roster (OCTOPUS_COUNCIL_DEFAULT_PROVIDERS): ${roster//$'\n'/ }"
fi
while IFS=$'\t' read -r provider status reason; do
    case "$status" in
        available) icon="✅" ;;
        degraded) icon="⚠️ " ;;
        *) icon="○ " ;;
    esac
    printf '  %s %-18s %s\n' "$icon" "$provider" "$reason"
done < <(jq -r '.[] | [.provider, .status, .reason_code] | @tsv' <<<"$results_json")
echo ""
echo "  Ready: $providers_ready  |  Needs attention: $providers_degraded"
echo ""
ready_provider_names="$(jq -r '.[] | select(.status == "available") | .provider' <<<"$results_json")"
if [[ -n "$roster" ]]; then
    roster_not_ready="$(jq -r --arg unchecked " $roster_unchecked " '[.[] | select(.status != "available") | .provider as $p | select(($unchecked | contains(" " + $p + " ")) | not) | $p] | join(" ")' <<<"$results_json")"
    if [[ -z "$roster_not_ready" ]]; then
        echo "  Council roster ready."
    else
        echo "  Council roster seat(s) not ready: $roster_not_ready"
    fi
    if [[ -n "$roster_unchecked" ]]; then
        echo "  Not checked by preflight (no provider detection; the council checks it when it dispatches): $roster_unchecked"
    fi
elif [[ "$providers_ready" -eq 0 ]]; then
    echo "  No provider is ready. Run /octo:setup to configure one provider."
elif [[ "$providers_ready" -eq 1 && "$ready_provider_names" == "claude" ]]; then
    echo "  Claude-only mode is available. Run /octo:setup to add one provider."
elif [[ "$providers_ready" -eq 1 ]]; then
    echo "  One provider is ready: $ready_provider_names. Run /octo:setup to add another."
else
    echo "  Multi-provider mode is ready. Run /octo:embrace for full orchestration."
fi
if [[ "$providers_degraded" -gt 0 && -n "$sandbox" ]]; then
    echo "  $(octo_preflight_sandbox_note)"
fi

if [[ -f "$CHECK_VERSIONS" ]]; then
    bash "$CHECK_VERSIONS" 2>/dev/null || true
fi
if [[ "$CHECK_KIND" == "live" && -f "$CHECK_OLLAMA_MODELS" ]]; then
    bash "$CHECK_OLLAMA_MODELS" 2>/dev/null || true
fi

echo ""
exit 0
