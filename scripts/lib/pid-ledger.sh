#!/usr/bin/env bash

_OCTO_PID_LEDGER_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/pid-ledger.py"

octopus_pid_register() {
    python3 "$_OCTO_PID_LEDGER_HELPER" register "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_matches() {
    python3 "$_OCTO_PID_LEDGER_HELPER" verify "$PID_FILE" "$1" "$2"
}

# Active PID arrays can outlive a worker. Re-read its registration before use.
octopus_pid_task_matches() {
    local wanted_pid="$1" wanted_task="$2" pid agent task identity
    [[ -f "$PID_FILE" ]] || return 1
    while IFS=: read -r pid agent task identity; do
        [[ "$pid" == "$wanted_pid" && "$task" == "$wanted_task" ]] || continue
        if octopus_pid_matches "$pid" "$identity"; then return 0; fi
    done < "$PID_FILE"
    return 1
}

octopus_pid_retire() {
    python3 "$_OCTO_PID_LEDGER_HELPER" remove "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_prune() {
    python3 "$_OCTO_PID_LEDGER_HELPER" prune "$PID_FILE" "$1"
}

octopus_pid_agent_name() {
    local name="${1//%3A/:}"
    printf '%s\n' "${name//%25/%}"
}
