#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Installation health documentation contracts"

DOCTOR_SKILL="$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md"
SETUP_COMMAND="$PROJECT_ROOT/commands/setup.md"
HEALTH_DOC="$PROJECT_ROOT/docs/INSTALLATION-HEALTH.md"
REFERENCE_DOC="$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"

test_case "setup activates read-only installation health"
if grep -Fq 'setup_installation_health' "$SETUP_COMMAND" &&
   grep -Fq 'doctor installation --json' "$SETUP_COMMAND" &&
   grep -Fq 'cache-check --json' "$SETUP_COMMAND" &&
   [[ "$(grep -Fc 'setup_installation_health' "$SETUP_COMMAND")" -ge 3 ]]; then
    test_pass
else
    test_fail "setup does not run the installation and cache checks at troubleshooting and completion boundaries"
fi

test_case "doctor resolves both host roots without mutating the stable root"
resolver_block="$(awk '
  /^```bash$/ && !found {found=1; capture=1; next}
  capture && /^```$/ {exit}
  capture {print}
' "$DOCTOR_SKILL")"
if grep -Fq 'CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}' "$DOCTOR_SKILL" &&
   grep -Fq 'doctor installation' "$DOCTOR_SKILL" &&
   grep -Fq 'repair --dry-run' "$DOCTOR_SKILL" &&
   grep -Fq 'repair --apply' "$DOCTOR_SKILL" &&
   ! grep -Eq '(^|[[:space:]])(mkdir|rm|ln)[[:space:]]' <<<"$resolver_block"; then
    test_pass
else
    test_fail "doctor resolver lacks Codex support, installation coverage, or repair authorization guidance"
fi

test_case "docs separate optional profiles and preserve safety hooks"
if grep -Fq 'OCTOPUS_CONTEXT_PROFILE' "$HEALTH_DOC" &&
   grep -Fq 'OCTOPUS_HOOK_PROFILE' "$HEALTH_DOC" &&
   grep -Fq 'OCTO_PROFILE' "$HEALTH_DOC" &&
   grep -Fq 'never disable safety or lifecycle hooks' "$HEALTH_DOC"; then
    test_pass
else
    test_fail "profile documentation conflates context settings with legacy intensity or safety behavior"
fi

test_case "handoff documentation states its limits"
if grep -Fq 'not imported runtime' "$HEALTH_DOC" &&
   grep -Fq '/octo:resume' "$HEALTH_DOC" &&
   grep -Fq 'not a guarantee that every secret is removed' "$HEALTH_DOC" &&
   grep -Fq 'repair --dry-run' "$REFERENCE_DOC"; then
    test_pass
else
    test_fail "handoff or bounded repair behavior is overstated"
fi

test_summary
