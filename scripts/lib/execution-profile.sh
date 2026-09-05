#!/usr/bin/env bash
# Unified role/phase execution profile resolution.
# Backward compatible with string routes (provider:model) and supports object routes:
# {"provider":"codex","model":"gpt-5.6","reasoning":"medium","reasoningPolicy":"strict"}

_octo_execution_profile_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_model_family >/dev/null 2>&1; then
  source "${_octo_execution_profile_dir}/models.sh" 2>/dev/null || true
fi

# octo_route_task_class <prompt> <role> <phase>
#
# A deliberately small, deterministic classifier for routing policy evaluation.
# It does not inspect the filesystem, provider health, auth, or session state.
# Callers that need different behavior can use explicit role/phase routes, which
# retain precedence over every eval-backed default.
octo_route_task_class() {
  local prompt="${1:-}" role="${2:-}" phase="${3:-}" combined
  combined="$(printf '%s %s %s' "$role" "$phase" "$prompt" | tr '[:upper:]' '[:lower:]')"

  case "$combined" in
    *security*|*threat-model*|*threat\ model*|*red-team*|*red\ team*)
      printf '%s\n' security
      return 0
      ;;
  esac
  case "$combined" in
    *reviewer*|*review*)
      printf '%s\n' review
      return 0
      ;;
  esac
  case "$combined" in
    *architect*|*strategist*|*tradeoff*|*trade-off*|*durable\ coordination*|*choose\ the*)
      printf '%s\n' premium
      return 0
      ;;
  esac
  case "$combined" in
    *"find every reference"*|*"report the file"*|*"list every"*|*"rename the same"*|*"without changing behavior"*|*"small parsing change"*|*"mechanical"*)
      printf '%s\n' mechanical
      return 0
      ;;
  esac
  printf '%s\n' balanced
}

_octo_route_provider_for_model() {
  case "${1:-}" in
    composer-*|cursor-agent*|cursor-grok-*) printf '%s\n' cursor-agent; return 0 ;;
    grok-*) printf '%s\n' grok; return 0 ;;
  esac
  case "$(octo_model_family "${1:-}")" in
    anthropic)
      case "${1:-}" in
        *haiku*) printf '%s\n' claude-haiku ;;
        *sonnet*) printf '%s\n' claude-sonnet ;;
        *) printf '%s\n' claude-opus ;;
      esac
      ;;
    openai) printf '%s\n' codex-standard ;;
    google) printf '%s\n' agy ;;
    *) printf '%s\n' unknown ;;
  esac
}

# octo_route_decision <class> <policy> <user-pin> <project-pin>
#                     <requires-independent> <author-model> <candidate-verifier>
#
# Emits one JSON decision and never calls a provider. Explicit pins are selected
# before evaluated defaults. An explicit same-family verifier is honored but its
# coverage is marked degraded; an unpinned same-family candidate is replaced by
# a cross-vendor verifier.
octo_route_decision() {
  local task_class="${1:-balanced}" policy="${2:-off}"
  local user_pin="${3:-}" project_pin="${4:-}"
  local requires_independent="${5:-false}" author_model="${6:-}"
  local candidate_verifier="${7:-}"
  local model provider reason coverage="not-required" pinned=false

  if [[ -n "$user_pin" ]]; then
    model="$user_pin"
    reason="user-pin"
    pinned=true
  elif [[ -n "$project_pin" ]]; then
    model="$project_pin"
    reason="project-route"
    pinned=true
  elif [[ "$policy" != "eval" ]]; then
    model="${candidate_verifier:-retain-current}"
    reason="policy-${policy:-off}"
  elif [[ "$requires_independent" == true && -n "$author_model" && -n "$candidate_verifier" ]] &&
       [[ "$(octo_model_family "$author_model")" != "$(octo_model_family "$candidate_verifier")" ]]; then
    model="$candidate_verifier"
    reason="independent-verifier"
    coverage="independent"
  elif [[ "$requires_independent" == true && -n "$author_model" ]]; then
    if [[ "$(octo_model_family "$author_model")" == openai ]]; then
      model="claude-opus-5"
    else
      model="gpt-5.6-sol"
    fi
    reason="cross-vendor-verifier"
    coverage="independent"
  else
    case "$task_class" in
      mechanical) model="gpt-5.6-luna"; reason="eval-mechanical" ;;
      balanced) model="gpt-5.6-terra"; reason="eval-balanced" ;;
      premium) model="claude-opus-5"; reason="eval-premium" ;;
      security) model="gpt-5.6-sol"; reason="security-cross-vendor" ;;
      review) model="gpt-5.6-sol"; reason="eval-review" ;;
      *) return 2 ;;
    esac
  fi

  provider="$(_octo_route_provider_for_model "$model")"
  if [[ "$requires_independent" == true && "$coverage" != independent ]]; then
    if [[ "$model" == retain-current ]]; then
      coverage="degraded-verifier-unresolved"
    elif [[ -n "$author_model" && "$(octo_model_family "$author_model")" == "$(octo_model_family "$model")" ]]; then
      coverage="degraded-same-family"
    elif [[ -n "$author_model" ]]; then
      coverage="independent"
    else
      coverage="degraded-author-unknown"
    fi
  fi

  jq -cn \
    --arg task_class "$task_class" --arg policy "$policy" \
    --arg provider "$provider" --arg model "$model" --arg reason "$reason" \
    --arg coverage "$coverage" --argjson pinned "$pinned" \
    '{schema_version:"10.0", task_class:$task_class, policy:$policy,
      provider:$provider, model:$model, reason:$reason, coverage:$coverage,
      explicit_pin:$pinned}'
}

_octopus_profile_config_file() {
  printf "%s\n" "${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
}

octo_routing_policy() {
  local policy="${OCTOPUS_ROUTING_POLICY:-}" cfg
  if [[ -z "$policy" ]]; then
    cfg="$(_octopus_profile_config_file)"
    if [[ -f "$cfg" ]]; then
      policy="$(jq -r '.routing.policy // "off"' "$cfg" 2>/dev/null || printf '%s' off)"
    fi
  fi
  policy="${policy:-off}"
  case "$policy" in
    off|eval) printf '%s\n' "$policy" ;;
    *) return 2 ;;
  esac
}

_octopus_profile_route_json() {
  local phase="${1:-}" role="${2:-}" cfg
  cfg="$(_octopus_profile_config_file)"
  [[ -f "$cfg" ]] || { printf "%s\n" "null"; return 0; }
  jq -c --arg phase "$phase" --arg role "$role" '
    if ($role != "" and (.routing.roles[$role] != null)) then .routing.roles[$role]
    elif ($phase != "" and (.routing.phases[$phase] != null)) then .routing.phases[$phase]
    else null end
  ' "$cfg" 2>/dev/null
}

_octopus_profile_field() {
  local phase="${1:-}" role="${2:-}" field="$3" route
  route="$(_octopus_profile_route_json "$phase" "$role")" || return $?
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

_octopus_profile_env_value() {
  local env_name="${1:-}" value=""
  [[ -n "$env_name" && "$env_name" != *[!A-Z0-9_]* ]] || return 1
  eval "value=\${${env_name}-}"
  printf '%s
' "$value"
}

octopus_explicit_provider_override() {
  local phase="$1" operation="$2" phase_key operation_key env_name value
  phase_key="$(_octopus_profile_env_key "$phase")"
  operation_key="$(_octopus_profile_env_key "$operation")"

  if [[ -n "$phase_key" && -n "$operation_key" ]]; then
    env_name="OCTOPUS_${phase_key}_${operation_key}_AGENT"
    value="$(_octopus_profile_env_value "$env_name" 2>/dev/null || true)"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  fi
  if [[ -n "$phase_key" ]]; then
    env_name="OCTOPUS_${phase_key}_AGENT"
    value="$(_octopus_profile_env_value "$env_name" 2>/dev/null || true)"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  fi
  if [[ -n "$operation_key" ]]; then
    env_name="OCTOPUS_${operation_key}_AGENT"
    value="$(_octopus_profile_env_value "$env_name" 2>/dev/null || true)"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  fi
  return 1
}

# Canonical provider resolution for workflow dispatch.
# Precedence: explicit operation/phase env override > configured role/phase
# route > release role mapping > historical caller default. Workflows should
# not duplicate this logic.
octopus_execution_profile_provider() {
  local phase="$1" operation="$2" role="$3" default_provider="$4"
  local explicit_provider configured_provider role_provider="$default_provider"

  explicit_provider="$(octopus_explicit_provider_override "$phase" "$operation" 2>/dev/null || true)"
  if [[ -n "$explicit_provider" ]]; then
    printf '%s\n' "$explicit_provider"
    return 0
  fi

  # get_role_agent() owns the release's default role table and consent-gated
  # reviewer flip. It is defined by agent-utils.sh in the production source
  # order. Keep this guard so execution-profile.sh remains sourceable alone.
  if declare -F get_role_agent >/dev/null 2>&1 && [[ -n "$role" ]]; then
    role_provider="$(get_role_agent "$role" 2>/dev/null || printf '%s\n' "$default_provider")"
    role_provider="${role_provider:-$default_provider}"
  fi

  configured_provider="$(octopus_profile_provider "$phase" "$role" "$role_provider" 2>/dev/null || true)"
  printf '%s\n' "${configured_provider:-$role_provider}"
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
  phase_key="$(_octopus_profile_env_key "$phase")"
  role_key="$(_octopus_profile_env_key "$role")"
  provider_key="$(_octopus_profile_env_key "$provider")"
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
