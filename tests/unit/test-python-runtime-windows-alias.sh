#!/usr/bin/env bash
# Regression: Windows Store App Execution Alias must never be invoked as Python.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-python-runtime.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

WINDOWS_APPS="$TMP_DIR/WindowsApps"
REAL_BIN="$TMP_DIR/RealPython"
mkdir -p "$WINDOWS_APPS" "$REAL_BIN"

cat > "$WINDOWS_APPS/python3" <<EOF
#!/usr/bin/env bash
touch "$TMP_DIR/store-alias-invoked"
exit 49
EOF
cat > "$REAL_BIN/python" <<'EOF'
#!/usr/bin/env bash
printf 'REAL_PYTHON:%s\n' "$*"
EOF
chmod +x "$WINDOWS_APPS/python3" "$REAL_BIN/python"

ORIGINAL_PATH="$PATH"
PATH="$WINDOWS_APPS:$REAL_BIN:$ORIGINAL_PATH"
source "$ROOT_DIR/scripts/lib/python-runtime.sh"

output="$(python3 -c 'probe')"
[[ "$output" == "REAL_PYTHON:-c probe" ]] || {
    echo "FAIL: python3 was not redirected to the real interpreter" >&2
    exit 1
}

child_output="$(bash -c "python3 -c child-probe")"
[[ "$child_output" == "REAL_PYTHON:-c child-probe" ]] || {
    echo "FAIL: child Bash process lost the safe Python resolver" >&2
    exit 1
}
[[ ! -e "$TMP_DIR/store-alias-invoked" ]] || {
    echo "FAIL: Windows Store alias was invoked" >&2
    exit 1
}

while IFS= read -r hook; do
    grep -Fq 'scripts/lib/python-runtime.sh' "$hook" || {
        echo "FAIL: hook uses python3 without runtime guard: $hook" >&2
        exit 1
    }
done < <(rg -l '(^|[^[:alnum:]_])python3([^[:alnum:]_]|$)' "$ROOT_DIR/hooks" -g '*.sh')

echo "PASS: Windows Store Python alias is rejected by hook runtime"
