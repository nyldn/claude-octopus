#!/usr/bin/env bash
# Claude Octopus — state-root capability helpers
#
# Restricted hosts own filesystem policy. These helpers only test the state
# root already selected by the host/caller; they never select a fallback path.

octopus_state_root_is_writable() {
    local root="${1:-}"
    [[ -n "$root" ]] || return 1

    mkdir -p "$root" 2>/dev/null || return 1

    local probe="${root}/.octopus-write-probe-$$-${RANDOM:-0}"
    (umask 077; : >"$probe") 2>/dev/null || return 1
    rm -f "$probe" 2>/dev/null || true
    return 0
}

octopus_configure_persistence() {
    local root="${1:-}"
    if octopus_state_root_is_writable "$root"; then
        OCTOPUS_PERSISTENCE_AVAILABLE=true
    else
        OCTOPUS_PERSISTENCE_AVAILABLE=false
        unset OCTO_EVENT_LOG
    fi
    export OCTOPUS_PERSISTENCE_AVAILABLE
}

octopus_persistence_diagnostic() {
    [[ "${OCTOPUS_PERSISTENCE_AVAILABLE:-true}" == "false" ]] || return 0
    [[ "${OCTOPUS_DEBUG:-false}" == "true" ]] || return 0
    [[ "${_OCTOPUS_PERSISTENCE_DIAGNOSTIC_EMITTED:-false}" == "true" ]] && return 0

    _OCTOPUS_PERSISTENCE_DIAGNOSTIC_EMITTED=true
    local escaped_root
    escaped_root=$(json_escape "${WORKSPACE_DIR:-unavailable}")
    printf '{"source":"octopus","event":"persistence.disabled","state_root":"%s"}\n' \
        "$escaped_root" >&2
}

# Run a provider without Octopus-owned result, metric, event, PID, or log files.
# Output is streamed directly to the caller so a denied optional state root
# cannot hide an otherwise successful provider result.
octopus_run_provider_without_persistence() {
    local agent_type="$1"
    local prompt="$2"
    local timeout_secs="$3"
    local cmd="$4"
    local -a cmd_array
    local -a inner_cmd_array

    octopus_persistence_diagnostic
    build_provider_env "$agent_type"
    read -ra inner_cmd_array <<<"$cmd"
    if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
        cmd_array=("${PROVIDER_ENV_ARRAY[@]}" "${inner_cmd_array[@]}")
    else
        cmd_array=("${inner_cmd_array[@]}")
    fi

    if [[ "$agent_type" == gemini* || "$agent_type" == copilot* || \
          "$agent_type" == qwen* || "$agent_type" == cursor-agent* ]]; then
        cmd_array+=(-p "")
    fi

    local exit_code=0
    if printf '%s' "$prompt" | run_with_timeout "$timeout_secs" "${cmd_array[@]}"; then
        exit_code=0
    else
        local -a pipeline_status=("${PIPESTATUS[@]}")
        exit_code="${pipeline_status[1]:-1}"
    fi
    return "$exit_code"
}
