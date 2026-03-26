#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# lib/resilience.sh — Provider error classification, circuit breaker, retry
# ═══════════════════════════════════════════════════════════════════════════════
# Functions:
#   classify_error, get_circuit_state, record_failure, record_success,
#   check_circuit_recovery, backoff_delay, is_provider_available
# ═══════════════════════════════════════════════════════════════════════════════

[[ -n "${_OCTOPUS_RESILIENCE_LOADED:-}" ]] && return 0
_OCTOPUS_RESILIENCE_LOADED=true

# Persist circuit breaker state across sessions (survives restarts)
RESILIENCE_STATE_DIR="${CLAUDE_PLUGIN_DATA:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}}/provider-state"

# ═══════════════════════════════════════════════════════════════════════════════
# ERROR CLASSIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

# Classify an HTTP status code or error message
# Returns: "transient", "permanent", or "unknown"
classify_error() {
    local code_or_msg="$1"
    # Lowercase for case-insensitive text matching (bash 3.2 compat)
    local lower
    lower=$(echo "$code_or_msg" | tr '[:upper:]' '[:lower:]')

    # Numeric HTTP status codes first
    case "$code_or_msg" in
        429|500|502|503|504) echo "transient"; return 0 ;;
        401|403)             echo "permanent"; return 0 ;;
        408)                 echo "transient"; return 0 ;;
        400|404|422)         echo "permanent"; return 0 ;;
    esac

    # Text pattern matching (already lowercased)
    case "$lower" in
        *rate*limit*|*too*many*request*) echo "transient"; return 0 ;;
        *timeout*|*timed*out*)           echo "transient"; return 0 ;;
        *connection*refused*)            echo "transient"; return 0 ;;
        *econnreset*|*econnrefused*)     echo "transient"; return 0 ;;
        *server*error*|*internal*error*) echo "transient"; return 0 ;;
        *service*unavailable*)           echo "transient"; return 0 ;;
        *unauthorized*|*forbidden*)      echo "permanent"; return 0 ;;
        *invalid*key*|*invalid*token*)   echo "permanent"; return 0 ;;
        *billing*|*quota*exceeded*)      echo "permanent"; return 0 ;;
        *bad*request*|*not*found*)       echo "permanent"; return 0 ;;
        *model*not*found*)               echo "permanent"; return 0 ;;
    esac

    echo "unknown"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CIRCUIT BREAKER
# States: closed (normal), open (failing — skip provider), half-open (testing)
# ═══════════════════════════════════════════════════════════════════════════════

# Get current circuit state for a provider
get_circuit_state() {
    local provider="$1"
    local state_file="$RESILIENCE_STATE_DIR/${provider}.state"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "closed"
    fi
}

# Record a provider failure — opens circuit after threshold
record_failure() {
    local provider="$1"
    local error_type="${2:-transient}"  # transient or permanent
    mkdir -p "$RESILIENCE_STATE_DIR"

    local count_file="$RESILIENCE_STATE_DIR/${provider}.failures"
    local count=0
    [[ -f "$count_file" ]] && count=$(<"$count_file")
    count=$((count + 1))
    echo "$count" > "$count_file"

    # Open circuit after 3 transient failures or 1 permanent
    local threshold=3
    [[ "$error_type" == "permanent" ]] && threshold=1

    if [[ $count -ge $threshold ]]; then
        echo "open" > "$RESILIENCE_STATE_DIR/${provider}.state"
        date +%s > "$RESILIENCE_STATE_DIR/${provider}.opened_at"
    fi
}

# Record a provider success — resets circuit to closed
record_success() {
    local provider="$1"
    mkdir -p "$RESILIENCE_STATE_DIR"
    echo "0" > "$RESILIENCE_STATE_DIR/${provider}.failures"
    echo "closed" > "$RESILIENCE_STATE_DIR/${provider}.state"
}

# Check if circuit should transition from open to half-open (cooldown expired)
# Returns the current/new state
check_circuit_recovery() {
    local provider="$1"
    local cooldown="${2:-30}"  # seconds
    local state
    state=$(get_circuit_state "$provider")

    if [[ "$state" == "open" ]]; then
        local opened_at_file="$RESILIENCE_STATE_DIR/${provider}.opened_at"
        if [[ -f "$opened_at_file" ]]; then
            local opened_at now
            opened_at=$(<"$opened_at_file")
            now=$(date +%s)
            if [[ $((now - opened_at)) -ge $cooldown ]]; then
                echo "half-open" > "$RESILIENCE_STATE_DIR/${provider}.state"
                echo "half-open"
                return 0
            fi
        fi
    fi
    echo "$state"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RETRY UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Calculate exponential backoff delay with jitter
# Usage: backoff_delay <attempt> [base_seconds] [max_seconds]
backoff_delay() {
    local attempt="$1"
    local base="${2:-1}"   # base delay in seconds
    local max="${3:-30}"   # maximum delay in seconds

    local delay=$((base * (2 ** (attempt - 1))))
    [[ $delay -gt $max ]] && delay=$max

    # Add jitter: 0–25% of delay
    local jitter_range=$((delay / 4 + 1))
    local jitter=$((RANDOM % jitter_range))
    echo $((delay + jitter))
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROVIDER AVAILABILITY
# ═══════════════════════════════════════════════════════════════════════════════

# Check if provider is available (circuit not open)
# Returns 0 (true) if available, 1 (false) if circuit is open
is_provider_available() {
    local provider="$1"
    local state
    state=$(check_circuit_recovery "$provider")
    [[ "$state" != "open" ]]
}

# Reset all circuit breaker state (e.g., at session start)
reset_all_circuits() {
    if [[ -d "$RESILIENCE_STATE_DIR" ]]; then
        rm -rf "$RESILIENCE_STATE_DIR"
    fi
}

# Get failure count for a provider
get_failure_count() {
    local provider="$1"
    local count_file="$RESILIENCE_STATE_DIR/${provider}.failures"
    if [[ -f "$count_file" ]]; then
        cat "$count_file"
    else
        echo "0"
    fi
}
