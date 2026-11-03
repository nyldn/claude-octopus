#!/usr/bin/env bash
# Test: Plugin assembly standard and structural validator
# Ensures Octopus keeps skills, agents, commands, and connector metadata in a
# disciplined Claude Code plugin shape.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Plugin assembly standard and validator"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_file() {
    local file="$1"
    local label="$2"
    if [[ -f "$PROJECT_ROOT/$file" ]]; then
        pass "$label"
    else
        fail "$label" "missing $file"
    fi
}

assert_executable() {
    local file="$1"
    local label="$2"
    if [[ -x "$PROJECT_ROOT/$file" ]]; then
        pass "$label"
    else
        fail "$label" "$file is not executable"
    fi
}

assert_contains_file() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if grep -qE "$pattern" "$PROJECT_ROOT/$file"; then
        pass "$label"
    else
        fail "$label" "missing pattern '$pattern' in $file"
    fi
}

assert_contains_repo_file() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    local content=""

    if [[ -f "$PROJECT_ROOT/$file" ]]; then
        content=$(cat "$PROJECT_ROOT/$file")
    elif git -C "$PROJECT_ROOT" cat-file -e "HEAD:$file" 2>/dev/null; then
        content=$(git -C "$PROJECT_ROOT" show "HEAD:$file")
    else
        fail "$label" "missing $file"
        return
    fi

    if grep -qE "$pattern" <<<"$content"; then
        pass "$label"
    else
        fail "$label" "missing pattern '$pattern' in $file"
    fi
}

echo "=== 1. Assembly standard documentation ==="
assert_file "docs/PLUGIN-ASSEMBLY-STANDARD.md" \
    "plugin assembly standard document exists"
assert_contains_file "docs/PLUGIN-ASSEMBLY-STANDARD.md" '^## Skill Assembly Contract' \
    "standard defines skill assembly contract"
assert_contains_file "docs/PLUGIN-ASSEMBLY-STANDARD.md" '^## Agent Assembly Contract' \
    "standard defines agent assembly contract"
assert_contains_file "docs/PLUGIN-ASSEMBLY-STANDARD.md" '^## Connector Assembly Contract' \
    "standard defines connector assembly contract"
assert_contains_file "docs/PLUGIN-ASSEMBLY-STANDARD.md" '^## Validation Contract' \
    "standard defines validation contract"
assert_contains_file "docs/README.md" 'PLUGIN-ASSEMBLY-STANDARD.md' \
    "docs index links plugin assembly standard"

echo ""
echo "=== 2. Validator exists and passes current repo ==="
assert_file "scripts/validate-plugin-assembly.py" \
    "plugin assembly validator exists"
assert_executable "scripts/validate-plugin-assembly.py" \
    "plugin assembly validator is executable"
assert_contains_repo_file "Makefile" '^validate-plugin-assembly:' \
    "Makefile exposes validate-plugin-assembly target"

if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$PROJECT_ROOT" 2>&1); then
    if grep -q '^OK — plugin assembly' <<<"$output"; then
        pass "validator passes current plugin assembly"
    else
        fail "validator passes current plugin assembly" "unexpected output: $output"
    fi
else
    fail "validator passes current plugin assembly" "$output"
fi

echo ""
echo "=== 3. Validator catches structural drift ==="
fixture="$TEST_TMP_DIR/assembly-bad"
rm -rf "$fixture"
mkdir -p "$fixture/.claude-plugin" "$fixture/skills/bad-skill" "$fixture/commands"
printf '{"name":"bad","version":"0.0.0"}\n' > "$fixture/.claude-plugin/plugin.json"
printf '# Bad Skill\n\nNo frontmatter.\n' > "$fixture/skills/bad-skill/SKILL.md"
cat > "$fixture/commands/bad.md" <<'EOF'
---
argument-hint: "[thing]"
---

# Missing description
EOF

if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$fixture" 2>&1); then
    fail "validator rejects missing frontmatter and command descriptions" \
        "validator unexpectedly passed: $output"
else
    if grep -q 'missing frontmatter' <<<"$output" && grep -q 'missing required frontmatter field: description' <<<"$output"; then
        pass "validator rejects missing frontmatter and command descriptions"
    else
        fail "validator rejects missing frontmatter and command descriptions" \
            "unexpected failure output: $output"
    fi
fi


test_case "validator rejects a Codex-adapted skill registered for Claude"
mkdir -p "$fixture/skills/portable"
printf '%s\n' '---' 'name: portable' 'description: fixture' 'disable-model-invocation: true' '---' '> **Host: Codex CLI**' > "$fixture/skills/portable/SKILL.md"
printf '%s\n' '{"name":"fixture","version":"0.0.0","description":"fixture","skills":["./skills/portable"]}' > "$fixture/.claude-plugin/plugin.json"
if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$fixture" 2>&1); then
    test_fail "validator accepted Codex instructions for Claude"
elif [[ "$output" == *"Claude Code registers a Codex-adapted skill"* ]]; then
    test_pass
else
    test_fail "missing host mismatch diagnostic: $output"
fi


scalar_fixture="$TEST_TMP_DIR/assembly-scalar"
mkdir -p "$scalar_fixture/.claude-plugin" "$scalar_fixture/skills/demo"
printf '%s\n' '---' 'name: demo' 'description: fixture' 'disable-model-invocation: true' '---' '# Native skill' > "$scalar_fixture/skills/demo/SKILL.md"
for skill_path in './skills/demo' './skills/'; do
    test_case "validator accepts native scalar skill registration: $skill_path"
    python3 - "$scalar_fixture/.claude-plugin/plugin.json" "$skill_path" <<'PY_MANIFEST'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"name":"fixture", "version":"0.0.0", "description":"fixture", "skills":sys.argv[2]}))
PY_MANIFEST
    if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$scalar_fixture" 2>&1); then
        test_pass
    else
        test_fail "supported scalar registration rejected: $output"
    fi
done

test_case "container registrations still reject nested Codex adaptations"
printf '%s\n' '> **Host: Codex CLI**' >> "$scalar_fixture/skills/demo/SKILL.md"
if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$scalar_fixture" 2>&1); then
    test_fail "container bypassed host validation"
elif [[ "$output" == *"Claude Code registers a Codex-adapted skill"* ]]; then
    test_pass
else
    test_fail "missing nested host mismatch diagnostic: $output"
fi

test_summary
