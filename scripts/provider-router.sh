#!/usr/bin/env bash
# Provider Router for Claude Octopus v9.8.0
# Provider routing with reliability layer: error classification, circuit breaker, backoff
# Config: OCTOPUS_ROUTING_MODE=round-robin|fastest|cheapest|scored (default: round-robin)

_provider_router_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${_provider_router_dir}/lib/provider-registry.sh" || { echo "provider-router: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }

# Routing mode configuration
OCTOPUS_ROUTING_MODE="${OCTOPUS_ROUTING_MODE:-round-robin}"

# Round-robin state (file-based for cross-process persistence)
_ROUTER_STATE_FILE="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.router-state"
_ROUTER_STATS_FILE="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.provider-stats.json"

# Opt-in lifecycle event stream (oco-aek) — no-op unless OCTO_EVENT_LOG is set.
# Sourced guarded; emits below are also declare-f guarded.
if ! declare -f _octo_event_lock >/dev/null 2>&1; then
    _octo_pr_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    # shellcheck source=/dev/null
    source "${_octo_pr_lib_dir}/lib/events.sh" 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Provider Reliability Layer (v9.8.0)
# Error classification, circuit breaker, graduated backoff
# ═══════════════════════════════════════════════════════════════════════════════

_PROVIDER_STATE_DIR="${HOME}/.claude-octopus/provider-state"

# Circuit breaker defaults (configurable via env)
OCTO_CB_FAILURE_THRESHOLD="${OCTO_CB_FAILURE_THRESHOLD:-3}"   # failures before opening
OCTO_CB_COOLDOWN_SECS="${OCTO_CB_COOLDOWN_SECS:-300}"        # 5 min cooldown
OCTO_CB_HALF_OPEN_PROBE="${OCTO_CB_HALF_OPEN_PROBE:-1}"      # allow 1 probe in half-open

# Classify an error as transient or permanent
# Args: exit_code error_text
# Returns: "transient" or "permanent" (stdout)
classify_provider_error() {
    local exit_code="${1:-1}"
    local error_text="${2:-}"

    # Timeout is always transient
    [[ "$exit_code" == "124" ]] && { echo "transient"; return 0; }

    # Check error text for HTTP status codes and known patterns
    local lower_error
    lower_error=$(printf '%s' "$error_text" | tr '[:upper:]' '[:lower:]')

    # Transient: rate limits, server errors, network issues
    if printf '%s' "$lower_error" | grep -qE '429|rate.limit|too many requests'; then
        echo "transient"; return 0
    fi
    if printf '%s' "$lower_error" | grep -qE '500|502|503|504|internal server|bad gateway|service unavailable|gateway timeout'; then
        echo "transient"; return 0
    fi
    if printf '%s' "$lower_error" | grep -qE 'timeout|timed out|connection refused|network|ECONNRESET|ECONNREFUSED|ETIMEDOUT'; then
        echo "transient"; return 0
    fi
    if printf '%s' "$lower_error" | grep -qE 'overloaded|capacity|temporarily'; then
        echo "transient"; return 0
    fi

    # Permanent: auth failures, billing, invalid requests
    if printf '%s' "$lower_error" | grep -qE '401|403|unauthorized|forbidden|invalid.api.key|authentication'; then
        echo "permanent"; return 0
    fi
    if printf '%s' "$lower_error" | grep -qE 'billing|payment|quota exceeded|insufficient'; then
        echo "permanent"; return 0
    fi
    if printf '%s' "$lower_error" | grep -qE '404|not found|invalid model|model.*not.*available'; then
        echo "permanent"; return 0
    fi
    if printf '%s' "$lower_error" | grep -qE '400|bad request|invalid.*parameter'; then
        echo "permanent"; return 0
    fi

    # Default: treat unknown errors as transient (safer — allows retry)
    echo "transient"
}

# Extract Retry-After value from error text (seconds)
# Returns: seconds to wait, or empty if not found
extract_retry_after() {
    local error_text="$1"
    local retry_after
    retry_after=$(printf '%s' "$error_text" | grep -oiE 'retry.after[: ]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    echo "${retry_after:-}"
}

# Record a provider failure for circuit breaker tracking
# Args: provider exit_code error_text
record_provider_failure() (
    local provider="$1"
    local exit_code="${2:-1}"
    local error_text="${3:-}"

    mkdir -p "$_PROVIDER_STATE_DIR" || return 1
    local error_class
    error_class=$(classify_provider_error "$exit_code" "$error_text")
    # All writers share one bounded, portable lock per provider. Atomic rename
    # alone cannot protect the preceding append/trim/count transaction.
    local state_key="${_PROVIDER_STATE_DIR}/${provider}.breaker"
    _octo_event_lock "$state_key" || return $?
    trap '_octo_event_unlock "$state_key"' EXIT

    local timestamp
    timestamp=$(date +%s)

    # Append failure to provider's failure log (keep last 20 entries)
    local failure_file="${_PROVIDER_STATE_DIR}/${provider}.failures"
    echo "${timestamp}:${error_class}:${exit_code}" >> "$failure_file" || return 1
    # Trim to last 20 entries
    if [[ -f "$failure_file" ]]; then
        local failure_tmp
        failure_tmp=$(mktemp "${failure_file}.XXXXXX") || return 1
        if ! tail -20 "$failure_file" > "$failure_tmp" || ! mv "$failure_tmp" "$failure_file"; then
            rm -f "$failure_tmp" || true
            return 1
        fi
    fi

    # Check if circuit should open (only on transient — permanent errors don't trigger breaker)
    if [[ "$error_class" == "transient" ]]; then
        local recent_failures
        recent_failures=$(grep -c ":transient:" "$failure_file" 2>/dev/null) || recent_failures=0
        if [[ $recent_failures -ge $OCTO_CB_FAILURE_THRESHOLD ]]; then
            # Open the circuit breaker
            local cooldown_file="${_PROVIDER_STATE_DIR}/${provider}.cooldown" cooldown_tmp
            cooldown_tmp=$(mktemp "${cooldown_file}.XXXXXX") || return 1
            if ! printf '%s\n' "$timestamp" > "$cooldown_tmp" || ! mv "$cooldown_tmp" "$cooldown_file"; then
                rm -f "$cooldown_tmp"
                return 1
            fi
            log "WARN" "Circuit breaker OPEN for $provider — $recent_failures consecutive failures, cooling down ${OCTO_CB_COOLDOWN_SECS}s" 2>/dev/null || true
            declare -f octo_event_emit >/dev/null 2>&1 && octo_event_emit "circuit-breaker.open" provider="$provider" failures="$recent_failures" cooldown="$OCTO_CB_COOLDOWN_SECS" || true
        fi
    fi

    echo "$error_class"
)

# Record a provider success (clears failure state)
# Args: provider
record_provider_success() (
    local provider="$1"
    # Nothing to clear: a failure recorded after this check is ordered after
    # this success, so parallel seats need not contend for the lock.
    [[ -e "${_PROVIDER_STATE_DIR}/${provider}.failures" ||
       -e "${_PROVIDER_STATE_DIR}/${provider}.cooldown" ]] || return 0
    mkdir -p "$_PROVIDER_STATE_DIR" || return 1
    local state_key="${_PROVIDER_STATE_DIR}/${provider}.breaker"
    _octo_event_lock "$state_key" || return $?
    trap '_octo_event_unlock "$state_key"' EXIT

    # Clear failure log and cooldown on success
    local _was_open=0
    [[ -f "${_PROVIDER_STATE_DIR}/${provider}.cooldown" ]] && _was_open=1
    rm -f "${_PROVIDER_STATE_DIR}/${provider}.failures" 2>/dev/null
    rm -f "${_PROVIDER_STATE_DIR}/${provider}.cooldown" 2>/dev/null
    if [[ "$_was_open" == "1" ]] && declare -f octo_event_emit >/dev/null 2>&1; then
        octo_event_emit "circuit-breaker.closed" provider="$provider" || true
    fi
)

# Print the seconds elapsed in a cooldown; fail when its timestamp is unusable.
_provider_cooldown_elapsed() {
    local cooldown_start now elapsed
    cooldown_start=$(cat "$1" 2>/dev/null) || return 1
    [[ "$cooldown_start" =~ ^[0-9]{1,18}$ ]] || return 1
    now=$(date +%s)
    elapsed=$((now - 10#$cooldown_start))
    # Clock rollback or corrupt future state must not extend the configured wait.
    [[ $elapsed -ge 0 ]] || elapsed=$OCTO_CB_COOLDOWN_SECS
    printf '%s\n' "$elapsed"
}

# Check if a provider is available (not in cooldown)
# Args: provider
# Returns: 0 if available, 1 if in cooldown
is_provider_available() (
    local provider="$1"
    local cooldown_file="${_PROVIDER_STATE_DIR}/${provider}.cooldown"

    [[ ! -f "$cooldown_file" ]] && return 0
    local elapsed state_locked=0
    elapsed=$(_provider_cooldown_elapsed "$cooldown_file") || return 0
    # Only expiry changes shared state, so an active cooldown needs no lock.
    if [[ $elapsed -ge $OCTO_CB_COOLDOWN_SECS ]]; then
        # Expiry must not remove a new cooldown published by a concurrent failure.
        local state_key="${_PROVIDER_STATE_DIR}/${provider}.breaker"
        if _octo_event_lock "$state_key"; then
            state_locked=1
            trap '_octo_event_unlock "$state_key"' EXIT
        else
            # Contention or an unwritable lock is not an open circuit. Inspect the
            # current deadline without deleting state owned by another writer.
            log "DEBUG" "Provider $provider breaker lock unavailable; checking cooldown read-only" 2>/dev/null || true
        fi
        elapsed=$(_provider_cooldown_elapsed "$cooldown_file") || return 0
    fi

    if [[ $elapsed -ge $OCTO_CB_COOLDOWN_SECS ]]; then
        # Cooldown expired → half-open state (allow probe)
        [[ "$state_locked" -eq 0 ]] || rm -f "$cooldown_file"
        log "INFO" "Circuit breaker HALF-OPEN for $provider — allowing probe after ${elapsed}s cooldown" 2>/dev/null || true
        declare -f octo_event_emit >/dev/null 2>&1 && octo_event_emit "circuit-breaker.half-open" provider="$provider" cooldown_elapsed="$elapsed" || true
        return 0
    fi

    local remaining=$((OCTO_CB_COOLDOWN_SECS - elapsed))
    log "DEBUG" "Provider $provider in cooldown (${remaining}s remaining)" 2>/dev/null || true
    return 1
)

# Filter candidate providers, removing those in cooldown
# Args: candidate1 candidate2 ...
# Returns: space-separated list of available candidates
filter_available_providers() {
    local available=""
    for candidate in "$@"; do
        local base_provider
        base_provider="$(octo_provider_canonical "$candidate" 2>/dev/null || printf '%s' "$candidate")"
        if is_provider_available "$base_provider"; then
            available+="$candidate "
        fi
    done
    # Trim trailing space
    echo "${available% }"
}

# Get circuit breaker status for all providers (for /octo:doctor)
# Returns: multi-line status report
get_circuit_breaker_status() {
    mkdir -p "$_PROVIDER_STATE_DIR"
    local status=""
    local now
    now=$(date +%s)

    for provider in $(octo_provider_ids dispatch); do
        local state="closed"
        local detail=""
        local cooldown_file="${_PROVIDER_STATE_DIR}/${provider}.cooldown"
        local failure_file="${_PROVIDER_STATE_DIR}/${provider}.failures"

        if [[ -f "$cooldown_file" ]]; then
            local cooldown_start
            cooldown_start=$(cat "$cooldown_file" 2>/dev/null) || continue
            [[ "$cooldown_start" =~ ^[0-9]{1,18}$ ]] || continue
            local elapsed=$((now - 10#$cooldown_start))
            [[ $elapsed -ge 0 ]] || elapsed=$OCTO_CB_COOLDOWN_SECS
            if [[ $elapsed -lt $OCTO_CB_COOLDOWN_SECS ]]; then
                state="OPEN"
                local remaining=$((OCTO_CB_COOLDOWN_SECS - elapsed))
                detail=" (${remaining}s remaining)"
            else
                state="half-open"
                detail=" (cooldown expired, probing)"
            fi
        elif [[ -f "$failure_file" ]]; then
            local count
            count=$(wc -l < "$failure_file" 2>/dev/null | tr -d ' ')
            if [[ $count -gt 0 ]]; then
                state="closed"
                detail=" ($count recent failures)"
            fi
        fi

        [[ "$state" != "closed" || -f "$failure_file" ]] && status+="  $provider: $state$detail\n"
    done

    if [[ -z "$status" ]]; then
        echo "  All providers: healthy (no recent failures)"
    else
        echo -e "$status"
    fi
}

# Calculate graduated backoff delay for retries
# Args: attempt_number [base_delay_secs]
# Returns: delay in seconds (with jitter)
calculate_backoff() {
    local attempt="${1:-1}"
    local base="${2:-2}"

    # Exponential backoff: base * 2^(attempt-1), capped at 60s
    local delay=$((base * (1 << (attempt - 1))))
    [[ $delay -gt 60 ]] && delay=60

    # Add jitter (0-25% of delay) using $RANDOM
    local jitter=$((RANDOM % (delay / 4 + 1)))
    delay=$((delay + jitter))

    echo "$delay"
}

# Build provider latency stats from metrics-session.json
build_provider_stats() {
    local metrics_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
    local metrics_file="${metrics_dir}/metrics-session.json"
    local stats_file="$_ROUTER_STATS_FILE"

    if [[ ! -f "$metrics_file" ]] || ! command -v jq &>/dev/null; then
        return 1
    fi

    mkdir -p "$metrics_dir" "$(dirname "$stats_file")"

    # Extract per-provider average latency from completed agent metrics
    local provider_contract_json
    provider_contract_json=$(octo_provider_jq_contract_json) || return 1
    jq --argjson provider_contract "$provider_contract_json" '
        def canonical_provider($agent_type):
            ($provider_contract.exact[$agent_type]
             // ([ $provider_contract.prefixes[]
                    | .prefix as $prefix
                    | select($agent_type | startswith($prefix))
                    | .id ][0])
             // $agent_type);
        {
          providers: (
            [.phases[]?.agents[]? | select(.status == "completed")
             | . + {canonical_provider: canonical_provider(.agent_type)}] |
            sort_by(.canonical_provider) |
            group_by(.canonical_provider) |
            map({
                key: .[0].canonical_provider,
                value: {
                    avg_latency_ms: ([.[].duration_ms // 0] | add / length),
                    call_count: length,
                    avg_cost_usd: ([.[].estimated_cost_usd // 0] | add / length)
                }
            }) | from_entries
          ),
          updated_at: now | todate
        }
    ' "$metrics_file" > "$stats_file" 2>/dev/null || return 1
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
                local base_provider
                base_provider="$(octo_provider_canonical "$candidate" 2>/dev/null || printf '%s' "$candidate")"
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
                local base_provider
                base_provider="$(octo_provider_canonical "$candidate" 2>/dev/null || printf '%s' "$candidate")"
                local cost
                cost=$(jq -r ".providers.\"$base_provider\".avg_cost_usd // 999999" "$stats_file" 2>/dev/null || echo "999999")
                if awk -v a="$cost" -v b="$best_cost" 'BEGIN { exit !(a < b) }'; then
                    best="$candidate"
                    best_cost="$cost"
                fi
            done
            echo "${best:-${candidates[0]}}"
            ;;
        scored)
            # Use intelligence scoring (get_provider_score from lib/intelligence.sh)
            # Filter out providers in cooldown first
            local available_candidates
            available_candidates=$(filter_available_providers "${candidates[@]}")
            [[ -z "$available_candidates" ]] && { echo "${candidates[0]}"; return; }

            local best="" best_score="0.00"
            for candidate in $available_candidates; do
                local base_provider
                base_provider="$(octo_provider_canonical "$candidate" 2>/dev/null || printf '%s' "$candidate")"
                local score
                if type get_provider_score &>/dev/null; then
                    score=$(get_provider_score "$base_provider" 2>/dev/null || echo "0.70")
                else
                    score="0.70"
                fi
                if awk -v a="$score" -v b="$best_score" 'BEGIN { exit !(a > b) }'; then
                    best="$candidate"
                    best_score="$score"
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
