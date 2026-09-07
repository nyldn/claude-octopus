#!/usr/bin/env bash

_OCTO_PID_LEDGER_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/pid-ledger.py"

octopus_pid_register() {
    python3 "$_OCTO_PID_LEDGER_HELPER" register "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_matches() {
    python3 "$_OCTO_PID_LEDGER_HELPER" verify "$PID_FILE" "$1" "$2"
}

# Resolve a workflow's rows in one interpreter instead of rescanning per worker.
octopus_pid_verified_rows() {
    python3 "$_OCTO_PID_LEDGER_HELPER" verified "$PID_FILE" "$1"
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
