#!/usr/bin/env bash
# Execute portable task waves through the existing validation and dispatch paths.
source "${BASH_SOURCE[0]%/*}/feature-tasks.sh"

_feature_tasks_json_digest() {
    python3 - "$1" <<'PY'
import hashlib,json,sys
with open(sys.argv[1], "rb") as handle:
    raw=handle.read(2*1024*1024+1)
if len(raw)>2*1024*1024: sys.exit(2)
value=json.loads(raw)
print("sha256:"+hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",", ":"),ensure_ascii=True).encode()).hexdigest())
PY
}

_feature_tasks_validate_wave() {
    local target="$1" source_root="${FEATURE_SOURCE_ROOT:-${PROJECT_ROOT:-$PWD}}"
    [[ "$(_feature_tasks_json_digest "$FEATURE_TASK_CONTRACT")" == "$FEATURE_TASK_CONTRACT_SEAL" ]] || return 2
    octopus_feature_tasks_wave --root "${PROJECT_ROOT:-$PWD}" --source-root "$source_root" \
        --contract "$FEATURE_TASK_CONTRACT" --completed "$FEATURE_TASK_COMPLETION" \
        --limit "$FEATURE_TASK_WAVE_LIMIT" > "$target"
}

feature_tasks_revalidate_active_wave() {
    local check="${FEATURE_TASK_SCHEDULER_DIR}/pre-dispatch.json" snapshot
    _feature_tasks_validate_wave "$check" || return 1
    snapshot=$(jq -r '.snapshot_digest // empty' "$check") || return 1
    [[ -n "$snapshot" && "$snapshot" == "$OCTOPUS_FEATURE_WAVE_SNAPSHOT" ]] || {
        log WARN "Feature task paths or Git state changed before dispatch; preserving a partial result"
        return 1
    }
    [[ "$(_feature_tasks_json_digest "$OCTOPUS_FEATURE_WAVE_JSON")" == "$OCTOPUS_FEATURE_WAVE_SEAL" ]] || return 1
    [[ "$(_feature_tasks_json_digest "$OCTOPUS_FEATURE_WAVE_DECOMPOSITION")" == "$OCTOPUS_FEATURE_DECOMPOSITION_SEAL" ]] || return 1
    [[ "$(_feature_tasks_json_digest "$OCTOPUS_FEATURE_WAVE_IDS_FILE")" == "$OCTOPUS_FEATURE_IDS_SEAL" ]] || return 1
}

_feature_tasks_capture_wave() {
    local wave_file="$1" wave_seal="$2" status="$3" evidence="$4" next
    next="${FEATURE_TASK_COMPLETION}.tmp"
    [[ "$(_feature_tasks_json_digest "$FEATURE_TASK_CONTRACT")" == "$FEATURE_TASK_CONTRACT_SEAL" ]] || return 1
    octopus_feature_tasks capture --root "${PROJECT_ROOT:-$PWD}" --contract "$FEATURE_TASK_CONTRACT" \
        --wave "$wave_file" --wave-digest "$wave_seal" --completed "$FEATURE_TASK_COMPLETION" \
        --status "$status" --evidence "$evidence" > "$next" || return 1
    mv -f "$next" "$FEATURE_TASK_COMPLETION" || return 1
    _feature_tasks_publish_completion
}


_feature_tasks_publish_completion() {
    if declare -F feature_workflow_tasks_completed >/dev/null 2>&1; then
        feature_workflow_tasks_completed "$FEATURE_TASK_COMPLETION" || {
            log WARN "Portable completion publication failed; preserving the runtime proof for recovery"
            return 1
        }
    fi
}

_feature_tasks_resume() {
    [[ -n "${FEATURE_TASK_HISTORY_COMPLETION:-}" ]] || return 0
    local candidates="${FEATURE_TASK_SCHEDULER_DIR}/resume-candidates.json"
    local recheck="${FEATURE_TASK_SCHEDULER_DIR}/resume-recheck.json" candidates_seal next
    if [[ -z "${FEATURE_RESUME_BASELINE:-}" ]] || ! declare -F feature_workflow_verify_resume >/dev/null 2>&1; then
        log WARN "Historical task completion has no current repository verifier or baseline; keeping it pending"
        return 0
    fi
    if ! octopus_feature_tasks resume --root "${PROJECT_ROOT:-$PWD}" --source-root "${FEATURE_SOURCE_ROOT:-${PROJECT_ROOT:-$PWD}}" \
        --contract "$FEATURE_TASK_CONTRACT" --history "$FEATURE_TASK_HISTORY_COMPLETION" --baseline "$FEATURE_RESUME_BASELINE" > "$candidates"; then
        log WARN "Historical task scope could not be verified against committed HEAD; keeping it pending"
        return 0
    fi
    if [[ "$(jq '.rejected|length' "$candidates")" -gt 0 ]]; then
        log WARN "Historical task identities or committed scope did not match; rejected completion stays pending"
    fi
    if [[ "$(jq '.tasks|length' "$candidates")" -eq 0 ]]; then
        log WARN "No matching committed historical task evidence was found; keeping tasks pending"
        return 0
    fi
    candidates_seal=$(_feature_tasks_json_digest "$candidates") || return 1
    if ! feature_workflow_verify_resume "$candidates" "$FEATURE_RESUME_BASELINE"; then
        log WARN "Fresh repository validation did not pass; historical tasks remain pending"
        return 0
    fi
    if [[ "$(_feature_tasks_json_digest "$FEATURE_TASK_CONTRACT")" != "$FEATURE_TASK_CONTRACT_SEAL" ]] || \
       [[ "$(_feature_tasks_json_digest "$candidates")" != "$candidates_seal" ]] || \
       ! octopus_feature_tasks resume --root "${PROJECT_ROOT:-$PWD}" --source-root "${FEATURE_SOURCE_ROOT:-${PROJECT_ROOT:-$PWD}}" \
            --contract "$FEATURE_TASK_CONTRACT" --history "$FEATURE_TASK_HISTORY_COMPLETION" --baseline "$FEATURE_RESUME_BASELINE" > "$recheck" || \
       [[ "$(_feature_tasks_json_digest "$recheck")" != "$candidates_seal" ]]; then
        log WARN "Historical scope, contract or HEAD changed during verification; keeping completion pending"
        return 0
    fi
    next="${FEATURE_TASK_COMPLETION}.tmp"
    jq '{contract_digest:.contract_digest,tasks:[.tasks[]|{id,identity,status,contract_digest,parent_verified:true,evidence:("resume:" + .evidence.run_id),historical_evidence:.evidence}]}' "$recheck" > "$next" || return 1
    mv -f "$next" "$FEATURE_TASK_COMPLETION" || return 1
    _feature_tasks_publish_completion
}

_feature_tasks_agent() {
    local kind="$1" profile='' coding_role='' default=''
    if [[ "$kind" == "reasoning" ]]; then
        profile=reasoning; coding_role=researcher; default=agy
    else
        profile=coding; coding_role=implementer; default=codex
    fi
    if declare -F octopus_execution_profile_provider >/dev/null 2>&1; then
        octopus_execution_profile_provider tangle "$profile" "$coding_role" "$default"
    else
        printf '%s\n' "$default"
    fi
}

_feature_tasks_reasoning_wave() {
    local wave_file="$1" run_group="$2" original_prompt="$3" task tid agent output task_prompt rc=0
    feature_tasks_revalidate_active_wave || return 1
    while IFS= read -r task; do
        tid=$(jq -r '.id' <<< "$task") || return 1
        agent=$(_feature_tasks_agent reasoning) || return 1
        output="${FEATURE_TASK_SCHEDULER_DIR}/${run_group}-${tid}.md"
        task_prompt="${original_prompt}
Assigned reasoning contract: ${task}
Use Reads only as read-only context; return the reasoning result without editing repository files."
        if ! run_agent_sync_consultative "$agent" "$task_prompt" \
            "${OCTOPUS_FEATURE_REASONING_TIMEOUT:-120}" researcher tangle > "$output" || \
            [[ -z "$(tr -d '[:space:]' < "$output")" ]]; then
            rc=1
        fi
    done < <(jq -c '.selected[]' "$wave_file")
    return "$rc"
}

_feature_tasks_parallel_wave() {
    local wave_file="$1" run_group="$2" source_tasks="$3" original_prompt="$4" wire manifest before before_state start_head legacy
    local task tid kind agent role prompt assigned index rc=0
    wire=$(tangle_render_json_decomposition_output "$(<"$OCTOPUS_FEATURE_WAVE_DECOMPOSITION")") || return 1
    manifest=$(tangle_scope_manifest_digest "$wire") || return 1
    tangle_require_execution_boundary || return 125
    before="${FEATURE_TASK_SCHEDULER_DIR}/${run_group}-before.txt"
    before_state="${FEATURE_TASK_SCHEDULER_DIR}/${run_group}-before-state.txt"
    snapshot_tangle_worktree_paths > "$before" || return 1
    snapshot_tangle_worktree_state > "$before_state" || return 1
    start_head=$(git -C "${PROJECT_ROOT:-$PWD}" rev-parse HEAD) || return 1
    local TANGLE_WORKTREE_BEFORE_PATHS_DIGEST TANGLE_WORKTREE_BEFORE_STATE_DIGEST
    TANGLE_WORKTREE_BEFORE_PATHS_DIGEST=$(tangle_file_digest "$before") || return 1
    TANGLE_WORKTREE_BEFORE_STATE_DIGEST=$(tangle_file_digest "$before_state") || return 1
    local OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true OCTOPUS_TANGLE_WORKTREE="${PROJECT_ROOT:-$PWD}"
    local OCTOPUS_TANGLE_RESULTS_DIR="$RESULTS_DIR"
    export OCTOPUS_TANGLE_EXECUTION_BOUNDARY OCTOPUS_TANGLE_WORKTREE OCTOPUS_TANGLE_RESULTS_DIR
    export TANGLE_WORKTREE_BEFORE_PATHS_DIGEST TANGLE_WORKTREE_BEFORE_STATE_DIGEST
    legacy="${FEATURE_TASK_SCHEDULER_DIR}/${run_group}-parallel.json"
    jq -n '{tasks:[]}' > "$legacy" || return 1
    while IFS= read -r task; do
        tid=$(jq -r '.id' <<< "$task") || return 1
        kind=$(jq -r '.kind' <<< "$task") || return 1
        agent=""
        if [[ -f "$source_tasks" ]]; then
            agent=$(jq -r --arg id "$tid" '.tasks[]? | select(.id == $id) | .agent // empty' "$source_tasks" 2>/dev/null | head -1) || true
        fi
        [[ -n "$agent" ]] || agent=$(_feature_tasks_agent "$kind") || return 1
        role=implementer
        [[ "$kind" != reasoning ]] || role=researcher
        index=$(jq -r '.execution_index' <<< "$task") || return 1
        assigned=$(printf '%s\n' "$wire" | sed -n "${index}p") || return 1
        prompt=$(build_tangle_subtask_prompt "$original_prompt" "$assigned") || return 1
        jq --arg id "tangle-${run_group}-${tid}" --arg agent "$agent" --arg prompt "$prompt" --arg role "$role" \
            '.tasks += [{id:$id,agent:$agent,prompt:$prompt,role:$role}]' "$legacy" > "${legacy}.tmp" && mv "${legacy}.tmp" "$legacy" || return 1
    done < <(jq -c '.selected[]' "$wave_file")
    feature_tasks_revalidate_active_wave || return 1
    local OCTOPUS_FEATURE_PARALLEL_WAVE_ACTIVE=true
    local OCTOPUS_PARALLEL_REPORT_FILE="${FEATURE_TASK_SCHEDULER_DIR}/${run_group}-parallel-report.json"
    export OCTOPUS_FEATURE_PARALLEL_WAVE_ACTIVE OCTOPUS_PARALLEL_REPORT_FILE
    parallel_execute "$legacy" || rc=$?
    [[ "$rc" -eq 0 ]] && jq -e '.status == "complete" and .counts.failed == 0 and .counts.skipped == 0' \
        "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null || return 1
    local expected_ids
    expected_ids=$(jq -r '.tasks[].id' "$legacy") || return 1
    tangle_validate_results_with_scope_contract "$run_group" "$original_prompt" \
        "$before" "$wire" "$start_head" "$manifest" "$before_state" "$expected_ids"
}

_feature_tasks_execute() {
    local mode="$1" prompt="$2" grasp_file="$3" task_group="$4" plan_file="$5" source_tasks="${6:-}"
    local grasp_results_root="${7:-}"
    local total wave_number=0 wave_file wave_seal gate_subset task tid wave_rc=0 remaining selected_count
    local FEATURE_TASK_SCHEDULER_DIR FEATURE_TASK_WAVE_LIMIT FEATURE_TASK_COMPLETION FEATURE_TASK_REPORT FEATURE_TASK_CONTRACT_SEAL
    FEATURE_TASK_SCHEDULER_DIR="${FEATURE_RUNTIME_DIR:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}/features}/task-runs/${task_group}"
    mkdir -p "$FEATURE_TASK_SCHEDULER_DIR" || return 1
    FEATURE_TASK_WAVE_LIMIT="${MAX_PARALLEL:-6}"
    [[ "$FEATURE_TASK_WAVE_LIMIT" =~ ^[1-9][0-9]*$ ]] || return 1
    (( FEATURE_TASK_WAVE_LIMIT <= 6 )) || FEATURE_TASK_WAVE_LIMIT=6
    FEATURE_TASK_COMPLETION="${FEATURE_TASK_SCHEDULER_DIR}/completed.json"
    FEATURE_TASK_REPORT="${FEATURE_TASK_SCHEDULER_DIR}/summary.json"
    FEATURE_TASK_CONTRACT_SEAL=$(_feature_tasks_json_digest "$FEATURE_TASK_CONTRACT") || return 2
    jq -n --arg digest "$(jq -r '.contract_digest' "$FEATURE_TASK_CONTRACT")" \
        '{contract_digest:$digest,tasks:[]}' > "$FEATURE_TASK_COMPLETION" || return 1
    total=$(jq '.tasks | length' "$FEATURE_TASK_CONTRACT") || return 1
    [[ "$total" =~ ^[1-9][0-9]*$ && "$total" -le 256 ]] || return 1
    export FEATURE_TASK_SCHEDULER_DIR FEATURE_TASK_WAVE_LIMIT FEATURE_TASK_COMPLETION FEATURE_TASK_REPORT FEATURE_TASK_CONTRACT_SEAL
    _feature_tasks_resume || return 1
    while (( wave_number < total )); do
        wave_number=$((wave_number + 1))
        wave_file="${FEATURE_TASK_SCHEDULER_DIR}/wave-${wave_number}.json"
        if ! _feature_tasks_validate_wave "$wave_file"; then
            log WARN "Portable task metadata could not be validated; keeping requested work pending"
            return 2
        fi
        selected_count=$(jq '.selected|length' "$wave_file") || return 1
        [[ "$selected_count" -gt 0 ]] || break
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log INFO "[DRY-RUN] Validated portable task wave: $(jq -r '.selected[].id' "$wave_file" | tr '\n' ' ')"
            return 0
        fi
        gate_subset="${FEATURE_TASK_SCHEDULER_DIR}/gate-blocked.json"
        jq '.selected = []' "$wave_file" > "$gate_subset" || return 1
        if declare -F feature_workflow_gate >/dev/null 2>&1; then
            while IFS= read -r task; do
                tid=$(jq -r '.id' <<< "$task") || return 1
                if ! feature_workflow_gate develop "$tid"; then
                    jq --argjson task "$task" '.selected += [$task]' "$gate_subset" > "${gate_subset}.tmp" && \
                        mv "${gate_subset}.tmp" "$gate_subset" || return 1
                fi
            done < <(jq -c '.selected[]' "$wave_file")
            if [[ "$(jq '.selected|length' "$gate_subset")" -gt 0 ]]; then
                _feature_tasks_capture_wave "$gate_subset" "$(_feature_tasks_json_digest "$gate_subset")" blocked "gate:${task_group}" || return 1
                continue
            fi
        fi
        local OCTOPUS_FEATURE_WAVE_ACTIVE=true OCTOPUS_FEATURE_WAVE_DECOMPOSITION
        local OCTOPUS_TANGLE_WRITE_SCOPE_MODE=strict
        local OCTOPUS_FEATURE_WAVE_IDS_FILE OCTOPUS_FEATURE_WAVE_JSON="$wave_file"
        local OCTOPUS_FEATURE_WAVE_SEAL OCTOPUS_FEATURE_WAVE_SNAPSHOT OCTOPUS_FEATURE_DECOMPOSITION_SEAL OCTOPUS_FEATURE_IDS_SEAL
        OCTOPUS_FEATURE_WAVE_DECOMPOSITION="${FEATURE_TASK_SCHEDULER_DIR}/wave-${wave_number}-decomposition.json"
        OCTOPUS_FEATURE_WAVE_IDS_FILE="${FEATURE_TASK_SCHEDULER_DIR}/wave-${wave_number}-ids.json"
        jq '.decomposition' "$wave_file" > "$OCTOPUS_FEATURE_WAVE_DECOMPOSITION" || return 1
        jq '[.selected[].id]' "$wave_file" > "$OCTOPUS_FEATURE_WAVE_IDS_FILE" || return 1
        OCTOPUS_FEATURE_WAVE_SEAL=$(_feature_tasks_json_digest "$wave_file") || return 1
        OCTOPUS_FEATURE_WAVE_SNAPSHOT=$(jq -r '.snapshot_digest' "$wave_file") || return 1
        OCTOPUS_FEATURE_DECOMPOSITION_SEAL=$(_feature_tasks_json_digest "$OCTOPUS_FEATURE_WAVE_DECOMPOSITION") || return 1
        OCTOPUS_FEATURE_IDS_SEAL=$(_feature_tasks_json_digest "$OCTOPUS_FEATURE_WAVE_IDS_FILE") || return 1
        export OCTOPUS_FEATURE_WAVE_ACTIVE OCTOPUS_FEATURE_WAVE_DECOMPOSITION OCTOPUS_FEATURE_WAVE_IDS_FILE
        export OCTOPUS_TANGLE_WRITE_SCOPE_MODE
        export OCTOPUS_FEATURE_WAVE_JSON OCTOPUS_FEATURE_WAVE_SEAL OCTOPUS_FEATURE_WAVE_SNAPSHOT OCTOPUS_FEATURE_DECOMPOSITION_SEAL OCTOPUS_FEATURE_IDS_SEAL
        wave_seal="$OCTOPUS_FEATURE_WAVE_SEAL"
        local run_group="${task_group}-wave-${wave_number}" wave_prompt
        wave_prompt="Execute ONLY the task contracts in this wave. Preserve the original intent as context, and leave other feature tasks pending.
Selected contracts: $(jq -c '.selected' "$wave_file")
Original feature intent: $prompt"
        wave_rc=0
        if [[ "$(jq -r '.decomposition == null' "$wave_file")" == true ]]; then
            _feature_tasks_reasoning_wave "$wave_file" "$run_group" "$wave_prompt" || wave_rc=$?
        elif [[ "$mode" == tangle ]]; then
            _tangle_develop_in_workspace "$wave_prompt" "$grasp_file" "$run_group" "$plan_file" "$grasp_results_root" || wave_rc=$?
        else
            _feature_tasks_parallel_wave "$wave_file" "$run_group" "$source_tasks" "$wave_prompt" || wave_rc=$?
        fi
        if [[ "$wave_rc" -eq 0 ]]; then
            _feature_tasks_capture_wave "$wave_file" "$wave_seal" completed "run:${run_group}" || return 1
        else
            _feature_tasks_capture_wave "$wave_file" "$wave_seal" failed "run:${run_group}" || return 1
        fi
    done
    _feature_tasks_validate_wave "${FEATURE_TASK_SCHEDULER_DIR}/final-wave.json" || return 2
    remaining=$(jq --slurpfile completed "$FEATURE_TASK_COMPLETION" \
        '[.tasks[] | .id as $id | select([$completed[0].tasks[] | select(.status == "completed" and .parent_verified == true) | .id] | index($id) | not)] | length' "$FEATURE_TASK_CONTRACT") || return 1
    jq --arg status "$([[ "$remaining" -eq 0 ]] && echo complete || echo partial)" \
        --slurpfile completed "$FEATURE_TASK_COMPLETION" \
        '{schema_version:1,status:$status,contract_digest:.contract_digest,completion_records:$completed[0].tasks,completed:[$completed[0].tasks[]|select(.status == "completed")],blocked_pending:.blocked_pending,serial_reasons:.serial_reasons}' \
        "${FEATURE_TASK_SCHEDULER_DIR}/final-wave.json" > "$FEATURE_TASK_REPORT" || return 1
    log INFO "Portable task run $([[ "$remaining" -eq 0 ]] && echo complete || echo partial): $FEATURE_TASK_REPORT"
    FEATURE_LAST_TASK_REPORT="$FEATURE_TASK_REPORT"
    FEATURE_LAST_TASK_COMPLETION="$FEATURE_TASK_COMPLETION"
    export FEATURE_LAST_TASK_REPORT FEATURE_LAST_TASK_COMPLETION
    [[ "$remaining" -eq 0 ]]
}

feature_tasks_tangle_execute() {
    _feature_tasks_execute tangle "$1" "${2:-}" "$3" "${4:-}" "" "${5:-}"
}

feature_tasks_parallel_execute() {
    local tasks_file="$1" run_group
    run_group="feature-parallel-$(date +%s)-$$"
    _feature_tasks_execute parallel "Implement the selected portable feature tasks." "" "$run_group" "" "$tasks_file"
}
