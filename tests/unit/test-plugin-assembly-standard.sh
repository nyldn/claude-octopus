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

test_case "default root discovery rejects unlisted Codex skills"
mkdir -p "$scalar_fixture/native/demo"
grep -v 'Host: Codex CLI' "$scalar_fixture/skills/demo/SKILL.md" > "$scalar_fixture/native/demo/SKILL.md"
printf '%s\n' '{"name":"fixture","version":"0.0.0","description":"fixture","skills":"./native/demo"}' > "$scalar_fixture/.claude-plugin/plugin.json"
if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$scalar_fixture" 2>&1); then
    test_fail "unlisted root skill bypassed native host validation"
elif [[ "$output" == *"Claude Code registers a Codex-adapted skill"* ]]; then
    test_pass
else
    test_fail "missing default-root diagnostic: $output"
fi
rm -rf "$scalar_fixture/skills"
for invalid_path in 'native/demo' "$scalar_fixture/native/demo" ''; do
    test_case "native manifest rejects malformed skill path: $invalid_path"
    python3 - "$scalar_fixture/.claude-plugin/plugin.json" "$invalid_path" <<'PY_MANIFEST'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"name":"fixture", "version":"0.0.0", "description":"fixture", "skills":sys.argv[2]}))
PY_MANIFEST
    if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$scalar_fixture" 2>&1); then
        test_fail "malformed registration accepted"
    elif [[ "$output" == *"skill path must be . or start with ./"* ]]; then
        test_pass
    else
        test_fail "missing path-shape diagnostic: $output"
    fi
done

test_case "native registration permits an empty automatic root skills directory"
mkdir -p "$scalar_fixture/skills"
printf '%s\n' '{"name":"fixture","version":"0.0.0","description":"fixture","skills":"./native/demo"}' > "$scalar_fixture/.claude-plugin/plugin.json"
if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$scalar_fixture" 2>&1); then test_pass; else test_fail "$output"; fi

test_case "native registration permits a plugin-root skill"
cp "$scalar_fixture/native/demo/SKILL.md" "$scalar_fixture/SKILL.md"
printf '%s\n' '{"name":"fixture","version":"0.0.0","description":"fixture","skills":"."}' > "$scalar_fixture/.claude-plugin/plugin.json"
if output=$(python3 "$PROJECT_ROOT/scripts/validate-plugin-assembly.py" --root "$scalar_fixture" 2>&1); then test_pass; else test_fail "$output"; fi
test_case "custom registrations validate frontmatter and Codex packages retain their generated tree"
if python3 - "$PROJECT_ROOT" <<'PY_REGISTRATIONS'
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

validator = Path(sys.argv[1]) / 'scripts/validate-plugin-assembly.py'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    manifest = root / '.claude-plugin/plugin.json'
    manifest.parent.mkdir()
    skill = root / 'native/demo/SKILL.md'
    skill.parent.mkdir(parents=True)
    valid = '---\nname: demo\ndescription: fixture\ndisable-model-invocation: true\n---\nBody.\n'
    cases = [
        ('valid', valid, None),
        ('missing frontmatter', '# Body only\n', 'missing frontmatter'),
        ('missing name', valid.replace('name: demo\n', ''), 'missing required frontmatter field: name'),
        ('bad name', valid.replace('name: demo', 'name: Bad Name'), 'name must be kebab-case'),
        ('missing description', valid.replace('description: fixture\n', ''), 'missing required frontmatter field: description'),
        ('missing invocation policy', valid.replace('disable-model-invocation: true\n', ''), 'disable-model-invocation must be true'),
        ('implicit invocation', valid.replace('disable-model-invocation: true', 'disable-model-invocation: false'), 'disable-model-invocation must be true'),
    ]
    def validate():
        return subprocess.run([sys.executable, str(validator), '--root', str(root)],
                              capture_output=True, text=True, timeout=10)
    for registration in ['./native/demo', ['./native'], '.']:
        manifest.write_text(json.dumps({'name': 'fixture', 'version': '0.0.0',
                                       'description': 'fixture', 'skills': registration}))
        for name, text, diagnostic in cases:
            skill.write_text(text)
            result = validate()
            assert (result.returncode == 0) == (diagnostic is None), (registration, name, result.stderr)
            if diagnostic:
                assert diagnostic in result.stderr, (registration, name, result.stderr)
    skill.write_text(valid)
    codex_manifest = root / '.codex-plugin/plugin.json'
    codex_manifest.parent.mkdir()
    codex_manifest.write_text(json.dumps({'name': 'fixture', 'version': '0.0.0',
                                         'skills': './codex-skills/'}))
    result = validate()
    assert result.returncode != 0 and 'codex-skills/: missing or unsafe required' in result.stderr, result.stderr
    generated = root / 'codex-skills/demo/SKILL.md'
    generated.parent.mkdir(parents=True)
    generated.write_text(valid)
    assert validate().returncode == 0
    manifest.write_text(json.dumps({'name': 'claude-octopus', 'version': '0.0.0',
                                   'description': 'fixture', 'skills': './native/demo'}))
    result = validate()
    assert result.returncode != 0 and '.claude/skills/: missing or unsafe required Octopus command catalog' in result.stderr, result.stderr
    authored = root / '.claude/skills/demo/SKILL.md'
    authored.parent.mkdir(parents=True)
    result = validate()
    assert result.returncode != 0 and 'required Octopus command catalog' in result.stderr, result.stderr
    authored.write_text(valid)
    assert validate().returncode == 0
    shutil.rmtree(root / 'codex-skills')
    outside = root.parent / (root.name + '-outside')
    outside.mkdir()
    try:
        (root / 'codex-skills').symlink_to(outside, target_is_directory=True)
        result = validate()
        assert result.returncode != 0 and 'codex-skills/: missing or unsafe required' in result.stderr, result.stderr
    finally:
        outside.rmdir()
print('21 custom-registration cases and required Codex-tree controls passed')
PY_REGISTRATIONS
then test_pass; else test_fail "registered frontmatter or required Codex-tree check failed"; fi

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
