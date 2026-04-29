#!/usr/bin/env bash
# yaml-workflow.sh — YAML-driven workflow engine
# Contains: parse_yaml_workflow, yaml_get_phases, yaml_get_phase_config,
#           yaml_get_phase_agents, yaml_get_agent_prompt, resolve_prompt_template,
#           execute_workflow_phase, run_yaml_workflow
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# disabled = always use hardcoded logic
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_YAML_RUNTIME="${OCTOPUS_YAML_RUNTIME:-auto}"

# Lightweight YAML parser for workflow files
# Extracts structured data from embrace.yaml using awk
# No external deps required (uses awk/sed, falls back gracefully)
parse_yaml_workflow() {
    local yaml_file="$1"

    if [[ ! -f "$yaml_file" ]]; then
        log "WARN" "Workflow YAML not found: $yaml_file"
        return 1
    fi

    # Use yq if available for robust parsing, else awk fallback
    if command -v yq &>/dev/null; then
        # Validate YAML structure
        if ! yq eval '.name' "$yaml_file" &>/dev/null; then
            log "ERROR" "Invalid YAML in $yaml_file"
            return 1
        fi
        log "DEBUG" "YAML parsed with yq: $yaml_file"
        return 0
    fi

    # awk-based validation: check required top-level keys
    local has_name has_phases
    has_name=$(awk '/^name:/' "$yaml_file")
    has_phases=$(awk '/^phases:/' "$yaml_file")

    if [[ -z "$has_name" || -z "$has_phases" ]]; then
        log "ERROR" "YAML missing required fields (name, phases): $yaml_file"
        return 1
    fi

    log "DEBUG" "YAML parsed with awk fallback: $yaml_file"
    return 0
}

# Extract phase list from workflow YAML
# Returns newline-separated list of phase names
yaml_get_phases() {
    local yaml_file="$1"

    if command -v yq &>/dev/null; then
        yq eval '.phases[].name' "$yaml_file" 2>/dev/null
    else
        # awk fallback: extract phase names from "- name: <phase>" lines under phases:
        awk '
            /^phases:/ { in_phases=1; next }
            in_phases && /^[a-z]/ { exit }
            in_phases && /^  - name:/ {
                gsub(/^  - name:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                print
            }
        ' "$yaml_file"
    fi
}

# Extract phase config for a specific phase
# Returns key=value pairs for the phase
yaml_get_phase_config() {
    local yaml_file="$1"
    local phase_name="$2"
    local field="$3"

    if command -v yq &>/dev/null; then
        yq eval ".phases[] | select(.name == \"$phase_name\") | .$field" "$yaml_file" 2>/dev/null
    else
        # awk fallback for simple fields
        awk -v phase="$phase_name" -v field="$field" '
            /^  - name:/ {
                gsub(/^  - name:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                current_phase = $0
            }
            current_phase == phase && $0 ~ "^    " field ":" {
                gsub(/^[[:space:]]*[a-z_]+:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                print
                exit
            }
        ' "$yaml_file"
    fi
}

# Extract agents for a specific phase
# Returns provider:role:parallel lines
yaml_get_phase_agents() {
    local yaml_file="$1"
    local phase_name="$2"

    if command -v yq &>/dev/null; then
        yq eval ".phases[] | select(.name == \"$phase_name\") | .agents[] | .provider + \":\" + .role + \":\" + (.parallel // true | tostring)" "$yaml_file" 2>/dev/null
    else
        # awk fallback: extract agents block for the phase
        awk -v phase="$phase_name" '
            /^  - name:/ {
                gsub(/^  - name:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                current_phase = $0
            }
            current_phase == phase && /^      - provider:/ {
                gsub(/^      - provider:[[:space:]]*/, "")
                provider = $0
            }
            current_phase == phase && /^        role:/ {
                gsub(/^        role:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                role = $0
            }
            current_phase == phase && /^        parallel:/ {
                gsub(/^        parallel:[[:space:]]*/, "")
                parallel = $0
            }
            current_phase == phase && /^        prompt_template:/ {
                # End of agent block, emit
                if (provider != "") {
                    if (parallel == "") parallel = "true"
                    print provider ":" role ":" parallel
                    provider = ""; role = ""; parallel = ""
                }
            }
            # New phase starts
            current_phase == phase && /^  - name:/ && !/name: *phase/ { exit }
        ' "$yaml_file"
    fi
}

# Extract prompt template for a specific phase agent
yaml_get_agent_prompt() {
    local yaml_file="$1"
    local phase_name="$2"
    local provider="$3"

    if command -v yq &>/dev/null; then
        yq eval ".phases[] | select(.name == \"$phase_name\") | .agents[] | select(.provider == \"$provider\") | .prompt_template" "$yaml_file" 2>/dev/null
    else
        # For awk fallback, return empty - hardcoded prompts will be used
        echo ""
    fi
}

# Resolve template variables in prompt
# Supports: {{prompt}}, {{previous_phase_output}}, {{probe_synthesis}}, etc.
resolve_prompt_template() {
    local template="$1"
    local prompt="$2"
    local previous_output="${3:-}"

    local resolved="$template"
    resolved="${resolved//\{\{prompt\}\}/$prompt}"
    resolved="${resolved//\{\{previous_phase_output\}\}/$previous_output}"
    resolved="${resolved//\{\{probe_synthesis\}\}/$previous_output}"
    resolved="${resolved//\{\{grasp_consensus\}\}/$previous_output}"
    resolved="${resolved//\{\{tangle_implementation\}\}/$previous_output}"

    echo "$resolved"
}

_yaml_wait_for_pids() {
    local max_wait="${1:-${TIMEOUT:-600}}"
    shift || true
    local pids=("$@")
    local wait_start=$SECONDS

    while [[ ${#pids[@]} -gt 0 && $(( SECONDS - wait_start )) -lt $max_wait ]]; do
        local all_done=true
        local pid
        for pid in "${pids[@]}"; do
            [[ -z "$pid" ]] && continue
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                break
            fi
        done
        [[ "$all_done" == "true" ]] && return 0
        sleep 2
    done

    return 0
}

# Execute a single workflow phase from YAML definition
# Spawns agents as defined, respects parallel/sequential flags, evaluates quality gates
execute_workflow_phase() {
    local yaml_file="$1"
    local phase_name="$2"
    local prompt="$3"
    local previous_output="${4:-}"
    local task_group="$5"

    local emoji
    emoji=$(yaml_get_phase_config "$yaml_file" "$phase_name" "emoji") || emoji="🐙"
    local description
    description=$(yaml_get_phase_config "$yaml_file" "$phase_name" "description") || description="$phase_name"
    local alias_name
    alias_name=$(yaml_get_phase_config "$yaml_file" "$phase_name" "alias") || alias_name="$phase_name"

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    local alias_upper
    alias_upper=$(echo "$alias_name" | tr '[:lower:]' '[:upper:]')
    echo -e "${MAGENTA}║  ${GREEN}${alias_upper}${MAGENTA} - ${description}${MAGENTA}${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""

    log "INFO" "YAML Runtime: Executing phase '$phase_name' ($description)"

    # v8.7.0: Update bridge phase and inject quality gate
    bridge_update_current_phase "$phase_name"
    local qg_threshold_val
    qg_threshold_val=$(yaml_get_phase_config "$yaml_file" "$phase_name" "threshold") || qg_threshold_val="0.75"
    bridge_inject_gate_task "$phase_name" "quality" "$qg_threshold_val"

    # Get agents for this phase
    local agents_raw
    agents_raw=$(yaml_get_phase_agents "$yaml_file" "$phase_name")

    if [[ -z "$agents_raw" ]]; then
        log "WARN" "No agents defined for phase $phase_name in YAML, using defaults"
        return 1
    fi

    local pids=()
    local agent_idx=0

    # Update session state for hooks
    local session_dir="${HOME}/.claude-octopus"
    mkdir -p "$session_dir"

    # Count total agents for this phase
    local total_agents
    total_agents=$(echo "$agents_raw" | wc -l | tr -d ' ')

    # Write phase task info for task-completed-transition.sh
    if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
        jq --argjson total "$total_agents" \
           '.phase_tasks = {total: $total, completed: 0}' \
           "$session_dir/session.json" > "$session_dir/session.json.tmp" \
           && mv "$session_dir/session.json.tmp" "$session_dir/session.json" 2>/dev/null || true
    fi

    # Spawn agents
    fleet_dispatch_begin
    while IFS=':' read -r provider role is_parallel; do
        [[ -z "$provider" ]] && continue

        local task_id="${phase_name}-${task_group}-${agent_idx}"

        # Resolve prompt template
        local agent_prompt
        agent_prompt=$(yaml_get_agent_prompt "$yaml_file" "$phase_name" "$provider")
        if [[ -n "$agent_prompt" ]]; then
            agent_prompt=$(resolve_prompt_template "$agent_prompt" "$prompt" "$previous_output")
        else
            # Fallback: construct prompt from role
            agent_prompt="$role: $prompt"
            if [[ -n "$previous_output" ]]; then
                agent_prompt="$agent_prompt

Previous phase output:
$previous_output"
            fi
        fi

        # Map provider to agent type
        local agent_type="$provider"
        case "$provider" in
            claude) agent_type="claude-sonnet" ;;
        esac

        # Check provider availability
        case "$provider" in
            codex)
                if ! command -v codex &>/dev/null && [[ -z "${OPENAI_API_KEY:-}" ]]; then
                    log "WARN" "Codex not available, skipping agent in phase $phase_name"
                    ((agent_idx++)) || true
                    continue
                fi
                ;;
            gemini)
                if ! command -v gemini &>/dev/null && [[ -z "${GEMINI_API_KEY:-}" ]]; then
                    log "WARN" "Gemini not available, skipping agent in phase $phase_name"
                    ((agent_idx++)) || true
                    continue
                fi
                ;;
        esac

        if [[ "$is_parallel" == "true" ]]; then
            local pid
            pid=$(spawn_agent_capture_pid "$agent_type" "$agent_prompt" "$task_id" "$role" "$phase_name")
            pids+=("$pid")
        else
            # Sequential agent - wait for parallel agents first
            if [[ ${#pids[@]} -gt 0 ]]; then
                log "DEBUG" "Waiting for ${#pids[@]} parallel agents before sequential agent"
                _yaml_wait_for_pids "${TIMEOUT:-600}" "${pids[@]}"
                pids=()
            fi
            spawn_agent "$agent_type" "$agent_prompt" "$task_id" "$role" "$phase_name"
        fi

        ((agent_idx++)) || true
        sleep 0.1
    done <<< "$agents_raw"
    fleet_dispatch_end

    # Wait for remaining parallel agents (v8.7.0: convergence-aware polling)
    if [[ ${#pids[@]} -gt 0 ]]; then
        log "INFO" "Waiting for ${#pids[@]} parallel agents in phase $phase_name"
        if [[ "$OCTOPUS_CONVERGENCE_ENABLED" == "true" ]]; then
            # Convergence-aware: poll results while waiting
            local wait_start=$SECONDS
            local max_wait=${TIMEOUT:-600}
            while [[ $(( SECONDS - wait_start )) -lt $max_wait ]]; do
                local all_done=true
                for pid in "${pids[@]}"; do
                    if kill -0 "$pid" 2>/dev/null; then
                        all_done=false
                        break
                    fi
                done
                [[ "$all_done" == "true" ]] && break

                # Check convergence on available results
                if check_convergence "$RESULTS_DIR"/*-${phase_name}-${task_group}-*.md; then
                    log "INFO" "CONVERGENCE: Early termination - agents converged in phase $phase_name"
                    break
                fi
                sleep 2
            done
            _yaml_wait_for_pids "$max_wait" "${pids[@]}"
        else
            _yaml_wait_for_pids "${TIMEOUT:-600}" "${pids[@]}"
        fi
    fi

    # Collect phase output
    local phase_output=""
    local result_files
    result_files=$(ls -t "$RESULTS_DIR"/*-${phase_name}-${task_group}-*.md 2>/dev/null || true)
    if [[ -n "$result_files" ]]; then
        for f in $result_files; do
            # v8.7.0: Verify result integrity before reading
            if ! verify_result_integrity "$f"; then
                log "WARN" "Skipping tampered result file: $f"
                continue
            fi
            phase_output+="$(cat "$f" 2>/dev/null)
---
"
        done
    fi

    # v8.7.0: Run deduplication check on results (log-only in v8.7.0)
    if [[ -n "$result_files" ]]; then
        local -a dedup_files
        for f in $result_files; do dedup_files+=("$f"); done
        deduplicate_results "${dedup_files[@]}"
    fi

    # Write synthesis file
    local synthesis_file="${RESULTS_DIR}/${phase_name}-synthesis-${task_group}.md"
    if [[ -n "$phase_output" ]]; then
        echo "# $(_ucfirst "$phase_name") Phase Synthesis" > "$synthesis_file"
        echo "# Generated by YAML Runtime" >> "$synthesis_file"
        echo "# Task Group: $task_group" >> "$synthesis_file"
        echo "" >> "$synthesis_file"
        echo "$phase_output" >> "$synthesis_file"
    fi

    # Evaluate quality gate
    local qg_threshold
    qg_threshold=$(yaml_get_phase_config "$yaml_file" "$phase_name" "threshold") || qg_threshold="0.5"
    local result_count
    result_count=$(echo "$result_files" | wc -l | tr -d ' ')
    if [[ $result_count -ge 1 ]]; then
        log "INFO" "Phase $phase_name quality gate: $result_count results (threshold: $qg_threshold)"
    else
        log "WARN" "Phase $phase_name quality gate: no results produced"
    fi

    log "INFO" "YAML Runtime: Phase '$phase_name' complete ($result_count agent results)"

    # v8.7.0: Generate phase summary for bridge and refresh provider stats
    bridge_generate_phase_summary "$phase_name" "$synthesis_file"
    bridge_evaluate_gate "$phase_name" || log "WARN" "Phase $phase_name quality gate did not pass"
    refresh_provider_stats

    echo "$synthesis_file"
}

# Top-level YAML workflow runner
# Loads a workflow YAML file and executes all phases in sequence
run_yaml_workflow() {
    local workflow_name="$1"
    local prompt="$2"
    local task_group="${3:-$(date +%s)}"

    local yaml_file="${PLUGIN_DIR}/config/workflows/${workflow_name}.yaml"

    # Parse and validate
    if ! parse_yaml_workflow "$yaml_file"; then
        log "ERROR" "Failed to parse workflow YAML: $yaml_file"
        return 1
    fi

    # Get phase list
    local phases
    phases=$(yaml_get_phases "$yaml_file")
    if [[ -z "$phases" ]]; then
        log "ERROR" "No phases found in workflow YAML: $yaml_file"
        return 1
    fi

    local phase_count
    phase_count=$(echo "$phases" | wc -l | tr -d ' ')
    log "INFO" "YAML Runtime: Starting workflow '$workflow_name' with $phase_count phases"

    # v8.7.0: Initialize bridge ledger
    bridge_init_ledger "$workflow_name" "$task_group"

    local phase_num=0
    local previous_output=""
    local all_outputs=()

    while IFS= read -r phase_name; do
        [[ -z "$phase_name" ]] && continue
        ((phase_num++)) || true

        echo ""
        local phase_upper
        phase_upper=$(echo "$phase_name" | tr '[:lower:]' '[:upper:]')
        echo -e "${CYAN}[${phase_num}/${phase_count}] Starting ${phase_upper} phase...${NC}"
        echo ""

        # Update workflow state
        export OCTOPUS_WORKFLOW_PHASE="$phase_name"
        export OCTOPUS_COMPLETED_PHASES=$((phase_num - 1))

        # Update session.json for hooks
        local session_dir="${HOME}/.claude-octopus"
        if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
            jq --arg phase "$phase_name" --arg status "running" \
               --argjson completed "$((phase_num - 1))" \
               '.current_phase = $phase | .phase_status = $status | .completed_phases = $completed' \
               "$session_dir/session.json" > "$session_dir/session.json.tmp" \
               && mv "$session_dir/session.json.tmp" "$session_dir/session.json" 2>/dev/null || true
        fi

        # Read previous phase output if available
        if [[ -n "$previous_output" && -f "$previous_output" ]]; then
            local prev_content
            prev_content=$(head -c 8000 "$previous_output" 2>/dev/null) || prev_content=""
        else
            local prev_content=""
        fi

        # Execute phase
        local phase_result
        phase_result=$(execute_workflow_phase "$yaml_file" "$phase_name" "$prompt" "$prev_content" "$task_group")

        previous_output="$phase_result"
        all_outputs+=("$phase_result")

        # Update session state
        if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
            jq --arg phase "$phase_name" --arg status "completed" \
               --argjson completed "$phase_num" \
               '.current_phase = $phase | .phase_status = $status | .completed_phases = $completed' \
               "$session_dir/session.json" > "$session_dir/session.json.tmp" \
               && mv "$session_dir/session.json.tmp" "$session_dir/session.json" 2>/dev/null || true
        fi

        # Handle autonomy checkpoint
        handle_autonomy_checkpoint "$phase_name" "completed" 2>/dev/null || true

        # v7.25.0: Display phase metrics
        if command -v display_phase_metrics &>/dev/null; then
            display_phase_metrics "$phase_name" 2>/dev/null || true
        fi

        sleep 1
    done <<< "$phases"

    log "INFO" "YAML Runtime: Workflow '$workflow_name' complete ($phase_num phases executed)"

    # Return the last synthesis file path
    echo "${all_outputs[-1]:-}"
}

# v8.54.0: Single-agent probe for multi-agentic skill dispatch
