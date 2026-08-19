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

    local value=""
    if command -v yq &>/dev/null; then
        # Fall back to the phase quality_gate block for nested fields (threshold)
        value=$(yq eval ".phases[] | select(.name == \"$phase_name\") | .$field // .quality_gate.$field // \"\"" "$yaml_file" 2>/dev/null)
    else
        # awk fallback: match the field at any indent inside the phase block.
        # Stops at the next top-level key so the last phase cannot bleed into
        # the document-level quality_gates: block (that bug made ink report the
        # consensus threshold 0.75 instead of its own 0.80).
        value=$(awk -v phase="$phase_name" -v field="$field" '
            in_phases && /^[a-zA-Z_]+:/ { exit }
            /^phases:/ { in_phases=1 }
            /^  - name:/ {
                gsub(/^  - name:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                current_phase = $0
                next
            }
            current_phase == phase && $0 ~ "^[[:space:]]+" field ":" {
                gsub(/^[[:space:]]*[a-zA-Z_]+:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                print
                exit
            }
        ' "$yaml_file")
    fi
    [[ "$value" == "null" ]] && value=""
    [[ -n "$value" ]] && printf '%s\n' "$value"
    [[ -n "$value" ]]
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
        local yq_out
        yq_out=$(yq eval ".phases[] | select(.name == \"$phase_name\") | .agents[] | select(.provider == \"$provider\") | .prompt_template // \"\"" "$yaml_file" 2>/dev/null)
        [[ "$yq_out" == "null" ]] && yq_out=""
        printf '%s\n' "$yq_out"
    else
        # awk fallback: extract the `prompt_template: |` block scalar for the
        # matching phase+provider. Without this, every agent silently ran a
        # bare "role: prompt" fallback whenever yq was not installed.
        awk -v phase="$phase_name" -v provider="$provider" '
            /^  - name:/ {
                gsub(/^  - name:[[:space:]]*/, "")
                gsub(/["\047]/, "")
                current_phase = $0
                current_provider = ""
                in_block = 0
                next
            }
            /^      - provider:/ {
                if (in_block) exit
                gsub(/^      - provider:[[:space:]]*/, "")
                current_provider = $0
                next
            }
            in_block {
                if ($0 == "" || $0 ~ /^[[:space:]]{10}/) {
                    line = $0
                    sub(/^[[:space:]]{10}/, "", line)
                    print line
                    next
                }
                exit
            }
            current_phase == phase && current_provider == provider && /^        prompt_template:[[:space:]]*\|/ {
                in_block = 1
            }
        ' "$yaml_file"
    fi
}

# Resolve template variables in prompt
# Supports: {{prompt}}, {{previous_phase_output}}, {{probe_synthesis}}, etc.
# Any further "name" "value" argument pairs are substituted as {{name}}
# placeholders too — used by execute_workflow_phase to wire same-phase
# sibling outputs (e.g. {{ink_codex}}, {{ink_agy}}) into a later sequential
# agent's prompt.
resolve_prompt_template() {
    local template="$1"
    local prompt="$2"
    local previous_output="${3:-}"
    shift 3 || true

    local resolved="$template"
    resolved="${resolved//\{\{prompt\}\}/$prompt}"
    resolved="${resolved//\{\{previous_phase_output\}\}/$previous_output}"
    resolved="${resolved//\{\{probe_synthesis\}\}/$previous_output}"
    resolved="${resolved//\{\{grasp_consensus\}\}/$previous_output}"
    resolved="${resolved//\{\{tangle_implementation\}\}/$previous_output}"

    while [[ $# -ge 2 ]]; do
        local var_name="$1" var_value="$2"
        resolved="${resolved//\{\{${var_name}\}\}/$var_value}"
        shift 2
    done

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

# Wait for the .done completion markers of the given task ids. The spawn
# wrapper writes the result file and marker AFTER the provider PID exits, so a
# PID wait alone races the file writes. Markers hold the agent exit code.
_yaml_wait_for_done_markers() {
    local max_wait="$1"
    shift || true
    local done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"
    local wait_start=$SECONDS

    while [[ $(( SECONDS - wait_start )) -lt $max_wait ]]; do
        local all_done=true
        local task_id
        for task_id in "$@"; do
            [[ -f "${done_dir}/${task_id}.done" ]] || { all_done=false; break; }
        done
        [[ "$all_done" == "true" ]] && return 0
        sleep 1
    done
    return 1
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

    # Decorative output goes to stderr: this function is invoked inside a
    # command substitution and stdout is reserved for the synthesis file path.
    # Banners on stdout corrupted that path, so downstream phases never
    # received the previous phase's output.
    {
        echo ""
        echo -e "${MAGENTA}${_BOX_TOP}${NC}"
        local alias_upper
        alias_upper=$(echo "$alias_name" | tr '[:lower:]' '[:upper:]')
        echo -e "${MAGENTA}║  ${GREEN}${alias_upper}${MAGENTA} - ${description}${MAGENTA}${NC}"
        echo -e "${MAGENTA}${_BOX_BOT}${NC}"
        echo ""
    } >&2

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
    local spawned_tasks=()
    # Configured provider name for each entry in spawned_tasks, same index —
    # the result-file prefix (agent_type) differs for claude (claude-sonnet),
    # so this can't be recovered by parsing the filename.
    local spawned_providers=()
    # Same-phase sibling outputs already captured, in provider order, for
    # {{<phase>_<provider>}} placeholders (e.g. {{ink_codex}}, {{ink_agy}}).
    # Rebuilt fresh on every agent iteration (see below), so it only ever
    # holds completed spawned_tasks entries.
    local sib_providers=()
    local sib_outputs=()
    # Providers skipped for unavailability never enter spawned_tasks, so
    # they'd be lost on every sib_providers/sib_outputs rebuild — tracked
    # separately here and merged back in each time instead.
    local skipped_providers=()
    local skipped_outputs=()
    local done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"

    # Update session state for hooks
    local session_dir="${HOME}/.claude-octopus"
    mkdir -p "$session_dir"

    # Count total agents for this phase
    local total_agents
    total_agents=$(echo "$agents_raw" | wc -l | tr -d ' ')

    # Write phase task info for task-completed-transition.sh
    if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
        local phase_tasks_tmp=""
        if phase_tasks_tmp=$(mktemp "$session_dir/session.json.tmp.XXXXXX"); then
            jq --argjson total "$total_agents" \
           '.phase_tasks = {total: $total, completed: 0}' \
           "$session_dir/session.json" > "$phase_tasks_tmp" \
           && mv "$phase_tasks_tmp" "$session_dir/session.json" 2>/dev/null || rm -f "$phase_tasks_tmp"
        fi
    fi

    # Spawn agents
    fleet_dispatch_begin
    while IFS=':' read -r provider role is_parallel; do
        [[ -z "$provider" ]] && continue

        local task_id="${phase_name}-${task_group}-${agent_idx}"

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
                    skipped_providers+=("codex")
                    skipped_outputs+=("(codex unavailable — skipped this run)")
                    ((agent_idx++)) || true
                    continue
                fi
                ;;
            agy)
                if ! command -v agy &>/dev/null && [[ -z "${ANTIGRAVITY_API_KEY:-}" ]]; then
                    log "WARN" "Antigravity not available, skipping agent in phase $phase_name"
                    skipped_providers+=("agy")
                    skipped_outputs+=("(antigravity unavailable — skipped this run)")
                    ((agent_idx++)) || true
                    continue
                fi
                ;;
        esac

        # Sequential agent - wait for this phase's parallel siblings first, so
        # their result files are on disk before we resolve this agent's
        # prompt: a sequential agent's prompt_template may reference a
        # sibling's own-phase output (e.g. {{ink_codex}}, {{ink_agy}}), and
        # that placeholder can only resolve to real content once the sibling
        # has actually finished.
        if [[ "$is_parallel" != "true" && ${#pids[@]} -gt 0 ]]; then
            log "DEBUG" "Waiting for ${#pids[@]} parallel agents before sequential agent"
            _yaml_wait_for_pids "${TIMEOUT:-600}" "${pids[@]}"
            # _yaml_wait_for_pids always returns 0 (even on timeout — it has
            # other bare, unchecked call sites under this file's set -e
            # caller), so confirm completion ourselves rather than trusting
            # its return value: a sibling still alive past its wait window
            # must halt the phase, not silently let the sequential agent
            # start beside it.
            local _still_running=false _pid
            for _pid in "${pids[@]}"; do
                [[ -z "$_pid" ]] && continue
                kill -0 "$_pid" 2>/dev/null && _still_running=true
            done
            if [[ "$_still_running" == "true" ]]; then
                log "ERROR" "Phase $phase_name: a parallel sibling did not finish within its wait window — halting phase rather than starting the sequential agent early"
                fleet_dispatch_end
                return 1
            fi
            if ! _yaml_wait_for_done_markers "${OCTOPUS_YAML_DONE_WAIT:-30}" "${spawned_tasks[@]}"; then
                log "ERROR" "Phase $phase_name: parallel sibling completion marker(s) missing — halting phase rather than starting the sequential agent early"
                fleet_dispatch_end
                return 1
            fi
            pids=()
        fi

        # Gather same-phase sibling outputs from every task completed so far
        # in this phase — not only the most recent parallel batch — so a
        # later agent's {{<phase>_<provider>}} placeholder can also resolve
        # to an earlier sequential agent's own output. Rebuilt fresh each
        # iteration rather than accumulated, so it always reflects exactly
        # what's confirmed done right now (a task still running, e.g. a
        # third parallel agent spawned but not yet awaited, is correctly
        # left out until its own .done marker appears).
        sib_providers=()
        sib_outputs=()
        if [[ ${#skipped_providers[@]} -gt 0 ]]; then
            sib_providers=("${skipped_providers[@]}")
            sib_outputs=("${skipped_outputs[@]}")
        fi
        local _sib_idx _sib_task _sib_provider _sib_file
        for (( _sib_idx=0; _sib_idx<${#spawned_tasks[@]}; _sib_idx++ )); do
            _sib_task="${spawned_tasks[$_sib_idx]}"
            _sib_provider="${spawned_providers[$_sib_idx]}"
            # Only trust a result written after its .done marker was
            # observed — a file that exists but whose marker never appeared
            # may still be mid-write.
            [[ -f "${done_dir}/${_sib_task}.done" ]] || continue
            _sib_file=$(ls "$RESULTS_DIR"/*-"${_sib_task}".md 2>/dev/null | head -n1)
            [[ -n "$_sib_file" && -f "$_sib_file" ]] || continue
            if ! verify_result_integrity "$_sib_file"; then
                log "WARN" "Skipping tampered sibling result: $_sib_file"
                continue
            fi
            sib_providers+=("$_sib_provider")
            sib_outputs+=("$(cat "$_sib_file")")
        done

        # Resolve prompt template, including any same-phase sibling outputs
        # gathered above.
        local agent_prompt
        agent_prompt=$(yaml_get_agent_prompt "$yaml_file" "$phase_name" "$provider")
        if [[ -n "$agent_prompt" ]]; then
            local sibling_args=()
            local _si
            for (( _si=0; _si<${#sib_providers[@]}; _si++ )); do
                sibling_args+=("${phase_name}_${sib_providers[$_si]}" "${sib_outputs[$_si]}")
            done
            if [[ ${#sibling_args[@]} -gt 0 ]]; then
                agent_prompt=$(resolve_prompt_template "$agent_prompt" "$prompt" "$previous_output" "${sibling_args[@]}")
            else
                agent_prompt=$(resolve_prompt_template "$agent_prompt" "$prompt" "$previous_output")
            fi
            # Only flag a placeholder shaped like this phase's own
            # {{<phase_name>_<provider>}} sibling-var convention — a blind
            # "any {{...}} left" scan would also trip on literal
            # double-curly-brace text substituted verbatim via {{prompt}} or
            # {{grasp_consensus}}/{{tangle_implementation}} (a user's own
            # request or a prior phase's AI output quoting a Jinja/Helm/GH
            # Actions template), which is not a resolution failure at all.
            if [[ "$agent_prompt" =~ \{\{${phase_name}_[A-Za-z0-9_-]+\}\} ]]; then
                log "ERROR" "Phase $phase_name: unresolved sibling template placeholder in $provider prompt — halting phase"
                # Drain any parallel siblings already spawned earlier in this
                # phase and close out fleet_dispatch_begin so this early exit
                # doesn't orphan background PIDs or leave dispatch state
                # (e.g. OCTOPUS_FORCE_LEGACY_DISPATCH) stuck for later phases.
                if [[ ${#pids[@]} -gt 0 ]]; then
                    _yaml_wait_for_pids "${TIMEOUT:-600}" "${pids[@]}"
                fi
                fleet_dispatch_end
                return 1
            fi
        else
            # Fallback: construct prompt from role
            agent_prompt="$role: $prompt"
            if [[ -n "$previous_output" ]]; then
                agent_prompt="$agent_prompt

Previous phase output:
$previous_output"
            fi
        fi

        if [[ "$is_parallel" == "true" ]]; then
            local pid
            pid=$(spawn_agent_capture_pid "$agent_type" "$agent_prompt" "$task_id" "$role" "$phase_name")
            pids+=("$pid")
        else
            # spawn_agent backgrounds the provider internally, so capture the
            # PID and block until it exits. Without this the phase synthesized
            # and moved on while its sequential agent was still running, losing
            # that agent's output from the synthesis handed to the next phase.
            local seq_pid
            seq_pid=$(spawn_agent_capture_pid "$agent_type" "$agent_prompt" "$task_id" "$role" "$phase_name")
            _yaml_wait_for_pids "${TIMEOUT:-600}" "$seq_pid"
        fi
        spawned_tasks+=("$task_id")
        spawned_providers+=("$provider")

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

    # Result files land shortly after the provider PIDs exit; wait for the
    # completion markers so the collection below sees every agent's output.
    if [[ ${#spawned_tasks[@]} -gt 0 ]]; then
        local marker_wait="${OCTOPUS_YAML_DONE_WAIT:-30}"
        _yaml_wait_for_done_markers "$marker_wait" "${spawned_tasks[@]}" \
            || log "WARN" "Phase $phase_name: not all completion markers appeared within ${marker_wait}s"
    fi

    # Record completions in the bridge ledger. bridge_evaluate_gate reads
    # completed_tasks from the ledger, but nothing ever marked tasks complete,
    # so every gate evaluated as 0/N and "did not pass" on every phase.
    local done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"
    local _task_id _agent_exit
    if [[ ${#spawned_tasks[@]} -gt 0 ]]; then
        for _task_id in "${spawned_tasks[@]}"; do
            [[ -f "${done_dir}/${_task_id}.done" ]] || continue
            _agent_exit=$(cat "${done_dir}/${_task_id}.done" 2>/dev/null)
            if [[ "$_agent_exit" == "0" ]]; then
                bridge_mark_task_complete "$_task_id" "completed" 2>/dev/null || true
            else
                bridge_mark_task_complete "$_task_id" "failed" 2>/dev/null || true
            fi
        done
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

    # Evaluate quality gate: results produced vs agents spawned
    local qg_threshold
    qg_threshold=$(yaml_get_phase_config "$yaml_file" "$phase_name" "threshold") || qg_threshold="0.5"
    local result_count=0
    [[ -n "$result_files" ]] && result_count=$(echo "$result_files" | wc -l | tr -d ' ')
    local spawned_count=${#spawned_tasks[@]}

    local gate_passed=false
    if [[ $spawned_count -gt 0 && $result_count -gt 0 ]]; then
        if awk -v r="$result_count" -v s="$spawned_count" -v t="$qg_threshold" \
               'BEGIN { exit !((r / s) >= t) }'; then
            gate_passed=true
        fi
    fi

    if [[ "$gate_passed" == "true" ]]; then
        log "INFO" "Phase $phase_name quality gate PASSED: $result_count/$spawned_count results (threshold: $qg_threshold)"
    else
        log "ERROR" "Phase $phase_name quality gate FAILED: $result_count/$spawned_count results (threshold: $qg_threshold)"
    fi

    log "INFO" "YAML Runtime: Phase '$phase_name' complete ($result_count agent results)"

    # v8.7.0: Generate phase summary for bridge and refresh provider stats
    bridge_generate_phase_summary "$phase_name" "$synthesis_file"
    bridge_evaluate_gate "$phase_name" 2>/dev/null \
        || log "DEBUG" "Bridge ledger gate did not pass for $phase_name"
    refresh_provider_stats

    echo "$synthesis_file"
    [[ "$gate_passed" == "true" ]]
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

        # Progress lines to stderr: run_yaml_workflow's stdout is captured by
        # the caller and must carry only the final synthesis file path.
        {
            echo ""
            local phase_upper
            phase_upper=$(echo "$phase_name" | tr '[:lower:]' '[:upper:]')
            echo -e "${CYAN}[${phase_num}/${phase_count}] Starting ${phase_upper} phase...${NC}"
            echo ""
        } >&2

        # Update workflow state
        export OCTOPUS_WORKFLOW_PHASE="$phase_name"
        export OCTOPUS_COMPLETED_PHASES=$((phase_num - 1))

        # Update session.json for hooks
        local session_dir="${HOME}/.claude-octopus"
        if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
            local phase_start_tmp=""
            if phase_start_tmp=$(mktemp "$session_dir/session.json.tmp.XXXXXX"); then
                jq --arg phase "$phase_name" --arg status "running" \
               --argjson completed "$((phase_num - 1))" \
               '.current_phase = $phase | .phase_status = $status | .completed_phases = $completed' \
               "$session_dir/session.json" > "$phase_start_tmp" \
               && mv "$phase_start_tmp" "$session_dir/session.json" 2>/dev/null || rm -f "$phase_start_tmp"
            fi
        fi

        # Read previous phase output if available
        if [[ -n "$previous_output" && -f "$previous_output" ]]; then
            local prev_content
            prev_content=$(head -c 8000 "$previous_output" 2>/dev/null) || prev_content=""
        else
            local prev_content=""
        fi

        # Execute phase — halt the workflow when a phase's quality gate fails
        # (fail fast; later phases would only compound on missing output)
        local phase_result
        if ! phase_result=$(execute_workflow_phase "$yaml_file" "$phase_name" "$prompt" "$prev_content" "$task_group"); then
            log "ERROR" "YAML Runtime: Halting workflow '$workflow_name' — phase '$phase_name' failed its quality gate"
            if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
                local phase_failed_tmp=""
                if phase_failed_tmp=$(mktemp "$session_dir/session.json.tmp.XXXXXX"); then
                    jq --arg phase "$phase_name" --arg status "failed" \
                   '.current_phase = $phase | .phase_status = $status |
                    .quality_gates = {passed: false, failed: true}' \
                   "$session_dir/session.json" > "$phase_failed_tmp" \
                   && mv "$phase_failed_tmp" "$session_dir/session.json" 2>/dev/null || rm -f "$phase_failed_tmp"
                fi
            fi
            return 1
        fi

        previous_output="$phase_result"
        all_outputs+=("$phase_result")

        # Update session state
        if command -v jq &>/dev/null && [[ -f "$session_dir/session.json" ]]; then
            local phase_complete_tmp=""
            if phase_complete_tmp=$(mktemp "$session_dir/session.json.tmp.XXXXXX"); then
                jq --arg phase "$phase_name" --arg status "completed" \
               --argjson completed "$phase_num" \
               '.current_phase = $phase | .phase_status = $status | .completed_phases = $completed' \
               "$session_dir/session.json" > "$phase_complete_tmp" \
               && mv "$phase_complete_tmp" "$session_dir/session.json" 2>/dev/null || rm -f "$phase_complete_tmp"
            fi
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
