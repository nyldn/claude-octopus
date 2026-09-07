#!/usr/bin/env bash
# Add method requirements to provider prompts without changing dispatch policy.
_octo_methods_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

octo_with_engineering_methods() {
    local phase="${1:-}" prompt="${2:-}" contract
    case "$phase" in
        tangle|develop|review|ink|deliver|grasp|define) ;;
        *) printf '%s' "$prompt"; return 0 ;;
    esac
    contract="${_octo_methods_root}/skills/blocks/engineering-method-selection.md"
    if [[ ! -f "$contract" ]]; then
        printf '%s\n' "Engineering method reference unavailable: $contract" >&2
        return 1
    fi
    contract=$(cat "$contract") || return 1
    # Fallbacks may receive an already-enriched prompt. This avoids duplicate
    # prose, and is not a security or dispatch-admission check.
    if [[ "$prompt" == *"$contract"* ]]; then
        printf '%s' "$prompt"
        return 0
    fi
    printf 'Installed Octopus plugin root: %s\n\n' "$_octo_methods_root"
    printf '%s' "$contract"
    printf '\n\n## Assigned task\n%s' "$prompt"
}
