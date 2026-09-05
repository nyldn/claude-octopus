#!/usr/bin/env bash
# Claude Octopus — Cost Tracking & Usage Reporting
# Extracted from orchestrate.sh
# Source-safe: no main execution block.

_octopus_cost_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTOPUS_MODEL_PRICING_FILE="${OCTOPUS_MODEL_PRICING_FILE:-${_octopus_cost_lib_dir}/../../config/model-pricing.tsv}"

# Session usage tracking file
USAGE_FILE="${WORKSPACE_DIR}/usage-session.json"
USAGE_HISTORY_DIR="${WORKSPACE_DIR}/usage-history"

# Initialize usage tracking for current session
init_usage_tracking() {
    mkdir -p "$USAGE_HISTORY_DIR"

    # Initialize session usage file
    cat > "$USAGE_FILE" << 'EOF'
{
  "session_id": "",
  "started_at": "",
  "total_calls": 0,
  "total_tokens_estimated": 0,
  "total_cost_estimated": 0.0,
  "by_model": {},
  "by_agent": {},
  "by_phase": {},
  "by_role": {},
  "calls": []
}
EOF

    # Set session ID and start time
    # Claude Code v2.1.132+: use CLAUDE_CODE_SESSION_ID in Bash subprocesses.
    # Fall back to older CLAUDE_CODE_SESSION / CLAUDE_SESSION_ID wiring.
    local session_id
    local claude_session="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_CODE_SESSION:-${CLAUDE_SESSION_ID:-}}}"
    if [[ -n "$claude_session" ]]; then
        session_id="claude-${claude_session}"
    else
        session_id="session-$(date +%Y%m%d-%H%M%S)"
    fi
    local started_at
    started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update session metadata (using sed for portability)
    sed -i.bak "s/\"session_id\": \"\"/\"session_id\": \"$session_id\"/" "$USAGE_FILE" 2>/dev/null || \
        sed -i '' "s/\"session_id\": \"\"/\"session_id\": \"$session_id\"/" "$USAGE_FILE"
    sed -i.bak "s/\"started_at\": \"\"/\"started_at\": \"$started_at\"/" "$USAGE_FILE" 2>/dev/null || \
        sed -i '' "s/\"started_at\": \"\"/\"started_at\": \"$started_at\"/" "$USAGE_FILE"
    rm -f "${USAGE_FILE}.bak" 2>/dev/null

    log DEBUG "Usage tracking initialized: $session_id"
}

# Estimate tokens from prompt length (rough approximation: ~4 chars per token)
estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    echo $(( (char_count + 3) / 4 ))  # Round up
}

# Apply request-size pricing rules from the canonical pricing table.
octo_effective_model_pricing() {
    local model="$1" input_tokens="$2" input_price="$3" output_price="$4"
    local rule="" threshold="" input_multiplier="" output_multiplier=""
    rule="$(awk -F'\t' -v model="$model" '$1 == "request-rule" && $2 == model {print $3 ":" $4 ":" $5; exit}' "$OCTOPUS_MODEL_PRICING_FILE" 2>/dev/null || true)"
    if [[ -n "$rule" ]]; then
        threshold="${rule%%:*}"
        rule="${rule#*:}"
        input_multiplier="${rule%%:*}"
        output_multiplier="${rule##*:}"
    fi
    if [[ "$threshold" =~ ^[0-9]+$ && "$input_tokens" -gt "$threshold" ]]; then
        input_price="$(awk -v price="$input_price" -v multiplier="$input_multiplier" 'BEGIN {printf "%.6f", price * multiplier}')"
        output_price="$(awk -v price="$output_price" -v multiplier="$output_multiplier" 'BEGIN {printf "%.6f", price * multiplier}')"
    fi
    printf '%s:%s\n' "$input_price" "$output_price"
}

# Estimate per-call API spend for progress reporting. Subscription and OAuth
# seats intentionally remain zero because they have no attributable call price.
estimate_agent_call_cost() {
    local agent_type="$1"
    local model="$2"
    local prompt="$3"

    if ! is_api_based_provider "$agent_type"; then
        printf '%s\n' "0.000000"
        return 0
    fi

    local input_tokens output_tokens pricing input_price output_price
    input_tokens=$(estimate_tokens "$prompt")
    output_tokens=$((input_tokens * 2))
    pricing=$(get_model_pricing "$model" "$agent_type")
    input_price="${pricing%%:*}"
    output_price="${pricing##*:}"
    [[ "$input_price" =~ ^[0-9]+([.][0-9]+)?$ ]] || input_price=0
    [[ "$output_price" =~ ^[0-9]+([.][0-9]+)?$ ]] || output_price=0
    pricing="$(octo_effective_model_pricing "$model" "$input_tokens" "$input_price" "$output_price")"
    input_price="${pricing%%:*}"
    output_price="${pricing##*:}"
    awk -v input_tokens="$input_tokens" -v output_tokens="$output_tokens" \
        -v input_price="$input_price" -v output_price="$output_price" \
        'BEGIN {printf "%.6f\n", (input_tokens * input_price + output_tokens * output_price) / 1000000}'
}

# Parse native Task tool metrics from <usage> blocks (v8.6.0, enhanced v8.8.0)
# Sets globals: _PARSED_TOKENS, _PARSED_TOOL_USES, _PARSED_DURATION_MS, _PARSED_SPEED
# Guards on SUPPORTS_NATIVE_TASK_METRICS. Falls back gracefully on parse failure.
parse_task_metrics() {
    local output="$1"
    _PARSED_TOKENS="" ; _PARSED_TOOL_USES="" ; _PARSED_DURATION_MS="" ; _PARSED_SPEED=""
    [[ "$SUPPORTS_NATIVE_TASK_METRICS" != "true" ]] && return 0

    local usage_block
    usage_block=$(echo "$output" | sed -n '/<usage>/,/<\/usage>/p' 2>/dev/null || true)
    if [[ -n "$usage_block" ]]; then
        # v9.5: bash regex extraction (zero subshells, was 4 echo|grep|grep chains)
        [[ "$usage_block" =~ total_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_TOKENS="${BASH_REMATCH[1]}" || _PARSED_TOKENS=""
        [[ "$usage_block" =~ tool_uses:[[:space:]]*([0-9]+) ]] && _PARSED_TOOL_USES="${BASH_REMATCH[1]}" || _PARSED_TOOL_USES=""
        [[ "$usage_block" =~ duration_ms:[[:space:]]*([0-9]+) ]] && _PARSED_DURATION_MS="${BASH_REMATCH[1]}" || _PARSED_DURATION_MS=""
        # v8.8: Parse OTel speed attribute (fast|standard) when available
        if [[ "$SUPPORTS_OTEL_SPEED" == "true" ]]; then
            [[ "$usage_block" =~ speed:[[:space:]]*(fast|standard) ]] && _PARSED_SPEED="${BASH_REMATCH[1]}" || _PARSED_SPEED=""
        fi
    fi
    [[ "$_PARSED_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_TOKENS=""
    [[ "$_PARSED_TOOL_USES" =~ ^[0-9]+$ ]] || _PARSED_TOOL_USES=""
    [[ "$_PARSED_DURATION_MS" =~ ^[0-9]+$ ]] || _PARSED_DURATION_MS=""
    [[ "$_PARSED_SPEED" =~ ^(fast|standard)$ ]] || _PARSED_SPEED=""
}

# [EXTRACTED to lib/provider-routing.sh]

# Calculate cost for a single agent call (only for API-based providers)
calculate_agent_cost() {
    local agent_type="$1"
    local prompt_length="${2:-1000}"  # Character count or default

    # Check if this provider costs money
    if ! is_api_based_provider "$agent_type"; then
        echo "0.00"
        return 0
    fi

    local model
    model=$(get_agent_model "$agent_type" "$phase" "$role")

    local input_tokens
    input_tokens=$(estimate_tokens "$(printf '%*s' "$prompt_length" '')")
    local output_tokens=$((input_tokens * 2))

    local pricing
    pricing=$(get_model_pricing "$model" "$agent_type")
    local input_price="${pricing%%:*}"
    local output_price="${pricing##*:}"
    pricing="$(octo_effective_model_pricing "$model" "$input_tokens" "$input_price" "$output_price")"
    input_price="${pricing%%:*}"
    output_price="${pricing##*:}"

    # Cost = (input_tokens / 1M) * input_price + (output_tokens / 1M) * output_price
    local cost=$(awk "BEGIN {printf \"%.4f\", (($input_tokens / 1000000.0) * $input_price) + (($output_tokens / 1000000.0) * $output_price)}")

    echo "$cost"
}

# v8.5: Estimate total workflow cost (auth-mode aware)
# Returns a formatted cost estimate string for a workflow
# Respects is_api_based_provider() - auth-connected providers show "included"
estimate_workflow_cost() {
    local workflow_name="$1"
    local prompt_length="${2:-2000}"

    # Define expected agent calls per workflow
    local codex_calls=0
    local agy_calls=0
    local claude_calls=0

    case "$workflow_name" in
        embrace)
            codex_calls=8; agy_calls=6; claude_calls=8 ;;
        probe|discover)
            codex_calls=3; agy_calls=2; claude_calls=2 ;;
        grasp|define)
            codex_calls=2; agy_calls=1; claude_calls=2 ;;
        tangle|develop)
            codex_calls=2; agy_calls=2; claude_calls=3 ;;
        ink|deliver)
            codex_calls=2; agy_calls=2; claude_calls=2 ;;
        *)
            codex_calls=2; agy_calls=2; claude_calls=2 ;;
    esac

    local codex_cost="0.00"
    local agy_cost="0.00"
    local codex_label="" agy_label="" claude_label=""
    local has_any_cost=false

    # Codex cost
    if is_api_based_provider "codex"; then
        local per_call
        per_call=$(calculate_agent_cost "codex" "$prompt_length")
        codex_cost=$(awk "BEGIN {printf \"%.2f\", $per_call * $codex_calls}")
        local codex_high
        codex_high=$(awk "BEGIN {printf \"%.2f\", $codex_cost * 1.5}")
        codex_label="~\$${codex_cost}-${codex_high} (${codex_calls} calls, API key)"
        has_any_cost=true
    else
        codex_label="Included (auth-connected)"
    fi

    # Antigravity is a bundled Google seat; Octopus never uses a direct Gemini
    # API key or CLI for these calls.
    agy_label="Included (Antigravity access; ${agy_calls} calls)"

    # Claude is always subscription-based
    claude_label="Included (subscription)"

    local total_low
    total_low=$(awk "BEGIN {printf \"%.2f\", $codex_cost + $agy_cost}")
    local total_high
    total_high=$(awk "BEGIN {printf \"%.2f\", ($codex_cost + $agy_cost) * 1.5}")

    # Return structured result (pipe-delimited for easy parsing)
    echo "${has_any_cost}|${codex_label}|${agy_label}|${claude_label}|${total_low}|${total_high}"
}

# v8.5: Compact cost estimate display (non-interactive, no approval prompt)
# Used for inline cost display within phase entry functions
show_cost_estimate() {
    local workflow_name="$1"
    local prompt_length="${2:-2000}"

    local estimate
    estimate=$(estimate_workflow_cost "$workflow_name" "$prompt_length")

    local has_cost codex_label agy_label claude_label total_low total_high
    IFS='|' read -r has_cost codex_label agy_label claude_label total_low total_high <<< "$estimate"

    # If ALL providers are auth-connected, skip the cost estimate entirely
    if [[ "$has_cost" == "false" ]]; then
        log "DEBUG" "All providers auth-connected, skipping cost estimate for $workflow_name"
        return 0
    fi

    echo -e "  ${BOLD}Estimated Costs:${NC}"
    echo -e "    ${RED}🔴${NC} Codex:  ${codex_label}"
    echo -e "    ${YELLOW}🟡${NC} Antigravity: ${agy_label}"
    echo -e "    ${BLUE}🔵${NC} Claude: ${claude_label}"

    if [[ "$USER_FAST_MODE" == "true" ]] && [[ "$SUPPORTS_FAST_OPUS" == "true" ]]; then
        echo -e "    ${YELLOW}⚡${NC} /fast mode active - Opus costs 6x higher for single-shot tasks"
    fi

    echo -e "    ${BOLD}Total estimated: ~\$${total_low}-${total_high}${NC}"
    echo ""
}

# Display cost estimate for a workflow and require user approval
display_workflow_cost_estimate() {
    local workflow_name="$1"
    local num_codex_calls="${2:-4}"
    local num_agy_calls="${3:-4}"
    local prompt_size="${4:-2000}"

    # Skip in non-interactive mode, if disabled, or if called from embrace workflow
    if [[ ! -t 0 ]] || [[ "${OCTOPUS_SKIP_COST_PROMPT:-false}" == "true" ]] || [[ "${OCTOPUS_SKIP_PHASE_COST_PROMPT:-false}" == "true" ]]; then
        log "DEBUG" "Cost estimate skipped (non-interactive, disabled, or already shown)"
        return 0
    fi

    # Check which providers are API-based (cost money)
    local codex_is_api=false
    local perplexity_is_api=false
    local has_costs=false

    is_api_based_provider "codex" && codex_is_api=true && has_costs=true
    is_api_based_provider "perplexity" && perplexity_is_api=true && has_costs=true

    # If no API-based providers, skip cost display
    if [[ "$has_costs" == "false" ]]; then
        log "INFO" "Using subscription/auth-based providers (no per-call costs)"
        return 0
    fi

    # Calculate costs
    local codex_cost="0.00"
    local perplexity_cost="0.00"
    local codex_status="Subscription (no per-call cost)"
    local agy_status="Antigravity access (no per-call cost)"
    local perplexity_status="Not configured"

    if [[ "$codex_is_api" == "true" ]]; then
        codex_cost=$(awk "BEGIN {printf \"%.2f\", $(calculate_agent_cost \"codex\" \"$prompt_size\") * $num_codex_calls}")
        codex_status="~\$$codex_cost (API key detected)"
    fi

    if [[ "$perplexity_is_api" == "true" ]]; then
        perplexity_cost=$(awk "BEGIN {printf \"%.2f\", $(calculate_agent_cost \"perplexity\" \"$prompt_size\") * 1}")
        perplexity_status="~\$$perplexity_cost (API key detected)"
    fi

    local total_cost=$(awk "BEGIN {printf \"%.2f\", $codex_cost + $perplexity_cost}")

    # Display cost estimate
    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  ${YELLOW}💰 MULTI-AI WORKFLOW COST ESTIMATE${MAGENTA}                    ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""
    echo -e "${BOLD}Workflow:${NC} $workflow_name"
    echo ""
    echo -e "${BOLD}Estimated Costs:${NC}"
    echo -e "  ${RED}🔴 Codex${NC}  (~${num_codex_calls} requests): ${codex_status}"
    echo -e "  ${YELLOW}🟡 Antigravity${NC} (~${num_agy_calls} requests): ${agy_status}"
    # Resolve the actual Claude model after pins, role/phase routing, capability
    # fallback, and Fable guards. Agent-type labels alone are insufficient:
    # claude-opus may resolve to a legacy Opus, while Fable is a distinct 2x tier.
    local claude_agent_type="claude"
    case "${WORKFLOW_AGENTS:-}" in
        *claude-opus-fast*) claude_agent_type="claude-opus-fast" ;;
        *claude-opus*)      claude_agent_type="claude-opus" ;;
        *claude-sdk*)       claude_agent_type="claude-sdk" ;;
    esac
    local claude_model=""
    if declare -f get_agent_model >/dev/null 2>&1; then
        claude_model="$(get_agent_model "$claude_agent_type" "$workflow_name" "" 2>/dev/null || true)"
    fi
    [[ -n "$claude_model" ]] || claude_model="${OCTOPUS_OPUS_MODEL:-${OCTOPUS_CLAUDE_MODEL:-claude-sonnet-5}}"
    local claude_model_label="$claude_model"
    case "${claude_agent_type}:${claude_model}" in
        claude-opus-fast:claude-opus-5)   claude_model_label="Opus 5 Fast" ;;
        claude-opus-fast:claude-opus-4.8) claude_model_label="Opus 4.8 Fast" ;;
        claude-opus-fast:claude-opus-4.7) claude_model_label="Opus 4.7 Fast" ;;
        claude-opus-fast:claude-opus-4.6) claude_model_label="Opus 4.6 Fast" ;;
        *:claude-fable-5-1) claude_model_label="Fable 5.1" ;;
        *:claude-fable-5) claude_model_label="Fable 5" ;;
        *:claude-opus-5-fast) claude_model_label="Opus 5 Fast" ;;
        *:claude-opus-5)      claude_model_label="Opus 5" ;;
        *:claude-opus-4.8)    claude_model_label="Opus 4.8" ;;
        *:claude-opus-4.7)    claude_model_label="Opus 4.7" ;;
        *:claude-opus-4.6)    claude_model_label="Opus 4.6" ;;
        *:claude-sonnet-5)    claude_model_label="Sonnet 5" ;;
        *:claude-sonnet-4.6)  claude_model_label="Sonnet 4.6" ;;
        *:claude-haiku-4.5)   claude_model_label="Haiku 4.5" ;;
    esac
    echo -e "  ${BLUE}🔵 Claude${NC} ($claude_model_label): ${DIM}Included in Claude Code subscription${NC}"
    if [[ "$perplexity_is_api" == "true" ]]; then
        echo -e "  ${MAGENTA}🟣 Perplexity${NC} (~1 request): ${perplexity_status}"
    fi
    echo ""

    if [[ $(awk "BEGIN {print ($total_cost > 0)}") -eq 1 ]]; then
        echo -e "${BOLD}Total API Costs: ~\$${total_cost}${NC}"
        echo ""
        echo -e "${DIM}Note: Costs shown only for providers using API keys (OPENAI_API_KEY/PERPLEXITY_API_KEY and other metered seats).${NC}"
        echo -e "${DIM}Actual costs may vary. Disable prompt with: OCTOPUS_SKIP_COST_PROMPT=true${NC}"
    else
        echo -e "${GREEN}✓ All providers using subscription/auth-based access (no per-call costs)${NC}"
        echo ""
        echo -e "${DIM}To skip this check: OCTOPUS_SKIP_COST_PROMPT=true${NC}"
    fi
    echo ""

    # Require approval
    local response
    read -p "$(echo -e "${BOLD}Proceed with multi-AI execution?${NC} [Y/n] ")" -r response
    echo ""

    case "$response" in
        [Nn]*)
            echo -e "${YELLOW}⚠ Workflow cancelled by user${NC}"
            return 1
            ;;
        *)
            echo -e "${GREEN}✓ User approved - proceeding with workflow${NC}"
            echo ""
            return 0
            ;;
    esac
}

# Record an agent call (append to usage tracking)
record_agent_call() {
    local agent_type="$1"
    local model="$2"
    local prompt="$3"
    local phase="${4:-unknown}"
    local role="${5:-none}"
    local duration_ms="${6:-0}"

    # Skip if dry run
    [[ "$DRY_RUN" == "true" ]] && return 0

    # Estimate tokens
    local input_tokens
    input_tokens=$(estimate_tokens "$prompt")
    local output_tokens=$((input_tokens * 2))  # Estimate output as 2x input
    local total_tokens=$((input_tokens + output_tokens))

    local cost
    cost=$(estimate_agent_call_cost "$agent_type" "$model" "$prompt")

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # v8.34.0: Capture account context in metrics (G10)
    if [[ "$SUPPORTS_ACCOUNT_ENV_VARS" == "true" ]]; then
        local account_uuid="${CLAUDE_CODE_ACCOUNT_UUID:-unknown}"
        local org_uuid="${CLAUDE_CODE_ORGANIZATION_UUID:-unknown}"
        log "DEBUG" "Account: $account_uuid | Org: $org_uuid"
    fi

    # v8.32.0: Account env vars for per-user traceability (Claude Code v2.1.51+)
    local account_uuid="${CLAUDE_ACCOUNT_UUID:-unknown}"
    local account_org="${CLAUDE_ORG_UUID:-unknown}"
    # Hash email for PII protection — log UUID freely
    local account_email_hash="unknown"
    if [[ -n "${CLAUDE_USER_EMAIL:-}" ]] && command -v sha256sum &>/dev/null; then
        account_email_hash=$(printf '%s' "$CLAUDE_USER_EMAIL" | sha256sum | cut -d' ' -f1)
    elif [[ -n "${CLAUDE_USER_EMAIL:-}" ]] && command -v shasum &>/dev/null; then
        account_email_hash=$(printf '%s' "$CLAUDE_USER_EMAIL" | shasum -a 256 | cut -d' ' -f1)
    fi

    # Append to calls array using a temp file approach (jq-free for portability)
    if [[ -f "$USAGE_FILE" ]]; then
        # Create call record
        local call_record
        call_record=$(cat << EOF
    {
      "timestamp": "$timestamp",
      "agent": "$agent_type",
      "model": "$model",
      "phase": "$phase",
      "role": "$role",
      "input_tokens": $input_tokens,
      "output_tokens": $output_tokens,
      "total_tokens": $total_tokens,
      "cost_usd": $cost,
      "duration_ms": $duration_ms,
      "account_uuid": "$account_uuid",
      "org_uuid": "$account_org",
      "email_hash": "$account_email_hash"
    }
EOF
)

        # Update totals in a simple tracking file
        echo "$timestamp|$agent_type|$model|$phase|$role|$input_tokens|$output_tokens|$total_tokens|$cost|$duration_ms|$account_uuid" >> "${USAGE_FILE}.log"

        log DEBUG "Recorded call: agent=$agent_type model=$model tokens=$total_tokens cost=\$$cost"
    fi
}

# Generate usage report (bash 3.x compatible using awk)
generate_usage_report() {
    local format="${1:-table}"  # table, json, csv

    if [[ ! -f "${USAGE_FILE}.log" ]]; then
        echo "No usage data recorded in this session."
        return 0
    fi

    case "$format" in
        json)
            generate_usage_json
            ;;
        csv)
            generate_usage_csv
            ;;
        *)
            generate_usage_table
            ;;
    esac
}

# Generate table format report using awk (bash 3.x compatible)
generate_usage_table() {
    local log_file="${USAGE_FILE}.log"

    # Calculate totals using awk
    local totals
    totals=$(awk -F'|' '
        { calls++; tokens+=$8; cost+=$9 }
        END { printf "%d|%d|%.6f", calls, tokens, cost }
    ' "$log_file")

    local total_calls total_tokens total_cost
    total_calls="${totals%%|*}"
    local _t_rest="${totals#*|}"; total_tokens="${_t_rest%%|*}"
    local _t_rest2="${totals#*|}"; total_cost="${_t_rest2#*|}"

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ${GREEN}USAGE REPORT${CYAN}                                                 ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    printf "${CYAN}║${NC}  Total Calls:    ${GREEN}%-6s${NC}                                       ${CYAN}║${NC}\n" "$total_calls"
    printf "${CYAN}║${NC}  Total Tokens:   ${GREEN}%-10s${NC}                                   ${CYAN}║${NC}\n" "$total_tokens"
    printf "${CYAN}║${NC}  Total Cost:     ${GREEN}\$%-10s${NC}                                  ${CYAN}║${NC}\n" "$total_cost"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}By Model${NC}                           Tokens      Cost    Calls ${CYAN}║${NC}"
    echo -e "${CYAN}╟${_DASH}───╢${NC}"

    # Aggregate by model using awk
    awk -F'|' '
        { model[$3] += $8; cost[$3] += $9; calls[$3]++ }
        END {
            for (m in model) {
                printf "  %-30s %8d  $%-7.4f  %3d\n", m, model[m], cost[m], calls[m]
            }
        }
    ' "$log_file" | while read -r line; do
        echo -e "${CYAN}║${NC}$line   ${CYAN}║${NC}"
    done

    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}By Agent${NC}                           Tokens      Cost    Calls ${CYAN}║${NC}"
    echo -e "${CYAN}╟${_DASH}───╢${NC}"

    # Aggregate by agent using awk
    awk -F'|' '
        { agent[$2] += $8; cost[$2] += $9; calls[$2]++ }
        END {
            for (a in agent) {
                printf "  %-30s %8d  $%-7.4f  %3d\n", a, agent[a], cost[a], calls[a]
            }
        }
    ' "$log_file" | while read -r line; do
        echo -e "${CYAN}║${NC}$line   ${CYAN}║${NC}"
    done

    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}By Phase${NC}                           Tokens      Cost    Calls ${CYAN}║${NC}"
    echo -e "${CYAN}╟${_DASH}───╢${NC}"

    # Aggregate by phase using awk
    awk -F'|' '
        { phase[$4] += $8; cost[$4] += $9; calls[$4]++ }
        END {
            for (p in phase) {
                printf "  %-30s %8d  $%-7.4f  %3d\n", p, phase[p], cost[p], calls[p]
            }
        }
    ' "$log_file" | while read -r line; do
        echo -e "${CYAN}║${NC}$line   ${CYAN}║${NC}"
    done

    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} Token counts are estimates (~4 chars/token). Actual costs may vary."
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# POST-RUN USAGE DISPLAY (v8.49.0)
# Functions called by embrace_full_workflow after all phases complete.
# Wires the existing generate_usage_table() into the embrace end-of-run output.
# ═══════════════════════════════════════════════════════════════════════════════

# v8.49.0: Display session-level metrics (totals + per-model + per-phase)
display_session_metrics() {
    if [[ ! -f "${USAGE_FILE}.log" ]]; then
        log DEBUG "No usage data for session metrics"
        return 0
    fi
    generate_usage_table
}

# v8.49.0: Display per-provider breakdown (codex/agy/claude)
display_provider_breakdown() {
    local log_file="${USAGE_FILE}.log"
    [[ -f "$log_file" ]] || return 0

    echo -e "${CYAN}Provider Breakdown:${NC}"
    awk -F'|' '
        {
            # Extract provider from agent type (e.g., codex-spark -> codex)
            provider = $2
            gsub(/-.*/, "", provider)
            tokens[provider] += $8
            cost[provider] += $9
            calls[provider]++
        }
        END {
            for (p in calls) {
                printf "  %-12s  %6d calls  %8d tokens  $%.4f est.\n", p, calls[p], tokens[p], cost[p]
            }
        }
    ' "$log_file"
    echo ""
}

# v8.49.0: Display per-phase cost table with model used
display_per_phase_cost_table() {
    local log_file="${USAGE_FILE}.log"
    [[ -f "$log_file" ]] || return 0

    echo -e "${CYAN}Per-Phase Cost Breakdown:${NC}"
    printf "  %-12s  %-25s  %8s  %s\n" "Phase" "Model" "Tokens" "Est. Cost"
    echo "  ${_DASH}─"
    awk -F'|' '
        {
            phase = $4
            model = $3
            key = phase "|" model
            tokens[key] += $8
            cost[key] += $9
            calls[key]++
            # Track which model was used per phase (last one wins for display)
            phase_model[phase] = model
            phase_tokens[phase] += $8
            phase_cost[phase] += $9
        }
        END {
            # Sort by phase name
            n = asorti(phase_tokens, sorted)
            for (i = 1; i <= n; i++) {
                p = sorted[i]
                printf "  %-12s  %-25s  %8d  $%.4f\n", p, phase_model[p], phase_tokens[p], phase_cost[p]
            }
        }
    ' "$log_file"
    echo ""
}

# v8.49.0: Record agent start (returns metrics ID for correlation)
record_agent_start() {
    local agent_type="$1"
    local model="$2"
    local prompt="$3"
    local phase="${4:-unknown}"
    local metrics_id="m-$(date +%s)-$$-${RANDOM}"
    echo "$metrics_id"
}

# v8.49.0: Record agent completion with actual parsed metrics
# Updates the usage log with actual token counts when available
record_agent_complete() {
    local metrics_id="$1"
    local agent_type="$2"
    local model="$3"
    local output="$4"
    local phase="${5:-unknown}"
    local actual_tokens="${6:-}"
    local tool_uses="${7:-}"
    local duration_ms="${8:-0}"

    [[ "$DRY_RUN" == "true" ]] && return 0

    # If we have actual token data from <usage> block, record a completion entry
    if [[ -n "$actual_tokens" && "$actual_tokens" =~ ^[0-9]+$ ]]; then
        local timestamp
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Calculate cost with actual tokens
        local pricing
        pricing=$(get_model_pricing "$model" "$agent_type")
        local input_price="${pricing%%:*}"
        local output_price="${pricing##*:}"
        # Assume 40% input, 60% output split for actual tokens
        local input_tokens=$(( actual_tokens * 40 / 100 ))
        local output_tokens=$(( actual_tokens * 60 / 100 ))
        pricing="$(octo_effective_model_pricing "$model" "$input_tokens" "$input_price" "$output_price")"
        input_price="${pricing%%:*}"
        output_price="${pricing##*:}"
        local cost
        cost=$(awk "BEGIN {printf \"%.6f\", ($input_tokens * $input_price + $output_tokens * $output_price) / 1000000}")

        # Append actual metrics (suffixed with :actual to distinguish from estimates)
        if [[ -f "${USAGE_FILE}.log" ]]; then
            echo "${timestamp}|${agent_type}|${model}|${phase}|actual|${input_tokens}|${output_tokens}|${actual_tokens}|${cost}|${duration_ms}|${metrics_id}" >> "${USAGE_FILE}.log"
            log DEBUG "Recorded actual metrics: agent=$agent_type tokens=$actual_tokens cost=\$$cost duration=${duration_ms}ms"
        fi
    fi
}

# [EXTRACTED to lib/error-tracking.sh]

# Generate CSV format report
generate_usage_csv() {
    echo "timestamp,agent,model,phase,role,input_tokens,output_tokens,total_tokens,cost_usd,duration_ms"
    cat "${USAGE_FILE}.log" | tr '|' ','
}

# Generate JSON format report (bash 3.x compatible)
generate_usage_json() {
    local log_file="${USAGE_FILE}.log"

    # Calculate totals using awk
    local totals
    totals=$(awk -F'|' '
        { calls++; tokens+=$8; cost+=$9 }
        END { printf "%d|%d|%.6f", calls, tokens, cost }
    ' "$log_file")

    local total_calls total_tokens total_cost
    total_calls="${totals%%|*}"
    local _t_rest="${totals#*|}"; total_tokens="${_t_rest%%|*}"
    local _t_rest2="${totals#*|}"; total_cost="${_t_rest2#*|}"

    local session_id
    session_id=$(grep -o '"session_id": "[^"]*"' "$USAGE_FILE" 2>/dev/null | cut -d'"' -f4)
    local started_at
    started_at=$(grep -o '"started_at": "[^"]*"' "$USAGE_FILE" 2>/dev/null | cut -d'"' -f4)

    cat << EOF
{
  "session_id": "$session_id",
  "started_at": "$started_at",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "totals": {
    "calls": $total_calls,
    "tokens": $total_tokens,
    "cost_usd": $total_cost
  },
  "calls": [
EOF

    local first=true
    while IFS='|' read -r timestamp agent model phase role input_tokens output_tokens tokens cost duration; do
        [[ "$first" == "true" ]] || echo ","
        first=false
        cat << EOF
    {
      "timestamp": "$timestamp",
      "agent": "$agent",
      "model": "$model",
      "phase": "$phase",
      "role": "$role",
      "input_tokens": $input_tokens,
      "output_tokens": $output_tokens,
      "total_tokens": $tokens,
      "cost_usd": $cost,
      "duration_ms": $duration
    }
EOF
    done < "$log_file"

    echo ""
    echo "  ]"
    echo "}"
}


# Clear current session usage
clear_usage_session() {
    rm -f "$USAGE_FILE" "${USAGE_FILE}.log"
    log INFO "Usage session cleared"
}

# ═══════════════════════════════════════════════════════════════════════════════
# AGENT USAGE ANALYTICS (v5.0)
# Tracks agent invocations for optimization insights
# Privacy-preserving: only logs metadata, not prompt content
# ═══════════════════════════════════════════════════════════════════════════════

log_agent_usage() {
    local agent="$1"
    local phase="$2"
    local prompt="$3"

    mkdir -p "$ANALYTICS_DIR"

    local timestamp=$(date +%s)
    local date_str=$(date +%Y-%m-%d)
    local prompt_hash=$(echo "$prompt" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "nohash")
    local prompt_len=${#prompt}

    echo "$timestamp,$date_str,$agent,$phase,$prompt_hash,$prompt_len" >> "$ANALYTICS_DIR/agent-usage.csv"
}

generate_analytics_report() {
    local period=${1:-30}
    local csv_file="$ANALYTICS_DIR/agent-usage.csv"

    if [[ ! -f "$csv_file" ]]; then
        echo "No analytics data yet. Usage tracking begins after first agent invocation."
        return
    fi

    local cutoff_date
    if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
        cutoff_date=$(date -v-${period}d +%s)
    else
        cutoff_date=$(date -d "$period days ago" +%s)
    fi

    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐙 Claude Octopus Agent Usage Report (Last $period Days)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Top 10 Most Used Agents:
EOF

    awk -F',' -v cutoff="$cutoff_date" '
        $1 >= cutoff { agents[$3]++ }
        END { for (agent in agents) print agents[agent], agent }
    ' "$csv_file" | sort -rn | head -10 | nl

    cat <<EOF

Least Used Agents:
EOF

    awk -F',' -v cutoff="$cutoff_date" '
        $1 >= cutoff { agents[$3]++ }
        END { for (agent in agents) print agents[agent], agent }
    ' "$csv_file" | sort -n | head -5 | nl

    cat <<EOF

Usage by Phase:
EOF

    awk -F',' -v cutoff="$cutoff_date" '
        $1 >= cutoff && $4 != "" { phases[$4]++ }
        END { for (phase in phases) print phases[phase], phase }
    ' "$csv_file" | sort -rn

    cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Map cost tier to numeric value for comparison
get_cost_tier_value() {
    local cost_tier="$1"
    case "$cost_tier" in
        free)       echo 0 ;;
        bundled)    echo 1 ;;
        low)        echo 2 ;;
        medium)     echo 3 ;;
        high)       echo 4 ;;
        pay-per-use) echo 5 ;;
        *)          echo 3 ;;
    esac
}

# Map subscription tier to cost tier
get_cost_tier_for_subscription() {
    local provider="$1"
    local sub_tier="$2"

    case "$provider" in
        codex)
            case "$sub_tier" in
                plus) echo "low" ;;
                api-only) echo "pay-per-use" ;;
                *) echo "pay-per-use" ;;
            esac
            ;;
        agy)
            echo "bundled"
            ;;
        claude)
            case "$sub_tier" in
                pro) echo "medium" ;;
                *) echo "medium" ;;
            esac
            ;;
        opencode)
            case "$sub_tier" in
                free) echo "free" ;;
                api-only) echo "pay-per-use" ;;
                *) echo "variable" ;;
            esac
            ;;
        *)
            echo "pay-per-use"
            ;;
    esac
}


# ── Extracted from orchestrate.sh (optimization sweep) ──

get_model_pricing() {
    local model="$1"
    local provider="${2:-}" kind="" id="" input_price="" output_price="" _notes=""
    local model_price="" provider_price="" provider_override="" default_price="1.00:5.00"

    case "$provider" in
        claude-sdk*) provider="claude-sdk" ;;
        claude*) provider="claude" ;;
        codex*) provider="codex" ;;
        agy*|antigravity|gemini*) provider="agy" ;;
        openrouter*) provider="openrouter" ;;
        openai-compatible*|openai-tools) provider="openai-compatible-agent" ;;
        atlascloud*) provider="atlascloud" ;;
        perplexity*) provider="perplexity" ;;
        cursor-agent*) provider="cursor-agent" ;;
        copilot*) provider="copilot" ;;
        ollama*) provider="ollama" ;;
        qwen*) provider="qwen" ;;
        grok*) provider="grok" ;;
        opencode*) provider="opencode" ;;
        vibe*) provider="vibe" ;;
        kimi*) provider="kimi" ;;
    esac

    if [[ ! -r "$OCTOPUS_MODEL_PRICING_FILE" ]]; then
        printf '%s\n' "$default_price"
        return 0
    fi

    while IFS=$'\t' read -r kind id input_price output_price _notes; do
        [[ -n "$kind" && "$kind" != \#* ]] || continue
        if [[ "$kind" == "model" && "$id" == "$model" ]]; then
            model_price="${input_price}:${output_price}"
        elif [[ "$kind" == "provider-override" && "$id" == "$provider" ]]; then
            provider_override="${input_price}:${output_price}"
        elif [[ "$kind" == "provider" && "$id" == "$provider" ]]; then
            provider_price="${input_price}:${output_price}"
        elif [[ "$kind" == "provider" && "$id" == "default" ]]; then
            default_price="${input_price}:${output_price}"
        fi
    done < "$OCTOPUS_MODEL_PRICING_FILE"

    printf '%s\n' "${provider_override:-${model_price:-${provider_price:-$default_price}}}"
}
