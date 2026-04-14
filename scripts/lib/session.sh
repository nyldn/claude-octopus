#!/usr/bin/env bash
# session.sh — Session management and progress tracking
# Contains: init_progress_tracking, display_progress_summary, cleanup_old_progress_files,
#           display_rich_progress, generate_session_name, init_session,
#           save_session_checkpoint, check_resume_session, get_resume_phase,
#           get_phase_output, complete_session
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════
# PROGRESS TRACKING
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize progress tracking for a workflow
init_progress_tracking() {
    local phase="$1"
    local total_agents="${2:-0}"

    # Skip if progress tracking disabled
    if [[ "$PROGRESS_TRACKING_ENABLED" != "true" ]]; then
        log DEBUG "Progress tracking disabled - skipping init"
        return 0
    fi

    # Use atomic write to prevent race conditions
    cat > "${PROGRESS_FILE}.tmp.$$" << EOF
{
  "session_id": "${CLAUDE_CODE_SESSION:-session}",
  "phase": "$phase",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_agents": $total_agents,
  "completed_agents": 0,
  "total_cost": 0.0,
  "total_time_ms": 0,
  "agents": []
}
EOF
    mv "${PROGRESS_FILE}.tmp.$$" "$PROGRESS_FILE"

    log DEBUG "Progress tracking initialized for phase: $phase ($total_agents agents)"
}

# Update agent status in progress file
# [EXTRACTED to lib/agents.sh]

# Format and display progress summary
display_progress_summary() {
    if [[ "$PROGRESS_TRACKING_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi

    local phase completed total total_cost total_time
    phase=$(jq -r '.phase // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
    completed=$(jq -r '.completed_agents // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    total=$(jq -r '.total_agents // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    total_cost=$(jq -r '.total_cost // 0.0' "$PROGRESS_FILE" 2>/dev/null || echo "0.0")
    total_time=$(jq -r '(.total_time_ms // 0) / 1000' "$PROGRESS_FILE" 2>/dev/null || echo "0")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐙 WORKFLOW SUMMARY: $phase Phase"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Provider Results:"
    echo ""

    # Read agents and format status with timeout info (v7.16.0 Feature 3)
    jq -r '.agents[] |
        if .status == "completed" then
            "✅ \(.name): Completed (\(.elapsed_ms / 1000)s) - $\(.cost)"
        elif .status == "running" then
            if .timeout_warning then
                "⏳ \(.name): Running... (\(.elapsed_ms / 1000)s / \(.timeout_ms / 1000)s timeout - \(.timeout_pct)%)\n⚠️  WARNING: Approaching timeout! (\(.remaining_ms / 1000)s remaining)"
            else
                "⏳ \(.name): Running... (\(.elapsed_ms / 1000)s / \(.timeout_ms / 1000)s timeout)"
            end
        elif .status == "failed" then
            "❌ \(.name): Failed"
        else
            "⏸️  \(.name): Waiting"
        end
    ' "$PROGRESS_FILE" 2>/dev/null | sed 's/codex/🔴 Codex CLI/; s/gemini/🟡 Gemini CLI/; s/claude/🔵 Claude/' || echo "  (No agent data available)"

    echo ""

    # Show timeout guidance if any warnings (v7.16.0 Feature 3)
    local has_warnings
    has_warnings=$(jq -r '[.agents[].timeout_warning] | any' "$PROGRESS_FILE" 2>/dev/null || echo "false")

    if [[ "$has_warnings" == "true" ]]; then
        local current_timeout
        current_timeout=$(jq -r '.agents[0].timeout_ms // 300000' "$PROGRESS_FILE" 2>/dev/null)
        current_timeout=$((current_timeout / 1000))
        local recommended_timeout=$((current_timeout * 2))

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "💡 Timeout Guidance:"
        echo "   Current timeout: ${current_timeout}s"
        echo "   Recommended: --timeout ${recommended_timeout}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "Progress: %s/%s providers completed\n" "$completed" "$total"
    printf "💰 Total Cost: \$%s\n" "$total_cost"
    printf "⏱️  Total Time: %ss\n" "$total_time"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Clean up old progress files (older than 1 day)
cleanup_old_progress_files() {
    if [[ "$PROGRESS_TRACKING_ENABLED" != "true" ]]; then
        return 0
    fi

    # Remove progress files older than 1 day
    find "$WORKSPACE_DIR" -name "progress-*.json" -type f -mtime +1 -delete 2>/dev/null || true
    # Also clean up lock files
    find "$WORKSPACE_DIR" -name "progress-*.json.lock" -type f -mtime +1 -delete 2>/dev/null || true
}

# [EXTRACTED to lib/error-tracking.sh]

# [EXTRACTED to lib/cost.sh] generate_usage_csv(), generate_usage_json(), clear_usage_session()

# classify_task() — extracted to lib/routing.sh (v8.21.0)

# Get best agent for task type

# ═══════════════════════════════════════════════════════════════════════════════
# RICH PROGRESS DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════

display_rich_progress() {
    local task_group="$1"
    local total_agents="$2"
    local start_time="$3"
    shift 3
    local pids=("$@")

    # Agent metadata arrays
    local -a agent_names=()
    local -a agent_types=()

    # Build agent info from task IDs
    for i in $(seq 0 $((total_agents - 1))); do
        local agent="gemini"
        [[ $((i % 2)) -eq 0 ]] && agent="codex"
        agent_types+=("$agent")

        case $i in
            0) agent_names+=("Problem Analysis") ;;
            1) agent_names+=("Solution Research") ;;
            2) agent_names+=("Edge Cases") ;;
            3) agent_names+=("Feasibility") ;;
            *) agent_names+=("Agent $i") ;;
        esac
    done

    # Progress bar function
    local bar_width=20

    while true; do
        local all_done=true
        local completed=0

        # Clear previous output (move cursor up and clear)
        [[ $completed -gt 0 ]] && printf "\033[%dA" $((total_agents + 4))

        # Header
        echo -e "${MAGENTA}${_BOX_TOP}${NC}"
        echo -e "${MAGENTA}║  ${CYAN}Multi-AI Research Progress${MAGENTA}                             ║${NC}"
        echo -e "${MAGENTA}${_BOX_BOT}${NC}"

        # Agent status rows
        for i in $(seq 0 $((total_agents - 1))); do
            local task_id="probe-${task_group}-${i}"
            local agent_type="${agent_types[$i]}"
            local agent_name="${agent_names[$i]}"
            local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"
            local pid="${pids[$i]}"

            # Check if agent is still running
            local running=true
            if ! kill -0 "$pid" 2>/dev/null; then
                running=false
                ((completed++)) || true
            else
                all_done=false
            fi

            # Get file size if result exists
            local file_size=0
            local size_display="0B"
            if [[ -f "$result_file" ]]; then
                file_size=$(wc -c < "$result_file" 2>/dev/null || echo "0")
                if [[ $file_size -gt 1048576 ]]; then
                    size_display="$(( file_size / 1048576 ))MB"
                elif [[ $file_size -gt 1024 ]]; then
                    size_display="$(( file_size / 1024 ))KB"
                else
                    size_display="${file_size}B"
                fi
            fi

            # Determine status and progress
            local status_icon="⏳"
            local progress_pct=0
            local bar_color="${YELLOW}"

            if ! $running; then
                if [[ $file_size -gt 1024 ]]; then
                    status_icon="${GREEN}✓${NC}"
                    progress_pct=100
                    bar_color="${GREEN}"
                else
                    status_icon="${RED}✗${NC}"
                    progress_pct=0
                    bar_color="${RED}"
                fi
            else
                # Estimate progress based on file size (rough heuristic)
                if [[ $file_size -gt 10000 ]]; then
                    progress_pct=75
                elif [[ $file_size -gt 5000 ]]; then
                    progress_pct=50
                elif [[ $file_size -gt 1000 ]]; then
                    progress_pct=25
                else
                    progress_pct=10
                fi
                bar_color="${CYAN}"
            fi

            # Build progress bar
            local filled=$(( progress_pct * bar_width / 100 ))
            local empty=$(( bar_width - filled ))
            local bar=""
            for ((j=0; j<filled; j++)); do bar+="═"; done
            for ((j=0; j<empty; j++)); do bar+=" "; done

            # Display row with emoji for agent type
            local agent_emoji="🔴"
            [[ "$agent_type" == "gemini" ]] && agent_emoji="🟡"

            printf " %b %s %-18s [%b%s%b] %6s\n" \
                "$status_icon" \
                "$agent_emoji" \
                "$agent_name" \
                "$bar_color" \
                "$bar" \
                "${NC}" \
                "$size_display"
        done

        # Footer with timing
        local elapsed=$(( $(date +%s) - start_time ))
        local elapsed_display="${elapsed}s"
        if [[ $elapsed -gt 60 ]]; then
            elapsed_display="$(( elapsed / 60 ))m $(( elapsed % 60 ))s"
        fi

        echo -e "${MAGENTA}${_DASH}${NC}"
        # v9.2.0: ETA based on provider-specific benchmarks (OctoBench data)
        # Codex ~150s, Gemini ~90s, Sonnet ~45s — parallel = max(providers)
        local eta_secs=120  # default estimate
        if [[ $completed -gt 0 && $completed -lt $total_agents ]]; then
            local avg_per_agent=$(( elapsed / completed ))
            local remaining=$(( total_agents - completed ))
            eta_secs=$(( avg_per_agent * remaining ))
        fi
        local eta_display="${eta_secs}s"
        [[ $eta_secs -gt 60 ]] && eta_display="$(( eta_secs / 60 ))m $(( eta_secs % 60 ))s"

        printf " Progress: ${CYAN}%d/%d${NC} complete | Elapsed: ${CYAN}%s${NC} | ETA: ${CYAN}~%s${NC}\n" \
            "$completed" "$total_agents" "$elapsed_display" "$eta_display"

        # Exit if all done
        $all_done && break

        sleep 1
    done

    echo ""
}

# v7.19.0 P2.3: Result caching for probe workflows
# Cache directory
CACHE_DIR="${WORKSPACE_DIR}/.cache/probe-results"
CACHE_TTL=3600  # 1 hour in seconds

# v7.19.0 P2.4: Progressive synthesis flag
ENABLE_PROGRESSIVE_SYNTHESIS="${OCTOPUS_PROGRESSIVE_SYNTHESIS:-true}"

# Generate cache key from prompt (SHA256 hash)

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Generate a short session name from workflow type and prompt
# Args: $1=workflow, $2=prompt
# Returns: human-readable session name (max 60 chars)
generate_session_name() {
    local workflow="$1"
    local prompt="$2"

    # Extract first meaningful words from prompt (skip common prefixes)
    local summary
    summary=$(echo "$prompt" | tr '[:upper:]' '[:lower:]' | \
        sed 's/^[[:space:]]*//' | \
        sed 's/please //; s/can you //; s/i want to //; s/help me //' | \
        cut -c1-50 | \
        sed 's/[[:space:]]*$//')

    # Replace spaces with hyphens, remove non-alphanumeric except hyphens
    summary=$(echo "$summary" | tr ' ' '-' | tr -cd 'a-z0-9-')

    # Truncate to keep total name reasonable
    summary="${summary:0:40}"

    echo "${workflow}: ${summary}"
}

# Initialize a new session
init_session() {
    local workflow="$1"
    local prompt="$2"

    # v8.32.0: Check for mid-session config changes before starting workflow
    check_config_reload

    # Claude Code v2.1.9: Use CLAUDE_SESSION_ID for cross-session tracking
    local session_id
    if [[ -n "$CLAUDE_CODE_SESSION" ]]; then
        session_id="${workflow}-claude-${CLAUDE_CODE_SESSION}"
    else
        session_id="${workflow}-$(date +%Y%m%d-%H%M%S)"
    fi

    # v8.8: Generate human-readable session name for easier resume
    local session_name
    session_name=$(generate_session_name "$workflow" "$prompt")

    # v8.8: Auto-name session via claude rename (non-blocking, best-effort)
    if [[ "$SUPPORTS_AUTH_CLI" == "true" ]] && [[ -n "$CLAUDE_CODE_SESSION" ]]; then
        # Use /rename auto-naming by setting a meaningful name
        claude --no-input --print "Session: ${session_name}" &>/dev/null &
        log "DEBUG" "Auto-naming session: ${session_name}"
    fi

    # Ensure jq is available for JSON manipulation
    if ! command -v jq &> /dev/null; then
        log WARN "jq not available - session recovery disabled"
        return 1
    fi

    mkdir -p "$(dirname "$SESSION_FILE")"

    cat > "$SESSION_FILE" << EOF
{
  "session_id": "$session_id",
  "session_name": $(printf '%s' "$session_name" | jq -Rs .),
  "workflow": "$workflow",
  "status": "in_progress",
  "current_phase": null,
  "started_at": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)",
  "last_checkpoint": null,
  "prompt": $(printf '%s' "$prompt" | jq -Rs .),
  "phases": {}
}
EOF
    log INFO "Session initialized: $session_id (name: $session_name)"

    # v8.14.0: Initialize persistent state tracking
    init_state 2>/dev/null || true
    set_current_workflow "$workflow" "init" 2>/dev/null || true
}

# Save checkpoint after phase completion
save_session_checkpoint() {
    local phase="$1"
    local status="$2"
    local output_file="$3"

    if [[ ! -f "$SESSION_FILE" ]] || ! command -v jq &> /dev/null; then
        return 0
    fi

    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

    jq --arg phase "$phase" \
       --arg status "$status" \
       --arg output "$output_file" \
       --arg time "$timestamp" \
       '.phases[$phase] = {status: $status, output: $output, timestamp: $time} | .last_checkpoint = $time | .current_phase = $phase' \
       "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # v8.14.0: Sync to persistent state
    set_current_workflow "$(jq -r '.workflow // ""' "$SESSION_FILE" 2>/dev/null)" "$phase" 2>/dev/null || true
    update_metrics "phases_completed" "1" 2>/dev/null || true
    write_state_md 2>/dev/null || true

    # Route through memory contract so any enabled backend picks it up (#220).
    if [[ "$(memory_available 2>/dev/null)" == "true" ]]; then
        local workflow_name
        workflow_name=$(jq -r '.workflow // "unknown"' "$SESSION_FILE" 2>/dev/null || echo "unknown")
        memory_observe "decision" \
            "Octopus ${phase} phase ${status}" \
            "Workflow: ${workflow_name}, Phase: ${phase}, Status: ${status}, Output: ${output_file}" \
            2>/dev/null &
    fi

    log DEBUG "Checkpoint saved: $phase ($status)"
}

# Check for resumable session
check_resume_session() {
    if [[ ! -f "$SESSION_FILE" ]] || ! command -v jq &> /dev/null; then
        return 1
    fi

    local status workflow phase
    status=$(jq -r '.status' "$SESSION_FILE" 2>/dev/null)

    if [[ "$status" == "in_progress" ]]; then
        workflow=$(jq -r '.workflow' "$SESSION_FILE")
        phase=$(jq -r '.current_phase // "none"' "$SESSION_FILE")

        # Claude Code v2.1.9: CI mode auto-declines session resume
        if [[ "$CI_MODE" == "true" ]]; then
            log INFO "CI mode: Auto-declining session resume, starting fresh"
            return 1
        fi

        echo ""
        echo -e "${YELLOW}${_BOX_TOP}${NC}"
        echo -e "${YELLOW}║  Interrupted Session Found                                ║${NC}"
        echo -e "${YELLOW}${_BOX_BOT}${NC}"
        echo -e "Workflow: ${CYAN}$workflow${NC}"
        echo -e "Last phase: ${CYAN}$phase${NC}"
        echo ""
        read -p "Resume from last checkpoint? (y/n) " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0  # Resume
        fi
    fi
    return 1  # Start fresh
}

# Get the phase to resume from
get_resume_phase() {
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        jq -r '.current_phase // ""' "$SESSION_FILE"
    fi
}

# Get saved output file for a phase
get_phase_output() {
    local phase="$1"
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        jq -r ".phases.$phase.output // \"\"" "$SESSION_FILE"
    fi
}

# Mark session as complete
complete_session() {
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        jq '.status = "completed"' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && \
            mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
        log INFO "Session marked complete"
    fi

    # v8.14.0: Mark persistent state as completed
    set_current_workflow "completed" "done" 2>/dev/null || true
    write_state_md 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: SPECIALIZED AGENT ROLES
# Role-based agent selection for different phases of work

# [EXTRACTED to lib/agent-utils.sh] get_role_mapping, get_role_agent, get_role_model,
# log_role_assignment, has_curated_agents, parse_yaml_value, check_completion_promise,
# init_ralph_state, update_ralph_state, get_ralph_iteration, run_with_ralph_loop,
# has_claude_code, run_with_claude_code_ralph, refine_image_prompt, detect_image_type,
# retry_failed_subtasks, build_anchor_ref, build_file_reference, resume_agent



# ── Extracted from orchestrate.sh ──
cleanup_expired_checkpoints() {
    local checkpoint_dir="${WORKSPACE_DIR}/.octo/checkpoints"

    if [[ ! -d "$checkpoint_dir" ]]; then
        return 0
    fi

    local now
    now=$(date +%s)

    for checkpoint in "$checkpoint_dir"/*.checkpoint.json; do
        [[ -f "$checkpoint" ]] || continue

        local mod_time age
        if stat -f %m "$checkpoint" &>/dev/null; then
            mod_time=$(stat -f %m "$checkpoint")
        else
            mod_time=$(stat -c %Y "$checkpoint")
        fi
        age=$((now - mod_time))

        if [[ $age -gt 86400 ]]; then
            rm -f "$checkpoint"
            log DEBUG "Cleaned up expired checkpoint: $(basename "$checkpoint")"
        fi
    done
}
