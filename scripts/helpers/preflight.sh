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

results_json="$({ octo_provider_readiness_all "$CHECK_KIND"; } | jq -s '.')"
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
        '{providers_ready:$providers_ready,
          providers_degraded:$providers_degraded,
          check_kind:$check_kind,
          results:$results,
          versions:$versions,
          ollama_models:$ollama_models}'
    exit 0
fi

echo ""
echo "🐙 Octopus Provider Readiness (${CHECK_KIND})"
echo "────────────────────────────────────"
while IFS= read -r result; do
    provider="$(jq -r '.provider' <<<"$result")"
    status="$(jq -r '.status' <<<"$result")"
    reason="$(jq -r '.reason_code' <<<"$result")"
    case "$status" in
        available) icon="✅" ;;
        degraded) icon="⚠️ " ;;
        *) icon="○ " ;;
    esac
    printf '  %s %-18s %s\n' "$icon" "$provider" "$reason"
done < <(jq -c '.[]' <<<"$results_json")
echo ""
echo "  Ready: $providers_ready  |  Needs attention: $providers_degraded"
echo ""
if [[ "$providers_ready" -le 1 ]]; then
    echo "  Claude-only mode is available. Run /octo:setup to add one provider."
elif [[ "$providers_ready" -ge 3 ]]; then
    echo "  Multi-provider mode is ready. Run /octo:embrace for full orchestration."
fi

if [[ -f "$CHECK_VERSIONS" ]]; then
    bash "$CHECK_VERSIONS" 2>/dev/null || true
fi
if [[ "$CHECK_KIND" == "live" && -f "$CHECK_OLLAMA_MODELS" ]]; then
    bash "$CHECK_OLLAMA_MODELS" 2>/dev/null || true
fi

echo ""
exit 0
