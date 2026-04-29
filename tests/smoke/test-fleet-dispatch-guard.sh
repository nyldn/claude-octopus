#!/bin/bash
# tests/smoke/test-fleet-dispatch-guard.sh
# Ensures every parallel spawn_agent call site is wrapped with fleet_dispatch_begin/end.
# Prevents regression of issue #289 / #288: Agent Teams dispatch silently drops results
# when orchestrate.sh runs as a Bash tool subprocess.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Fleet Dispatch Guard"

# Files that contain parallel spawn_agent calls and must have fleet_dispatch_begin/end
FLEET_FILES=(
    "scripts/lib/workflows.sh"
    "scripts/lib/review.sh"
    "scripts/lib/yaml-workflow.sh"
)

test_fleet_guard_present() {
    test_case "fleet_dispatch_begin/end present in all parallel spawn files"
    local failed=0
    for rel in "${FLEET_FILES[@]}"; do
        local f="$PROJECT_ROOT/$rel"
        if ! grep -q "fleet_dispatch_begin" "$f" 2>/dev/null; then
            echo "  MISSING fleet_dispatch_begin in: $rel"
            failed=1
        fi
        if ! grep -q "fleet_dispatch_end" "$f" 2>/dev/null; then
            echo "  MISSING fleet_dispatch_end in: $rel"
            failed=1
        fi
    done
    [[ $failed -eq 0 ]] && test_pass || test_fail "One or more fleet dispatch sites are missing guards"
}

test_no_bare_force_legacy_export() {
    test_case "No raw OCTOPUS_FORCE_LEGACY_DISPATCH exports outside agent-sync.sh"
    local found
    found=$(grep -rn "export OCTOPUS_FORCE_LEGACY_DISPATCH" "$PROJECT_ROOT/scripts" \
        --include="*.sh" | grep -v "scripts/lib/agent-sync.sh" || true)
    if [[ -z "$found" ]]; then
        test_pass
    else
        test_fail "Raw export of OCTOPUS_FORCE_LEGACY_DISPATCH found (use fleet_dispatch_begin instead):
$found"
    fi
}

test_hooks_json_matchers() {
    test_case "Every hook block in .claude-plugin/hooks.json has a matcher"
    local hooks_json="$PROJECT_ROOT/.claude-plugin/hooks.json"
    if [[ ! -f "$hooks_json" ]]; then
        test_fail "hooks.json not found"
        return 1
    fi
    if ! python3 -m json.tool "$hooks_json" > /dev/null 2>&1; then
        test_fail "hooks.json is not valid JSON"
        return 1
    fi
    # Extract all hook-block objects and check each has "matcher"
    local missing
    missing=$(python3 - "$hooks_json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
bad = []
for event, blocks in data.items():
    if not isinstance(blocks, list):
        continue
    for i, block in enumerate(blocks):
        if isinstance(block, dict) and "matcher" not in block:
            bad.append(f"{event}[{i}]")
if bad:
    print("Missing matcher in: " + ", ".join(bad))
    sys.exit(1)
EOF
)
    if [[ $? -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing"
    fi
}

test_provider_pid_capture() {
    test_case "Parallel workflow waits track provider PIDs, not wrapper PIDs"

    local failed=0
    local pid_capture_files=(
        "scripts/lib/workflows.sh"
        "scripts/lib/yaml-workflow.sh"
        "scripts/lib/agent-utils.sh"
        "scripts/lib/parallel.sh"
        "scripts/lib/auto-route.sh"
        "scripts/async-tmux-features.sh"
    )
    local pid_capture_paths=()
    local rel
    for rel in "${pid_capture_files[@]}"; do
        pid_capture_paths+=("$PROJECT_ROOT/$rel")
    done

    if ! grep -q '^spawn_agent_capture_pid()' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
        echo "  MISSING spawn_agent_capture_pid helper in scripts/lib/spawn.sh"
        failed=1
    fi

    for rel in "${pid_capture_files[@]}"; do
        if ! grep -q 'spawn_agent_capture_pid' "$PROJECT_ROOT/$rel"; then
            echo "  MISSING provider PID capture in: $rel"
            failed=1
        fi
    done

    local wrapper_tracking
    wrapper_tracking=$(
        {
            grep -RnE 'pids[^=]*[+]?=.*\$!' \
                "${pid_capture_paths[@]}" 2>/dev/null || true
            awk '
                /pid=\$!/ { pending=NR; line=$0; next }
                pending && NR <= pending + 5 && /pids/ { print FILENAME ":" pending ":" line " ... " $0; pending=0 }
                pending && NR > pending + 5 { pending=0 }
            ' "${pid_capture_paths[@]}" 2>/dev/null || true
            grep -RnE 'pid=\$\(spawn_agent[[:space:]]' \
                "${pid_capture_paths[@]}" 2>/dev/null || true
        } | sed '/^$/d'
    )
    if [[ -n "$wrapper_tracking" ]]; then
        echo "  Found wrapper PID tracking:"
        echo "$wrapper_tracking"
        failed=1
    fi

    [[ $failed -eq 0 ]] && test_pass || test_fail "Parallel workflow code still risks tracking short-lived spawn_agent wrapper PIDs"
}

test_fleet_guard_present
test_no_bare_force_legacy_export
test_hooks_json_matchers
test_provider_pid_capture

test_summary
