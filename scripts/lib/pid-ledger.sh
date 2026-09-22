#!/usr/bin/env bash

_OCTO_PID_LEDGER_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/pid-ledger.py"

# #1075: a bare `python3` on PATH is not necessarily pidfd-capable — the build
# matters, not the version, so a newer interpreter (e.g. an Anaconda build
# earlier on PATH) can lack os.pidfd_open/signal.pidfd_send_signal while an
# older one has them. Probe candidates for the actual capability once and
# cache the winner; OCTO_PYTHON lets a caller pin an interpreter directly.
# Non-Linux cancellation never uses pidfd, so the probe harmlessly falls
# through to the default there.
_octopus_pid_ledger_python() {
    if [[ -z "${_OCTO_PID_LEDGER_PYTHON:-}" ]]; then
        local candidate
        for candidate in "${OCTO_PYTHON:-}" python3 /usr/bin/python3 python3.13 python3.12 python3.11 python3.10 python3.9; do
            [[ -n "$candidate" ]] || continue
            command -v "$candidate" >/dev/null 2>&1 || continue
            if "$candidate" -c 'import os, signal, sys
sys.exit(0 if callable(getattr(os, "pidfd_open", None)) and callable(getattr(signal, "pidfd_send_signal", None)) else 1)' 2>/dev/null; then
                _OCTO_PID_LEDGER_PYTHON="$candidate"
                break
            fi
        done
        [[ -n "${_OCTO_PID_LEDGER_PYTHON:-}" ]] || _OCTO_PID_LEDGER_PYTHON="${OCTO_PYTHON:-python3}"
    fi
    printf '%s\n' "$_OCTO_PID_LEDGER_PYTHON"
}

octopus_pid_register() {
    "$(_octopus_pid_ledger_python)" "$_OCTO_PID_LEDGER_HELPER" register "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_matches() {
    "$(_octopus_pid_ledger_python)" "$_OCTO_PID_LEDGER_HELPER" verify "$PID_FILE" "$1" "$2"
}

# Resolve a workflow's rows in one interpreter instead of rescanning per worker.
octopus_pid_verified_rows() {
    "$(_octopus_pid_ledger_python)" "$_OCTO_PID_LEDGER_HELPER" verified "$PID_FILE" "$1"
}

octopus_pid_retire() {
    "$(_octopus_pid_ledger_python)" "$_OCTO_PID_LEDGER_HELPER" remove "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_prune() {
    "$(_octopus_pid_ledger_python)" "$_OCTO_PID_LEDGER_HELPER" prune "$PID_FILE" "$1"
}

octopus_pid_agent_name() {
    local name="${1//%3A/:}"
    printf '%s\n' "${name//%25/%}"
}
