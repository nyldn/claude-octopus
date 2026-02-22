#!/bin/bash
# tests/unit/test-dependency-wbs.sh
# Tests dependency-aware parallel WBS (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Dependency-Aware Parallel WBS"

TEST_WORKSPACE="/tmp/octopus-test-wbs-$$"

setup_wbs_env() {
    rm -rf "$TEST_WORKSPACE"
    mkdir -p "$TEST_WORKSPACE/.octo/parallel"
}

cleanup_wbs_env() {
    rm -rf "$TEST_WORKSPACE"
}

# Helper: write a WBS file and run the dependency validation python script
run_dependency_validation() {
    local wbs_json="$1"
    echo "$wbs_json" > "$TEST_WORKSPACE/.octo/parallel/wbs.json"

    cd "$TEST_WORKSPACE/.octo/parallel" || return 1

    python3 << 'DEPEOF'
import json, sys

with open('wbs.json') as f:
    wbs = json.load(f)

packages = wbs['work_packages']
ids = {wp['id'] for wp in packages}
deps = {wp['id']: wp.get('dependencies', []) for wp in packages}

errors = []
for wp_id, wp_deps in deps.items():
    for dep in wp_deps:
        if dep not in ids:
            errors.append(f"WP {wp_id} depends on unknown {dep}")

if errors:
    print("DEPENDENCY VALIDATION: FAILED")
    for e in errors:
        print(f"  ERROR: {e}")
    sys.exit(1)

WHITE, GRAY, BLACK = 0, 1, 2
color = {wp_id: WHITE for wp_id in ids}

def has_cycle(node, path):
    color[node] = GRAY
    for dep in deps[node]:
        if color[dep] == GRAY:
            cycle = path[path.index(dep):] + [dep]
            return cycle
        if color[dep] == WHITE:
            result = has_cycle(dep, path + [dep])
            if result:
                return result
    color[node] = BLACK
    return None

for wp_id in ids:
    if color[wp_id] == WHITE:
        cycle = has_cycle(wp_id, [wp_id])
        if cycle:
            print(f"DEPENDENCY VALIDATION: FAILED - Cycle detected: {' -> '.join(cycle)}")
            sys.exit(1)

waves = {}
def get_wave(wp_id):
    if wp_id in waves:
        return waves[wp_id]
    if not deps[wp_id]:
        waves[wp_id] = 1
        return 1
    max_dep_wave = max(get_wave(d) for d in deps[wp_id])
    waves[wp_id] = max_dep_wave + 1
    return waves[wp_id]

for wp_id in ids:
    get_wave(wp_id)

for wp in packages:
    wp['wave'] = waves[wp['id']]

with open('wbs.json', 'w') as f:
    json.dump(wbs, f, indent=2)

max_wave = max(waves.values())
print(f"DEPENDENCY VALIDATION: PASSED")
print(f"Waves assigned: {max_wave}")
for w in range(1, max_wave + 1):
    wave_wps = [wp_id for wp_id, wave in waves.items() if wave == w]
    print(f"  Wave {w}: {', '.join(wave_wps)}")
DEPEOF

    cd - > /dev/null || true
}

# ── Tests ──

test_no_dependencies_all_wave_1() {
    test_case "No dependencies: all WPs get wave 1 (backward compatible)"
    setup_wbs_env

    local output
    output=$(run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": []},
        {"id": "WP-2", "name": "B", "scope": "b", "expected_outputs": [], "dependencies": []},
        {"id": "WP-3", "name": "C", "scope": "c", "expected_outputs": [], "dependencies": []}
      ]
    }')

    if echo "$output" | grep -q "PASSED" && echo "$output" | grep -q "Waves assigned: 1"; then
        test_pass
    else
        test_fail "Expected all wave 1: $output"
    fi
    cleanup_wbs_env
}

test_linear_dependencies() {
    test_case "Linear dependencies produce sequential waves"
    setup_wbs_env

    local output
    output=$(run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": []},
        {"id": "WP-2", "name": "B", "scope": "b", "expected_outputs": [], "dependencies": ["WP-1"]},
        {"id": "WP-3", "name": "C", "scope": "c", "expected_outputs": [], "dependencies": ["WP-2"]}
      ]
    }')

    if echo "$output" | grep -q "PASSED" && echo "$output" | grep -q "Waves assigned: 3"; then
        test_pass
    else
        test_fail "Expected 3 waves: $output"
    fi
    cleanup_wbs_env
}

test_diamond_dependencies() {
    test_case "Diamond dependencies produce correct waves"
    setup_wbs_env

    local output
    output=$(run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": []},
        {"id": "WP-2", "name": "B", "scope": "b", "expected_outputs": [], "dependencies": ["WP-1"]},
        {"id": "WP-3", "name": "C", "scope": "c", "expected_outputs": [], "dependencies": ["WP-1"]},
        {"id": "WP-4", "name": "D", "scope": "d", "expected_outputs": [], "dependencies": ["WP-2", "WP-3"]}
      ]
    }')

    if echo "$output" | grep -q "PASSED" && echo "$output" | grep -q "Waves assigned: 3"; then
        test_pass
    else
        test_fail "Expected 3 waves for diamond: $output"
    fi
    cleanup_wbs_env
}

test_cycle_detection() {
    test_case "Cycle detection catches circular dependencies"
    setup_wbs_env

    local output
    output=$(run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": ["WP-2"]},
        {"id": "WP-2", "name": "B", "scope": "b", "expected_outputs": [], "dependencies": ["WP-1"]}
      ]
    }' 2>&1) || true

    if echo "$output" | grep -q "FAILED.*Cycle"; then
        test_pass
    else
        test_fail "Expected cycle detection: $output"
    fi
    cleanup_wbs_env
}

test_missing_reference() {
    test_case "Missing reference detection"
    setup_wbs_env

    local output
    output=$(run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": ["WP-99"]}
      ]
    }' 2>&1) || true

    if echo "$output" | grep -q "FAILED" && echo "$output" | grep -q "unknown"; then
        test_pass
    else
        test_fail "Expected missing reference error: $output"
    fi
    cleanup_wbs_env
}

test_wave_assignment_written_to_file() {
    test_case "Wave assignments are written back to wbs.json"
    setup_wbs_env

    run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": []},
        {"id": "WP-2", "name": "B", "scope": "b", "expected_outputs": [], "dependencies": ["WP-1"]}
      ]
    }' > /dev/null

    local wave1 wave2
    wave1=$(python3 -c "import json; wbs=json.load(open('$TEST_WORKSPACE/.octo/parallel/wbs.json')); print([wp['wave'] for wp in wbs['work_packages'] if wp['id']=='WP-1'][0])")
    wave2=$(python3 -c "import json; wbs=json.load(open('$TEST_WORKSPACE/.octo/parallel/wbs.json')); print([wp['wave'] for wp in wbs['work_packages'] if wp['id']=='WP-2'][0])")

    if [[ "$wave1" == "1" && "$wave2" == "2" ]]; then
        test_pass
    else
        test_fail "Expected wave1=1, wave2=2, got wave1=$wave1, wave2=$wave2"
    fi
    cleanup_wbs_env
}

test_skill_file_updated() {
    test_case "flow-parallel.md contains wave-based execution"

    if grep -q "wave" "$PROJECT_ROOT/.claude/skills/flow-parallel.md" && \
       grep -q "Wave" "$PROJECT_ROOT/.claude/skills/flow-parallel.md" && \
       grep -q "STEP 4.5" "$PROJECT_ROOT/.claude/skills/flow-parallel.md"; then
        test_pass
    else
        test_fail "flow-parallel.md missing wave/dependency content"
    fi
}

test_backward_compat() {
    test_case "Empty dependencies still produce wave 1 (backward compat)"
    setup_wbs_env

    local output
    output=$(run_dependency_validation '{
      "task": "test",
      "work_packages": [
        {"id": "WP-1", "name": "A", "scope": "a", "expected_outputs": [], "dependencies": []},
        {"id": "WP-2", "name": "B", "scope": "b", "expected_outputs": [], "dependencies": []}
      ]
    }')

    # Should all be wave 1 when no dependencies
    local wave1 wave2
    wave1=$(python3 -c "import json; wbs=json.load(open('$TEST_WORKSPACE/.octo/parallel/wbs.json')); print([wp['wave'] for wp in wbs['work_packages'] if wp['id']=='WP-1'][0])")
    wave2=$(python3 -c "import json; wbs=json.load(open('$TEST_WORKSPACE/.octo/parallel/wbs.json')); print([wp['wave'] for wp in wbs['work_packages'] if wp['id']=='WP-2'][0])")

    if [[ "$wave1" == "1" && "$wave2" == "1" ]]; then
        test_pass
    else
        test_fail "Expected both wave 1, got wave1=$wave1, wave2=$wave2"
    fi
    cleanup_wbs_env
}

# Run all tests
test_no_dependencies_all_wave_1
test_linear_dependencies
test_diamond_dependencies
test_cycle_detection
test_missing_reference
test_wave_assignment_written_to_file
test_skill_file_updated
test_backward_compat

test_summary
