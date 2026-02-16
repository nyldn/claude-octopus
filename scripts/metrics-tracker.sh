#!/usr/bin/env bash
# Metrics Tracker for Claude Octopus v8.3.0
# Tracks resource usage (tokens, duration, costs) for multi-AI operations
# Supports native Task tool metrics from Claude Code v2.1.30+ (token_count, tool_uses, duration_ms)

# Get metrics base directory (evaluate dynamically to support testing)
get_metrics_base() {
    echo "${METRICS_BASE:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}}"
}

# Initialize metrics tracking for session
init_metrics_tracking() {
    local base
    base=$(get_metrics_base)
    local metrics_file="${base}/metrics-session.json"
    local metrics_dir="${base}/metrics-history"

    mkdir -p "$metrics_dir"

    cat > "$metrics_file" << 'EOF'
{
  "session_id": "",
  "started_at": "",
  "phases": [],
  "totals": {
    "duration_seconds": 0,
    "estimated_tokens": 0,
    "native_tokens": 0,
    "tool_uses": 0,
    "estimated_cost_usd": 0,
    "agent_calls": 0,
    "native_metrics_available": false
  }
}
EOF

    # Set session ID
    local session_id="${SESSION_ID:-$(date +%Y%m%d-%H%M%S)}"
    jq ".session_id = \"$session_id\" | .started_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
        "$metrics_file" > "${metrics_file}.tmp" && mv "${metrics_file}.tmp" "$metrics_file"
}

# Record agent call start
record_agent_start() {
    local agent_type="$1"
    local model="$2"
    local prompt="$3"
    local phase="${4:-unknown}"

    local agent_id="${agent_type}-$(date +%s)-$$"
    local start_time=$(date +%s)

    # Estimate input tokens (rough: 4 chars per token)
    local prompt_length=${#prompt}
    local estimated_input_tokens=$((prompt_length / 4))

    # Store start time for duration tracking
    local base
    base=$(get_metrics_base)
    echo "$start_time" > "${base}/.agent-start-${agent_id}"

    echo "$agent_id"
}

# Record agent call completion
# Args: agent_id agent_type model output [phase] [native_token_count] [native_tool_uses] [native_duration_ms]
record_agent_complete() {
    local agent_id="$1"
    local agent_type="$2"
    local model="$3"
    local output="$4"
    local phase="${5:-unknown}"
    local native_token_count="${6:-}"
    local native_tool_uses="${7:-}"
    local native_duration_ms="${8:-}"

    local base
    base=$(get_metrics_base)
    local metrics_file="${base}/metrics-session.json"
    local start_file="${base}/.agent-start-${agent_id}"

    if [[ ! -f "$start_file" ]]; then
        # log "WARN" "No start time found for agent $agent_id"
        return 1
    fi

    local start_time=$(cat "$start_file")
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Use native metrics from Task tool (v2.1.30+) when available, fall back to estimates
    local has_native=false
    local token_count=0
    local tool_use_count=0

    if [[ -n "$native_token_count" && "$native_token_count" =~ ^[0-9]+$ ]]; then
        has_native=true
        token_count=$native_token_count
        tool_use_count=${native_tool_uses:-0}
        # Prefer native duration if available (convert ms to seconds)
        if [[ -n "$native_duration_ms" && "$native_duration_ms" =~ ^[0-9]+$ ]]; then
            duration=$(( native_duration_ms / 1000 ))
        fi
    fi

    # Estimate tokens as fallback (rough: 4 chars per token)
    local output_length=${#output}
    local estimated_output_tokens=$((output_length / 4))
    local estimated_total_tokens=$((estimated_output_tokens + 100))  # +100 for input overhead

    # Use native token count for cost if available, otherwise use estimate
    local cost_basis_tokens=$estimated_total_tokens
    if [[ "$has_native" == "true" ]]; then
        cost_basis_tokens=$token_count
    fi

    # Get pricing for model
    local cost_per_1k
    cost_per_1k=$(get_model_cost "$model")
    local estimated_cost=$(awk "BEGIN {printf \"%.4f\", ($cost_basis_tokens / 1000.0) * $cost_per_1k}")

    # Record in metrics file
    if command -v jq &> /dev/null; then
        local native_fields=""
        if [[ "$has_native" == "true" ]]; then
            native_fields=", \"native_token_count\": $token_count, \"native_tool_uses\": $tool_use_count, \"metrics_source\": \"native\""
        else
            native_fields=", \"metrics_source\": \"estimated\""
        fi

        local phase_entry=$(cat <<EOF
{
  "agent": "$agent_type",
  "model": "$model",
  "phase": "$phase",
  "duration_seconds": $duration,
  "estimated_tokens": $estimated_total_tokens,
  "estimated_cost_usd": $estimated_cost,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  $native_fields
}
EOF
)

        local native_update=""
        if [[ "$has_native" == "true" ]]; then
            native_update="| .totals.native_tokens += $token_count | .totals.tool_uses += $tool_use_count | .totals.native_metrics_available = true"
        fi

        jq ".phases += [$phase_entry] |
            .totals.duration_seconds += $duration |
            .totals.estimated_tokens += $estimated_total_tokens |
            .totals.estimated_cost_usd += $estimated_cost |
            .totals.agent_calls += 1 $native_update" \
            "$metrics_file" > "${metrics_file}.tmp" && mv "${metrics_file}.tmp" "$metrics_file"
    fi

    # Cleanup start file
    rm -f "$start_file"
}

# Get model pricing (cost per 1K tokens, rough estimates)
get_model_cost() {
    local model="$1"

    case "$model" in
        # Claude models (input cost, simplified)
        claude-opus-4-6)        echo "5.00" ;;
        claude-opus-4-5)        echo "15.00" ;;    # legacy
        claude-sonnet-4-5)      echo "3.00" ;;
        claude-sonnet-4)        echo "3.00" ;;
        claude-haiku-*)         echo "0.25" ;;

        # OpenAI/Codex models (rough estimates)
        gpt-5.3-codex)          echo "4.00" ;;
        gpt-5*)                 echo "3.00" ;;
        gpt-4*)                 echo "3.00" ;;

        # Gemini models (rough estimates)
        gemini-2.0-pro*)        echo "2.50" ;;
        gemini-2.0-flash*)      echo "0.30" ;;
        gemini-3-pro*)          echo "3.00" ;;
        gemini-3-flash*)        echo "0.25" ;;

        # Default
        *)                      echo "1.00" ;;
    esac
}

# Display phase metrics
display_phase_metrics() {
    local phase="$1"
    local base
    base=$(get_metrics_base)
    local metrics_file="${base}/metrics-session.json"

    if [[ ! -f "$metrics_file" ]] || ! command -v jq &> /dev/null; then
        return 0
    fi

    # Get metrics for this phase
    local phase_data=$(jq ".phases[] | select(.phase == \"$phase\")" "$metrics_file")
    if [[ -z "$phase_data" ]]; then
        return 0
    fi

    local total_duration=$(echo "$phase_data" | jq -s 'map(.duration_seconds) | add')
    local total_tokens=$(echo "$phase_data" | jq -s 'map(.estimated_tokens) | add')
    local total_cost=$(echo "$phase_data" | jq -s 'map(.estimated_cost_usd) | add')
    local agent_count=$(echo "$phase_data" | jq -s 'length')
    local native_tokens=$(echo "$phase_data" | jq -s 'map(.native_token_count // 0) | add')
    local tool_uses=$(echo "$phase_data" | jq -s 'map(.native_tool_uses // 0) | add')
    local has_any_native=$(echo "$phase_data" | jq -s 'any(.metrics_source == "native")')

    echo ""
    echo "📊 Phase Metrics ($phase):"
    echo "  ⏱️  Duration: ${total_duration}s"
    if [[ "$has_any_native" == "true" ]]; then
        echo "  📝 Tokens: ${native_tokens} (native) / ${total_tokens} (est.)"
        echo "  🔧 Tool Uses: ${tool_uses}"
    else
        echo "  📝 Est. Tokens: ${total_tokens}"
    fi
    echo "  💰 Est. Cost: \$${total_cost}"
    echo "  🤖 Agents: ${agent_count}"
}

# Display session totals
display_session_metrics() {
    local base
    base=$(get_metrics_base)
    local metrics_file="${base}/metrics-session.json"
    local metrics_dir="${base}/metrics-history"

    if [[ ! -f "$metrics_file" ]] || ! command -v jq &> /dev/null; then
        return 0
    fi

    local totals=$(jq '.totals' "$metrics_file")
    local duration=$(echo "$totals" | jq -r '.duration_seconds')
    local tokens=$(echo "$totals" | jq -r '.estimated_tokens')
    local cost=$(echo "$totals" | jq -r '.estimated_cost_usd')
    local calls=$(echo "$totals" | jq -r '.agent_calls')

    local native_tokens=$(echo "$totals" | jq -r '.native_tokens // 0')
    local tool_uses=$(echo "$totals" | jq -r '.tool_uses // 0')
    local has_native=$(echo "$totals" | jq -r '.native_metrics_available // false')

    echo ""
    echo "═══════════════════════════════════════════"
    echo "📊 Session Totals"
    echo "═══════════════════════════════════════════"
    echo "  ⏱️  Total Duration: ${duration}s ($(awk "BEGIN {printf \"%.1f\", $duration/60}")m)"
    if [[ "$has_native" == "true" ]]; then
        echo "  📝 Tokens: ${native_tokens} (native) / ${tokens} (est.)"
        echo "  🔧 Tool Uses: ${tool_uses}"
    else
        echo "  📝 Est. Tokens: ${tokens}"
    fi
    echo "  💰 Est. Cost: \$${cost}"
    echo "  🤖 Agent Calls: ${calls}"
    echo "═══════════════════════════════════════════"

    # Save to history
    local history_file="${metrics_dir}/session-$(date +%Y%m%d-%H%M%S).json"
    cp "$metrics_file" "$history_file"
}

# Display provider breakdown
display_provider_breakdown() {
    local base
    base=$(get_metrics_base)
    local metrics_file="${base}/metrics-session.json"

    if [[ ! -f "$metrics_file" ]] || ! command -v jq &> /dev/null; then
        return 0
    fi

    echo ""
    echo "Provider Breakdown:"

    # Codex
    local codex_data=$(jq '.phases[] | select(.agent | startswith("codex"))' "$metrics_file")
    if [[ -n "$codex_data" ]]; then
        local codex_tokens=$(echo "$codex_data" | jq -s 'map(.estimated_tokens) | add // 0')
        local codex_cost=$(echo "$codex_data" | jq -s 'map(.estimated_cost_usd) | add // 0')
        echo "  🔴 Codex:  ${codex_tokens} tokens (\$${codex_cost})"
    fi

    # Gemini
    local gemini_data=$(jq '.phases[] | select(.agent | startswith("gemini"))' "$metrics_file")
    if [[ -n "$gemini_data" ]]; then
        local gemini_tokens=$(echo "$gemini_data" | jq -s 'map(.estimated_tokens) | add // 0')
        local gemini_cost=$(echo "$gemini_data" | jq -s 'map(.estimated_cost_usd) | add // 0')
        echo "  🟡 Gemini: ${gemini_tokens} tokens (\$${gemini_cost})"
    fi

    # Claude (if any)
    local claude_data=$(jq '.phases[] | select(.agent | startswith("claude"))' "$metrics_file")
    if [[ -n "$claude_data" ]]; then
        local claude_tokens=$(echo "$claude_data" | jq -s 'map(.estimated_tokens) | add // 0')
        local claude_cost=$(echo "$claude_data" | jq -s 'map(.estimated_cost_usd) | add // 0')
        echo "  🔵 Claude: ${claude_tokens} tokens (\$${claude_cost})"
    fi
}

# Record completion for agents by reading their result files
record_agents_batch_complete() {
    local phase="$1"
    local task_group="$2"

    local base
    base=$(get_metrics_base)

    # Read metrics mapping file
    local metrics_map="${base}/.metrics-map"
    if [[ ! -f "$metrics_map" ]]; then
        return 0
    fi

    # Process each result file
    for result in "$RESULTS_DIR"/${phase}-${task_group}-*.md; do
        [[ ! -f "$result" ]] && continue

        # Extract task ID from filename (e.g., probe-123-0.md -> 123-0)
        local filename=$(basename "$result" .md)
        local task_id="${filename#${phase}-${task_group}-}"

        # Look up metrics_id and agent info
        local metrics_line
        metrics_line=$(grep "^${task_group}-${task_id}:" "$metrics_map" 2>/dev/null || true)
        if [[ -z "$metrics_line" ]]; then
            continue
        fi

        # Parse: task_id:metrics_id:agent_type:model
        local metrics_id agent_type model
        IFS=':' read -r _ metrics_id agent_type model <<< "$metrics_line"

        # Read output
        local output
        output=$(cat "$result" 2>/dev/null || echo "")

        # v8.6.0: Extract native metrics from result file
        local native_tokens="" native_tools="" native_duration=""
        if declare -f parse_task_metrics &>/dev/null; then
            parse_task_metrics "$output"
            native_tokens="$_PARSED_TOKENS"
            native_tools="$_PARSED_TOOL_USES"
            native_duration="$_PARSED_DURATION_MS"
        fi

        # Record completion
        record_agent_complete "$metrics_id" "$agent_type" "$model" "$output" "$phase" \
            "$native_tokens" "$native_tools" "$native_duration"

        # Remove from map
        sed -i.bak "/^${task_group}-${task_id}:/d" "$metrics_map" 2>/dev/null || true
    done
}

# Display per-phase cost breakdown table (v8.6.0, enhanced v8.8.0 with speed column)
# Reads metrics-session.json and renders a table grouped by phase and provider
display_per_phase_cost_table() {
    local base
    base=$(get_metrics_base)
    local metrics_file="${base}/metrics-session.json"

    if [[ ! -f "$metrics_file" ]] || ! command -v jq &>/dev/null; then
        return 0
    fi

    # Check if there are any phase entries
    local phase_count
    phase_count=$(jq '.phases | length' "$metrics_file" 2>/dev/null || echo "0")
    if [[ "$phase_count" == "0" ]]; then
        return 0
    fi

    # v8.8: Check if any entries have speed data for column display
    local has_speed
    has_speed=$(jq '[.phases[] | select(.speed != null and .speed != "")] | length > 0' "$metrics_file" 2>/dev/null || echo "false")

    echo ""
    echo "Per-Phase Cost Breakdown:"
    if [[ "$has_speed" == "true" ]]; then
        echo "┌──────────┬──────────────┬────────────┬──────────┬──────────┬──────────┐"
        echo "│ Phase    │ Provider     │ Tokens     │ Cost     │ Duration │ Mode     │"
        echo "├──────────┼──────────────┼────────────┼──────────┼──────────┼──────────┤"
    else
        echo "┌──────────┬──────────────┬────────────┬──────────┬──────────┐"
        echo "│ Phase    │ Provider     │ Tokens     │ Cost     │ Duration │"
        echo "├──────────┼──────────────┼────────────┼──────────┼──────────┤"
    fi

    local has_native=false
    local has_fast=false

    # Iterate unique phases and providers
    jq -r '.phases[] | "\(.phase)\t\(.agent)\t\(.estimated_tokens // 0)\t\(.estimated_cost_usd // 0)\t\(.duration_seconds // 0)\t\(.has_native_metrics // false)\t\(.speed // "")"' \
        "$metrics_file" 2>/dev/null | while IFS=$'\t' read -r phase agent tokens cost duration native speed; do

        # Determine provider emoji
        local provider_label
        case "$agent" in
            codex*) provider_label="🔴 codex" ;;
            gemini*) provider_label="🟡 gemini" ;;
            claude*) provider_label="🔵 claude" ;;
            *) provider_label="   $agent" ;;
        esac

        # Format native indicator
        local token_display="$tokens"
        if [[ "$native" == "true" ]]; then
            token_display="${tokens}*"
            has_native=true
        fi

        # Format duration
        local dur_display="${duration}s"

        # Format cost
        local cost_display
        cost_display=$(printf '$%.3f' "$cost" 2>/dev/null || echo "\$$cost")

        # v8.8: Format speed mode indicator
        local speed_display=""
        if [[ "$speed" == "fast" ]]; then
            speed_display="⚡ fast"
            has_fast=true
        elif [[ "$speed" == "standard" ]]; then
            speed_display="  std"
        fi

        if [[ "$has_speed" == "true" ]]; then
            printf "│ %-8s │ %-12s │ %10s │ %8s │ %8s │ %-8s │\n" \
                "$phase" "$provider_label" "$token_display" "$cost_display" "$dur_display" "$speed_display"
        else
            printf "│ %-8s │ %-12s │ %10s │ %8s │ %8s │\n" \
                "$phase" "$provider_label" "$token_display" "$cost_display" "$dur_display"
        fi
    done

    if [[ "$has_speed" == "true" ]]; then
        echo "└──────────┴──────────────┴────────────┴──────────┴──────────┴──────────┘"
    else
        echo "└──────────┴──────────────┴────────────┴──────────┴──────────┘"
    fi

    local notes=()
    if [[ "$has_native" == "true" ]]; then
        notes+=("* = native metrics (from Task tool)")
    fi
    if [[ "$has_fast" == "true" ]]; then
        notes+=("⚡ = fast mode (6x cost vs standard)")
    fi
    for note in "${notes[@]}"; do
        echo "  $note"
    done
}

# Export functions
export -f get_metrics_base
export -f init_metrics_tracking
export -f record_agent_start
export -f record_agent_complete
export -f record_agents_batch_complete
export -f get_model_cost
export -f display_phase_metrics
export -f display_session_metrics
export -f display_provider_breakdown
export -f display_per_phase_cost_table
