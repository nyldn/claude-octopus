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

test_case "registered hook commands execute from a plugin path containing spaces"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PYHOOKS'
from pathlib import Path
import json
import os
import re
import shlex
import subprocess
import sys

source = Path(sys.argv[1])
fixture = Path(sys.argv[2]) / "plugin root with spaces"
fixture.mkdir()
manifest = json.loads((source / "hooks/hooks.json").read_text())
checked = 0
for groups in manifest["hooks"].values():
    for group in groups:
        for hook in group.get("hooks", []):
            if hook.get("type") != "command":
                continue
            command = hook["command"]
            match = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}(/[^"\s]+)', command)
            assert match, command
            relative = match.group(1).lstrip("/")
            assert (source / relative).is_file(), relative
            script = fixture / relative
            script.parent.mkdir(parents=True, exist_ok=True)
            script.write_text("#!" + sys.executable + "\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
            script.chmod(0o700)
            result = subprocess.run(["bash", "-c", command], env=dict(os.environ,
                CLAUDE_PLUGIN_ROOT=str(fixture)), capture_output=True, text=True)
            assert result.returncode == 0, (command, result.stderr)
            assert json.loads(result.stdout) == shlex.split(command)[1:], command
            checked += 1
assert checked > 0
print(f"Validated {checked} registered hook commands with inert executables")
PYHOOKS
then test_pass; else test_fail "registered hook path split into shell words"; fi

test_summary
