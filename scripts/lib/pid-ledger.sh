#!/usr/bin/env bash

_OCTO_PID_LEDGER_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/pid-ledger.py"

# #1075: a bare `python3` on PATH is not necessarily pidfd-capable — the build
# matters, not the version, so a newer interpreter (e.g. an Anaconda build
# earlier on PATH) can lack os.pidfd_open/signal.pidfd_send_signal while an
# older one has them. Probe candidates for the actual capability once and
# cache the winner in _OCTO_PID_LEDGER_PYTHON. OCTO_PYTHON is tried first,
# not a hard pin — if it fails the capability check, the probe still falls
# through to the remaining candidates rather than failing closed on a
# caller's stale or unrelated override. pidfd is Linux-only (process_control.py
# gates it on sys.platform.startswith("linux")), so non-Linux hosts skip the
# probe entirely rather than burning subprocesses on a check that can never
# pass there.
#
# Must be called directly (never as "$(_octopus_pid_ledger_resolve_python)")
# — command substitution forks a subshell, and an assignment made inside one
# never reaches the calling shell, which would silently turn the cache into
# a no-op and re-run the full probe on every call. This also means the cache
# does not survive from a worker's registration into its own EXIT-trap
# retirement: spawn_agent forks each worker into a dedicated subshell, and
# the register call inside it is itself wrapped in a further "$(...)" to
# capture its output — both fork fresh subshells, so a cache populated there
# cannot reach the trap's later octopus_pid_retire call, which runs directly
# in the worker's own subshell. spawn_agent resolves the interpreter once,
# before forking that subshell, specifically so both calls inherit an
# already-cached value instead of each probing again.
_octopus_pid_ledger_resolve_python() {
    [[ -n "${_OCTO_PID_LEDGER_PYTHON:-}" ]] && return 0
    [[ "$(uname -s 2>/dev/null)" == "Linux" ]] || { _octopus_pid_ledger_default_python; return 0; }
    local candidate
    for candidate in "${OCTO_PYTHON:-}" python3 /usr/bin/python3 python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9; do
        [[ -n "$candidate" ]] || continue
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -c 'import os, signal, sys
sys.exit(0 if callable(getattr(os, "pidfd_open", None)) and callable(getattr(signal, "pidfd_send_signal", None)) else 1)' 2>/dev/null; then
            _OCTO_PID_LEDGER_PYTHON="$candidate"
            return 0
        fi
    done
    _octopus_pid_ledger_default_python
}

# No candidate passed the capability probe (or it was skipped on non-Linux).
# Prefer OCTO_PYTHON only if it's an actual executable — an unresolved or
# stale override must not become a hard "command not found" on every ledger
# call, which pre-#1075 code (always bare `python3`) never risked.
_octopus_pid_ledger_default_python() {
    if [[ -n "${OCTO_PYTHON:-}" ]] && command -v "$OCTO_PYTHON" >/dev/null 2>&1; then
        _OCTO_PID_LEDGER_PYTHON="$OCTO_PYTHON"
    else
        _OCTO_PID_LEDGER_PYTHON="python3"
    fi
}

octopus_pid_register() {
    _octopus_pid_ledger_resolve_python
    "$_OCTO_PID_LEDGER_PYTHON" "$_OCTO_PID_LEDGER_HELPER" register "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_matches() {
    _octopus_pid_ledger_resolve_python
    "$_OCTO_PID_LEDGER_PYTHON" "$_OCTO_PID_LEDGER_HELPER" verify "$PID_FILE" "$1" "$2"
}

# Resolve a workflow's rows in one interpreter instead of rescanning per worker.
octopus_pid_verified_rows() {
    _octopus_pid_ledger_resolve_python
    "$_OCTO_PID_LEDGER_PYTHON" "$_OCTO_PID_LEDGER_HELPER" verified "$PID_FILE" "$1"
}

octopus_pid_retire() {
    _octopus_pid_ledger_resolve_python
    "$_OCTO_PID_LEDGER_PYTHON" "$_OCTO_PID_LEDGER_HELPER" remove "$PID_FILE" "$1" "$2" "$3"
}

octopus_pid_prune() {
    _octopus_pid_ledger_resolve_python
    "$_OCTO_PID_LEDGER_PYTHON" "$_OCTO_PID_LEDGER_HELPER" prune "$PID_FILE" "$1"
}

octopus_pid_agent_name() {
    local name="${1//%3A/:}"
    printf '%s\n' "${name//%25/%}"
}
