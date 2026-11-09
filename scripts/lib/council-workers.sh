#!/usr/bin/env bash
# Council phase workers. Source-safe and compatible with Bash 3.2.
# Variables assigned here are consumed by council.sh through Bash dynamic scope.
# shellcheck disable=SC2034

# Decode one roster record into the caller's seat variables using NUL separators.
council_read_seat_fields() {
    # Assign into the advice loop's local variables, preserving empty strings.
    {
        IFS= read -r -d '' persona
        IFS= read -r -d '' seat
        IFS= read -r -d '' mprovider_spec
        IFS= read -r -d '' seat_org
        IFS= read -r -d '' seat_model
        IFS= read -r -d '' seat_model_family
    } < <(jq -j '[.persona, .seat, (.agent_spec // .provider),
        (.provider_org // ""), (.model // ""), (.model_family // "")]
        | .[] | (if . == null then "null" else tostring end), "\u0000"' <<< "$1")
}

# Print monotonic milliseconds shared by seat preparation and timeout accounting.
council_pool_now_ms() {
    # EPOCHREALTIME is a wall clock and can jump during a timeout. Keep one
    # monotonic clock domain for preparation, reservation waits and dispatch.
    python3 -c 'import time; print(int(time.monotonic() * 1000))'
}

# Normalize a positive decimal concurrency limit, using the supplied fallback
# for zero, malformed or excessively long input before performing arithmetic.
council_pool_limit() {
    local value="$1" fallback="$2"
    case "$value" in ''|*[!0-9]*) value="$fallback" ;; esac
    # Bound arithmetic and reject zero, including all-zero decimal strings.
    if [[ ${#value} -gt 6 ]] || ! [[ "$value" =~ [1-9] ]]; then value="$fallback"; fi
    printf '%s\n' "$((10#$value))"
}

# Resolve the pool limit within MAX_PARALLEL; fixtures and inline mode stay serial.
council_pool_global_limit() {
    local limit outer
    limit="$(council_pool_limit "${OCTOPUS_COUNCIL_MAX_PARALLEL:-2}" 2)"
    outer="$(council_pool_limit "${MAX_PARALLEL:-$limit}" "$limit")"
    (( outer >= limit )) || limit="$outer"
    [[ "${OCTOPUS_COUNCIL_DETACH:-1}" == 1 && -z "${COUNCIL_FIXTURE:-}" ]] || limit=1
    printf '%s\n' "$limit"
}

# Resolve a canonical provider's override or the shared per-provider limit.
council_pool_provider_limit() {
    local provider="$1" knob limit specific
    knob="OCTOPUS_COUNCIL_MAX_PARALLEL_$(printf '%s' "$provider" | tr '[:lower:]-' '[:upper:]_')"
    limit="$(council_pool_limit "${OCTOPUS_COUNCIL_PROVIDER_MAX_PARALLEL:-1}" 1)"
    specific="$(council_pool_limit "${!knob:-$limit}" "$limit")"
    printf '%s\n' "$specific"
}

# Return a pooled seat's saved status and timeout provenance, or dispatch inline
# when no pooled result exists and the aggregate deadline still permits it.
council_collect_seat() {
    local output="$3" rc
    COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE=""
    if council_deadline_exceeded; then COUNCIL_DEADLINE_HIT=true; fi
    if [[ "${COUNCIL_POOL_PHASE:-}" == "$2" && -f "${output}.pool-result" ]]; then
        IFS= read -r rc < "${output}.pool-result" || true
        COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE="$(sed -n '2p' "${output}.pool-result")"
        [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
        return "$rc"
    fi
    if council_deadline_exceeded; then COUNCIL_DEADLINE_HIT=true; return 1; fi
    council_dispatch_member_detached "$@"
}

# The sync dispatcher supplies its resolved model, enhanced prompt and call ID.
# Delegate only the reservation to the scheduler; completion keeps that same ID.
council_pool_request_reservation() {
    local output="$1"; shift
    (umask 077; printf '%s\0' "$@" > "${output}.reserve.tmp") || return 74
    council_pool_now_ms > "${output}.reserve-start.tmp" || return 74
    mv -f "${output}.reserve-start.tmp" "${output}.reserve-start" || return 74
    mv -f "${output}.reserve.tmp" "${output}.reserve" || return 74
    while [[ ! -f "${output}.reserved" ]]; do
        [[ "${_COUNCIL_POOL_PID:-}" =~ ^[1-9][0-9]*$ ]] || return 75
        kill -0 "$_COUNCIL_POOL_PID" 2>/dev/null || return 75
        council_deadline_exceeded && return 124
        sleep 0.05
    done
    [[ "$(<"${output}.reserved")" == 0 ]]
}

# Record one seat's requested usage in scheduler order and publish its result
# atomically so the waiting provider can proceed only after reservation succeeds.
council_pool_reserve_call() {
    local output="$1" value rc=0
    local -a args
    args=()
    while IFS= read -r -d '' value; do args[${#args[@]}]="$value"; done < "${output}.reserve"
    # record_agent_call is the existing usage reservation helper, called exactly
    # once in admission order. The provider cannot execute until its acknowledgement.
    record_agent_call "${args[@]}" || rc=$?
    printf '%s\n' "$rc" > "${output}.reserved.tmp"
    mv -f "${output}.reserved.tmp" "${output}.reserved"
    rm -f "${output}.reserve"
    return "$rc"
}

# The parent waits on an interruptible background job. Restore caller traps from
# Bash's own trap serialization, without parsing or evaluating roster fields.
council_run_seat_pool() {
    COUNCIL_POOL_PHASE=""
    [[ "$(council_pool_global_limit)" -gt 1 ]] || return 0
    COUNCIL_POOL_PHASE="$1"
    local pool_pid="" rc=0 interrupted=0 old_int old_term old_hup
    old_int="$(trap -p INT)"; old_term="$(trap -p TERM)"; old_hup="$(trap -p HUP)"
    trap 'interrupted=130; [[ -z "$pool_pid" ]] || kill -TERM "$pool_pid" 2>/dev/null || true' INT
    trap 'interrupted=143; [[ -z "$pool_pid" ]] || kill -TERM "$pool_pid" 2>/dev/null || true' TERM HUP
    _council_seat_pool_impl "$@" &
    pool_pid=$!
    (( interrupted == 0 )) || kill -TERM "$pool_pid" 2>/dev/null || true
    wait "$pool_pid" || rc=$?
    if (( interrupted != 0 )); then wait "$pool_pid" 2>/dev/null || true; rc="$interrupted"; fi
    trap - INT TERM HUP
    source /dev/stdin <<< "$old_int
$old_term
$old_hup"
    return "$rc"
}

# Admit eligible seats by roster scan under global, provider and deadline limits.
# Retain each seat's completion record and partial evidence when cancelling.
_council_seat_pool_impl() {
    umask 077
    local phase="$1" directory="$2" through limit
    # exec makes Python's PPID this scheduler, including on Bash 3.2 where $$
    # remains the top-level shell's PID inside a background function.
    local _COUNCIL_POOL_PID
    _COUNCIL_POOL_PID="$(exec python3 -c 'import os; print(os.getppid())')" || return 1
    export _COUNCIL_POOL_PID
    case "$phase" in independent-advice) through=advice ;; cross-critique) through=critique ;; *) through=revision ;; esac
    limit="$(council_pool_global_limit)"
    local -a members providers outputs pids timeouts starts launch_order launched
    local member persona provider spec output index=0 i running=0 same cap rc elapsed now wait_start reservation_now
    local grace
    grace="$(council_deadline_reap_grace)"
    members=(); providers=(); outputs=(); pids=(); timeouts=(); starts=(); launch_order=(); launched=()
    # NUL separators retain empty fields, embedded newlines and qualified specs.
    # No tab splitting, command substitution trimming or eval is involved.
    while IFS= read -r -d '' member && IFS= read -r -d '' persona && IFS= read -r -d '' spec; do
        members[index]="$member"
        providers[index]="$(octo_agent_spec_provider "$spec")"
        outputs[index]="${COUNCIL_RUN_DIR}/${directory}/$(printf '%02d' "$index")-$(council_slug "$persona").md"
        rm -f "${outputs[index]}.pool-result" "${outputs[index]}.admitted" \
            "${outputs[index]}.reserve" "${outputs[index]}.reserve.tmp"             "${outputs[index]}.reserve-start" "${outputs[index]}.reserve-start.tmp" \
            "${outputs[index]}.reserved" "${outputs[index]}.reserved.tmp"
        pids[index]=""; timeouts[index]=0; starts[index]=0; launched[index]=0
        index=$((index + 1))
    done < <(jq -j '.[] | (tojson + "\u0000"), ((.persona | if . == null then "null" else tostring end) + "\u0000"), ((.agent_spec // .provider // "") + "\u0000")' <<< "$COUNCIL_ROSTER_JSON")

    _council_pool_cancel() {
        trap '' INT TERM HUP
        # A signal may land between fork and the scheduler's ownership transfer.
        # The launch helper publishes the PID before returning to this loop.
        if [[ -n "${COUNCIL_ASYNC_PID:-}" ]]; then
            local registered=false
            for ((i=0; i<index; i++)); do
                [[ "${pids[i]}" != "$COUNCIL_ASYNC_PID" ]] || registered=true
            done
            [[ "$registered" == true ]] || _council_cancel_tree "$COUNCIL_ASYNC_PID"
        fi
        for ((i=0; i<index; i++)); do
            [[ -n "${pids[i]}" ]] || continue
            _council_cancel_tree "${pids[i]}"
            wait "${pids[i]}" 2>/dev/null || true
            rm -f "${outputs[i]}.reserve" "${outputs[i]}.reserve.tmp"
            printf '143\ninterrupted\n' > "${outputs[i]}.pool-result.tmp"
            mv -f "${outputs[i]}.pool-result.tmp" "${outputs[i]}.pool-result"
        done
        exit 143
    }
    trap '_council_pool_cancel' INT TERM HUP
    local next=0 reservation_next=0 launch_count=0 pending="$index" seat_index
    COUNCIL_ASYNC_PID=""
    while (( pending > 0 || running > 0 )); do
        now="$(council_pool_now_ms)" || { _council_pool_cancel; }
        [[ "$now" =~ ^[0-9]+$ ]] || { _council_pool_cancel; }
        for ((i=0; i<index; i++)); do
            [[ -n "${pids[i]}" ]] || continue
            elapsed=$(( now - starts[i] ))
            if [[ -f "${outputs[i]}.reserve-start" && ! -f "${outputs[i]}.reserved" ]]; then
                IFS= read -r wait_start < "${outputs[i]}.reserve-start" || { _council_pool_cancel; }
                [[ "$wait_start" =~ ^[0-9]+$ ]] || { _council_pool_cancel; }
                # Exclude queue waiting, while still charging this seat's own
                # preparation time. The aggregate deadline always keeps running.
                elapsed=$((elapsed - now + wait_start))
            fi
            if [[ -f "${outputs[i]}.done" ]] || ! kill -0 "${pids[i]}" 2>/dev/null \
                    || (( elapsed >= (timeouts[i] + grace) * 1000 )) || council_deadline_exceeded; then
                rc=0
                COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE=""
                council_reap_member_detached "${outputs[i]}" "${pids[i]}" "${timeouts[i]}" "$elapsed" || rc=$?
                wait "${pids[i]}" 2>/dev/null || true
                printf '%s\n%s\n' "$rc" "$COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE" > "${outputs[i]}.pool-result.tmp"
                mv -f "${outputs[i]}.pool-result.tmp" "${outputs[i]}.pool-result"
                pids[i]=""; running=$((running - 1))
            fi
        done
        # Preparation may finish out of order. Reserve in deterministic admission
        # order, skipping seats still queued behind a capped provider. Never charge
        # those unlaunched seats merely to allow another provider to start.
        while (( reservation_next < launch_count )); do
            seat_index="${launch_order[reservation_next]}"
            output="${outputs[seat_index]}"
            if [[ -n "${pids[seat_index]}" && -f "${output}.reserve" && ! -f "${output}.reserved" ]]; then
                IFS= read -r wait_start < "${output}.reserve-start" || { _council_pool_cancel; }
                [[ "$wait_start" =~ ^[0-9]+$ ]] || { _council_pool_cancel; }
                council_pool_reserve_call "$output" || { _council_pool_cancel; }
                reservation_now="$(council_pool_now_ms)" || { _council_pool_cancel; }
                [[ "$reservation_now" =~ ^[0-9]+$ ]] || { _council_pool_cancel; }
                starts[seat_index]=$((starts[seat_index] + reservation_now - wait_start))
            elif [[ ! -f "${output}.pool-result" ]]; then
                break
            fi
            reservation_next=$((reservation_next + 1))
        done
        if (( pending > 0 && running < limit )); then
            if council_deadline_exceeded; then
                pending=0
                continue
            fi
            # Scan from the start each time to retain FIFO order within a provider
            # while allowing another provider to use otherwise idle capacity.
            next="$index"
            for ((seat_index=0; seat_index<index; seat_index++)); do
                (( launched[seat_index] == 0 )) || continue
                provider="${providers[seat_index]}"; same=0
                cap="$(council_pool_provider_limit "$provider")"
                for ((i=0; i<index; i++)); do
                    [[ -z "${pids[i]}" || "${providers[i]}" != "$provider" ]] || same=$((same + 1))
                done
                if (( same < cap )); then next="$seat_index"; break; fi
            done
            if (( next < index )); then
                # The existing estimator admits ALL required calls through this
                # phase, including earlier phases. Reserve that cumulative bound
                # before every admitted launch; children never admit budget.
                if [[ -n "${COUNCIL_MAX_COST:-}" ]] && council_cost_exceeds_cap "$through"; then
                    printf 'Council phase exceeds its projected cost cap: %s\n' "$through" >&2
                    _council_pool_cancel
                fi
                output="${outputs[next]}"
                printf '%s\n' "${COUNCIL_COST_CHECK_ESTIMATED:-0}" > "${output}.admitted.tmp"
                mv -f "${output}.admitted.tmp" "${output}.admitted"
                launch_order[launch_count]="$next"; launch_count=$((launch_count + 1))
                launched[next]=1; pending=$((pending - 1))
                COUNCIL_ASYNC_PID=""; COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE=""; rc=0
                _COUNCIL_POOL_LAUNCH=1 _OCTOPUS_SEAT_STDERR_FILE="${COUNCIL_RUN_DIR}/stderr/$(basename "$output" .md).log" \
                    council_dispatch_member_detached "${members[next]}" "$phase" "$output" || rc=$?
                if [[ -n "$COUNCIL_ASYNC_PID" ]]; then
                    pids[next]="$COUNCIL_ASYNC_PID"; timeouts[next]="$COUNCIL_ASYNC_TIMEOUT"
                    starts[next]="$(council_pool_now_ms)"; running=$((running + 1))
                else
                    printf '%s\n%s\n' "$rc" "$COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE" > "${output}.pool-result.tmp"
                    mv -f "${output}.pool-result.tmp" "${output}.pool-result"
                fi
                COUNCIL_ASYNC_PID=""
                continue
            fi
        fi
        (( running == 0 )) || sleep 0.1
    done
}
