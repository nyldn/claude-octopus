#!/usr/bin/env bash
# Regression coverage for Factory/Cursor command generation and portable roots.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Factory command generation"

GENERATOR="$PROJECT_ROOT/scripts/build-factory-skills.sh"

test_case "check-mode temporary output is cleaned on exit and termination"
if grep -Eq "trap 'rm -rf \"\\\$CHECK_ROOT\"' EXIT INT TERM" "$GENERATOR"; then
    test_pass
else
    test_fail "Factory check root is not trapped for EXIT, INT, and TERM"
fi

test_case "commands without descriptions reach the explicit skip path"
fixture="$TEST_TMP_DIR/factory-fixture"
mkdir -p "$fixture/scripts" "$fixture/commands" \
    "$fixture/.claude/skills/skill-doctor" "$fixture/.cursor-plugin/commands"
cp "$GENERATOR" "$fixture/scripts/build-factory-skills.sh"
cat > "$fixture/scripts/build-codex-skills.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$fixture/scripts/build-codex-skills.sh"
cat > "$fixture/commands/valid.md" <<'COMMAND'
---
description: A valid command
---

# Valid
COMMAND
cat > "$fixture/commands/missing.md" <<'COMMAND'
---
allowed-tools: Bash
---

# Missing description
COMMAND
cat > "$fixture/.claude/skills/skill-doctor/SKILL.md" <<'SKILL'
---
name: skill-doctor
description: Fixture Doctor
---

# Doctor
SKILL
if output="$(bash "$fixture/scripts/build-factory-skills.sh" 2>&1)" &&
   [[ "$output" == *"SKIP (no description): missing.md"* ]] &&
   [[ -f "$fixture/.cursor-plugin/commands/octo-valid.md" ]]; then
    test_pass
else
    test_fail "missing-description command aborted generation: $output"
fi

test_case "portable commands resolve the installed plugin root"
portable_failures=""
for command_file in usage whats-new; do
    if ! grep -Fq '${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}' \
        "$PROJECT_ROOT/commands/${command_file}.md"; then
        portable_failures+="${command_file} has no installed-root fallback"$'\n'
    fi
done
if [[ -z "$portable_failures" ]]; then
    test_pass
else
    test_fail "$portable_failures"
fi

test_case "whats-new describes only outstanding unrecorded choices"
if grep -Eqi 'revisit(s|ed|ing)? (a )?choice|revisit a settled choice' \
    "$PROJECT_ROOT/commands/whats-new.md"; then
    test_fail "whats-new promises a revisit path that the ledger excludes"
else
    test_pass
fi

test_summary
