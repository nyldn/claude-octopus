#!/usr/bin/env bash
# Provider Router for Claude Octopus v8.7.0
# Latency-based provider routing with round-robin, fastest, and cheapest strategies
# Config: OCTOPUS_ROUTING_MODE=round-robin|fastest|cheapest (default: round-robin)

# Routing mode configuration
OCTOPUS_ROUTING_MODE="${OCTOPUS_ROUTING_MODE:-round-robin}"

# Round-robin state (file-based for cross-process persistence)
_ROUTER_STATE_FILE="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.router-state"
_ROUTER_STATS_FILE="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.provider-stats.json"

# Build provider latency stats from metrics-session.json
build_provider_stats() {
    local metrics_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
    local metrics_file="${metrics_dir}/metrics-session.json"
    local stats_file="$_ROUTER_STATS_FILE"

    if [[ ! -f "$metrics_file" ]] || ! command -v jq &>/dev/null; then
        return 1
    fi

    mkdir -p "$metrics_dir"

    # Extract per-provider average latency from completed agent metrics
    jq '{
        providers: (
            [.phases[]?.agents[]? | select(.status == "completed")] |
            group_by(.agent_type | split("-")[0]) |
            map({
                key: .[0].agent_type | split("-")[0],
                value: {
                    avg_latency_ms: ([.[].duration_ms // 0] | add / length),
                    call_count: length,
                    avg_cost_usd: ([.[].estimated_cost_usd // 0] | add / length)
                }
            }) | from_entries
        ),
        updated_at: now | todate
    }' "$metrics_file" > "$stats_file" 2>/dev/null || return 1
}

# Select fastest provider from candidates
# Args: candidate1 candidate2 ...
select_fastest_provider() {
    local stats_file="$_ROUTER_STATS_FILE"
    local candidates=("$@")

    case "$OCTOPUS_ROUTING_MODE" in
        round-robin)
            # Simple round-robin: rotate through candidates
            local idx=0
            if [[ -f "$_ROUTER_STATE_FILE" ]]; then
                idx=$(cat "$_ROUTER_STATE_FILE" 2>/dev/null || echo "0")
            fi
            local selected="${candidates[$((idx % ${#candidates[@]}))]}"
            echo $(( (idx + 1) % ${#candidates[@]} )) > "$_ROUTER_STATE_FILE"
            echo "$selected"
            ;;
        fastest)
            if [[ ! -f "$stats_file" ]] || ! command -v jq &>/dev/null; then
                echo "${candidates[0]}"
                return
            fi
            local best=""
            local best_latency=999999
            for candidate in "${candidates[@]}"; do
                local base_provider="${candidate%%-*}"
                local latency
                latency=$(jq -r ".providers.\"$base_provider\".avg_latency_ms // 999999" "$stats_file" 2>/dev/null || echo "999999")
                if awk -v a="$latency" -v b="$best_latency" 'BEGIN { exit !(a < b) }'; then
                    best="$candidate"
                    best_latency="$latency"
                fi
            done
            echo "${best:-${candidates[0]}}"
            ;;
        cheapest)
            if [[ ! -f "$stats_file" ]] || ! command -v jq &>/dev/null; then
                echo "${candidates[0]}"
                return
            fi
            local best=""
            local best_cost=999999
            for candidate in "${candidates[@]}"; do
                local base_provider="${candidate%%-*}"
                local cost
                cost=$(jq -r ".providers.\"$base_provider\".avg_cost_usd // 999999" "$stats_file" 2>/dev/null || echo "999999")
                if awk -v a="$cost" -v b="$best_cost" 'BEGIN { exit !(a < b) }'; then
                    best="$candidate"
                    best_cost="$cost"
                fi
            done
            echo "${best:-${candidates[0]}}"
            ;;
        *)
            echo "${candidates[0]}"
            ;;
    esac
}

# Refresh provider stats after agent completion
refresh_provider_stats() {
    build_provider_stats 2>/dev/null || true
}
