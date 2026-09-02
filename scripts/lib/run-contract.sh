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

octo_run_contract_manifest_path() {
    printf '%s/run.json\n' "$(octo_run_contract_dir)"
}

octo_run_contract_latest_path() {
    local contract_dir
    contract_dir="$(octo_run_contract_dir)"
    printf '%s/latest\n' "$(dirname "$contract_dir")"
}

octo_run_contract_events_path() {
    printf '%s/events.jsonl\n' "$(octo_run_contract_dir)"
}

octo_run_contract_lock_path() {
    printf '%s/contract\n' "$(octo_run_contract_dir)"
}

octo_run_contract_recovery_path() {
    printf '%s.recovery\n' "$(octo_run_contract_ledger_path)"
}

# A published generation is committed only when both durable snapshots contain
# the same latest-seat projection as the ledger. This lets recovery distinguish
# a stale cleanup marker from an append whose snapshot never committed.
_octo_run_contract_snapshot_matches_ledger_unlocked() {
    local ledger snapshot manifest latest snapshot_dir latest_target
    ledger="$(octo_run_contract_ledger_path)"
    snapshot="$(octo_run_contract_snapshot_path)"
    manifest="$(octo_run_contract_manifest_path)"
    latest="$(octo_run_contract_latest_path)"
    snapshot_dir="$(dirname "$snapshot")"
    [[ -s "$ledger" && -s "$snapshot" && -s "$manifest" && -L "$latest" ]] || return 1
    latest_target="$(readlink "$latest" 2>/dev/null)" || return 1
    [[ "$latest_target" == "$snapshot_dir" ]] || return 1

    jq -e -s --slurpfile snapshot "$snapshot" --slurpfile manifest "$manifest" '
        reduce .[] as $record ({}; .[$record.seat_id] = $record)
        | ([.[]] | sort_by(.seat_id)) as $ledger_seats
        | (($snapshot[0].seats // [])
            | map(del(.started_at, .updated_at, .timeline))
            | sort_by(.seat_id)) == $ledger_seats
          and (($manifest[0].seats // [])
            | map(del(.started_at, .updated_at, .timeline))
            | sort_by(.seat_id)) == $ledger_seats
    ' "$ledger" >/dev/null 2>&1
}

# Rebuild the visible generation from the restored durable inputs. If the
# failed append was the first durable record, remove any partially published
# artifacts instead. The recovery marker remains until this step succeeds, so
# readers never accept a mixed generation.
_octo_run_contract_restore_snapshots_unlocked() {
    local ledger events_ledger snapshot manifest latest snapshot_dir latest_target
    ledger="$(octo_run_contract_ledger_path)"
    events_ledger="$(octo_run_contract_events_path)"
    snapshot="$(octo_run_contract_snapshot_path)"
    manifest="$(octo_run_contract_manifest_path)"
    latest="$(octo_run_contract_latest_path)"
    snapshot_dir="$(dirname "$snapshot")"

    if [[ -s "$ledger" || -s "$events_ledger" ]]; then
        _octo_run_contract_snapshot_unlocked >/dev/null 2>&1
        return $?
    fi

    rm -f "$snapshot" "$manifest" 2>/dev/null || return 1
    if [[ -L "$latest" ]]; then
        latest_target="$(readlink "$latest" 2>/dev/null)" || return 1
        if [[ "$latest_target" == "$snapshot_dir" ]]; then
            rm -f "$latest" 2>/dev/null || return 1
        fi
    fi
    return 0
}

# Restore a ledger rollback while the contract lock is held. The recovery
# marker deliberately outlives the ledger write: readers fail closed while it
# exists, and a later locked operation can retry from the intact backup.
_octo_run_contract_recover_unlocked() {
    local ledger marker existed backup restore_tmp
    ledger="$(octo_run_contract_ledger_path)"
    marker="$(octo_run_contract_recovery_path)"
    [[ -f "$marker" ]] || return 0

    IFS=$'\t' read -r existed backup < "$marker" 2>/dev/null || return 1
    [[ "$backup" == "$ledger".rollback.* && -f "$backup" ]] || return 1

    # Snapshot publication is the commit point. If both durable snapshots
    # already match the ledger, a leftover marker is cleanup debt, not license
    # to restore the pre-append backup.
    if _octo_run_contract_snapshot_matches_ledger_unlocked; then
        rm -f "$marker" 2>/dev/null || return 1
        rm -f "$backup" 2>/dev/null || true
        return 0
    fi

    if [[ "$existed" == true ]]; then
        restore_tmp="$(mktemp "${ledger}.restore.XXXXXX")" || return 1
        if ! cp "$backup" "$restore_tmp" 2>/dev/null ||
           ! mv "$restore_tmp" "$ledger" 2>/dev/null; then
            rm -f "$restore_tmp" 2>/dev/null || true
            return 1
        fi
    elif [[ "$existed" == false ]]; then
        rm -f "$ledger" 2>/dev/null || return 1
    else
        return 1
    fi

    _octo_run_contract_restore_snapshots_unlocked || return 1
    rm -f "$marker" 2>/dev/null || return 1
    rm -f "$backup" 2>/dev/null || true
    return 0
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
    [[ ! -e "$(octo_run_contract_recovery_path)" ]] || return 1
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
# artifact is ambiguous, 2 when no v10 contract record owns the file, and 3
# when the contract ledger cannot be evaluated. Evaluation errors fail closed.
run_contract_output_file_eligible() {
    local output_file="${1:-}" ledger records count
    ledger="$(octo_run_contract_ledger_path)"
    [[ ! -e "$(octo_run_contract_recovery_path)" ]] || return 3
    [[ -n "$output_file" && -s "$ledger" ]] || return 2
    records="$(jq -sc --arg output "$output_file" '
        reduce .[] as $record ({}; .[$record.seat_id] = $record)
        | [.[] | select(.artifacts.output == $output)]
    ' "$ledger" 2>/dev/null)" || return 3
    count="$(jq -r 'length' <<< "$records" 2>/dev/null)" || return 3
    [[ "$count" -gt 0 ]] || return 2
    [[ "$count" -eq 1 ]] || return 1
    jq -e '
        (.[0].transition == "contributed" and .[0].contribution == "eligible") or
        (.[0].transition == "degraded" and .[0].contribution == "eligible-with-warning")
    ' <<< "$records" >/dev/null 2>&1 || {
        local rc=$?
        [[ "$rc" -eq 1 ]] && return 1
        return 3
    }
}

# Finalize a background seat from durable provider artifacts. This lives in the
# contract library so out-of-process completion hooks do not need to source the
# full dispatch stack.
octo_run_contract_finish_background() {
    local seat_id="${1:-}" outcome="${2:-failed}" output_file="${3:-}"
    local stderr_file="${4:-}" reason="${5:-}" exit_code="${6:-1}"
    local duration_ms="${7:-}" cleanup_result="${8:-}" terminal_reason
    local provider_output_file="${9:-$output_file}"

    case "$outcome" in
        success|degraded)
            if ! _octo_run_output_usable_file "$provider_output_file"; then
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
                    "duration_ms=$duration_ms" "cleanup_result=$cleanup_result"
            else
                run_contract_transition "$seat_id" contributed contribution=eligible \
                    "duration_ms=$duration_ms" "cleanup_result=$cleanup_result"
            fi
            ;;
        timeout|cancelled|failed|skipped)
            terminal_reason="$reason"
            [[ -n "$terminal_reason" ]] || terminal_reason="Background provider ended with $outcome (exit $exit_code)"
            run_contract_transition "$seat_id" "$outcome" \
                "output_file=$output_file" "stderr_file=$stderr_file" \
                "reason=$terminal_reason" "duration_ms=$duration_ms" \
                "cleanup_result=$cleanup_result"
            ;;
        *) return 2 ;;
    esac
}

_octo_run_contract_snapshot_unlocked() {
    local ledger events_ledger snapshot manifest latest run_id snapshot_dir
    local tmp compat_tmp latest_tmp seats_json events_json generated_at
    ledger="$(octo_run_contract_ledger_path)"
    events_ledger="$(octo_run_contract_events_path)"
    snapshot="$(octo_run_contract_snapshot_path)"
    manifest="$(octo_run_contract_manifest_path)"
    latest="$(octo_run_contract_latest_path)"
    run_id="$(octo_run_contract_id)"
    snapshot_dir="$(dirname "$snapshot")"

    [[ -s "$ledger" || -s "$events_ledger" ]] || return 1
    mkdir -p "$snapshot_dir" 2>/dev/null || return 1
    tmp="$(mktemp "${manifest}.tmp.XXXXXX")" || return 1
    compat_tmp="$(mktemp "${snapshot}.tmp.XXXXXX")" || { rm -f "$tmp"; return 1; }
    latest_tmp="$(mktemp "${latest}.tmp.XXXXXX")" || { rm -f "$tmp" "$compat_tmp"; return 1; }
    rm -f "$latest_tmp" 2>/dev/null || { rm -f "$tmp" "$compat_tmp"; return 1; }

    seats_json='[]'
    events_json='[]'
    if [[ -s "$ledger" ]]; then
        seats_json="$(jq -s '
            group_by(.seat_id)
            | map(
                . as $records
                | ($records[-1] + {
                    started_at: $records[0].timestamp,
                    updated_at: $records[-1].timestamp,
                    timeline: [$records[] | {
                      transition, status, contribution, reason, timestamp
                    }]
                  })
              )
            | sort_by(.seat_id)
        ' "$ledger" 2>/dev/null)" || {
            rm -f "$tmp" "$compat_tmp" "$latest_tmp"
            return 1
        }
    fi
    if [[ -s "$events_ledger" ]]; then
        events_json="$(jq -s '.' "$events_ledger" 2>/dev/null)" || {
            rm -f "$tmp" "$compat_tmp" "$latest_tmp"
            return 1
        }
    fi

    generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! jq -n --arg schema_version "$OCTO_RUN_SCHEMA_VERSION" --arg run_id "$run_id" \
        --arg generated_at "$generated_at" --argjson seats "$seats_json" \
        --argjson events "$events_json" '
        def count_transition($name): [$seats[] | select(.transition == $name)] | length;
        def phase_rollup:
          reduce $seats[] as $seat ({};
            ($seat.execution.phase // "unknown") as $phase
            | .[$phase] = ((.[$phase] // {
                total: 0, contributed: 0, degraded: 0, skipped: 0,
                failed: 0, timeout: 0, cancelled: 0, running: 0
              })
              | .total += 1
              | if ($seat.transition | IN("contributed", "degraded", "skipped", "failed", "timeout", "cancelled"))
                then .[$seat.transition] += 1
                else .running += 1
                end)
          );
        {
          schema_version: $schema_version,
          run_id: $run_id,
          generated_at: $generated_at,
          seats: $seats,
          events: $events,
          summary: {
            total_seats: ($seats | length),
            contributed: count_transition("contributed"),
            degraded: count_transition("degraded"),
            skipped: count_transition("skipped"),
            failed: count_transition("failed"),
            timeout: count_transition("timeout"),
            cancelled: count_transition("cancelled"),
            running: ([$seats[] | select(.transition | IN("contributed", "degraded", "skipped", "failed", "timeout", "cancelled") | not)] | length),
            eligible_contributions: ([$seats[] | select(.contribution == "eligible" or .contribution == "eligible-with-warning")] | length),
            degraded_coverage: (count_transition("degraded") > 0)
          },
          phases: phase_rollup
        }
    ' > "$tmp" 2>/dev/null; then
        rm -f "$tmp" "$compat_tmp" "$latest_tmp"
        return 1
    fi

    if ! cp "$tmp" "$compat_tmp" 2>/dev/null ||
       ! ln -s "$snapshot_dir" "$latest_tmp" 2>/dev/null ||
       ! mv "$tmp" "$manifest" 2>/dev/null ||
       ! mv "$compat_tmp" "$snapshot" 2>/dev/null; then
        rm -f "$tmp" "$compat_tmp" "$latest_tmp"
        return 1
    fi
    # Replace a directory symlink itself instead of following it. GNU mv uses
    # -T for this operation; BSD/macOS mv uses -h.
    case "$(uname -s 2>/dev/null || true)" in
        Darwin|*BSD)
            # Homebrew GNU coreutils may shadow BSD mv on macOS and rejects -h.
            /bin/mv -fh "$latest_tmp" "$latest" 2>/dev/null || {
                rm -f "$latest_tmp"
                return 1
            }
            ;;
        *)
            mv -fT "$latest_tmp" "$latest" 2>/dev/null || {
                rm -f "$latest_tmp"
                return 1
            }
            ;;
    esac
    cat "$manifest"
}

run_contract_snapshot() (
    local ledger events_ledger lock_target output
    ledger="$(octo_run_contract_ledger_path)"
    events_ledger="$(octo_run_contract_events_path)"
    [[ -s "$ledger" || -s "$events_ledger" ]] || return 1
    lock_target="$(octo_run_contract_lock_path)"
    _octo_event_lock "$lock_target" || return 1
    trap '_octo_event_unlock "$lock_target"' EXIT
    _octo_run_contract_recover_unlocked || return 1
    output="$(_octo_run_contract_snapshot_unlocked)" || return 1
    _octo_event_unlock "$lock_target"
    trap - EXIT
    printf '%s\n' "$output"
)

_octo_run_contract_read_manifest() {
    local requested_run="${1:-latest}" runs_root run_id manifest
    runs_root="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/runs"
    if [[ -z "$requested_run" || "$requested_run" == "latest" ]]; then
        if [[ -d "$runs_root/latest" ]]; then
            manifest="$runs_root/latest/run.json"
            [[ -r "$manifest" ]] || return 1
            run_id="$(jq -er '.run_id' "$manifest" 2>/dev/null)" || return 1
        else
            # Backward compatibility for v10 prerelease snapshots that used a
            # text pointer before the legacy status writer contract was restored.
            [[ -r "$runs_root/latest" ]] || return 1
            IFS= read -r run_id < "$runs_root/latest" || return 1
            manifest="$runs_root/$run_id/run.json"
        fi
    else
        run_id="$requested_run"
        manifest="$runs_root/$run_id/run.json"
    fi
    [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]] || return 2
    [[ -r "$manifest" ]] || return 1
    jq -e --arg run_id "$run_id" '
      .schema_version == "10.0" and .run_id == $run_id and
      (.seats | type == "array") and (.summary | type == "object")
    ' "$manifest" >/dev/null 2>&1 || return 1
    cat "$manifest"
}

run_contract_status() {
    local run_id="${1:-latest}" format="${2:-human}" manifest
    manifest="$(_octo_run_contract_read_manifest "$run_id")" || return $?
    if [[ "$format" == "json" ]]; then
        printf '%s\n' "$manifest"
    elif [[ "$format" == "human" ]]; then
        jq -r '
          "Run \(.run_id) (schema \(.schema_version))",
          "Seats: \(.summary.total_seats) total, \(.summary.eligible_contributions) eligible, \(.summary.failed) failed, \(.summary.degraded) degraded",
          "Updated: \(.generated_at)"
        ' <<< "$manifest"
    else
        return 2
    fi
}

run_contract_explain() {
    local run_id="${1:-latest}" manifest
    manifest="$(_octo_run_contract_read_manifest "$run_id")" || return $?
    jq -r '
      "Run \(.run_id)",
      (.seats[] |
        "- \(.seat_id): \(.transition)" +
        (if (.reason // "") != "" then " - \(.reason)"
         elif .contribution == "eligible" then " - contribution eligible"
         elif .contribution == "eligible-with-warning" then " - contribution eligible with warning"
         else " - no contribution" end))
    ' <<< "$manifest"
}

# Record a run-scoped event that is not owned by a provider seat. Attribute
# values are strings so the append-only ledger stays simple and inspectable.
run_contract_record_event() (
    local event="${1:-}"
    shift || true
    [[ "$event" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]] || return 2

    local events_ledger run_dir lock_target attrs='{}' pair key value record timestamp run_id
    events_ledger="$(octo_run_contract_events_path)"
    run_dir="$(dirname "$events_ledger")"
    mkdir -p "$run_dir" 2>/dev/null || return 1

    for pair in "$@"; do
        [[ "$pair" == *=* ]] || return 2
        key="${pair%%=*}"
        value="${pair#*=}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_.:-]*$ ]] || return 2
        attrs="$(jq -cn --argjson attrs "$attrs" --arg key "$key" --arg value "$value" \
            '$attrs + {($key): $value}')" || return 1
    done

    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run_id="$(octo_run_contract_id)"
    record="$(jq -cn --arg schema_version "$OCTO_RUN_SCHEMA_VERSION" \
        --arg run_id "$run_id" --arg event "$event" --arg timestamp "$timestamp" \
        --argjson attributes "$attrs" \
        '{schema_version:$schema_version, run_id:$run_id, event:$event, timestamp:$timestamp, attributes:$attributes}')" || return 1

    lock_target="$(octo_run_contract_lock_path)"
    _octo_event_lock "$lock_target" || return 1
    trap '_octo_event_unlock "$lock_target"' EXIT
    _octo_run_contract_recover_unlocked || return 1
    printf '%s\n' "$record" >> "$events_ledger" 2>/dev/null || return 1
    _octo_run_contract_snapshot_unlocked >/dev/null || return 1
    _octo_event_unlock "$lock_target"
    trap - EXIT
    return 0
)

run_contract_reconcile_stale() {
    local seat_id="${1:-}" pid="${2:-}" record transition
    record="$(_octo_run_latest_record "$seat_id")" || return 1
    transition="$(jq -er '.transition' <<< "$record" 2>/dev/null)" || return 1
    _octo_run_terminal "$transition" && return 0
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    run_contract_transition "$seat_id" failed \
        "reason=Process exited without a terminal record" \
        "cleanup_result=already-exited"
}

run_contract_retry_seat() {
    local seat_id="${1:-}" attempt_id="${2:-}" record transition contribution suffix retry_seat
    [[ -n "$attempt_id" ]] || return 2
    record="$(_octo_run_latest_record "$seat_id")" || return 1
    transition="$(jq -er '.transition' <<< "$record" 2>/dev/null)" || return 1
    contribution="$(jq -r '.contribution // "none"' <<< "$record" 2>/dev/null)" || return 1
    _octo_run_terminal "$transition" || return 1
    [[ "$contribution" == "none" ]] || return 1
    [[ "$(jq -r '.attempt_id // ""' <<< "$record")" != "$attempt_id" ]] || return 1

    suffix="$(printf '%s' "$attempt_id" | sed 's/[^A-Za-z0-9_.:-]/_/g')"
    retry_seat="${seat_id}.retry-${suffix}"
    run_contract_transition "$retry_seat" planned \
        "attempt_id=$attempt_id" \
        "requested_provider=$(jq -r '.requested.provider // ""' <<< "$record")" \
        "requested_model=$(jq -r '.requested.model // ""' <<< "$record")" \
        "requested_effort=$(jq -r '.requested.effort // ""' <<< "$record")" \
        "phase=$(jq -r '.execution.phase // ""' <<< "$record")" \
        "role=$(jq -r '.execution.role // ""' <<< "$record")" \
        "isolation=$(jq -r '.execution.isolation // ""' <<< "$record")" \
        "worktree=$(jq -r '.execution.worktree // ""' <<< "$record")" \
        "checkpoint=$(jq -r '.execution.checkpoint // ""' <<< "$record")" \
        "source_sha=$(jq -r '.source.sha // ""' <<< "$record")" \
        "source_dirty=$(jq -r '.source.dirty_decision // ""' <<< "$record")" || return 1
    printf '%s\n' "$retry_seat"
}

run_contract_transition() (
    local seat_id="${1:-}" transition="${2:-}"
    shift 2 2>/dev/null || return 2

    [[ "$seat_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]] || return 2
    [[ "$transition" =~ ^[a-z_]+$ ]] || return 2

    local previous="{}" previous_record="" from="" ledger run_dir lock_target
    ledger="$(octo_run_contract_ledger_path)"
    run_dir="$(dirname "$ledger")"
    mkdir -p "$run_dir" 2>/dev/null || return 1
    lock_target="$(octo_run_contract_lock_path)"
    _octo_event_lock "$lock_target" || return 1
    trap '_octo_event_unlock "$lock_target"' EXIT
    _octo_run_contract_recover_unlocked || return 1

    if previous_record="$(_octo_run_latest_record "$seat_id" 2>/dev/null)"; then
        previous="$previous_record"
        from="$(jq -er '.transition' <<< "$previous" 2>/dev/null)" || return 1
    fi

    octo_run_transition_valid "$from" "$transition" || return 1
    _octo_run_terminal "$from" && return 1

    local requested_provider="" requested_model="" requested_effort=""
    local resolved_provider="" resolved_model="" resolved_effort=""
    local phase="" role="" isolation="" worktree="" attempt_id="" checkpoint=""
    local source_sha="" source_dirty="" pid="" pgid="" cleanup_result=""
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
            checkpoint) checkpoint="$value" ;;
            source_sha) source_sha="$value" ;;
            source_dirty) source_dirty="$value" ;;
            pid) pid="$value" ;;
            pgid) pgid="$value" ;;
            cleanup_result) cleanup_result="$value" ;;
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
        --arg checkpoint "$checkpoint" --arg source_sha "$source_sha" \
        --arg source_dirty "$source_dirty" --arg pid "$pid" --arg pgid "$pgid" \
        --arg cleanup_result "$cleanup_result" \
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
            worktree: carry($worktree; $previous.execution.worktree),
            checkpoint: carry($checkpoint; $previous.execution.checkpoint),
            cleanup_result: carry($cleanup_result; $previous.execution.cleanup_result)
          },
          source: {
            sha: carry($source_sha; $previous.source.sha),
            dirty_decision: carry($source_dirty; $previous.source.dirty_decision)
          },
          process: {
            pid: carry($pid; $previous.process.pid),
            pgid: carry($pgid; $previous.process.pgid)
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

    local ledger_backup ledger_existed=false recovery_marker recovery_marker_tmp
    ledger_backup="$(mktemp "${ledger}.rollback.XXXXXX")" || return 1
    if [[ -f "$ledger" ]]; then
        ledger_existed=true
        cat "$ledger" > "$ledger_backup" 2>/dev/null || { rm -f "$ledger_backup"; return 1; }
    fi

    recovery_marker="$(octo_run_contract_recovery_path)"
    recovery_marker_tmp="$(mktemp "${recovery_marker}.tmp.XXXXXX")" || {
        rm -f "$ledger_backup" 2>/dev/null || true
        return 1
    }
    if ! printf '%s\t%s\n' "$ledger_existed" "$ledger_backup" > "$recovery_marker_tmp" 2>/dev/null ||
       ! mv "$recovery_marker_tmp" "$recovery_marker" 2>/dev/null; then
        rm -f "$recovery_marker_tmp" "$ledger_backup" 2>/dev/null || true
        return 1
    fi

    if ! printf '%s\n' "$record" >> "$ledger" 2>/dev/null; then
        _octo_run_contract_recover_unlocked >/dev/null 2>&1 || true
        return 1
    fi

    if ! _octo_run_contract_snapshot_unlocked >/dev/null; then
        _octo_run_contract_recover_unlocked >/dev/null 2>&1 || true
        return 1
    fi
    rm -f "$recovery_marker" 2>/dev/null || return 1
    rm -f "$ledger_backup" 2>/dev/null || true
    _octo_event_unlock "$lock_target"
    trap - EXIT
    return 0
)
