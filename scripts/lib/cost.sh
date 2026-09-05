#!/usr/bin/env bash
# Claude Octopus — Cost Tracking & Usage Reporting
# Extracted from orchestrate.sh
# Source-safe: no main execution block.

_octopus_cost_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTOPUS_MODEL_PRICING_FILE="${OCTOPUS_MODEL_PRICING_FILE:-${_octopus_cost_lib_dir}/../../config/model-pricing.tsv}"
OCTOPUS_USAGE_LEDGER_HELPER="${OCTOPUS_USAGE_LEDGER_HELPER:-${_octopus_cost_lib_dir}/../helpers/usage-ledger.py}"

# Session usage tracking file
USAGE_FILE="${WORKSPACE_DIR}/usage-session.json"
USAGE_HISTORY_DIR="${WORKSPACE_DIR}/usage-history"

_octo_usage_tariff_version() {
    local digest=""
    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$OCTOPUS_MODEL_PRICING_FILE" 2>/dev/null | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        digest=$(shasum -a 256 "$OCTOPUS_MODEL_PRICING_FILE" 2>/dev/null | awk '{print $1}')
    fi
    [[ -n "$digest" ]] && printf 'sha256:%s\n' "$digest" || printf 'unknown\n'
}

_octo_usage_billing_mode() {
    if declare -f is_api_based_provider >/dev/null 2>&1 && is_api_based_provider "$1"; then
        printf 'api\n'
    else
        printf 'included\n'
    fi
}

_octo_usage_append() {
    if ! command -v python3 >/dev/null 2>&1 || [[ ! -r "$OCTOPUS_USAGE_LEDGER_HELPER" ]]; then
        declare -f log >/dev/null 2>&1 && log WARN "Usage ledger unavailable; usage event was not recorded"
        return 0
    fi
    if ! python3 "$OCTOPUS_USAGE_LEDGER_HELPER" append --file "${USAGE_FILE}.log" "$@"; then
        declare -f log >/dev/null 2>&1 && log WARN "Usage ledger rejected an event"
    fi
    return 0
}

_octo_usage_report() {
    local format="$1"
    if ! command -v python3 >/dev/null 2>&1 || [[ ! -r "$OCTOPUS_USAGE_LEDGER_HELPER" ]]; then
        printf '%s\n' "Usage reporting requires Python 3 and usage-ledger.py" >&2
        return 69
    fi
    python3 "$OCTOPUS_USAGE_LEDGER_HELPER" report \
        --file "${USAGE_FILE}.log" --session-file "$USAGE_FILE" --format "$format"
}

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
    if declare -f octo_model_canonical_id >/dev/null 2>&1; then
        model="$(octo_model_canonical_id "$model")" || return 1
    fi
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
# Sets globals: _PARSED_TOKENS, _PARSED_INPUT_TOKENS,
# _PARSED_CACHED_INPUT_TOKENS, _PARSED_CACHE_WRITE_TOKENS,
# _PARSED_OUTPUT_TOKENS, _PARSED_REASONING_TOKENS, _PARSED_TOOL_USES,
# _PARSED_DURATION_MS, _PARSED_SPEED
# Guards on SUPPORTS_NATIVE_TASK_METRICS. Falls back gracefully on parse failure.
parse_task_metrics() {
    local output="$1"
    _PARSED_TOKENS="" ; _PARSED_INPUT_TOKENS="" ; _PARSED_OUTPUT_TOKENS=""
    _PARSED_CACHED_INPUT_TOKENS="" ; _PARSED_CACHE_WRITE_TOKENS=""
    _PARSED_REASONING_TOKENS=""
    _PARSED_TOOL_USES="" ; _PARSED_DURATION_MS="" ; _PARSED_SPEED=""
    [[ "$SUPPORTS_NATIVE_TASK_METRICS" != "true" ]] && return 0

    local usage_block
    usage_block=$(echo "$output" | sed -n '/<usage>/,/<\/usage>/p' 2>/dev/null || true)
    if [[ -n "$usage_block" ]]; then
        # v9.5: bash regex extraction (zero subshells, was 4 echo|grep|grep chains)
        [[ "$usage_block" =~ total_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_TOKENS="${BASH_REMATCH[1]}" || _PARSED_TOKENS=""
        [[ "$usage_block" =~ (^|[[:space:]])input_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_INPUT_TOKENS="${BASH_REMATCH[2]}" || _PARSED_INPUT_TOKENS=""
        [[ "$usage_block" =~ cached_input_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_CACHED_INPUT_TOKENS="${BASH_REMATCH[1]}" || _PARSED_CACHED_INPUT_TOKENS=""
        [[ "$usage_block" =~ cache_(write|creation)_input_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_CACHE_WRITE_TOKENS="${BASH_REMATCH[2]}" || _PARSED_CACHE_WRITE_TOKENS=""
        [[ "$usage_block" =~ output_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_OUTPUT_TOKENS="${BASH_REMATCH[1]}" || _PARSED_OUTPUT_TOKENS=""
        [[ "$usage_block" =~ reasoning_tokens:[[:space:]]*([0-9]+) ]] && _PARSED_REASONING_TOKENS="${BASH_REMATCH[1]}" || _PARSED_REASONING_TOKENS=""
        [[ "$usage_block" =~ tool_uses:[[:space:]]*([0-9]+) ]] && _PARSED_TOOL_USES="${BASH_REMATCH[1]}" || _PARSED_TOOL_USES=""
        [[ "$usage_block" =~ duration_ms:[[:space:]]*([0-9]+) ]] && _PARSED_DURATION_MS="${BASH_REMATCH[1]}" || _PARSED_DURATION_MS=""
        # v8.8: Parse OTel speed attribute (fast|standard) when available
        if [[ "$SUPPORTS_OTEL_SPEED" == "true" ]]; then
            [[ "$usage_block" =~ speed:[[:space:]]*(fast|standard) ]] && _PARSED_SPEED="${BASH_REMATCH[1]}" || _PARSED_SPEED=""
        fi
    fi
    [[ "$_PARSED_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_TOKENS=""
    [[ "$_PARSED_INPUT_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_INPUT_TOKENS=""
    [[ "$_PARSED_CACHED_INPUT_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_CACHED_INPUT_TOKENS=""
    [[ "$_PARSED_CACHE_WRITE_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_CACHE_WRITE_TOKENS=""
    [[ "$_PARSED_OUTPUT_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_OUTPUT_TOKENS=""
    [[ "$_PARSED_REASONING_TOKENS" =~ ^[0-9]+$ ]] || _PARSED_REASONING_TOKENS=""
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
    local call_id="${7:-call-$(date +%s)-$$-${RANDOM}}"

    # Skip if dry run
    [[ "$DRY_RUN" == "true" ]] && return 0

    # Estimate tokens
    local input_tokens
    input_tokens=$(estimate_tokens "$prompt")
    local output_tokens=$((input_tokens * 2))  # Estimate output as 2x input
    local total_tokens=$((input_tokens + output_tokens))

    local cost
    cost=$(estimate_agent_call_cost "$agent_type" "$model" "$prompt")

    if [[ -f "$USAGE_FILE" ]]; then
        _octo_usage_append --state reserved --call-id "$call_id" \
            --agent "$agent_type" --model "$model" --phase "$phase" --role "$role" \
            --input-tokens "$input_tokens" --output-tokens "$output_tokens" \
            --total-tokens "$total_tokens" --usage-source estimated --cost "$cost" \
            --cost-status estimated --duration-ms "$duration_ms" \
            --billing-mode "$(_octo_usage_billing_mode "$agent_type")" \
            --tariff-version "$(_octo_usage_tariff_version)"
        log DEBUG "Reserved call: id=$call_id agent=$agent_type model=$model tokens=$total_tokens cost=\$$cost"
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

# Generate reports through the reconciled JSONL reader.
generate_usage_table() {
    _octo_usage_report table
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
    _octo_usage_report providers
}

# v8.49.0: Display per-phase cost table with model used
display_per_phase_cost_table() {
    _octo_usage_report phases
}

# v8.49.0: Record agent start (returns metrics ID for correlation)
record_agent_start() {
    local agent_type="$1"
    local model="$2"
    local prompt="$3"
    local phase="${4:-unknown}"
    local metrics_id="m-$(date +%s)-$$-${RANDOM}"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "$metrics_id"
        return 0
    fi
    local metrics_base="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
    local input_tokens
    input_tokens="$(estimate_tokens "$prompt")"
    if declare -f get_metrics_base >/dev/null 2>&1; then
        metrics_base="$(get_metrics_base)"
    fi
    if [[ -n "$metrics_base" ]] && mkdir -p "$metrics_base" 2>/dev/null; then
        (umask 077; printf '%s|%s\n' "$(date +%s)" "$input_tokens" > "${metrics_base}/.agent-start-${metrics_id}") 2>/dev/null || true
    fi
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
    local native_input_tokens="${9:-}"
    local native_output_tokens="${10:-}"
    local cached_input_tokens="${11:-0}"
    local cache_write_tokens="${12:-0}"
    local reasoning_tokens="${13:-0}"
    local metrics_base="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
    if declare -f get_metrics_base >/dev/null 2>&1; then
        metrics_base="$(get_metrics_base)"
    fi
    local start_file="${metrics_base}/.agent-start-${metrics_id}"

    [[ "$DRY_RUN" == "true" ]] && return 0

    local usage_source="actual"
    if [[ ! "$actual_tokens" =~ ^[0-9]+$ ]]; then
        local start_record measured_input_tokens
        start_record="$(cat "$start_file" 2>/dev/null || true)"
        measured_input_tokens="${start_record#*|}"
        if [[ "$start_record" == *"|"* && "$measured_input_tokens" =~ ^[0-9]+$ ]]; then
            native_input_tokens="$measured_input_tokens"
            native_output_tokens="$(estimate_tokens "$output")"
            actual_tokens=$((native_input_tokens + native_output_tokens))
            usage_source="estimated-output"
        fi
    fi

    # If we have actual token data from <usage> block, record a completion entry
    if [[ -n "$actual_tokens" && "$actual_tokens" =~ ^[0-9]+$ ]]; then
        local timestamp
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Use native component counts when available. If the provider reports
        # only a total, combine it with the prompt measurement captured at
        # dispatch start instead of inventing a percentage split.
        local input_tokens="" output_tokens=""
        local reported_component_total=0
        [[ "$cached_input_tokens" =~ ^[0-9]+$ ]] || cached_input_tokens=0
        [[ "$cache_write_tokens" =~ ^[0-9]+$ ]] || cache_write_tokens=0
        [[ "$reasoning_tokens" =~ ^[0-9]+$ ]] || reasoning_tokens=0
        if [[ "$native_input_tokens" =~ ^[0-9]+$ && "$native_output_tokens" =~ ^[0-9]+$ ]]; then
            reported_component_total=$((native_input_tokens + native_output_tokens + cached_input_tokens + cache_write_tokens + reasoning_tokens))
        fi
        if [[ "$native_input_tokens" =~ ^[0-9]+$ && "$native_output_tokens" =~ ^[0-9]+$ ]] &&
           (( native_input_tokens + native_output_tokens == actual_tokens || reported_component_total == actual_tokens )); then
            input_tokens="$native_input_tokens"
            output_tokens="$native_output_tokens"
        elif [[ "$native_input_tokens" =~ ^[0-9]+$ ]] && (( native_input_tokens <= actual_tokens )); then
            input_tokens="$native_input_tokens"
            output_tokens=$((actual_tokens - native_input_tokens))
        elif [[ "$native_output_tokens" =~ ^[0-9]+$ ]] && (( native_output_tokens <= actual_tokens )); then
            output_tokens="$native_output_tokens"
            input_tokens=$((actual_tokens - native_output_tokens))
        elif [[ -f "$start_file" ]]; then
            local start_record measured_input_tokens
            start_record="$(cat "$start_file" 2>/dev/null || true)"
            measured_input_tokens="${start_record#*|}"
            if [[ "$start_record" == *"|"* && "$measured_input_tokens" =~ ^[0-9]+$ ]]; then
                input_tokens="$measured_input_tokens"
                (( input_tokens > actual_tokens )) && input_tokens="$actual_tokens"
                output_tokens=$((actual_tokens - input_tokens))
            fi
        fi

        if [[ -z "$input_tokens" || -z "$output_tokens" ]]; then
            log WARN "Skipping actual-cost entry without native token components or a measured prompt"
            rm -f "$start_file" 2>/dev/null || true
            return 0
        fi

        # Calculate cost with the measured token components.
        local pricing
        pricing=$(get_model_pricing "$model" "$agent_type")
        local input_price="${pricing%%:*}"
        local output_price="${pricing##*:}"
        pricing="$(octo_effective_model_pricing "$model" "$input_tokens" "$input_price" "$output_price")"
        input_price="${pricing%%:*}"
        output_price="${pricing##*:}"
        local cost="" cost_status="$usage_source"
        if [[ "$cached_input_tokens" =~ ^[0-9]+$ && "$cache_write_tokens" =~ ^[0-9]+$ &&
              "$reasoning_tokens" =~ ^[0-9]+$ ]] &&
           (( cached_input_tokens > 0 || cache_write_tokens > 0 || reasoning_tokens > 0 )); then
            # The canonical table currently has uncached input/output tariffs
            # only. Preserve richer native components but do not silently price
            # cached or reasoning usage as ordinary input/output.
            cost_status="unknown-cache-tariff"
        else
            cached_input_tokens=0
            cache_write_tokens=0
            reasoning_tokens=0
            cost=$(awk "BEGIN {printf \"%.6f\", ($input_tokens * $input_price + $output_tokens * $output_price) / 1000000}")
        fi

        # Append one terminal event using the reservation's call ID.
        if [[ -f "${USAGE_FILE}.log" ]]; then
            _octo_usage_append --state completed --call-id "$metrics_id" \
                --timestamp "$timestamp" --agent "$agent_type" --model "$model" \
                --phase "$phase" --role actual --input-tokens "$input_tokens" \
                --cached-input-tokens "$cached_input_tokens" \
                --cache-write-tokens "$cache_write_tokens" \
                --output-tokens "$output_tokens" --reasoning-tokens "$reasoning_tokens" \
                --total-tokens "$actual_tokens" --usage-source "$usage_source" --cost "$cost" \
                --cost-status "$cost_status" --duration-ms "$duration_ms" \
                --tool-uses "$tool_uses" --billing-mode "$(_octo_usage_billing_mode "$agent_type")" \
                --tariff-version "$(_octo_usage_tariff_version)"
            log DEBUG "Completed call: id=$metrics_id agent=$agent_type tokens=$actual_tokens cost=${cost:-unknown} duration=${duration_ms}ms"
        fi
    fi
    rm -f "$start_file" 2>/dev/null || true
}

record_agent_failure() {
    local call_id="$1"
    local duration_ms="${2:-0}"
    local reason="${3:-Provider call failed}"
    local state="${4:-failed}"
    case "$state" in failed|cancelled|timeout) ;; *) state=failed ;; esac
    [[ "${DRY_RUN:-false}" == "true" || -z "$call_id" ]] && return 0
    _octo_usage_append --state "$state" --call-id "$call_id" \
        --duration-ms "$duration_ms" --failure-reason "$reason" \
        --usage-source estimated --cost-status estimated
    local metrics_base="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
    if declare -f get_metrics_base >/dev/null 2>&1; then
        metrics_base="$(get_metrics_base)"
    fi
    rm -f "${metrics_base}/.agent-start-${call_id}" 2>/dev/null || true
}

# [EXTRACTED to lib/error-tracking.sh]

# Generate CSV format report
generate_usage_csv() {
    _octo_usage_report csv
}

generate_usage_json() {
    _octo_usage_report json
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

    if declare -f octo_model_canonical_id >/dev/null 2>&1; then
        model="$(octo_model_canonical_id "$model")" || return 1
    fi

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
