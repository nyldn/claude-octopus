#!/usr/bin/env bash
# Unit tests for scripts/lib/plugin-root.sh — octo_write_stable_script_shim
# self-targeting guard. See #521.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/plugin-root.sh"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Plugin Root Shim Self-Targeting Guard (#521)"

test_lib_sourceable() {
    test_case "plugin-root.sh is readable and syntactically valid"
    [[ -r "$LIB" ]] && bash -n "$LIB" && test_pass || test_fail "lib missing or has syntax errors"
}

# Reproduces #521: stable_root/scripts is a symlink into the live plugin
# cache, so dst physically resolves to src. The shim must refuse to write
# and leave the live script untouched, instead of corrupting it into a
# self-referential exec stub.
test_refuses_self_targeting_write() {
    test_case "octo_write_stable_script_shim does not overwrite src when dst resolves to src"
    local work
    work=$(mktemp -d)
    mkdir -p "$work/cache/9.45.0/scripts"
    cat > "$work/cache/9.45.0/scripts/orchestrate.sh" <<'EOF'
#!/usr/bin/env bash
echo "real orchestrate.sh"
EOF
    chmod +x "$work/cache/9.45.0/scripts/orchestrate.sh"
    mkdir -p "$work/stable"
    ln -s "$work/cache/9.45.0/scripts" "$work/stable/scripts"

    bash -c "source '$LIB'; octo_write_stable_script_shim '$work/cache/9.45.0' '$work/stable' 'scripts/orchestrate.sh'"

    local contents
    contents="$(cat "$work/cache/9.45.0/scripts/orchestrate.sh")"
    rm -rf "$work"

    if [[ "$contents" == *"real orchestrate.sh"* && "$contents" != *"exec "* ]]; then
        test_pass
    else
        test_fail "live script was overwritten with a shim: $contents"
    fi
}

# Normal case: stable_root is a plain directory (e.g. Windows Git Bash
# fallback) whose children are NOT symlinks into the cache. The shim should
# still write the wrapper as before.
test_writes_shim_when_not_self_targeting() {
    test_case "octo_write_stable_script_shim still writes a wrapper for a genuinely separate dst"
    local work
    work=$(mktemp -d)
    mkdir -p "$work/cache/9.45.0/scripts"
    cat > "$work/cache/9.45.0/scripts/orchestrate.sh" <<'EOF'
#!/usr/bin/env bash
echo "real orchestrate.sh"
EOF
    chmod +x "$work/cache/9.45.0/scripts/orchestrate.sh"
    mkdir -p "$work/stable"

    bash -c "source '$LIB'; octo_write_stable_script_shim '$work/cache/9.45.0' '$work/stable' 'scripts/orchestrate.sh'"

    local contents
    contents="$(cat "$work/stable/scripts/orchestrate.sh" 2>/dev/null || echo MISSING)"
    rm -rf "$work"

    [[ "$contents" == *"exec "* ]] && test_pass || test_fail "expected an exec wrapper, got: $contents"
}

test_lib_sourceable
test_refuses_self_targeting_write
test_writes_shim_when_not_self_targeting

test_summary
