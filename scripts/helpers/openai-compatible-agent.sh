#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${OCTOPUS_PYTHON_BIN:-}" ]]; then
    exec "$OCTOPUS_PYTHON_BIN" "$SCRIPT_DIR/openai-compatible-agent.py" "$@"
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
    exec "$resolved" "$SCRIPT_DIR/openai-compatible-agent.py" "$@"
done

for candidate in "${HOME}"/.cache/codex-runtimes/*/dependencies/python/python.exe; do
    [[ -x "$candidate" ]] || continue
    exec "$candidate" "$SCRIPT_DIR/openai-compatible-agent.py" "$@"
done

if command -v py >/dev/null 2>&1; then
    exec py -3 "$SCRIPT_DIR/openai-compatible-agent.py" "$@"
fi

echo "ERROR: no real Python runtime found; set OCTOPUS_PYTHON_BIN" >&2
exit 127
