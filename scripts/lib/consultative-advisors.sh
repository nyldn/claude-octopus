#!/usr/bin/env bash
# Shared admission and launch contract for brainstorm and debate advisors.
# Sourced library: do not change the caller's shell options.

_octo_consultative_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_octo_consultative_allowlist="${_octo_consultative_lib_dir}/provider-allowlist.sh"
if [[ ! -r "$_octo_consultative_allowlist" ]] ||
   ! source "$_octo_consultative_allowlist"; then
    printf 'ERROR: consultative advisor allowlist is unavailable\n' >&2
    return 1 2>/dev/null || exit 1
fi

octo_consultative_provider_is_launchable() {
    local provider="${1%%:*}"
    case "$provider" in
        codex|commandcode|grok|agy|gemini|antigravity|copilot|qwen|\
        cursor-agent|opencode|ollama|vibe|openrouter|openai-compatible|\
        atlascloud-agent|perplexity)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

octo_consultative_host_allowed() {
    octo_provider_allowed claude-sonnet
}

octo_consultative_required_external_count() {
    if octo_consultative_host_allowed; then
        printf '1\n'
    else
        printf '2\n'
    fi
}

octo_consultative_provider_count_is_sufficient() {
    local external_count="$1" host_count="$2"
    case "$external_count" in ""|*[!0-9]*) return 1 ;; esac
    case "$host_count" in ""|*[!0-9]*) return 1 ;; esac
    [[ $((external_count + host_count)) -ge 2 ]]
}

# Print the provider's answer from a spawn result file. A length-framed file
# (Prompt-Format: octopus-length-v1) is read from just past its embedded prompt,
# skipped by exact byte count as tangle_result_output_excerpt does, so prompt
# text is never taken for output. The answer is the fenced block that opens
# after "# Started:" and "## Output". For codex-family output it closes at the
# fence before the END-UNTRUSTED marker whose nonce matches the BEGIN marker;
# otherwise at the last fence before the trailer spawn.sh appends (Native
# Metrics, Warnings/Errors, Runtime Identity, Status).
_octo_advisor_output_from_result() {
    local result_file="$1" frame prompt_line prompt_bytes header_bytes
    frame="$(awk '
        /^# Prompt: / || /^# Started: / || /^## Output[[:space:]]*$/ { exit }
        /^# Prompt-Format: octopus-length-v1$/ {
            format_line = NR
            if ((getline) > 0 && $0 ~ /^# Prompt-Bytes: [0-9]+$/) print format_line ":" $3
            exit
        }' "$result_file" 2>/dev/null)"
    if [[ "$frame" =~ ^([1-9][0-9]*):([0-9]+)$ ]]; then
        prompt_line="${BASH_REMATCH[1]}"
        prompt_bytes="${BASH_REMATCH[2]}"
        header_bytes="$(head -n "$((prompt_line + 1))" "$result_file" | wc -c | tr -d '[:space:]')"
        tail -c "+$((header_bytes + prompt_bytes + 1))" "$result_file"
    else
        cat "$result_file"
    fi | awk '
        { line[NR] = $0 }
        !open_at && /^# Started: / { started = 1 }
        !open_at && started && prev == "## Output" && $0 == "```" {
            open_at = NR
            # Codex-family output sits between BEGIN/END markers sharing a random
            # nonce; the matching END marker is the one exact end of the answer.
            if (prev2 ~ /^<!-- BEGIN-UNTRUSTED:provider=[^ ]*:nonce=[^ ]* -->$/) {
                end_mark = prev2
                sub(/BEGIN-UNTRUSTED/, "END-UNTRUSTED", end_mark)
            }
        }
        open_at && end_mark != "" && !end_mark_at && $0 == end_mark { end_mark_at = NR }
        { prev2 = prev; prev = $0 }
        /^## Runtime Identity$/ { ident_at = NR }
        /^## Status: / { status_at = NR }
        /^## Warnings\/Errors$/ { warn_at = NR }
        /^## Native Metrics$/ { metrics_at = NR }
        /^<!-- END-UNTRUSTED:provider=/ { end_at = NR }
        END {
            if (!open_at) exit 1
            if (end_mark_at && line[end_mark_at - 1] == "```" && end_mark_at - 1 > open_at) {
                for (i = open_at + 1; i < end_mark_at - 1; i++) print line[i]
                exit 0
            }
            stop = ident_at ? ident_at : (status_at ? status_at : NR + 1)
            if (warn_at > open_at && warn_at < stop && line[warn_at + 1] == "```") stop = warn_at
            if (metrics_at > open_at && metrics_at < stop) stop = metrics_at
            if (end_at > open_at && end_at < stop && line[end_at - 1] == "```") stop = end_at
            close_at = 0
            for (i = stop - 1; i > open_at; i--) if (line[i] == "```") { close_at = i; break }
            if (!close_at) exit 1
            for (i = open_at + 1; i < close_at; i++) print line[i]
        }
    '
}

# Wait for one advisor's worker and copy its answer into response_file.
# `orchestrate.sh spawn` is asynchronous: it prints status lines and the worker
# PID, then returns while the worker is still running, and the answer lands
# later in the worker's result file. The lifecycle hook installed by
# octo_launch_advisors records the worker's "spawned" and "completed" events
# (event, pid, status, result file) in event_log.
_octo_advisor_collect() {
    local event_log="$1" spawn_out="$2" response_file="$3" deadline="$4"
    local worker_pid result_file status gone_since="" now

    worker_pid="$(awk -F'\t' '$1 == "spawned" { p = $2 } END { print p }' "$event_log" 2>/dev/null)"
    if [[ -z "$worker_pid" ]]; then
        # A worker PID as spawn's last line means an asynchronous worker started
        # but its events were not recorded (the hook could not run). Its stdout
        # is not the answer, so fail loudly rather than report it as one.
        if [[ "$(awk 'NF { l = $0 } END { print l }' "$spawn_out" 2>/dev/null)" =~ ^[0-9]+$ ]]; then
            printf 'ERROR: advisor worker started but its lifecycle events were not recorded; answer not collected\n' >&2
            return 1
        fi
        # No asynchronous worker (the synchronous agy path): spawn's stdout is the answer.
        grep -c '[[:alnum:]]' "$spawn_out" >/dev/null 2>&1 || return 1
        cp "$spawn_out" "$response_file"
        return
    fi

    while ! awk -F'\t' '$1 == "completed" { found = 1 } END { exit !found }' "$event_log" 2>/dev/null; do
        now="$(date +%s)"
        if [[ "$now" -ge "$deadline" ]]; then
            printf 'ERROR: advisor worker %s did not finish before the wait deadline; it is still running\n' "$worker_pid" >&2
            return 1
        fi
        if ! kill -0 "$worker_pid" 2>/dev/null; then
            # The worker is gone; give its completion event a short grace period.
            [[ -n "$gone_since" ]] || gone_since="$now"
            [[ $((now - gone_since)) -ge 30 ]] && break
        fi
        sleep 2
    done

    status="$(awk -F'\t' '$1 == "completed" { s = $3 } END { print s }' "$event_log")"
    result_file="$(awk -F'\t' '$4 != "" { f = $4 } END { print f }' "$event_log")"
    if [[ -z "$result_file" || ! -f "$result_file" ]]; then
        printf 'ERROR: advisor worker %s left no result file\n' "$worker_pid" >&2
        return 1
    fi
    if [[ -n "$status" && "$status" != "completed" ]]; then
        printf 'ERROR: advisor worker %s ended with status %s (%s)\n' "$worker_pid" "$status" "$result_file" >&2
        return 1
    fi
    if [[ "$(awk '/^## Status: / { s = $0 } END { print s }' "$result_file")" != "## Status: SUCCESS"* ]]; then
        printf 'ERROR: advisor result is not a success: %s\n' "$result_file" >&2
        return 1
    fi
    # Write the answer beside response_file and move it into place only when it
    # holds real content (not just codex's "response was emitted on stderr"
    # placeholder), so a failed advisor never leaves a response behind.
    if _octo_advisor_output_from_result "$result_file" > "${response_file}.partial" &&
       awk 'NF && !/^\(Codex response was emitted on stderr/ { real = 1 } END { exit !real }' \
           "${response_file}.partial"; then
        mv -f "${response_file}.partial" "$response_file"
        return 0
    fi
    rm -f "${response_file}.partial"
    printf 'ERROR: no answer found in advisor result %s\n' "$result_file" >&2
    return 1
}

# Launch every selected external advisor, wait for each worker to finish, and
# print the number whose answer was collected. Return nonzero when fewer than
# required_successes produce usable output. This blocks for the whole provider
# run (often several minutes), so callers run it in the background or with a
# long timeout.
octo_launch_advisors() {
    local orchestrator="$1" advisors_csv="$2" output_dir="$3"
    local filename_prefix="$4" prompt_template="$5" required_successes="$6"
    local advisor safe_advisor prompt response_file pid index successful_count=0
    local advisor_list=() advisor_pids=() advisor_files=() advisor_events=() advisor_spawn_out=()
    local aux_dir hook event_log spawn_out deadline
    local wait_seconds="${OCTOPUS_ADVISOR_WAIT_SECONDS:-3600}"
    local prev_hook="${OCTOPUS_AGENT_LIFECYCLE_HOOK:-}"

    [[ -x "$orchestrator" ]] || {
        printf 'ERROR: advisor orchestrator is not executable: %s\n' "$orchestrator" >&2
        return 1
    }
    [[ -d "$output_dir" && -w "$output_dir" ]] || {
        printf 'ERROR: advisor output directory is not writable: %s\n' "$output_dir" >&2
        return 1
    }
    case "$required_successes" in
        ""|*[!0-9]*|0)
            printf 'ERROR: required advisor count must be a positive integer\n' >&2
            return 1
            ;;
    esac
    # 10# reads a leading zero (08, 09) as decimal, not invalid octal. An empty,
    # non-numeric or zero value falls back to the default.
    case "$wait_seconds" in ""|*[!0-9]*) wait_seconds=3600 ;; esac
    wait_seconds=$((10#$wait_seconds))
    [[ "$wait_seconds" -gt 0 ]] || wait_seconds=3600

    aux_dir="$(mktemp -d "${TMPDIR:-/tmp}/octo-advisors.XXXXXX")" || {
        printf 'ERROR: cannot create advisor work directory\n' >&2
        return 1
    }
    # Records each worker's lifecycle events, then chains any hook the caller set.
    hook="${aux_dir}/lifecycle-hook.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf '"'"'%s\t%s\t%s\t%s\n'"'"' "${1:-}" "${OCTOPUS_AGENT_PID:-}" "${OCTOPUS_AGENT_STATUS:-}" \' \
        '    "${OCTOPUS_AGENT_RESULT_FILE:-}" >> "$OCTO_ADVISOR_EVENT_LOG"' \
        'if [[ -n "${OCTO_ADVISOR_PREV_HOOK:-}" && -x "$OCTO_ADVISOR_PREV_HOOK" ]]; then' \
        '    exec "$OCTO_ADVISOR_PREV_HOOK" "$@"' \
        'fi' > "$hook"
    chmod +x "$hook"

    IFS=',' read -r -a advisor_list <<< "$advisors_csv"
    for advisor in "${advisor_list[@]}"; do
        [[ -n "$advisor" ]] || continue
        octo_consultative_provider_is_launchable "$advisor" || continue
        octo_provider_allowed "$advisor" || continue
        safe_advisor="$(printf '%s' "$advisor" | tr -c '[:alnum:]_-' '_')"
        response_file="${output_dir}/${filename_prefix}${safe_advisor}.md"
        prompt="${prompt_template//\{\{advisor\}\}/$advisor}"
        # A response left by an earlier attempt must not pass for this one.
        rm -f "$response_file"
        index=${#advisor_pids[@]}
        event_log="${aux_dir}/${index}-${safe_advisor}.events"
        spawn_out="${aux_dir}/${index}-${safe_advisor}.spawn"
        : > "$event_log"
        OCTOPUS_AGENT_LIFECYCLE_HOOK="$hook" OCTO_ADVISOR_EVENT_LOG="$event_log" \
            OCTO_ADVISOR_PREV_HOOK="$prev_hook" \
            "$orchestrator" spawn "$advisor" "$prompt" > "$spawn_out" &
        advisor_pids[$index]=$!
        advisor_files[$index]="$response_file"
        advisor_events[$index]="$event_log"
        advisor_spawn_out[$index]="$spawn_out"
    done

    if [[ ${#advisor_pids[@]} -eq 0 ]]; then
        rm -rf "$aux_dir"
        printf 'ERROR: no launchable external advisors were selected\n' >&2
        return 1
    fi

    deadline=$(( $(date +%s) + wait_seconds ))
    index=0
    while [[ $index -lt ${#advisor_pids[@]} ]]; do
        pid="${advisor_pids[$index]}"
        response_file="${advisor_files[$index]}"
        if wait "$pid" &&
           _octo_advisor_collect "${advisor_events[$index]}" "${advisor_spawn_out[$index]}" \
               "$response_file" "$deadline"; then
            successful_count=$((successful_count + 1))
        fi
        index=$((index + 1))
    done
    rm -rf "$aux_dir"

    if [[ "$successful_count" -lt "$required_successes" ]]; then
        printf 'ERROR: only %s of %s required external advisors succeeded\n' \
            "$successful_count" "$required_successes" >&2
        return 1
    fi
    printf '%s\n' "$successful_count"
}
