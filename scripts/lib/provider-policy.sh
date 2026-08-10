#!/usr/bin/env bash
# Shared provider-selection policy defaults.
# Identity and capabilities live in provider-registry.sh; these ordered lists
# are workflow policy and remain independently configurable.

_provider_policy_registry_dir="${BASH_SOURCE[0]%/*}"
[[ "$_provider_policy_registry_dir" == "${BASH_SOURCE[0]}" ]] && _provider_policy_registry_dir="."
_provider_policy_registry_dir="$(cd "$_provider_policy_registry_dir" && pwd)"
source "${_provider_policy_registry_dir}/provider-registry.sh" 2>/dev/null || true

OCTOPUS_COUNCIL_DEFAULT_PROVIDERS_DEFAULT="claude,codex,agy,qwen,opencode,openrouter,openai-compatible,openai-tools"
OCTOPUS_SMOKE_ROUTING_PROVIDERS_DEFAULT="codex agy claude opencode openrouter"

octo_validate_provider_policy_list() {
    local raw="$1" capability="$2" label="$3"
    local provider canonical seen=""
    [[ -n "$raw" ]] || {
        echo "$label must not be empty" >&2
        return 2
    }

    # Accept comma- or space-separated policy values, but reject empty comma items.
    case "$raw" in
        ,*|*,|*,,*)
            echo "$label contains an empty provider" >&2
            return 2
            ;;
    esac

    for provider in $(printf '%s' "$raw" | tr ',' ' '); do
        canonical="$(octo_provider_canonical "$provider" 2>/dev/null || true)"
        [[ -n "$canonical" ]] || {
            echo "$label references unknown provider '$provider'" >&2
            return 2
        }
        octo_provider_has_capability "$canonical" "$capability" || {
            reason="$(octo_provider_limitation_reason "$canonical" "$capability" 2>/dev/null || true)"
            echo "$label provider '$canonical' does not support '$capability'${reason:+ ($reason)}" >&2
            return 2
        }
        case " $seen " in
            *" $canonical "*)
                echo "$label contains duplicate provider '$canonical'" >&2
                return 2
                ;;
        esac
        seen="${seen}${seen:+ }${canonical}"
    done
    return 0
}

octo_council_default_providers() {
    local value="${OCTOPUS_COUNCIL_DEFAULT_PROVIDERS:-$OCTOPUS_COUNCIL_DEFAULT_PROVIDERS_DEFAULT}"
    octo_validate_provider_policy_list "$value" council OCTOPUS_COUNCIL_DEFAULT_PROVIDERS || return $?
    printf '%s\n' "$value"
}

octo_smoke_routing_providers() {
    local value="${OCTOPUS_SMOKE_ROUTING_PROVIDERS:-$OCTOPUS_SMOKE_ROUTING_PROVIDERS_DEFAULT}"
    octo_validate_provider_policy_list "$value" dispatch OCTOPUS_SMOKE_ROUTING_PROVIDERS || return $?
    printf '%s\n' "$value"
}
