#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_PATH="$SCRIPT_DIR/openai-compatible-agent.py"

case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
        if command -v cygpath >/dev/null 2>&1; then
            HELPER_PATH="$(cygpath -w "$HELPER_PATH")"
        fi
        ;;
esac

if [[ -n "${OCTOPUS_PYTHON_BIN:-}" ]]; then
    exec "$OCTOPUS_PYTHON_BIN" "$HELPER_PATH" "$@"
fi

is_windows_alias() {
    case "${1:-}" in
        *Microsoft/WindowsApps*|*Microsoft\\WindowsApps*) return 0 ;;
        *) return 1 ;;
    esac
}

case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) candidates=(python python3) ;;
    *) candidates=(python3 python) ;;
esac

for candidate in "${candidates[@]}"; do
    resolved="$(command -v "$candidate" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || continue
    is_windows_alias "$resolved" && continue
    exec "$resolved" "$HELPER_PATH" "$@"
done

for candidate in "${HOME}"/.cache/codex-runtimes/*/dependencies/python/python.exe; do
    [[ -x "$candidate" ]] || continue
    exec "$candidate" "$HELPER_PATH" "$@"
done

if command -v py >/dev/null 2>&1; then
    exec py -3 "$HELPER_PATH" "$@"
fi

echo "ERROR: no real Python runtime found; set OCTOPUS_PYTHON_BIN" >&2
exit 127
