#!/usr/bin/env bash
# Bounded, premium-only dispatch escalation for explicit-only frontier models.

if [[ -n "${_OCTO_FRONTIER_ESCALATION_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_OCTO_FRONTIER_ESCALATION_LOADED=1

_octo_frontier_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f get_model_policy >/dev/null 2>&1; then
    source "${_octo_frontier_lib_dir}/models.sh" 2>/dev/null || true
fi
if ! declare -f octo_provider_canonical >/dev/null 2>&1; then
    source "${_octo_frontier_lib_dir}/provider-registry.sh" 2>/dev/null || true
fi
if ! declare -f octo_codex_model_version_ok >/dev/null 2>&1; then
    source "${_octo_frontier_lib_dir}/provider-versions.sh" 2>/dev/null || true
fi

_octo_frontier_config_file() {
    printf '%s\n' "${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
}

octo_frontier_configured_model() {
    local provider="${1:-}" config_file
    [[ -n "$provider" ]] || return 1
    if declare -f octo_provider_canonical >/dev/null 2>&1; then
        provider="$(octo_provider_canonical "$provider" 2>/dev/null || printf '%s' "$provider")"
    fi
    config_file="$(_octo_frontier_config_file)"
    [[ -f "$config_file" ]] && command -v jq >/dev/null 2>&1 || return 1
    jq -r --arg provider "$provider" '
      .routing.frontier[$provider] as $entry |
      if ($entry | type) == "object" then ($entry.model // empty)
      elif ($entry | type) == "string" then $entry
      else empty end
    ' "$config_file" 2>/dev/null
}

octo_frontier_cost_mode() {
    local config_file mode="${OCTOPUS_COST_MODE:-}"
    config_file="$(_octo_frontier_config_file)"
    if [[ -z "$mode" && -f "$config_file" ]] && command -v jq >/dev/null 2>&1; then
        mode="$(jq -r '.cost_mode // "standard"' "$config_file" 2>/dev/null || true)"
    fi
    case "${mode:-standard}" in
        budget|standard|premium) printf '%s\n' "${mode:-standard}" ;;
        *) printf '%s\n' standard ;;
    esac
}

octo_frontier_model_budget() {
    local policy budget
    declare -f get_model_policy >/dev/null 2>&1 || return 1
    policy="$(get_model_policy "${1:-}")" || return 1
    budget="$(printf '%s\n' "$policy" | cut -d'|' -f4)"
    [[ "$budget" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "$budget"
}

octo_frontier_model_runtime_available() {
    local model="${1:-}" canonical
    if declare -f octo_model_canonical_id >/dev/null 2>&1; then
        canonical="$(octo_model_canonical_id "$model" 2>/dev/null)" || return 1
    else
        canonical="$model"
    fi
    case "$canonical" in
        gpt-6-astra)
            declare -f octo_codex_installed_version >/dev/null 2>&1 || return 1
            declare -f octo_codex_model_version_ok >/dev/null 2>&1 || return 1
            octo_codex_model_version_ok "$(octo_codex_installed_version)" "$canonical"
            ;;
        claude-fable-5-1)
            declare -f octo_claude_installed_version >/dev/null 2>&1 || return 1
            declare -f octo_claude_model_version_ok >/dev/null 2>&1 || return 1
            octo_claude_model_version_ok "$(octo_claude_installed_version)" "$canonical"
            ;;
        *)
            return 1
            ;;
    esac
}

octo_frontier_policy_enabled() {
    local provider="${1:-}" model="${2:-}" configured canonical_configured canonical_model
    [[ "$(octo_frontier_cost_mode)" == premium ]] || return 1
    configured="$(octo_frontier_configured_model "$provider" 2>/dev/null || true)"
    [[ -n "$configured" ]] || return 1
    if declare -f octo_model_canonical_id >/dev/null 2>&1; then
        canonical_configured="$(octo_model_canonical_id "$configured" 2>/dev/null || true)"
        canonical_model="$(octo_model_canonical_id "$model" 2>/dev/null || true)"
    else
        canonical_configured="$configured"
        canonical_model="$model"
    fi
    [[ -n "$canonical_model" && "$canonical_configured" == "$canonical_model" ]] || return 1
    octo_frontier_model_budget "$canonical_model" >/dev/null
}

octo_frontier_role_eligible() {
    case "${1:-}" in
        architect|strategist) return 0 ;;
        *) return 1 ;;
    esac
}

octo_frontier_projected_cost() {
    local model="${1:-}" prompt_bytes="${2:-}" pricing_file input_tokens output_tokens
    local input_price output_price threshold input_multiplier output_multiplier
    [[ "$prompt_bytes" =~ ^[0-9]+$ ]] || return 1
    [[ -n "$model" ]] || return 1
    pricing_file="${OCTOPUS_MODEL_PRICING_FILE:-${_octo_frontier_lib_dir}/../../config/model-pricing.tsv}"
    [[ -r "$pricing_file" ]] || return 1
    if declare -f octo_model_canonical_id >/dev/null 2>&1; then
        model="$(octo_model_canonical_id "$model" 2>/dev/null)" || return 1
    fi
    input_tokens=$(( (prompt_bytes + 3) / 4 ))
    output_tokens=$(( input_tokens * 2 ))
    IFS=: read -r input_price output_price <<EOF
$(awk -F '\t' -v model="$model" '
  $1 == "model" && $2 == model { print $3 ":" $4; exit }
' "$pricing_file")
EOF
    [[ "$input_price" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    [[ "$output_price" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    IFS=: read -r threshold input_multiplier output_multiplier <<EOF
$(awk -F '\t' -v model="$model" '
  $1 == "request-rule" && $2 == model { print $3 ":" $4 ":" $5; exit }
' "$pricing_file")
EOF
    if [[ "$threshold" =~ ^[0-9]+$ ]]; then
        # Request rules are data, not shell arithmetic. Validate both
        # multipliers before handing them to awk so malformed or negative
        # pricing metadata fails closed instead of changing the estimate.
        [[ "$input_multiplier" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
        [[ "$output_multiplier" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    fi
    if [[ "$threshold" =~ ^[0-9]+$ && "$input_tokens" -gt "$threshold" ]]; then
        input_price="$(awk -v price="$input_price" -v multiplier="$input_multiplier" 'BEGIN {printf "%.6f", price * multiplier}')"
        output_price="$(awk -v price="$output_price" -v multiplier="$output_multiplier" 'BEGIN {printf "%.6f", price * multiplier}')"
    fi
    awk -v input_tokens="$input_tokens" -v output_tokens="$output_tokens" \
        -v input_price="$input_price" -v output_price="$output_price" \
        'BEGIN {printf "%.6f\n", (input_tokens * input_price + output_tokens * output_price) / 1000000}'
}

octo_frontier_cost_ceiling_valid() {
    local model="${1:-}" prompt_bytes="${2:-}" ceiling="${OCTOPUS_MAX_COST_USD:-}" projected
    [[ "$ceiling" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v ceiling="$ceiling" 'BEGIN { exit !(ceiling > 0) }' || return 1
    projected="$(octo_frontier_projected_cost "$model" "$prompt_bytes")" || return 1
    awk -v projected="$projected" -v ceiling="$ceiling" \
        'BEGIN { exit !(projected <= ceiling) }'
}

# Atomically claim the single frontier slot for a run. Astra and Fable are
# intentionally one shared budget: using both expensive frontier families in
# one run would violate the documented one-frontier-dispatch contract.
octo_frontier_claim() {
    local claim_scope marker claim_root

    if declare -f octo_run_contract_dir >/dev/null 2>&1; then
        claim_scope="${OCTOPUS_RUN_ID:-process-$$}"
        claim_scope="$(printf '%s' "$claim_scope" | sed 's/[^A-Za-z0-9_.:-]/_/g')"
        marker="$(octo_run_contract_dir)/.frontier-escalated-${claim_scope}"
        mkdir -p "$(dirname "$marker")" 2>/dev/null || return 1
        mkdir "$marker" 2>/dev/null
        return $?
    fi

    # A process-local variable cannot survive the command substitution used by
    # dispatch. Use the configured state/workspace root for the same atomic
    # marker contract when the full run-contract library is not loaded. If no
    # controlled root is available, fail closed rather than permitting a
    # second frontier dispatch.
    if [[ -n "${OCTOPUS_STATE_DIR:-}" ]]; then
        claim_root="$OCTOPUS_STATE_DIR"
    elif [[ -n "${WORKSPACE_DIR:-}" ]]; then
        claim_root="$WORKSPACE_DIR"
    else
        return 1
    fi
    claim_scope="${OCTOPUS_RUN_ID:-process-$$}"
    claim_scope="$(printf '%s' "$claim_scope" | sed 's/[^A-Za-z0-9_.:-]/_/g')"
    marker="${claim_root}/.claude-octopus-frontier-escalated-${claim_scope}"
    mkdir -p "$claim_root" 2>/dev/null || return 1
    mkdir "$marker" 2>/dev/null
}

octo_frontier_astra_candidate() {
    local original_model="${1:-}" role="${2:-}" agent_type="${3:-}" phase="${4:-}" prompt_bytes="${5:-0}" canonical
    [[ "$agent_type" != *:* ]] || return 1
    # A missing measurement must never look like a free prompt. This protects
    # legacy probes and callers that omit the optional command argument from
    # accidentally claiming the premium seat.
    [[ "$prompt_bytes" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ -z "${OCTOPUS_CODEX_MODEL:-}" ]] || return 1
    case "$phase" in
        security|security-*|*security*|*squeeze*|*red-team*|*redteam*)
            return 1
            ;;
    esac
    if [[ -n "${OCTOPUS_CODEX_ALLOWED_MODELS:-}" &&
          ",${OCTOPUS_CODEX_ALLOWED_MODELS}," != *",gpt-6-astra,"* ]]; then
        return 1
    fi
    canonical="$(octo_model_canonical_id "$original_model" 2>/dev/null || true)"
    [[ "$canonical" == gpt-5.6-sol ]] || return 1
    octo_frontier_role_eligible "$role" || return 1
    octo_frontier_policy_enabled codex gpt-6-astra || return 1
    octo_frontier_cost_ceiling_valid gpt-6-astra "$prompt_bytes" || return 1
    if declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead gpt-6-astra; then
        return 1
    fi
    declare -f octo_codex_installed_version >/dev/null 2>&1 || return 1
    declare -f octo_codex_model_version_ok >/dev/null 2>&1 || return 1
    octo_codex_model_version_ok "$(octo_codex_installed_version)" gpt-6-astra
}

# octo_frontier_maybe_escalate PROVIDER MODEL ROLE AGENT_TYPE PHASE PROMPT_BYTES
# Emits the model to dispatch and never changes literal model-qualified seats.
octo_frontier_maybe_escalate() {
    local provider="${1:-}" original_model="${2:-}" role="${3:-}"
    local agent_type="${4:-}" phase="${5:-}" target=""

    case "$provider" in
        codex)
            target="gpt-6-astra"
            octo_frontier_astra_candidate "$original_model" "$role" "$agent_type" "$phase" "${6:-0}" || {
                printf '%s\n' "$original_model"
                return 0
            }
            ;;
        *)
            printf '%s\n' "$original_model"
            return 0
            ;;
    esac

    if [[ "${OCTOPUS_DISPATCH_PREVIEW:-false}" == true ]] || octo_frontier_claim "$target"; then
        if [[ "${OCTOPUS_DISPATCH_PREVIEW:-false}" != true ]] && declare -f log >/dev/null 2>&1; then
            log "WARN" "Frontier escalation: ${role:-unknown} ${original_model} -> ${target} (bounded premium seat)"
        fi
        printf '%s\n' "$target"
    else
        printf '%s\n' "$original_model"
    fi
}
