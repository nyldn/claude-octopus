#!/usr/bin/env bash
# shellcheck disable=SC2016 # Tests inspect and execute literal shell snippets.
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

test_case "doctor resolves an npm-style octopus executable symlink"
doctor_fixture="$TEST_TMP_DIR/doctor-cli-symlink"
doctor_root="$doctor_fixture/prefix/lib/node_modules/claude-octopus"
doctor_bin="$doctor_fixture/prefix/bin"
doctor_log="$doctor_fixture/doctor.log"
doctor_resolver="$doctor_fixture/resolver.sh"
mkdir -p "$doctor_root/bin" "$doctor_root/scripts" "$doctor_bin" "$doctor_fixture/home"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$doctor_root/bin/octopus"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" > "$DOCTOR_CALL_LOG"' \
    > "$doctor_root/scripts/orchestrate.sh"
chmod +x "$doctor_root/bin/octopus" "$doctor_root/scripts/orchestrate.sh"
ln -s ../lib/node_modules/claude-octopus/bin/octopus "$doctor_bin/octopus"
printf '%s\n' "$resolver_block" > "$doctor_resolver"
doctor_resolver_rc=0
env -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT -u OCTO_PLUGIN_ROOT \
    HOME="$doctor_fixture/home" PATH="$doctor_bin:/usr/bin:/bin" \
    DOCTOR_CALL_LOG="$doctor_log" bash "$doctor_resolver" >/dev/null 2>&1 || \
    doctor_resolver_rc=$?
if [[ "$doctor_resolver_rc" -eq 0 ]] &&
   [[ "$(cat "$doctor_log" 2>/dev/null || true)" == "doctor --verbose" ]] &&
   grep -Fq 'OCTO_LINK_HOPS' "$doctor_resolver" &&
   grep -Fq '[[ "$OCTO_LINK_HOPS" -le 40 ]]' "$doctor_resolver" &&
   [[ ! -e "$doctor_fixture/home/.claude-octopus/plugin" ]]; then
    test_pass
else
    test_fail "doctor did not resolve the linked CLI safely (exit=$doctor_resolver_rc)"
fi

test_case "doctor stops executable symlink cycles after 40 hops"
cycle_fixture="$TEST_TMP_DIR/doctor-cli-cycle"
cycle_bin="$cycle_fixture/bin"
cycle_log="$cycle_fixture/readlink.log"
cycle_resolver="$cycle_fixture/resolver.sh"
real_readlink="$(command -v readlink)"
mkdir -p "$cycle_bin" "$cycle_fixture/home"
ln -s octopus "$cycle_bin/octopus"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf x >> "$READLINK_CALL_LOG"' \
    'count="$(wc -c < "$READLINK_CALL_LOG")"' \
    '[[ "$count" -le 45 ]] || exit 1' \
    'exec "$REAL_READLINK" "$@"' > "$cycle_bin/readlink"
chmod +x "$cycle_bin/readlink"
printf '%s\n' "$resolver_block" > "$cycle_resolver"
cycle_rc=0
env -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT -u OCTO_PLUGIN_ROOT \
    HOME="$cycle_fixture/home" PATH="$cycle_bin:/usr/bin:/bin" \
    READLINK_CALL_LOG="$cycle_log" REAL_READLINK="$real_readlink" \
    bash -c 'octopus() { :; }; cd "$1"; source "$2"' \
    _ "$cycle_bin" "$cycle_resolver" >/dev/null 2>&1 || cycle_rc=$?
cycle_hops="$(wc -c < "$cycle_log" | tr -d '[:space:]')"
if [[ "$cycle_rc" -ne 0 ]] && [[ "$cycle_hops" == 40 ]]; then
    test_pass
else
    test_fail "doctor followed a symlink cycle $cycle_hops times (exit=$cycle_rc)"
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

test_case "command and repair prose cover guide and wrapper-based stable roots"
if grep -Fq '| `/octo:guide` | Browse installed commands without starting a provider workflow |' \
      "$REFERENCE_DOC" &&
   grep -Fq 'generated wrappers for Octopus script entry points' "$PROJECT_ROOT/README.md"; then
    test_pass
else
    test_fail "guide or wrapper-based repair ownership is missing from public documentation"
fi

test_summary
