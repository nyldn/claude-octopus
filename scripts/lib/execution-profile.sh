#!/usr/bin/env bash
# Unified role/phase execution profile resolution.
# Backward compatible with string routes (provider:model) and supports object routes:
# {"provider":"codex","model":"gpt-5.6","reasoning":"medium","reasoningPolicy":"strict"}

_octopus_profile_config_file() {
  printf "%s\n" "${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
}

_octopus_profile_route_json() {
  local phase="${1:-}" role="${2:-}" cfg
  cfg="$(_octopus_profile_config_file)"
  [[ -f "$cfg" ]] || { printf "%s\n" "null"; return 0; }
  jq -c --arg phase "$phase" --arg role "$role" '
    if ($role != "" and (.routing.roles[$role] != null)) then .routing.roles[$role]
    elif ($phase != "" and (.routing.phases[$phase] != null)) then .routing.phases[$phase]
    else null end
  ' "$cfg" 2>/dev/null || printf "%s\n" "null"
}

_octopus_profile_field() {
  local phase="${1:-}" role="${2:-}" field="$3" route
  route="$(_octopus_profile_route_json "$phase" "$role")"
  [[ "$route" != "null" ]] || return 1
  if [[ "$route" == \{* ]]; then
    jq -r --arg field "$field" '.[$field] // empty' <<<"$route" 2>/dev/null
    return 0
  fi
  route="$(jq -r '.' <<<"$route" 2>/dev/null || printf "%s" "$route")"
  case "$field" in
    provider) [[ "$route" == *:* ]] && printf "%s\n" "${route%%:*}" || printf "%s\n" "$route" ;;
    model) [[ "$route" == *:* ]] && printf "%s\n" "${route#*:}" || true ;;
    *) return 1 ;;
  esac
}

_octopus_profile_env_key() {
  printf '%s' "${1:-}" | tr '[:lower:]-' '[:upper:]_' | sed -E 's/[^A-Z0-9_]+/_/g; s/^_+//; s/_+$//'
}

octopus_explicit_provider_override() {
  local phase="$1" operation="$2" phase_key operation_key env_name value
  phase_key="$(_octopus_profile_env_key "$phase")"
  operation_key="$(_octopus_profile_env_key "$operation")"

  if [[ -n "$phase_key" && -n "$operation_key" ]]; then
    env_name="OCTOPUS_${phase_key}_${operation_key}_AGENT"
    value="${!env_name:-}"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  fi
  if [[ -n "$phase_key" ]]; then
    env_name="OCTOPUS_${phase_key}_AGENT"
    value="${!env_name:-}"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  fi
  if [[ -n "$operation_key" ]]; then
    env_name="OCTOPUS_${operation_key}_AGENT"
    value="${!env_name:-}"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  fi
  return 1
}

# Canonical provider resolution for workflow dispatch.
# Precedence: explicit operation/phase env override > configured role/phase
# route > historical caller default. Workflows should not duplicate this logic.
octopus_execution_profile_provider() {
  local phase="$1" operation="$2" role="$3" default_provider="$4"
  local explicit_provider configured_provider

  explicit_provider="$(octopus_explicit_provider_override "$phase" "$operation" 2>/dev/null || true)"
  if [[ -n "$explicit_provider" ]]; then
    printf '%s\n' "$explicit_provider"
    return 0
  fi

  configured_provider="$(octopus_profile_provider "$phase" "$role" "$default_provider" 2>/dev/null || true)"
  printf '%s\n' "${configured_provider:-$default_provider}"
}


_octopus_provider_definition_json() {
  local provider="$1" cfg
  cfg="$(_octopus_profile_config_file)"
  [[ -f "$cfg" ]] || { printf '%s\n' '{}'; return 0; }
  jq -c --arg provider "$provider" '.providers[$provider] // {}' "$cfg" 2>/dev/null || printf '%s\n' '{}'
}

octopus_provider_definition_field() {
  local provider="$1" field="$2" definition
  definition="$(_octopus_provider_definition_json "$provider")"
  jq -r --arg field "$field" '.[$field] // empty' <<<"$definition" 2>/dev/null || true
}


octopus_profile_provider() {
  local phase="$1" role="$2" default_provider="$3" value
  value="$(_octopus_profile_field "$phase" "$role" provider 2>/dev/null || true)"
  printf "%s\n" "${value:-$default_provider}"
}

octopus_profile_model() {
  _octopus_profile_field "$1" "$2" model 2>/dev/null || true
}

octopus_normalize_reasoning_level() {
  case "${1:-}" in
    ""|default|auto) printf "%s\n" "" ;;
    none|off|disabled) printf "%s\n" "none" ;;
    low|medium|high|max|xhigh) printf "%s\n" "$1" ;;
    *) return 1 ;;
  esac
}

octopus_resolve_reasoning_level() {
  local provider="$1" phase="${2:-}" role="${3:-}" phase_key role_key provider_key name value cfg
  phase_key=$(printf "%s" "$phase" | tr "[:lower:]-" "[:upper:]_")
  role_key=$(printf "%s" "$role" | tr "[:lower:]-" "[:upper:]_")
  provider_key=$(printf "%s" "$provider" | tr "[:lower:]-" "[:upper:]_")
  for name in     "OCTOPUS_${phase_key}_${role_key}_REASONING"     "OCTOPUS_${role_key}_REASONING"     "OCTOPUS_${phase_key}_REASONING"     "OCTOPUS_${provider_key}_REASONING"     OCTOPUS_REASONING_LEVEL; do
    value="${!name:-}"
    if [[ -n "$value" ]]; then octopus_normalize_reasoning_level "$value"; return $?; fi
  done
  value="$(_octopus_profile_field "$phase" "$role" reasoning 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    cfg="$(_octopus_profile_config_file)"
    [[ -f "$cfg" ]] && value=$(jq -r --arg p "$provider" '.providers[$p].reasoning.default // empty' "$cfg" 2>/dev/null || true)
  fi
  octopus_normalize_reasoning_level "$value"
}

octopus_resolve_reasoning_policy() {
  local provider="$1" phase="${2:-}" role="${3:-}" value cfg
  value="$(_octopus_profile_field "$phase" "$role" reasoningPolicy 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    cfg="$(_octopus_profile_config_file)"
    [[ -f "$cfg" ]] && value=$(jq -r --arg p "$provider" '.providers[$p].reasoning.policy // empty' "$cfg" 2>/dev/null || true)
  fi
  value="${value:-${OCTOPUS_REASONING_POLICY:-best_effort}}"
  case "$value" in strict|best_effort) printf "%s\n" "$value" ;; *) return 1 ;; esac
}

octopus_provider_supports_reasoning() {
  case "$1" in codex|claude|claude-sdk|openai-compatible-agent|openai-compatible|openai-tools) return 0 ;; *) return 1 ;; esac
}

octopus_reasoning_cli_fragment() {
  local provider="$1" level="$2" policy="${3:-best_effort}"
  [[ -z "$level" || "$level" == "none" ]] && return 0
  if ! octopus_provider_supports_reasoning "$provider"; then
    [[ "$policy" == strict ]] && return 2
    return 0
  fi
  case "$provider" in
    codex) printf "%s\n" "-c model_reasoning_effort=\"${level}\"" ;;
    claude|claude-sdk) printf "%s\n" "--effort ${level}" ;;
    openai-compatible-agent|openai-compatible|openai-tools)
      # The OpenAI reasoning_effort domain is low|medium|high; xhigh/max are
      # Claude-side levels and would fail command validation downstream.
      case "$level" in xhigh|max) level="high" ;; esac
      printf "%s\n" "--reasoning-effort ${level} --reasoning-policy ${policy}" ;;
  esac
}
