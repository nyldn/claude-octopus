#!/bin/bash
# tests/unit/test-persona-packs.sh
# Tests for v8.21.0 Persona Packs feature
# Covers: pack discovery, loading, replace/extend modes, auto-loading,
#         pack.yaml parsing, active packs registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

# Set up environment for intelligence.sh/personas.sh
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export PLUGIN_DIR="$PROJECT_ROOT"

# Source the libraries under test
source "$PROJECT_ROOT/scripts/lib/intelligence.sh"
source "$PROJECT_ROOT/scripts/lib/personas.sh" 2>/dev/null || true

test_suite "Persona Packs (v8.21.0)"

# ═══════════════════════════════════════════════════════════════════════════════
# Pack Discovery
# ═══════════════════════════════════════════════════════════════════════════════

test_discover_empty() {
    test_case "discover_persona_packs returns empty with no packs"

    local pack_dir="$TEST_TMP_DIR/empty-personas"
    mkdir -p "$pack_dir"

    local result
    result=$(OCTOPUS_PERSONA_PACKS="" discover_persona_packs "$pack_dir" 2>/dev/null)

    if [[ -z "$result" ]]; then
        test_pass
    else
        test_fail "Should return empty, got: $result"
    fi
}

test_discover_finds_pack_yaml() {
    test_case "discover_persona_packs finds directories with pack.yaml"

    local pack_dir="$TEST_TMP_DIR/find-packs"
    mkdir -p "$pack_dir/my-pack"
    cat > "$pack_dir/my-pack/pack.yaml" << 'EOF'
name: my-pack
version: 1.0.0
author: test
description: Test pack
personas:
  - file: analyst.md
    mode: extends
    target: research-synthesizer
EOF

    local result
    result=$(OCTOPUS_PERSONA_PACKS="" discover_persona_packs "$pack_dir" 2>/dev/null)

    if echo "$result" | grep -q "my-pack"; then
        test_pass
    else
        test_fail "Should find my-pack, got: $result"
    fi
}

test_discover_ignores_no_manifest() {
    test_case "discover_persona_packs ignores dirs without pack.yaml"

    local pack_dir="$TEST_TMP_DIR/no-manifest"
    mkdir -p "$pack_dir/fake-pack"
    echo "not a pack" > "$pack_dir/fake-pack/README.md"

    local result
    result=$(OCTOPUS_PERSONA_PACKS="" discover_persona_packs "$pack_dir" 2>/dev/null)

    if [[ -z "$result" ]]; then
        test_pass
    else
        test_fail "Should ignore dirs without pack.yaml, got: $result"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Pack Loading
# ═══════════════════════════════════════════════════════════════════════════════

test_load_pack_metadata() {
    test_case "load_persona_pack extracts name, version, author"

    local pack_dir="$TEST_TMP_DIR/load-test"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'EOF'
name: data-science
version: 2.1.0
author: analytics-team
description: Data science persona specializations
personas:
  - file: ml-engineer.md
    mode: extends
    target: python-pro
EOF

    local result
    result=$(load_persona_pack "$pack_dir" 2>/dev/null)

    local ok=true
    if ! echo "$result" | grep -q "name=data-science"; then ok=false; fi
    if ! echo "$result" | grep -q "version=2.1.0"; then ok=false; fi
    if ! echo "$result" | grep -q "author=analytics-team"; then ok=false; fi

    if $ok; then
        test_pass
    else
        test_fail "Should extract metadata, got: $result"
    fi
}

test_load_pack_missing_name() {
    test_case "load_persona_pack fails on missing name"

    local pack_dir="$TEST_TMP_DIR/no-name"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'EOF'
version: 1.0.0
description: Missing name field
EOF

    local result exit_code
    result=$(load_persona_pack "$pack_dir" 2>&1) || exit_code=$?

    if [[ "${exit_code:-0}" -ne 0 ]] || echo "$result" | grep -qi "error\|missing\|fail"; then
        test_pass
    else
        test_fail "Should fail on missing name, got exit=${exit_code:-0} result=$result"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Persona Entries
# ═══════════════════════════════════════════════════════════════════════════════

test_get_personas_extends() {
    test_case "get_pack_personas extracts extends-mode entries"

    local pack_dir="$TEST_TMP_DIR/extends-test"
    mkdir -p "$pack_dir"
    # Note: awk parser expects "extends: <target>" not "mode: extends" + "target: ..."
    cat > "$pack_dir/pack.yaml" << 'EOF'
name: test-pack
version: 1.0.0
author: test
description: Test
personas:
  - file: custom-auditor.md
    extends: security-auditor
  - file: custom-reviewer.md
    extends: code-reviewer
EOF

    local result
    result=$(get_pack_personas "$pack_dir" 2>/dev/null)

    if echo "$result" | grep -q "extends" && echo "$result" | grep -q "security-auditor"; then
        test_pass
    else
        test_fail "Should extract extends entries, got: $result"
    fi
}

test_get_personas_replaces() {
    test_case "get_pack_personas extracts replaces-mode entries"

    local pack_dir="$TEST_TMP_DIR/replaces-test"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'EOF'
name: replace-pack
version: 1.0.0
author: test
description: Test replaces
personas:
  - file: my-frontend.md
    replaces: frontend-developer
EOF

    local result
    result=$(get_pack_personas "$pack_dir" 2>/dev/null)

    if echo "$result" | grep -q "replaces" && echo "$result" | grep -q "frontend-developer"; then
        test_pass
    else
        test_fail "Should extract replaces entries, got: $result"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Active Packs Registry
# ═══════════════════════════════════════════════════════════════════════════════

test_apply_pack_creates_registry() {
    test_case "apply_persona_pack creates active-packs registry"

    mkdir -p "$WORKSPACE_DIR/.octo"
    rm -f "$WORKSPACE_DIR/.octo/active-packs.json"

    local pack_dir="$TEST_TMP_DIR/apply-test"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'EOF'
name: applied-pack
version: 1.0.0
author: test
description: Test apply
personas:
  - file: a.md
    mode: extends
    target: debugger
EOF

    apply_persona_pack "$pack_dir" >/dev/null 2>&1

    if [[ -f "$WORKSPACE_DIR/.octo/active-packs.json" ]]; then
        test_pass
    else
        test_fail "Should create active-packs.json"
    fi
}

test_list_active_packs() {
    test_case "list_active_packs shows registered packs"

    mkdir -p "$WORKSPACE_DIR/.octo"
    rm -f "$WORKSPACE_DIR/.octo/active-packs.json"

    local pack_dir="$TEST_TMP_DIR/list-test"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'EOF'
name: listed-pack
version: 1.0.0
author: test
description: Test listing
personas:
  - file: a.md
    mode: extends
    target: debugger
EOF

    apply_persona_pack "$pack_dir" >/dev/null 2>&1

    local result
    result=$(list_active_packs 2>/dev/null)

    if echo "$result" | grep -q "listed-pack"; then
        test_pass
    else
        test_fail "Should list applied pack, got: $result"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-Loading Control
# ═══════════════════════════════════════════════════════════════════════════════

test_auto_load_disabled() {
    test_case "auto_load_persona_packs skips when OCTOPUS_PERSONA_PACKS=off"

    mkdir -p "$WORKSPACE_DIR/.octo"
    rm -f "$WORKSPACE_DIR/.octo/active-packs.json"

    # Create a pack that would be discovered
    local pack_dir="$TEST_TMP_DIR/auto-off"
    mkdir -p "$pack_dir/auto-pack"
    cat > "$pack_dir/auto-pack/pack.yaml" << 'EOF'
name: auto-pack
version: 1.0.0
author: test
description: Should not auto-load
personas:
  - file: a.md
    mode: extends
    target: debugger
EOF

    OCTOPUS_PERSONA_PACKS=off auto_load_persona_packs >/dev/null 2>&1

    if [[ ! -f "$WORKSPACE_DIR/.octo/active-packs.json" ]]; then
        test_pass
    else
        local content
        content=$(cat "$WORKSPACE_DIR/.octo/active-packs.json" 2>/dev/null)
        if echo "$content" | grep -q "auto-pack"; then
            test_fail "Should not auto-load when disabled"
        else
            test_pass
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Persona Override
# ═══════════════════════════════════════════════════════════════════════════════

test_persona_override_no_override() {
    test_case "get_persona_override returns empty when no override exists"

    mkdir -p "$WORKSPACE_DIR/.octo"
    rm -f "$WORKSPACE_DIR/.octo/active-packs.json"

    local result
    result=$(get_persona_override "nonexistent-agent" 2>/dev/null)

    if [[ -z "$result" ]]; then
        test_pass
    else
        test_fail "Should return empty for nonexistent agent, got: $result"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/personas.sh Module Structure
# ═══════════════════════════════════════════════════════════════════════════════

test_personas_lib_exists() {
    test_case "lib/personas.sh exists"

    if [[ -f "$PROJECT_ROOT/scripts/lib/personas.sh" ]]; then
        test_pass
    else
        test_fail "scripts/lib/personas.sh not found"
    fi
}

test_personas_sourced_by_orchestrate() {
    test_case "orchestrate.sh sources lib/personas.sh"

    if grep -q 'personas.sh' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "orchestrate.sh should source lib/personas.sh"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════════════

# Discovery
test_discover_empty
test_discover_finds_pack_yaml
test_discover_ignores_no_manifest

# Loading
test_load_pack_metadata
test_load_pack_missing_name

# Persona entries
test_get_personas_extends
test_get_personas_replaces

# Active packs
test_apply_pack_creates_registry
test_list_active_packs

# Auto-loading
test_auto_load_disabled

# Overrides
test_persona_override_no_override

# Module structure
test_personas_lib_exists
test_personas_sourced_by_orchestrate

test_summary
