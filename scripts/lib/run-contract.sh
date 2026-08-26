#!/usr/bin/env bash
# run-contract.sh — Schema-versioned execution truth for provider seats.
# Source-safe: this library does not set shell options or resolve paths at load.

OCTO_RUN_SCHEMA_VERSION="10.0"
if [[ -z "${OCTO_RUN_CONTRACT_FALLBACK_ID:-}" ]]; then
    OCTO_RUN_CONTRACT_FALLBACK_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM:-0}"
fi

if ! type _octo_event_lock >/dev/null 2>&1; then
    _octo_run_events_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/events.sh"
    [[ -f "$_octo_run_events_lib" ]] && source "$_octo_run_events_lib"
fi

octo_run_contract_id() {
    printf '%s\n' "${OCTOPUS_RUN_ID:-${OCTOPUS_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION:-$OCTO_RUN_CONTRACT_FALLBACK_ID}}}}}"
}

octo_run_contract_dir() {
    local run_id contract_root
    run_id="$(octo_run_contract_id)"
    if [[ -n "${WORKSPACE_DIR:-}" ]]; then
        contract_root="$WORKSPACE_DIR"
    elif [[ -n "${TEST_TMP_DIR:-}" ]]; then
        contract_root="$TEST_TMP_DIR/run-contract-workspace"
    else
        contract_root="${HOME}/.claude-octopus"
    fi
    printf '%s\n' "${contract_root}/runs/${run_id}"
}

octo_run_contract_ledger_path() {
    printf '%s/seats.jsonl\n' "$(octo_run_contract_dir)"
}

octo_run_contract_snapshot_path() {
    printf '%s/seats.json\n' "$(octo_run_contract_dir)"
}

octo_run_transition_valid() {
    local from="${1:-}" to="${2:-}"
    case "${from}:${to}" in
        :planned|planned:starting|starting:authenticated|authenticated:running|running:output_received|output_received:validated|validated:contributed) return 0 ;;
        planned:skipped|planned:failed|starting:failed|starting:cancelled|authenticated:failed|authenticated:cancelled|running:degraded|running:skipped|running:failed|running:timeout|running:cancelled|output_received:degraded|output_received:failed|output_received:cancelled|validated:degraded|validated:failed|validated:cancelled) return 0 ;;
        *) return 1 ;;
    esac
}

_octo_run_terminal() {
    case "${1:-}" in
        contributed|degraded|skipped|failed|timeout|cancelled) return 0 ;;
        *) return 1 ;;
    esac
}

_octo_run_output_usable_file() {
    local output_file="${1:-}" normalized
    [[ -n "$output_file" && -f "$output_file" ]] || return 1
    LC_ALL=C grep -q '[^[:space:]]' "$output_file" 2>/dev/null || return 1

    normalized="$(tr '[:upper:]' '[:lower:]' < "$output_file" 2>/dev/null | tr -s '[:space:]' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$normalized" in
        "provider available"|"provider is available") return 1 ;;
    esac
    return 0
}

_octo_run_latest_record() {
    local seat_id="${1:-}" ledger record
    ledger="$(octo_run_contract_ledger_path)"
    [[ -n "$seat_id" && -s "$ledger" ]] || return 1
    record="$(jq -sc --arg seat_id "$seat_id" \
        '[.[] | select(.seat_id == $seat_id)] | last // empty' \
        "$ledger" 2>/dev/null)" || return 1
    [[ -n "$record" ]] || return 1
    printf '%s\n' "$record"
}

run_contract_latest_transition() {
    local record
    record="$(_octo_run_latest_record "${1:-}")" || return 1
    jq -er '.transition' <<< "$record" 2>/dev/null
}

run_contract_output_usable() {
    local record output_file
    record="$(_octo_run_latest_record "${1:-}")" || return 1
    output_file="$(jq -er '.artifacts.output // empty' <<< "$record" 2>/dev/null)" || return 1
    _octo_run_output_usable_file "$output_file"
}

run_contract_contribution_eligible() {
    local record
    record="$(_octo_run_latest_record "${1:-}")" || return 1
    jq -e '
        (.transition == "contributed" and .contribution == "eligible") or
        (.transition == "degraded" and .contribution == "eligible-with-warning")
    ' <<< "$record" >/dev/null 2>&1
}

# Return 0 when exactly one seat owns this artifact and its latest transition
# permits synthesis, 1 when a matching seat exists but is ineligible or the
# artifact is ambiguous, and 2 when no v10 contract record owns the file.
run_contract_output_file_eligible() {
    local output_file="${1:-}" ledger records count
    ledger="$(octo_run_contract_ledger_path)"
    [[ -n "$output_file" && -s "$ledger" ]] || return 2
    records="$(jq -sc --arg output "$output_file" '
        reduce .[] as $record ({}; .[$record.seat_id] = $record)
        | [.[] | select(.artifacts.output == $output)]
    ' "$ledger" 2>/dev/null)" || return 1
    count="$(jq -r 'length' <<< "$records" 2>/dev/null)" || return 1
    [[ "$count" -gt 0 ]] || return 2
    [[ "$count" -eq 1 ]] || return 1
    jq -e '
        (.[0].transition == "contributed" and .[0].contribution == "eligible") or
        (.[0].transition == "degraded" and .[0].contribution == "eligible-with-warning")
    ' <<< "$records" >/dev/null 2>&1
}

# Finalize a background seat from durable provider artifacts. This lives in the
# contract library so out-of-process completion hooks do not need to source the
# full dispatch stack.
octo_run_contract_finish_background() {
    local seat_id="${1:-}" outcome="${2:-failed}" output_file="${3:-}"
    local stderr_file="${4:-}" reason="${5:-}" exit_code="${6:-1}"
    local duration_ms="${7:-}" terminal_reason

    case "$outcome" in
        success|degraded)
            if ! _octo_run_output_usable_file "$output_file"; then
                terminal_reason="${reason:-Provider returned unusable output}"
                run_contract_transition "$seat_id" failed \
                    "output_file=$output_file" "stderr_file=$stderr_file" \
                    "reason=$terminal_reason" "duration_ms=$duration_ms" >/dev/null 2>&1 || true
                return 1
            fi
            if ! run_contract_transition "$seat_id" output_received \
                "output_file=$output_file" "stderr_file=$stderr_file" \
                "duration_ms=$duration_ms"; then
                run_contract_transition "$seat_id" failed \
                    "output_file=$output_file" "stderr_file=$stderr_file" \
                    "reason=Failed to persist background output" \
                    "duration_ms=$duration_ms" >/dev/null 2>&1 || true
                return 74
            fi
            if ! run_contract_transition "$seat_id" validated contribution=eligible; then
                run_contract_transition "$seat_id" failed \
                    "reason=Background output validation failed" >/dev/null 2>&1 || true
                return 1
            fi
            if [[ "$outcome" == degraded ]]; then
                run_contract_transition "$seat_id" degraded \
                    contribution=eligible-with-warning \
                    "reason=${reason:-Background provider returned degraded output}" \
                    "duration_ms=$duration_ms"
            else
                run_contract_transition "$seat_id" contributed contribution=eligible \
                    "duration_ms=$duration_ms"
            fi
            ;;
        timeout|cancelled|failed|skipped)
            terminal_reason="$reason"
            [[ -n "$terminal_reason" ]] || terminal_reason="Background provider ended with $outcome (exit $exit_code)"
            run_contract_transition "$seat_id" "$outcome" \
                "output_file=$output_file" "stderr_file=$stderr_file" \
                "reason=$terminal_reason" "duration_ms=$duration_ms"
            ;;
        *) return 2 ;;
    esac
}

_octo_run_contract_snapshot_unlocked() {
    local ledger snapshot run_id snapshot_dir tmp
    ledger="$(octo_run_contract_ledger_path)"
    snapshot="$(octo_run_contract_snapshot_path)"
    run_id="$(octo_run_contract_id)"
    snapshot_dir="$(dirname "$snapshot")"

    [[ -s "$ledger" ]] || return 1
    mkdir -p "$snapshot_dir" 2>/dev/null || return 1
    tmp="$(mktemp "${snapshot}.tmp.XXXXXX")" || return 1

    if ! jq -s --arg schema_version "$OCTO_RUN_SCHEMA_VERSION" --arg run_id "$run_id" '
        reduce .[] as $record ({}; .[$record.seat_id] = $record)
        | {
            schema_version: $schema_version,
            run_id: $run_id,
            seats: ([.[]] | sort_by(.seat_id))
          }
    ' "$ledger" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    if ! mv "$tmp" "$snapshot" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    cat "$snapshot"
}

run_contract_snapshot() (
    local ledger output
    ledger="$(octo_run_contract_ledger_path)"
    [[ -s "$ledger" ]] || return 1
    _octo_event_lock "$ledger" || return 1
    trap '_octo_event_unlock "$ledger"' EXIT
    output="$(_octo_run_contract_snapshot_unlocked)" || return 1
    _octo_event_unlock "$ledger"
    trap - EXIT
    printf '%s\n' "$output"
)

run_contract_transition() (
    local seat_id="${1:-}" transition="${2:-}"
    shift 2 2>/dev/null || return 2

    [[ "$seat_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]] || return 2
    [[ "$transition" =~ ^[a-z_]+$ ]] || return 2

    local previous="{}" previous_record="" from="" ledger run_dir
    ledger="$(octo_run_contract_ledger_path)"
    run_dir="$(dirname "$ledger")"
    mkdir -p "$run_dir" 2>/dev/null || return 1
    _octo_event_lock "$ledger" || return 1
    trap '_octo_event_unlock "$ledger"' EXIT

    if previous_record="$(_octo_run_latest_record "$seat_id" 2>/dev/null)"; then
        previous="$previous_record"
        from="$(jq -er '.transition' <<< "$previous" 2>/dev/null)" || return 1
    fi

    octo_run_transition_valid "$from" "$transition" || return 1
    _octo_run_terminal "$from" && return 1

    local requested_provider="" requested_model="" requested_effort=""
    local resolved_provider="" resolved_model="" resolved_effort=""
    local phase="" role="" isolation="" worktree="" attempt_id=""
    local output_file="" stderr_file="" diff_file="" reason=""
    local status="" contribution="" tokens_in="" tokens_out=""
    local duration_ms="" estimated_cost_usd=""
    local pair key value
    for pair in "$@"; do
        [[ "$pair" == *=* ]] || return 2
        key="${pair%%=*}"
        value="${pair#*=}"
        case "$key" in
            requested_provider) requested_provider="$value" ;;
            requested_model) requested_model="$value" ;;
            requested_effort) requested_effort="$value" ;;
            resolved_provider) resolved_provider="$value" ;;
            resolved_model) resolved_model="$value" ;;
            resolved_effort) resolved_effort="$value" ;;
            phase) phase="$value" ;;
            role) role="$value" ;;
            isolation) isolation="$value" ;;
            worktree) worktree="$value" ;;
            attempt_id) attempt_id="$value" ;;
            output_file) output_file="$value" ;;
            stderr_file) stderr_file="$value" ;;
            diff_file) diff_file="$value" ;;
            reason) reason="$value" ;;
            status) status="$value" ;;
            contribution) contribution="$value" ;;
            tokens_in) tokens_in="$value" ;;
            tokens_out) tokens_out="$value" ;;
            duration_ms) duration_ms="$value" ;;
            estimated_cost_usd) estimated_cost_usd="$value" ;;
            *) return 2 ;;
        esac
    done

    if [[ "$transition" == output_received ]]; then
        _octo_run_output_usable_file "$output_file" || return 1
    fi

    local inherited_output
    inherited_output="$(jq -r '.artifacts.output // ""' <<< "$previous" 2>/dev/null)" || return 1
    if [[ -z "$output_file" ]]; then
        output_file="$inherited_output"
    fi

    case "$transition" in
        validated)
            _octo_run_output_usable_file "$output_file" || return 1
            [[ "$contribution" == eligible ]] || return 1
            ;;
        contributed)
            [[ "$(jq -r '.contribution // ""' <<< "$previous" 2>/dev/null)" == eligible ]] || return 1
            [[ -z "$contribution" || "$contribution" == eligible ]] || return 1
            contribution=eligible
            ;;
        degraded)
            if [[ "$contribution" == eligible-with-warning ]]; then
                _octo_run_output_usable_file "$output_file" || return 1
            elif [[ -n "$contribution" && "$contribution" != none ]]; then
                return 1
            fi
            ;;
    esac

    if [[ -z "$contribution" ]]; then
        if _octo_run_terminal "$transition"; then
            contribution=none
        else
            contribution="$(jq -r '.contribution // "none"' <<< "$previous" 2>/dev/null)" || return 1
        fi
    fi

    if [[ -z "$status" ]]; then
        case "$transition" in
            contributed) status=ok ;;
            degraded|skipped|failed|timeout|cancelled) status="$transition" ;;
            *) status=running ;;
        esac
    fi

    local run_id timestamp record
    run_id="$(octo_run_contract_id)"
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record="$(jq -cn \
        --argjson previous "$previous" \
        --arg schema_version "$OCTO_RUN_SCHEMA_VERSION" \
        --arg run_id "$run_id" --arg seat_id "$seat_id" \
        --arg transition "$transition" --arg status "$status" \
        --arg contribution "$contribution" --arg reason "$reason" \
        --arg timestamp "$timestamp" --arg attempt_id "$attempt_id" \
        --arg requested_provider "$requested_provider" \
        --arg requested_model "$requested_model" \
        --arg requested_effort "$requested_effort" \
        --arg resolved_provider "$resolved_provider" \
        --arg resolved_model "$resolved_model" \
        --arg resolved_effort "$resolved_effort" \
        --arg phase "$phase" --arg role "$role" \
        --arg isolation "$isolation" --arg worktree "$worktree" \
        --arg output_file "$output_file" --arg stderr_file "$stderr_file" \
        --arg diff_file "$diff_file" --arg tokens_in "$tokens_in" \
        --arg tokens_out "$tokens_out" --arg duration_ms "$duration_ms" \
        --arg estimated_cost_usd "$estimated_cost_usd" '
        def carry($new; $old): if $new != "" then $new else ($old // "") end;
        {
          schema_version: $schema_version,
          run_id: $run_id,
          seat_id: $seat_id,
          attempt_id: carry($attempt_id; $previous.attempt_id),
          transition: $transition,
          status: $status,
          contribution: $contribution,
          requested: {
            provider: carry($requested_provider; $previous.requested.provider),
            model: carry($requested_model; $previous.requested.model),
            effort: carry($requested_effort; $previous.requested.effort)
          },
          resolved: {
            provider: carry($resolved_provider; $previous.resolved.provider),
            model: carry($resolved_model; $previous.resolved.model),
            effort: carry($resolved_effort; $previous.resolved.effort)
          },
          execution: {
            phase: carry($phase; $previous.execution.phase),
            role: carry($role; $previous.execution.role),
            isolation: carry($isolation; $previous.execution.isolation),
            worktree: carry($worktree; $previous.execution.worktree)
          },
          metrics: {
            tokens_in: carry($tokens_in; $previous.metrics.tokens_in),
            tokens_out: carry($tokens_out; $previous.metrics.tokens_out),
            duration_ms: carry($duration_ms; $previous.metrics.duration_ms),
            estimated_cost_usd: carry($estimated_cost_usd; $previous.metrics.estimated_cost_usd)
          },
          artifacts: {
            output: carry($output_file; $previous.artifacts.output),
            stderr: carry($stderr_file; $previous.artifacts.stderr),
            diff: carry($diff_file; $previous.artifacts.diff)
          },
          reason: $reason,
          timestamp: $timestamp
        }
    ')" || return 1

    if ! printf '%s\n' "$record" >> "$ledger" 2>/dev/null; then
        return 1
    fi

    _octo_run_contract_snapshot_unlocked >/dev/null || return 1
    _octo_event_unlock "$ledger"
    trap - EXIT
    return 0
)
