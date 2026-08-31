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
mkdir -p "$fixture/scripts" "$fixture/commands" "$fixture/.claude/agents" \
    "$fixture/.claude/skills/skill-doctor" "$fixture/.cursor-plugin/commands"
cp "$GENERATOR" "$fixture/scripts/build-factory-skills.sh"
cat > "$fixture/scripts/build-codex-skills.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$fixture/scripts/build-codex-skills.sh"
cat > "$fixture/commands/valid.md" <<'COMMAND'
---
description: "[advanced] A valid command"
argument-hint: "[--format json]"
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
cat > "$fixture/.claude/agents/reviewer.md" <<'AGENT'
---
description: "Review fixture changes"
model: inherit
---

# Reviewer
AGENT
if output="$(bash "$fixture/scripts/build-factory-skills.sh" 2>&1)" &&
   [[ "$output" == *"SKIP (no description): missing.md"* ]] &&
   [[ -f "$fixture/.cursor-plugin/commands/octo-valid.md" ]] &&
   [[ -f "$fixture/.cursor-plugin/commands/octo-doctor.md" ]] &&
   [[ ! -e "$fixture/.cursor-plugin/commands/octo-missing.md" ]] &&
   grep -Fq 'description: "[advanced] A valid command"' \
       "$fixture/.cursor-plugin/commands/octo-valid.md" &&
   grep -Fq 'argument-hint: "[--format json]"' \
       "$fixture/.cursor-plugin/commands/octo-valid.md" &&
   grep -Fq 'allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion' \
       "$fixture/.cursor-plugin/commands/octo-doctor.md" &&
   grep -Fq 'description: "Review fixture changes"' \
       "$fixture/agents/droids/octo-reviewer.md"; then
    test_pass
else
    test_fail "generation skipped a valid command or complete Doctor adapter: $output"
fi

test_case "generated command descriptions do not retain source quote characters"
if grep -R -E '^(description|argument-hint): "\\".*\\""$' \
    "$PROJECT_ROOT/.cursor-plugin/commands" >/dev/null 2>&1; then
    test_fail "generated command metadata contains literal leading and trailing quotes"
else
    test_pass
fi

test_case "check mode accepts generated output without modifying it"
before_check="$(find "$fixture/.cursor-plugin/commands" -type f -exec cksum {} \; | sort)"
if check_output="$(bash "$fixture/scripts/build-factory-skills.sh" --check 2>&1)" &&
   [[ "$(find "$fixture/.cursor-plugin/commands" -type f -exec cksum {} \; | sort)" == "$before_check" ]]; then
    test_pass
else
    test_fail "Factory --check failed or modified generated output: ${check_output:-<empty>}"
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
