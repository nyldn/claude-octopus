#!/usr/bin/env bash
# Tests for Windows Git Bash doctor/plugin-root compatibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"

test_suite "Windows doctor compatibility"

test_case "platform helper detects Windows Git Bash families"
source "$PROJECT_ROOT/scripts/lib/plugin-root.sh"
if octo_is_windows_git_bash "MINGW64_NT-10.0" &&
   octo_is_windows_git_bash "MSYS_NT-10.0" &&
   octo_is_windows_git_bash "CYGWIN_NT-10.0" &&
   ! octo_is_windows_git_bash "Darwin"; then
    test_pass
else
    test_fail "Windows Git Bash detection did not match expected platforms"
fi

test_case "doctor commands use portable plugin-root discovery"
doctor_source="$(< "$PROJECT_ROOT/.claude/commands/doctor.md")"
doctor_generated="$(< "$PROJECT_ROOT/.cursor-plugin/commands/octo-doctor.md")"
if assert_contains "$doctor_source" 'find "${HOME}/.claude/plugins"' "source command searches Claude plugin installs" &&
   assert_contains "$doctor_source" 'cd "$OCTO_PLUGIN_ROOT" && bash scripts/orchestrate.sh doctor --verbose' "source command runs doctor from resolved root" &&
   assert_contains "$doctor_generated" 'find "${HOME}/.claude/plugins"' "generated command searches Claude plugin installs" &&
   assert_contains "$doctor_generated" 'cd "$OCTO_PLUGIN_ROOT" && bash scripts/orchestrate.sh doctor --verbose' "generated command runs doctor from resolved root"; then
    test_pass
fi

test_case "doctor accepts directory skill entries with SKILL.md"
if (
    tmp_plugin="$TEST_TMP_DIR/doctor-dir-skill"
    mkdir -p "$tmp_plugin/.claude-plugin" "$tmp_plugin/skills/skill-example" "$tmp_plugin/scripts"
    cat > "$tmp_plugin/.claude-plugin/plugin.json" << 'EOF'
{
  "name": "doctor-test-plugin",
  "version": "0.0.0",
  "skills": ["./skills/skill-example"],
  "commands": []
}
EOF
    cat > "$tmp_plugin/skills/skill-example/SKILL.md" << 'EOF'
---
name: skill-example
description: Test skill.
---
EOF

    SCRIPT_DIR="$tmp_plugin/scripts"
    PLUGIN_DIR="$tmp_plugin"
    source "$PROJECT_ROOT/scripts/lib/doctor.sh"
    set +u
    doctor_check_skills
    set -u

    found_pass="false"
    found_missing="false"
    for i in "${!DOCTOR_RESULTS_NAME[@]}"; do
        if [[ "${DOCTOR_RESULTS_NAME[$i]}" == "skills-all" && "${DOCTOR_RESULTS_STATUS[$i]}" == "pass" ]]; then
            found_pass="true"
        fi
        if [[ "${DOCTOR_RESULTS_NAME[$i]}" == skill-missing-* ]]; then
            found_missing="true"
        fi
    done

    [[ "$found_pass" == "true" && "$found_missing" == "false" ]]
); then
    test_pass
else
    test_fail "doctor reported a directory skill as missing"
fi

test_case "install-deps skips RTK hook warning on Windows Git Bash"
tmp_home="$TEST_TMP_DIR/win-home"
mock_bin="$TEST_TMP_DIR/mock-win-bin"
mkdir -p "$tmp_home" "$mock_bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo MINGW64_NT-10.0' > "$mock_bin/uname"
printf '%s\n' '#!/usr/bin/env bash' 'echo "rtk 0.0.0-test"' > "$mock_bin/rtk"
chmod +x "$mock_bin/uname" "$mock_bin/rtk"

output="$(HOME="$tmp_home" PATH="$mock_bin:$PATH" bash "$PROJECT_ROOT/scripts/install-deps.sh" check 2>&1 || true)"
if assert_contains "$output" "hook check skipped on Windows Git Bash" "Windows RTK hook check is skipped" &&
   assert_not_contains "$output" "hook not configured" "Windows RTK check should not warn about missing Claude hook" &&
   assert_not_contains "$output" "Run: rtk init -g" "Windows RTK check should not recommend rtk init -g"; then
    test_pass
fi

test_case "session manager writes stable script shims when symlink root is unavailable"
shim_home="$TEST_TMP_DIR/shim-home"
mkdir -p "$shim_home/.claude-octopus/plugin"
HOME="$shim_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/session-manager.sh" export >/dev/null
shim="$shim_home/.claude-octopus/plugin/scripts/orchestrate.sh"
if assert_file_exists "$shim" "orchestrate shim exists" &&
   assert_file_contains "$shim" "$PROJECT_ROOT/scripts/orchestrate.sh" "shim points at real plugin root"; then
    test_pass
fi

test_summary
