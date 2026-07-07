#!/usr/bin/env bash
# error-tracking.sh — Extracted from orchestrate.sh
# Functions: record_error, update_task_progress, get_active_form_verb,
#            write_agent_status, render_agent_summary, record_oversize_event

if ! type probe_result_file_status >/dev/null 2>&1; then
    _octo_probe_results_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probe-results.sh"
    [[ -f "$_octo_probe_results_lib" ]] && source "$_octo_probe_results_lib"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# UX ENHANCEMENTS: Feature 1 - Enhanced Spinner Verbs (v7.16.0)
# Dynamic task progress updates with context-aware verbs
# ═══════════════════════════════════════════════════════════════════════════════

# Update Claude Code task progress with activeForm
update_task_progress() {
    local task_id="$1"
    local active_form="$2"

    # Skip if task progress disabled or missing parameters
    if [[ "$TASK_PROGRESS_ENABLED" != "true" ]]; then
        log DEBUG "Task progress disabled - skipping update"
        return 0
    fi

    if [[ -z "$task_id" || -z "$active_form" ]]; then
        log DEBUG "Missing task_id or active_form - skipping update"
        return 0
    fi

    if [[ -z "${CLAUDE_CODE_CONTROL_PIPE:-}" ]]; then
        log DEBUG "CLAUDE_CODE_CONTROL_PIPE not set - skipping update"
        return 0
    fi

    if [[ ! -p "$CLAUDE_CODE_CONTROL_PIPE" ]]; then
        log WARN "CLAUDE_CODE_CONTROL_PIPE is not a pipe: $CLAUDE_CODE_CONTROL_PIPE"
        return 1
    fi

    # Write to control pipe for Claude Code to update spinner
    echo "TASK_UPDATE:${task_id}:activeForm:${active_form}" >> "$CLAUDE_CODE_CONTROL_PIPE" 2>/dev/null || {
        log WARN "Failed to write to control pipe"
        return 1
    }

    log DEBUG "Updated task $task_id: $active_form"
    return 0
}

# Get context-aware activeForm verb for agent + phase combination
get_active_form_verb() {
    local phase="$1"
    local agent="$2"
    local prompt_context="${3:-}"  # Optional: for even more specific verbs

    # Normalize phase name (aliases to canonical names)
    case "$phase" in
        probe) phase="discover" ;;
        grasp) phase="define" ;;
        tangle) phase="develop" ;;
        ink) phase="deliver" ;;
    esac

    # Normalize agent name (remove version suffixes)
    local agent_base
    agent_base=$(echo "$agent" | sed 's/-[0-9].*$//' | sed 's/:.*//')

    # Generate phase/agent-specific verb with emoji indicators
    local verb=""
    case "$phase" in
        discover)
            case "$agent_base" in
                codex*) verb="🔴 Researching technical patterns (Codex)" ;;
                agy*|antigravity) verb="🟡 Exploring ecosystem and options (agy)" ;;
                claude*) verb="🔵 Synthesizing research findings" ;;
                *) verb="🔍 Researching and exploring" ;;
            esac
            ;;
        define)
            case "$agent_base" in
                codex*) verb="🔴 Analyzing technical requirements (Codex)" ;;
                agy*|antigravity) verb="🟡 Clarifying scope and constraints (agy)" ;;
                claude*) verb="🔵 Building consensus on approach" ;;
                *) verb="🎯 Defining requirements" ;;
            esac
            ;;
        develop)
            case "$agent_base" in
                codex*) verb="🔴 Generating implementation code (Codex)" ;;
                agy*|antigravity) verb="🟡 Exploring alternative approaches (agy)" ;;
                claude*) verb="🔵 Integrating and validating solution" ;;
                *) verb="🛠️  Developing implementation" ;;
            esac
            ;;
        deliver)
            case "$agent_base" in
                codex*) verb="🔴 Analyzing code quality (Codex)" ;;
                agy*|antigravity) verb="🟡 Testing edge cases and security (agy)" ;;
                claude*) verb="🔵 Final review and recommendations" ;;
                *) verb="✅ Validating and testing" ;;
            esac
            ;;
        *)
            verb="Processing with $agent"
            ;;
    esac

    echo "$verb"
}

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: ERROR LEARNING LOOP (Veritas-inspired)
# Structured error capture with similar-error detection and repeat flagging.
# ═══════════════════════════════════════════════════════════════════════════════

record_error() {
    local agent="$1"
    local task="$2"
    local error_msg="$3"
    local exit_code="${4:-1}"
    local attempt_desc="${5:-}"

    local error_dir="${WORKSPACE_DIR}/.octo/errors"
    local error_file="$error_dir/error-log.md"
    mkdir -p "$error_dir"

    # Cap at 100 entries: count existing, trim oldest if needed
    if [[ -f "$error_file" ]]; then
        local entry_count
        entry_count=$(grep -c "^### ERROR |" "$error_file" 2>/dev/null || echo "0")
        if [[ "$entry_count" -ge 100 ]]; then
            # Remove first entry (everything up to second ### ERROR)
            local second_entry_line
            second_entry_line=$(grep -n "^### ERROR |" "$error_file" | sed -n '2p' | cut -d: -f1)
            if [[ -n "$second_entry_line" ]]; then
                tail -n +"$second_entry_line" "$error_file" > "${error_file}.tmp" && mv "${error_file}.tmp" "$error_file"
            fi
        fi
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Sanitize error message (truncate, remove control chars)
    local safe_error="${error_msg:0:500}"
    safe_error=$(echo "$safe_error" | tr -d '\000-\011\013-\037')

    cat >> "$error_file" << ERREOF

### ERROR | $timestamp | agent: $agent | exit_code: $exit_code
**Task:** ${task:0:200}
**Error:** $safe_error
**Attempt:** ${attempt_desc:-Initial attempt}
**Root Cause:** Pending analysis
**Prevention:** Pending
---
ERREOF

    log DEBUG "Recorded error: agent=$agent, exit_code=$exit_code"
}

# Resolve the current run id for multi-provider diagnostics. Prefer the explicit
# run id when a workflow sets one, then host/session ids, then a stable fallback.
octo_current_run_id() {
    local fallback
    fallback="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    printf '%s\n' "${OCTOPUS_RUN_ID:-${OCTOPUS_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION:-$fallback}}}}}"
}

octo_run_dir() {
    local run_id
    run_id=$(octo_current_run_id)
    printf '%s\n' "${WORKSPACE_DIR:-${HOME}/.claude-octopus}/runs/${run_id}"
}

octo_estimate_tokens_for_file() {
    local file="$1"
    [[ -f "$file" ]] || { echo "0"; return; }
    local chars
    chars=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
    [[ -z "$chars" ]] && chars=0
    echo $((chars / 4))
}

octo_provider_rejection_pattern() {
    printf '%s\n' 'Prompt is too long|request entity too large|context limit|context length|tokens exceeded|too many tokens|maximum context|input is too large'
}

octo_file_has_provider_rejection() {
    local pattern
    pattern=$(octo_provider_rejection_pattern)
    local file
    for file in "$@"; do
        [[ -f "$file" ]] || continue
        if grep -qiE "$pattern" "$file" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

octo_file_has_codex_stdin_closed() {
    local stderr_file="${1:-}"
    [[ -n "$stderr_file" && -f "$stderr_file" ]] || return 1

    grep -q 'write_stdin failed: stdin is closed' "$stderr_file" 2>/dev/null
}

octo_file_has_codex_recoverable_stderr() {
    local stderr_file="${1:-}"
    [[ -n "$stderr_file" && -s "$stderr_file" ]] || return 1

    grep -qE '^# Completed:|^## Worktree Changes$|^## Integration Evidence$|^## Verification$|^tokens used$' "$stderr_file" 2>/dev/null
}

classify_agent_output() {
    local output_file="$1"
    local exit_code="${2:-0}"
    local agent="${3:-unknown}"
    local stderr_file="${4:-}"

    if [[ "$agent" == codex* ]] && octo_file_has_codex_stdin_closed "$stderr_file"; then
        echo "failed:Codex tool stdin closed (avoid write_stdin in non-interactive sessions)"
        return 0
    fi

    if [[ "$exit_code" -eq 124 || "$exit_code" -eq 143 ]]; then
        echo "timeout:Timed out before completion"
        return 0
    fi

    if [[ "$exit_code" -ne 0 ]]; then
        echo "failed:Exit code $exit_code"
        return 0
    fi

    if octo_file_has_provider_rejection "$output_file" "$stderr_file"; then
        echo "failed:Prompt rejected by provider (oversize)"
        return 0
    fi

    if [[ ! -s "$output_file" ]]; then
        if [[ "$agent" == codex* ]] && octo_file_has_codex_recoverable_stderr "$stderr_file"; then
            echo "degraded:Codex response captured on stderr"
            return 0
        fi
        echo "failed:Empty output"
        return 0
    fi

    if grep -q 'OUTPUT TRUNCATED' "$output_file" 2>/dev/null; then
        echo "degraded:Output truncated"
        return 0
    fi

    # Some CLIs exit 0 with only boilerplate after filtering.
    if ! grep -q '[[:alnum:]]' "$output_file" 2>/dev/null; then
        echo "failed:Empty output"
        return 0
    fi

    echo "ok:"
}

write_agent_run_snapshot() {
    command -v jq >/dev/null 2>&1 || return 0

    local run_id dir jsonl snapshot latest_dir
    run_id=$(octo_current_run_id)
    dir=$(octo_run_dir)
    jsonl="$dir/agents.jsonl"
    snapshot="$dir/agents.json"
    [[ -s "$jsonl" ]] || return 0

    jq -s \
        --arg run_id "$run_id" \
        --arg command "${OCTOPUS_COMMAND:-${COMMAND:-unknown}}" \
        --arg args "${OCTOPUS_COMMAND_ARGS:-}" \
        'group_by(.agent)
         | map(.[-1])
         | {
             run_id: $run_id,
             command: $command,
             args: $args,
             updated_at: (now | todate),
             agents: .
           }' \
        "$jsonl" > "${snapshot}.tmp" 2>/dev/null && mv "${snapshot}.tmp" "$snapshot"

    latest_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/runs/latest"
    rm -f "$latest_dir" 2>/dev/null || true
    ln -sfn "$dir" "$latest_dir" 2>/dev/null || true
}

write_agent_status() {
    local agent="$1"
    local status="$2"      # ok|degraded|failed|timeout|running
    local tokens_in="${3:-0}"
    local tokens_out="${4:-0}"
    local reason="${5:-}"
    local duration_ms="${6:-0}"
    local output_file="${7:-}"
    local role="${8:-}"

    local run_id dir
    run_id=$(octo_current_run_id)
    dir=$(octo_run_dir)
    mkdir -p "$dir"

    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg agent "$agent" \
            --arg role "$role" \
            --arg status "$status" \
            --arg reason "$reason" \
            --arg output_file "$output_file" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --argjson tokens_in "${tokens_in:-0}" \
            --argjson tokens_out "${tokens_out:-0}" \
            --argjson duration_ms "${duration_ms:-0}" \
            '{agent:$agent,role:$role,status:$status,tokens_in:$tokens_in,tokens_out:$tokens_out,duration_ms:$duration_ms,reason:(if ($reason|length)>0 then $reason else "" end),output_file:(if ($output_file|length)>0 then $output_file else "" end),ts:$ts}' \
            >> "$dir/agents.jsonl" 2>/dev/null || true
    else
        printf '{"agent":"%s","role":"%s","status":"%s","tokens_in":%d,"tokens_out":%d,"duration_ms":%d,"reason":"%s","output_file":"%s","ts":"%s"}\n' \
            "$agent" "$role" "$status" "$tokens_in" "$tokens_out" "$duration_ms" \
            "$reason" "$output_file" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$dir/agents.jsonl"
    fi

    write_agent_run_snapshot
}

record_oversize_event() {
    local agent="$1"
    local original_chars="$2"
    local final_chars="$3"
    local outcome="$4"

    local dir
    dir=$(octo_run_dir)
    mkdir -p "$dir"

    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg agent "$agent" \
            --arg outcome "$outcome" \
            --argjson original_chars "${original_chars:-0}" \
            --argjson final_chars "${final_chars:-0}" \
            '{ts:$ts,agent:$agent,original_chars:$original_chars,final_chars:$final_chars,outcome:$outcome}' \
            >> "$dir/oversize.jsonl" 2>/dev/null || true
    else
        printf '{"ts":"%s","agent":"%s","original_chars":%d,"final_chars":%d,"outcome":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$original_chars" "$final_chars" "$outcome" \
            >> "$dir/oversize.jsonl"
    fi
}

agent_status_output_files() {
    local filter="${1:-}"
    local dir jsonl
    dir=$(octo_run_dir)
    jsonl="$dir/agents.jsonl"
    [[ -s "$jsonl" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    jq -rs --arg filter "$filter" '
        group_by(.agent)
        | map(.[-1])
        | .[]
        | [
            .status,
            (.output_file // "")
          ]
        | @tsv
    ' "$jsonl" 2>/dev/null | while IFS=$'\t' read -r status file; do
        [[ -n "$file" && -f "$file" ]] || continue
        [[ -z "$filter" || "$file" == *"$filter"* ]] || continue
        if [[ "$status" == "ok" || "$status" == "degraded" || "$status" == "timeout" ]]; then
            printf '%s\n' "$file"
        elif [[ "$status" == "running" ]] && probe_result_file_is_usable "$file"; then
            printf '%s\n' "$file"
        fi
    done
}

render_agent_summary() {
    local dir jsonl
    dir=$(octo_run_dir)
    jsonl="$dir/agents.jsonl"
    [[ -s "$jsonl" ]] || return 0

    command -v jq >/dev/null 2>&1 || {
        echo "Agent run summary: $jsonl"
        return 0
    }

    local rows ok degraded failed timeout total
    local reconciled_rows=""
    while IFS=$'\t' read -r agent status tokens_out seconds reason output_file; do
        [[ -z "$agent" ]] && continue

        if [[ "$status" == "running" && -n "$output_file" && -f "$output_file" ]]; then
            local classification probe_status probe_reason output_chars
            classification="$(probe_result_file_status "$output_file")"
            probe_status="${classification%%:*}"
            probe_reason="${classification#*:}"

            case "$probe_status" in
                success)
                    status="ok"
                    reason="reconciled from result file"
                    ;;
                degraded)
                    status="degraded"
                    reason="${probe_reason:-reconciled partial result}"
                    ;;
                timeout)
                    status="timeout"
                    reason="${probe_reason:-reconciled timeout result}"
                    ;;
                failed)
                    status="failed"
                    reason="${probe_reason:-reconciled failed result}"
                    ;;
            esac

            output_chars="$(probe_result_output_chars "$output_file")"
            if [[ "$output_chars" =~ ^[0-9]+$ && "$output_chars" -gt 0 ]]; then
                tokens_out="$output_chars"
            fi
        fi

        reconciled_rows+="${agent}"$'\t'"${status}"$'\t'"${tokens_out}"$'\t'"${seconds}"$'\t'"${reason}"$'\n'
    done < <(jq -rs '
        group_by(.agent)
        | map(.[-1])
        | .[]
        | [
            .agent,
            .status,
            ((.tokens_out // 0) | tostring),
            (((.duration_ms // 0) / 1000) | floor | tostring),
            (if ((.reason // "") | length) > 0 then .reason else "-" end),
            (.output_file // "")
          ]
        | @tsv
    ' "$jsonl" 2>/dev/null) || return 0
    rows="$reconciled_rows"

    ok=$(awk -F '\t' '$2 == "ok" { n++ } END { print n + 0 }' <<< "$rows")
    degraded=$(awk -F '\t' '$2 == "degraded" { n++ } END { print n + 0 }' <<< "$rows")
    failed=$(awk -F '\t' '$2 == "failed" { n++ } END { print n + 0 }' <<< "$rows")
    timeout=$(awk -F '\t' '$2 == "timeout" { n++ } END { print n + 0 }' <<< "$rows")
    total=$((ok + degraded + failed + timeout))

    echo ""
    echo "Agent run summary"
    echo "─────────────────────────────────────────────────────────────────────"
    printf '%-22s | %-10s | %-6s | %-5s | %s\n' "Provider" "Status" "Tokens" "Time" "Reason"
    echo "─────────────────────────────────────────────────────────────────────"
    while IFS=$'\t' read -r agent status tokens_out seconds reason; do
        [[ -z "$agent" ]] && continue
        local glyph
        case "$status" in
            ok) glyph="✓" ;;
            degraded) glyph="⚠" ;;
            failed) glyph="✗" ;;
            timeout) glyph="⏱" ;;
            running) glyph="…" ;;
            *) glyph="?" ;;
        esac
        [[ ${#reason} -gt 44 ]] && reason="${reason:0:41}..."
        printf '%-22s | %s %-8s | %6s | %4ss | %s\n' "$agent" "$glyph" "$status" "$tokens_out" "$seconds" "${reason:--}"
    done <<< "$rows"
    echo ""

    if [[ $failed -gt 0 || $timeout -gt 0 ]]; then
        printf '⚠ %d of %d agents failed or timed out — synthesis should use %d available outputs. Details: %s\n' \
            "$((failed + timeout))" "$total" "$((ok + degraded + timeout))" "$dir"
        if [[ "${OCTOPUS_REQUIRE_ALL:-false}" == "true" ]]; then
            echo "Aborting: OCTOPUS_REQUIRE_ALL=true."
            return 78
        fi
    elif [[ $degraded -gt 0 ]]; then
        printf 'ℹ %d agents ran in degraded mode. Details: %s\n' "$degraded" "$dir"
    fi
}
