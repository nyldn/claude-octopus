#!/usr/bin/env bash
# Agent Teams Bridge for Claude Octopus v8.7.0
# Unified task-ledger that bridges orchestrate.sh's bash-spawned agents
# with Claude Code's native Agent Teams task management
#
# Feature gate: SUPPORTS_AGENT_TEAMS_BRIDGE (Claude Code v2.1.38+)
# Config: OCTOPUS_AGENT_TEAMS_BRIDGE=auto|enabled|disabled (default: auto)

OCTOPUS_AGENT_TEAMS_BRIDGE="${OCTOPUS_AGENT_TEAMS_BRIDGE:-auto}"

# Bridge state directory
_BRIDGE_DIR="${HOME}/.claude-octopus/bridge"
_BRIDGE_LEDGER="${_BRIDGE_DIR}/task-ledger.json"
_BRIDGE_LOCKFILE="${_BRIDGE_DIR}/.ledger.lock"

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Feature gate check
# ═══════════════════════════════════════════════════════════════════════════════
bridge_is_enabled() {
    case "$OCTOPUS_AGENT_TEAMS_BRIDGE" in
        enabled) return 0 ;;
        disabled) return 1 ;;
        auto)
            [[ "${SUPPORTS_AGENT_TEAMS_BRIDGE:-false}" == "true" ]] || return 1
            # Log if CC native agent teams feature is not enabled
            if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]]; then
                log "DEBUG" "BRIDGE: CC native agent teams not enabled (set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json env)" 2>/dev/null || true
            fi
            return 0
            ;;
        *) return 1 ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Lockfile-based atomic ledger updates
# ═══════════════════════════════════════════════════════════════════════════════
bridge_atomic_ledger_update() {
    local jq_expression="$1"
    shift

    bridge_is_enabled || return 0
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    local lockfile="$_BRIDGE_LOCKFILE"
    local max_retries=5
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        # Attempt to acquire lock (create lockfile atomically)
        if (set -C; echo $$ > "$lockfile") 2>/dev/null; then
            # Lock acquired - perform update
            local tmp="${_BRIDGE_LEDGER}.tmp.$$"
            if jq "$jq_expression" "$@" "$_BRIDGE_LEDGER" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$_BRIDGE_LEDGER"
            else
                rm -f "$tmp"
            fi
            rm -f "$lockfile"
            return 0
        fi

        # Check for stale lock (older than 10 seconds)
        if [[ -f "$lockfile" ]]; then
            local lock_pid
            lock_pid=$(cat "$lockfile" 2>/dev/null || echo "0")
            if ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -f "$lockfile"
                continue
            fi
        fi

        retry=$((retry + 1))
        sleep 0.2
    done

    log "WARN" "BRIDGE: Failed to acquire ledger lock after $max_retries retries"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Ledger initialization
# ═══════════════════════════════════════════════════════════════════════════════
bridge_init_ledger() {
    local workflow_name="${1:-embrace}"
    local task_group="${2:-$(date +%s)}"

    bridge_is_enabled || return 0
    command -v jq &>/dev/null || return 1

    # Nested team guard: refuse to init if a running workflow already exists
    if [[ -f "$_BRIDGE_LEDGER" ]]; then
        local existing_status
        existing_status=$(jq -r '.status // "unknown"' "$_BRIDGE_LEDGER" 2>/dev/null)
        if [[ "$existing_status" == "running" ]]; then
            log "WARN" "BRIDGE: Cannot create nested team — active workflow already running (status=$existing_status)" 2>/dev/null || true
            return 1
        fi
    fi

    mkdir -p "$_BRIDGE_DIR"

    jq -n \
        --arg workflow "$workflow_name" \
        --arg group "$task_group" \
        --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            workflow: $workflow,
            task_group: $group,
            started_at: $started,
            status: "running",
            current_phase: null,
            phases: {},
            tasks: {},
            gate_results: {},
            cross_provider_queue: [],
            memory: {
                warm_start: {},
                phase_summaries: {}
            }
        }' > "$_BRIDGE_LEDGER"

    log "INFO" "BRIDGE: Initialized task ledger for workflow=$workflow_name group=$task_group"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Task registration and lifecycle
# ═══════════════════════════════════════════════════════════════════════════════
bridge_register_task() {
    local task_id="$1"
    local agent_type="$2"
    local phase="$3"
    local role="${4:-none}"
    local depends_on="${5:-}"  # comma-separated task IDs (empty = no dependencies)

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg id "$task_id" \
        --arg agent "$agent_type" \
        --arg phase "$phase" \
        --arg role "$role" \
        --arg deps "$depends_on" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.tasks[$id] = {
            agent_type: $agent,
            phase: $phase,
            role: $role,
            status: "running",
            depends_on: ($deps | split(",") | map(select(. != ""))),
            registered_at: $ts,
            completed_at: null
        } | .phases[$phase].total_tasks = ((.phases[$phase].total_tasks // 0) + 1)'
}

# Check if all dependencies for a task are completed
# Returns 0 if unblocked, 1 if blocked
bridge_is_task_unblocked() {
    local task_id="$1"

    bridge_is_enabled || return 0
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 0
    command -v jq &>/dev/null || return 0

    local blocked
    blocked=$(jq -r --arg id "$task_id" '
        (.tasks[$id].depends_on // []) as $deps |
        if ($deps | length) == 0 then "no"
        else
            [.tasks | to_entries[] | select(.key as $k | $deps | index($k)) | select(.value.status != "completed")] |
            if length > 0 then "yes" else "no" end
        end
    ' "$_BRIDGE_LEDGER" 2>/dev/null)

    [[ "$blocked" != "yes" ]]
}

bridge_mark_task_complete() {
    local task_id="$1"
    local status="${2:-completed}"

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg id "$task_id" \
        --arg status "$status" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.tasks[$id].status = $status |
         .tasks[$id].completed_at = $ts |
         .phases[.tasks[$id].phase].completed_tasks = ((.phases[.tasks[$id].phase].completed_tasks // 0) + 1)'
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Phase completion check
# ═══════════════════════════════════════════════════════════════════════════════
bridge_check_phase_complete() {
    local phase="$1"

    bridge_is_enabled || return 1
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    local total completed
    total=$(jq -r ".phases.\"$phase\".total_tasks // 0" "$_BRIDGE_LEDGER" 2>/dev/null)
    completed=$(jq -r ".phases.\"$phase\".completed_tasks // 0" "$_BRIDGE_LEDGER" 2>/dev/null)

    [[ "$total" -gt 0 && "$completed" -ge "$total" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Quality gate injection and evaluation
# ═══════════════════════════════════════════════════════════════════════════════
bridge_inject_gate_task() {
    local phase="$1"
    local gate_type="${2:-quality}"
    local threshold="${3:-0.75}"

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg phase "$phase" \
        --arg type "$gate_type" \
        --argjson threshold "$threshold" \
        '.phases[$phase].gate = {
            type: $type,
            threshold: $threshold,
            status: "pending",
            result: null
        }'
}

bridge_evaluate_gate() {
    local phase="$1"

    bridge_is_enabled || return 0
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    local gate_type threshold
    gate_type=$(jq -r ".phases.\"$phase\".gate.type // \"quality\"" "$_BRIDGE_LEDGER" 2>/dev/null)
    threshold=$(jq -r ".phases.\"$phase\".gate.threshold // 0.75" "$_BRIDGE_LEDGER" 2>/dev/null)

    # Count completed vs total tasks
    local total completed
    total=$(jq -r ".phases.\"$phase\".total_tasks // 0" "$_BRIDGE_LEDGER" 2>/dev/null)
    completed=$(jq -r ".phases.\"$phase\".completed_tasks // 0" "$_BRIDGE_LEDGER" 2>/dev/null)

    local completion_ratio="0"
    if [[ "$total" -gt 0 ]]; then
        completion_ratio=$(awk -v c="$completed" -v t="$total" 'BEGIN { printf "%.2f", c / t }')
    fi

    local passed="false"
    if awk -v r="$completion_ratio" -v t="$threshold" 'BEGIN { exit !(r >= t) }'; then
        passed="true"
    fi

    bridge_atomic_ledger_update \
        --arg phase "$phase" \
        --arg passed "$passed" \
        --arg ratio "$completion_ratio" \
        '.phases[$phase].gate.status = "evaluated" |
         .phases[$phase].gate.result = {passed: ($passed == "true"), completion_ratio: ($ratio | tonumber)}'

    [[ "$passed" == "true" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Cross-provider task dispatch
# ═══════════════════════════════════════════════════════════════════════════════
bridge_get_idle_dispatch_target() {
    local preferred_provider="${1:-claude}"

    bridge_is_enabled || return 1
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    # Find providers with no running tasks
    local idle_providers
    idle_providers=$(jq -r '
        [.tasks | to_entries[] | select(.value.status == "running") | .value.agent_type | split("-")[0]] |
        unique |
        . as $busy |
        ["codex", "gemini", "claude"] - $busy |
        .[]
    ' "$_BRIDGE_LEDGER" 2>/dev/null)

    # Prefer the requested provider
    if echo "$idle_providers" | grep -q "^${preferred_provider}$"; then
        echo "$preferred_provider"
        return 0
    fi

    # Return first idle provider
    echo "$idle_providers" | head -1
}

bridge_enqueue_cross_provider_task() {
    local task_description="$1"
    local source_provider="$2"
    local target_provider="${3:-}"

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg desc "$task_description" \
        --arg source "$source_provider" \
        --arg target "$target_provider" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.cross_provider_queue += [{
            description: $desc,
            source: $source,
            target: $target,
            queued_at: $ts,
            status: "pending"
        }]'
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Memory and warm start
# ═══════════════════════════════════════════════════════════════════════════════
bridge_route_memory() {
    local phase="$1"
    local key="$2"
    local value="$3"

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg phase "$phase" \
        --arg key "$key" \
        --arg value "$value" \
        '.memory.warm_start[$phase + "." + $key] = $value'
}

bridge_write_warm_start_memory() {
    local phase="$1"
    local content="$2"

    bridge_is_enabled || return 0

    local memory_file="${_BRIDGE_DIR}/warm-start-${phase}.md"
    echo "$content" > "$memory_file"

    bridge_atomic_ledger_update \
        --arg phase "$phase" \
        --arg file "$memory_file" \
        '.memory.warm_start[$phase] = $file'
}

bridge_generate_phase_summary() {
    local phase="$1"
    local synthesis_file="$2"

    bridge_is_enabled || return 0
    [[ ! -f "$synthesis_file" ]] && return 1

    # Extract first 2000 chars as summary
    local summary
    summary=$(head -c 2000 "$synthesis_file" 2>/dev/null || true)

    bridge_atomic_ledger_update \
        --arg phase "$phase" \
        --arg summary "$summary" \
        --arg file "$synthesis_file" \
        '.memory.phase_summaries[$phase] = {
            summary: $summary,
            synthesis_file: $file,
            generated_at: (now | todate)
        }'
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Ledger query utilities
# ═══════════════════════════════════════════════════════════════════════════════
bridge_get_phase_status() {
    local phase="$1"

    bridge_is_enabled || return 1
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    jq -r ".phases.\"$phase\" // empty" "$_BRIDGE_LEDGER" 2>/dev/null
}

bridge_get_workflow_status() {
    bridge_is_enabled || return 1
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    jq -r '{
        workflow: .workflow,
        status: .status,
        current_phase: .current_phase,
        total_tasks: (.tasks | length),
        completed_tasks: ([.tasks | to_entries[] | select(.value.status == "completed")] | length),
        pending_cross_provider: ([.cross_provider_queue[] | select(.status == "pending")] | length)
    }' "$_BRIDGE_LEDGER" 2>/dev/null
}

bridge_update_current_phase() {
    local phase="$1"

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg phase "$phase" \
        '.current_phase = $phase'
}

bridge_mark_workflow_complete() {
    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.status = "completed" | .completed_at = $ts'
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Agent ID storage for continuation/resume (v8.30)
# ═══════════════════════════════════════════════════════════════════════════════

# Store Claude Code's agentId for a given task_id in the ledger
# Called by the flow skill after Agent tool returns an agentId
bridge_store_agent_id() {
    local task_id="$1"
    local agent_id="$2"

    bridge_is_enabled || return 0
    [[ -z "$task_id" || -z "$agent_id" ]] && return 1

    bridge_atomic_ledger_update \
        --arg id "$task_id" \
        --arg agent_id "$agent_id" \
        '.tasks[$id].agent_id = $agent_id'

    log "DEBUG" "BRIDGE: Stored agent_id=$agent_id for task=$task_id"
}

# Retrieve stored agentId for a given task_id
# Returns the agent_id string or empty if not found
bridge_get_agent_id() {
    local task_id="$1"

    bridge_is_enabled || return 1
    [[ ! -f "$_BRIDGE_LEDGER" ]] && return 1
    command -v jq &>/dev/null || return 1

    local agent_id
    agent_id=$(jq -r ".tasks.\"$task_id\".agent_id // empty" "$_BRIDGE_LEDGER" 2>/dev/null)

    if [[ -n "$agent_id" ]]; then
        echo "$agent_id"
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Teammate shutdown protocol
# ═══════════════════════════════════════════════════════════════════════════════

# Mark a task as shutting down (state transition before actual CC shutdown)
# The actual shutdown is handled by CC's native SendMessage/Agent tooling
bridge_shutdown_teammate() {
    local task_id="$1"

    bridge_is_enabled || return 0

    bridge_atomic_ledger_update \
        --arg id "$task_id" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.tasks[$id].status = "shutting_down" | .tasks[$id].shutdown_requested_at = $ts'
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Native team discovery
# ═══════════════════════════════════════════════════════════════════════════════

# Read CC's official team config from ~/.claude/teams/ (CC v2.1.83+)
# Returns tab-separated: name\tagent_id\tagent_type per line
bridge_discover_native_team() {
    local teams_dir="$HOME/.claude/teams"
    [[ -d "$teams_dir" ]] || return 1
    command -v jq &>/dev/null || return 1

    # Find most recent team config
    local latest
    latest=$(ls -t "$teams_dir"/*/config.json 2>/dev/null | head -1)
    [[ -n "$latest" ]] || return 1

    jq -r '.members[]? | "\(.name)\t\(.agent_id)\t\(.agent_type)"' "$latest" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE: Cleanup
# ═══════════════════════════════════════════════════════════════════════════════
bridge_cleanup() {
    bridge_is_enabled || return 0

    # Warn about running tasks before cleanup
    if [[ -f "$_BRIDGE_LEDGER" ]] && command -v jq &>/dev/null; then
        local running
        running=$(jq '[.tasks | to_entries[] | select(.value.status == "running")] | length' "$_BRIDGE_LEDGER" 2>/dev/null || echo 0)
        if [[ "${running:-0}" -gt 0 ]]; then
            log "WARN" "BRIDGE: $running task(s) still running during cleanup" 2>/dev/null || true
        fi
    fi

    # Archive current ledger
    if [[ -f "$_BRIDGE_LEDGER" ]]; then
        local archive_dir="${_BRIDGE_DIR}/history"
        mkdir -p "$archive_dir"
        local ts
        ts=$(date +%Y%m%d-%H%M%S)
        cp "$_BRIDGE_LEDGER" "${archive_dir}/ledger-${ts}.json" 2>/dev/null || true
    fi

    rm -f "$_BRIDGE_LOCKFILE"
}
