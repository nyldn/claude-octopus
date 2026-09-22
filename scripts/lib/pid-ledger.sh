#!/usr/bin/env bash

if declare -F octopus_pid_python_resolve >/dev/null 2>&1; then
    return 0 2>/dev/null || exit 0
fi

_OCTO_PID_LEDGER_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/pid-ledger.py"
_OCTO_PID_LEDGER_PYTHON=""
_OCTO_PID_LEDGER_PYTHON_ERROR=""
_OCTO_PID_PYTHON_CANDIDATES=(python3 /usr/bin/python3 python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9)

_octo_pid_python_path() {
    local candidate="$1"
    if [[ "$candidate" == */* ]]; then
        [[ -x "$candidate" ]] || return 1
        printf '%s\n' "$candidate"
    else
        command -v "$candidate" 2>/dev/null
    fi
}

_octo_pid_python_capable() {
    "$1" "$_OCTO_PID_LEDGER_HELPER" capability >/dev/null 2>&1
}

octopus_pid_python_resolve() {
    local candidate="" resolved="" seen=""
    if [[ -n "${OCTOPUS_PYTHON:-}" ]]; then
        resolved="$(_octo_pid_python_path "$OCTOPUS_PYTHON" 2>/dev/null || true)"
        if [[ -n "$resolved" && "${_OCTO_PID_LEDGER_PYTHON:-}" == "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
        if [[ -n "$resolved" ]] && _octo_pid_python_capable "$resolved"; then
            _OCTO_PID_LEDGER_PYTHON="$resolved"
            printf '%s\n' "$resolved"
            return 0
        fi
        _OCTO_PID_LEDGER_PYTHON_ERROR="OCTOPUS_PYTHON does not provide the native process APIs required on this platform: $OCTOPUS_PYTHON"
        printf '%s\n' "$_OCTO_PID_LEDGER_PYTHON_ERROR" >&2
        return 1
    fi

    if [[ -n "${_OCTO_PID_LEDGER_PYTHON:-}" ]]; then
        printf '%s\n' "$_OCTO_PID_LEDGER_PYTHON"
        return 0
    fi

    for candidate in "${_OCTO_PID_PYTHON_CANDIDATES[@]}"; do
        [[ -n "$candidate" ]] || continue
        resolved="$(_octo_pid_python_path "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        case "$seen" in *"|${resolved}|"*) continue ;; esac
        seen="${seen}|${resolved}|"
        if _octo_pid_python_capable "$resolved"; then
            _OCTO_PID_LEDGER_PYTHON="$resolved"
            printf '%s\n' "$resolved"
            return 0
        fi
    done

    _OCTO_PID_LEDGER_PYTHON_ERROR="No Python interpreter with the native process APIs required on this platform was found"
    printf '%s\n' "$_OCTO_PID_LEDGER_PYTHON_ERROR" >&2
    return 1
}

_octo_pid_python_run() {
    octopus_pid_python_resolve >/dev/null || return 1
    "${_OCTO_PID_LEDGER_PYTHON:?PID ledger Python was not resolved}" "$@"
}

octopus_pid_register() {
    _octo_pid_python_run "$_OCTO_PID_LEDGER_HELPER" register "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_matches() {
    _octo_pid_python_run "$_OCTO_PID_LEDGER_HELPER" verify "$PID_FILE" "$1" "$2"
}

# Resolve a workflow's rows in one interpreter instead of rescanning per worker.
octopus_pid_verified_rows() {
    _octo_pid_python_run "$_OCTO_PID_LEDGER_HELPER" verified "$PID_FILE" "$1"
}

octopus_pid_retire() {
    _octo_pid_python_run "$_OCTO_PID_LEDGER_HELPER" remove "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_prune() {
    _octo_pid_python_run "$_OCTO_PID_LEDGER_HELPER" prune "$PID_FILE" "$1"
}

octopus_pid_agent_name() {
    local name="${1//%3A/:}"
    printf '%s\n' "${name//%25/%}"
}
