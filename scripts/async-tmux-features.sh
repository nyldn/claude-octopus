# ═══════════════════════════════════════════════════════════════════════════════
# ASYNC TASK MANAGEMENT & TMUX VISUALIZATION
# Inspired by oh-my-opencode-slim's background task management and tmux integration
# ═══════════════════════════════════════════════════════════════════════════════

# Global variables for async/tmux modes
ASYNC_MODE="${ASYNC_MODE:-false}"
TMUX_MODE="${TMUX_MODE:-false}"
TMUX_SESSION="claude-octopus-$$"
TMUX_PANE_MAP=()  # Maps agent PIDs to tmux pane IDs

# ═══════════════════════════════════════════════════════════════════════════════
# TMUX VISUALIZATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Check if tmux is available and session is possible
tmux_check() {
    if [[ "$TMUX_MODE" != "true" ]]; then
        return 1
    fi

    if ! command -v tmux &> /dev/null; then
        log WARN "tmux not found - disabling tmux visualization"
        TMUX_MODE="false"
        return 1
    fi

    return 0
}

# Initialize tmux session for workflow visualization
tmux_init() {
    if ! tmux_check; then
        return 0
    fi

    log INFO "Initializing tmux session: $TMUX_SESSION"

    # Create new detached session if not already in tmux
    if [[ -z "$TMUX" ]]; then
        tmux new-session -d -s "$TMUX_SESSION" 2>/dev/null || {
            log WARN "Failed to create tmux session - running without tmux"
            TMUX_MODE="false"
            return 1
        }
        TMUX_CREATED="true"
    else
        # We're already in tmux, create a new window
        tmux new-window -t "$TMUX" -n "octopus" 2>/dev/null || {
            log WARN "Failed to create tmux window - running without tmux"
            TMUX_MODE="false"
            return 1
        }
        TMUX_SESSION="$TMUX"
    fi

    # Show session info
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  🐙 TMUX VISUALIZATION ACTIVE                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Session: ${GREEN}$TMUX_SESSION${NC}"

    if [[ "$TMUX_CREATED" == "true" ]]; then
        echo -e "  ${YELLOW}Attach with:${NC} tmux attach -t $TMUX_SESSION"
    fi
    echo ""
}

# Spawn agent in a new tmux pane with live output
tmux_spawn_pane() {
    local agent_type="$1"
    local task_id="$2"
    local pane_title="$3"
    local log_file="${LOGS_DIR}/${agent_type}-${task_id}.log"

    if ! tmux_check; then
        return 0
    fi

    # Create new pane (split window)
    local pane_id
    if [[ ${#TMUX_PANE_MAP[@]} -eq 0 ]]; then
        # First pane - use the existing pane
        pane_id=$(tmux display-message -p '#{pane_id}')
    else
        # Split the window for additional panes
        pane_id=$(tmux split-window -t "$TMUX_SESSION" -P -F '#{pane_id}' \
            "tail -f $log_file 2>/dev/null || echo 'Waiting for agent...'; sleep infinity" 2>/dev/null)
    fi

    if [[ -z "$pane_id" ]]; then
        log DEBUG "Failed to create tmux pane for $agent_type"
        return 1
    fi

    # Set pane title
    tmux select-pane -t "$pane_id" -T "$pane_title" 2>/dev/null || true

    # Send command to show live log
    tmux send-keys -t "$pane_id" "tail -f $log_file" C-m 2>/dev/null || true

    # Store mapping
    TMUX_PANE_MAP+=("$agent_type:$task_id:$pane_id")

    log DEBUG "Created tmux pane $pane_id for $agent_type-$task_id"

    # Re-balance layout after creating panes
    tmux_layout
}

# Re-arrange tmux panes in a balanced layout
tmux_layout() {
    if ! tmux_check; then
        return 0
    fi

    local pane_count=${#TMUX_PANE_MAP[@]}

    # Choose layout based on number of panes
    if [[ $pane_count -le 2 ]]; then
        tmux select-layout -t "$TMUX_SESSION" even-horizontal 2>/dev/null || true
    elif [[ $pane_count -le 4 ]]; then
        tmux select-layout -t "$TMUX_SESSION" tiled 2>/dev/null || true
    else
        tmux select-layout -t "$TMUX_SESSION" tiled 2>/dev/null || true
    fi

    log DEBUG "Applied tmux layout for $pane_count panes"
}

# Close tmux pane for completed agent
tmux_close_pane() {
    local agent_type="$1"
    local task_id="$2"

    if ! tmux_check; then
        return 0
    fi

    # Find pane ID from mapping
    local pane_id=""
    for mapping in "${TMUX_PANE_MAP[@]}"; do
        if [[ "$mapping" == "$agent_type:$task_id:"* ]]; then
            pane_id="${mapping##*:}"
            break
        fi
    done

    if [[ -n "$pane_id" ]]; then
        tmux kill-pane -t "$pane_id" 2>/dev/null || true
        log DEBUG "Closed tmux pane $pane_id for $agent_type-$task_id"

        # Re-balance layout
        tmux_layout
    fi
}

# Cleanup tmux session after workflow completes
tmux_cleanup() {
    if ! tmux_check; then
        return 0
    fi

    log INFO "Cleaning up tmux session"

    # Only kill session if we created it
    if [[ "$TMUX_CREATED" == "true" ]]; then
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    fi

    TMUX_PANE_MAP=()
}

# ═══════════════════════════════════════════════════════════════════════════════
# ASYNC TASK MANAGEMENT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Spawn agent asynchronously with optional tmux visualization
spawn_agent_async() {
    local agent_type="$1"
    local prompt="$2"
    local task_id="${3:-$(date +%s)-$RANDOM}"
    local role="${4:-}"
    local phase="${5:-}"
    local pane_title="${6:-$agent_type}"

    # Create tmux pane if tmux mode enabled
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_spawn_pane "$agent_type" "$task_id" "$pane_title"
    fi

    # Spawn agent normally (already runs in background)
    local pid
    pid=$(spawn_agent "$agent_type" "$prompt" "$task_id" "$role" "$phase")

    echo "$pid"
}

# Wait for multiple async agents to complete with progress indicator
wait_async_agents() {
    local pids=("$@")

    if [[ ${#pids[@]} -eq 0 ]]; then
        return 0
    fi

    log INFO "Waiting for ${#pids[@]} async agents to complete"

    local -A completed_pids=()
    local start_time=$(date +%s)

    while [[ ${#completed_pids[@]} -lt ${#pids[@]} ]]; do
        for pid in "${pids[@]}"; do
            # Skip already completed PIDs
            [[ -n "${completed_pids[$pid]:-}" ]] && continue

            # Check if process is still running
            if ! kill -0 "$pid" 2>/dev/null; then
                # Reap zombie process and capture exit code
                wait "$pid" 2>/dev/null
                completed_pids[$pid]=$?
            fi
        done

        # Calculate elapsed time
        local elapsed=$(($(date +%s) - start_time))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))

        # Show progress with elapsed time
        echo -ne "\r${CYAN}Progress: ${#completed_pids[@]}/${#pids[@]} agents complete (${mins}m ${secs}s elapsed)${NC}     "

        sleep 0.5
    done

    echo "" # New line after progress

    local total_time=$(($(date +%s) - start_time))
    log INFO "All async agents completed in ${total_time}s"
}

# Collect results from async agents
collect_async_results() {
    local task_group="$1"
    local pattern="${2:-*}"

    log INFO "Collecting async results for task group: $task_group"

    local results=""
    local result_count=0

    for result in "$RESULTS_DIR"/${pattern}-${task_group}-*.md; do
        [[ -f "$result" ]] || continue
        results+="$(cat "$result")\n\n---\n\n"
        ((result_count++))
    done

    if [[ $result_count -eq 0 ]]; then
        log WARN "No async results found for pattern: ${pattern}-${task_group}-*"
        return 1
    fi

    log INFO "Collected $result_count async results"
    echo "$results"
}

# Parallel execution wrapper with async and tmux support
parallel_execute_async() {
    local agents=("$@")
    local pids=()

    # Initialize tmux if enabled
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_init
    fi

    # Spawn all agents in parallel
    for agent_spec in "${agents[@]}"; do
        # Parse agent_spec: "agent_type:prompt:task_id:role:phase:title"
        IFS=':' read -r agent_type prompt task_id role phase title <<< "$agent_spec"

        local pid
        pid=$(spawn_agent_async "$agent_type" "$prompt" "$task_id" "$role" "$phase" "$title")
        pids+=("$pid")

        # Small delay to stagger spawns
        sleep 0.1
    done

    # Wait for all to complete
    wait_async_agents "${pids[@]}"

    # Cleanup tmux if we're done
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_cleanup
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLI FLAG PARSING FOR ASYNC/TMUX
# ═══════════════════════════════════════════════════════════════════════════════

# Parse async/tmux flags from command line arguments
parse_async_tmux_flags() {
    local args=("$@")

    for arg in "${args[@]}"; do
        case "$arg" in
            --async)
                ASYNC_MODE="true"
                log DEBUG "Async mode enabled"
                ;;
            --tmux)
                TMUX_MODE="true"
                log DEBUG "Tmux visualization enabled"
                ;;
            --no-async)
                ASYNC_MODE="false"
                ;;
            --no-tmux)
                TMUX_MODE="false"
                ;;
        esac
    done

    # Auto-enable async if tmux is enabled (tmux requires async)
    if [[ "$TMUX_MODE" == "true" ]]; then
        ASYNC_MODE="true"
        log DEBUG "Auto-enabled async mode (required for tmux)"
    fi
}

# Environment variable overrides
if [[ -n "${OCTOPUS_ASYNC_MODE:-}" ]]; then
    ASYNC_MODE="$OCTOPUS_ASYNC_MODE"
fi

if [[ -n "${OCTOPUS_TMUX_MODE:-}" ]]; then
    TMUX_MODE="$OCTOPUS_TMUX_MODE"
fi
