#!/usr/bin/env bash
# Source-safe Python resolver for Windows hook processes.
# Windows App Execution Aliases report as executables but launch Microsoft
# Store instead of an interpreter. Redirect python3 to a real python/py binary,
# or remove the alias directory from PATH so availability checks fail safely.

if [[ -z "${_OCTOPUS_PYTHON_RUNTIME_READY:-}" ]]; then
    _OCTOPUS_PYTHON_RUNTIME_READY=1
    _octopus_python3_path=$(type -P python3 2>/dev/null || true)

    case "$_octopus_python3_path" in
        */WindowsApps/*|*\\WindowsApps\\*)
            _octopus_real_python=$(type -P python 2>/dev/null || true)
            case "$_octopus_real_python" in
                */WindowsApps/*|*\\WindowsApps\\*) _octopus_real_python="" ;;
            esac

            if [[ -n "$_octopus_real_python" ]]; then
                _OCTOPUS_REAL_PYTHON="$_octopus_real_python"
                export _OCTOPUS_REAL_PYTHON
                python3() { "$_OCTOPUS_REAL_PYTHON" "$@"; }
            else
                _octopus_py_launcher=$(type -P py 2>/dev/null || true)
                case "$_octopus_py_launcher" in
                    */WindowsApps/*|*\\WindowsApps\\*) _octopus_py_launcher="" ;;
                esac
                if [[ -n "$_octopus_py_launcher" ]]; then
                    _OCTOPUS_PY_LAUNCHER="$_octopus_py_launcher"
                    export _OCTOPUS_PY_LAUNCHER
                    python3() { "$_OCTOPUS_PY_LAUNCHER" -3 "$@"; }
                else
                    _octopus_alias_dir=${_octopus_python3_path%/*}
                    _octopus_clean_path=""
                    _octopus_old_ifs=$IFS
                    IFS=:
                    for _octopus_path_entry in $PATH; do
                        [[ "$_octopus_path_entry" == "$_octopus_alias_dir" ]] && continue
                        _octopus_clean_path="${_octopus_clean_path:+${_octopus_clean_path}:}${_octopus_path_entry}"
                    done
                    IFS=$_octopus_old_ifs
                    PATH=$_octopus_clean_path
                    export PATH
                    hash -r 2>/dev/null || true
                fi
            fi
            ;;
    esac
fi

# Orchestrator subprocesses and helper scripts inherit the safe resolver.
if declare -F python3 >/dev/null 2>&1; then
    export -f python3 2>/dev/null || true
fi
