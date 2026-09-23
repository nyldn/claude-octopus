#!/usr/bin/env bash
# Tests for Windows Git Bash doctor/plugin-root compatibility.

set -euo pipefail

# Resolve physically. session-manager.sh:43 writes the shim with
# `cd "$plugin_root_raw" && pwd -P` deliberately — its header comment says the
# recorded path must be "the real install path", and the assertion below is
# named "shim points at real plugin root". A logically-derived PROJECT_ROOT
# agrees under a normal checkout and diverges behind a symlink, so the case
# failed in the symlinked-path job while the code was correct.
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
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

test_case "native Windows workflow startup fails early with WSL guidance"
mock_platform_bin="$TEST_TMP_DIR/mock-platform-bin"
mkdir -p "$mock_platform_bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo MINGW64_NT-10.0' > "$mock_platform_bin/uname"
chmod +x "$mock_platform_bin/uname"
workflow_rc=0
workflow_output="$(PATH="$mock_platform_bin:$PATH" bash "$PROJECT_ROOT/scripts/orchestrate.sh" debate 2>&1)" || workflow_rc=$?
if [[ "$workflow_rc" -eq 78 ]] &&
   assert_contains "$workflow_output" "Native Windows is unsupported" "workflow reports unsupported host" &&
   assert_contains "$workflow_output" "inside WSL" "workflow points to WSL"; then
    test_pass
else
    test_fail "native Windows workflow returned rc=$workflow_rc without the expected WSL guidance"
fi

test_case "WSL indicators prevent false native Windows detection"
if ! (export WSL_DISTRO_NAME=Ubuntu OS=Windows_NT MSYSTEM=MINGW64
      octo_is_windows_git_bash "MINGW64_NT-10.0") &&
   ! (export WSL_INTEROP=/run/WSL/1_interop OS=Windows_NT MSYSTEM=MINGW64
      octo_is_windows_git_bash "MSYS_NT-10.0"); then
    test_pass
else
    test_fail "WSL environment was misclassified as native Windows Git Bash"
fi

test_case "native Windows permits global help flags"
help_ok=true
for flag in -h --help; do
    help_rc=0
    PATH="$mock_platform_bin:$PATH" bash "$PROJECT_ROOT/scripts/orchestrate.sh" "$flag" >/dev/null 2>&1 || help_rc=$?
    [[ "$help_rc" -ne 78 ]] || help_ok=false
done
if [[ "$help_ok" == "true" ]]; then
    test_pass
else
    test_fail "a global help flag was rejected by the native Windows workflow guard"
fi

test_case "native Windows permits artifact-only run inspection"
inspection_ok=true
for command in explain status; do
    inspection_rc=0
    inspection_output="$(PATH="$mock_platform_bin:$PATH" \
        bash "$PROJECT_ROOT/scripts/orchestrate.sh" "$command" --run missing-run 2>&1)" || inspection_rc=$?
    if [[ "$inspection_rc" -eq 78 ]] || [[ "$inspection_output" == *"Native Windows is unsupported"* ]]; then
        inspection_ok=false
    fi
done
if [[ "$inspection_ok" == "true" ]]; then
    test_pass
else
    test_fail "artifact-only explain/status was rejected by the native Windows workflow guard"
fi

test_case "native Windows rejects non-inspection explain and status commands"
rejection_ok=true
for command in explain status; do
    command_rc=0
    PATH="$mock_platform_bin:$PATH" bash "$PROJECT_ROOT/scripts/orchestrate.sh" "$command" >/dev/null 2>&1 || command_rc=$?
    if [[ "$command_rc" -ne 78 ]]; then
        rejection_ok=false
    fi
done
if [[ "$rejection_ok" == "true" ]]; then
    test_pass
else
    test_fail "non-inspection explain/status bypassed the native Windows workflow guard"
fi

test_case "Doctor reports the native Windows platform contract"
doctor_home="$TEST_TMP_DIR/native-windows-doctor-home"
mkdir -p "$doctor_home"
doctor_rc=0
doctor_json="$(HOME="$doctor_home" PATH="$mock_platform_bin:$PATH" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" doctor installation --json 2>/dev/null)" || doctor_rc=$?
if [[ "$doctor_rc" -eq 1 ]] && jq -e '
    any(.results[];
        .name == "host-platform" and
        .category == "installation" and
        .status == "fail" and
        (.message | contains("Native Windows is unsupported")) and
        (.detail | contains("inside WSL")))
' <<< "$doctor_json" >/dev/null; then
    test_pass
else
    test_fail "Doctor did not expose the native Windows contract (rc=$doctor_rc)"
fi

test_case "Python helpers distinguish missing fcntl from native Windows"
python_output="$(PROJECT_ROOT="$PROJECT_ROOT" python3 - <<'PY'
import builtins
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys

root = Path(os.environ["PROJECT_ROOT"])
helpers = root / "scripts" / "helpers"
sys.path.insert(0, str(helpers))
real_import = builtins.__import__
real_platform = sys.platform

def without_fcntl(name, *args, **kwargs):
    if name == "fcntl":
        raise ImportError("simulated native Windows")
    return real_import(name, *args, **kwargs)

for name in ("pid-ledger.py", "setup-state.py"):
    builtins.__import__ = without_fcntl
    module_name = "octo_" + name.replace("-", "_").replace(".", "_")
    spec = importlib.util.spec_from_file_location(module_name, helpers / name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    builtins.__import__ = real_import
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        if name == "pid-ledger.py":
            try:
                module.require_supported_host()
            except Exception as exc:
                message = str(exc)
            else:
                raise SystemExit("pid ledger accepted missing fcntl")
        else:
            old_argv = sys.argv
            sys.argv = [name]
            try:
                rc = module.main()
            finally:
                sys.argv = old_argv
            if rc != 78:
                raise SystemExit(f"setup-state returned {rc}")
            message = stderr.getvalue()
    if "file locking is unavailable" not in message or "native Windows" in message:
        raise SystemExit(f"missing fcntl guidance from {name}: {message!r}")

    module.sys.platform = "win32"
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        if name == "pid-ledger.py":
            try:
                module.require_supported_host()
            except Exception as exc:
                message = str(exc)
            else:
                raise SystemExit("pid ledger accepted native Windows")
        else:
            old_argv = sys.argv
            sys.argv = [name]
            try:
                rc = module.main()
            finally:
                sys.argv = old_argv
            if rc != 78:
                raise SystemExit(f"setup-state returned {rc} on native Windows")
            message = stderr.getvalue()
    if "native Windows is unsupported" not in message or "inside WSL" not in message:
        raise SystemExit(f"missing native Windows guidance from {name}: {message!r}")
    module.sys.platform = real_platform
print("helpers-distinguished-host-errors")
PY
)"
if [[ "$python_output" == helpers-distinguished-host-errors ]]; then
    test_pass
else
    test_fail "Python helpers did not distinguish host and locking failures"
fi

test_case "README exposes a working WSL anchor"
if grep -q '^### Using Cursor on WSL$' "$PROJECT_ROOT/README.md" &&
   grep -q '\[WSL\](#using-cursor-on-wsl)' "$PROJECT_ROOT/README.md"; then
    test_pass
else
    test_fail "README WSL link does not target a generated heading anchor"
fi

test_case "doctor commands use portable plugin-root discovery"
doctor_generated="$(< "$PROJECT_ROOT/.cursor-plugin/commands/octo-doctor.md")"
if assert_contains "$doctor_generated" 'find "${HOME}/.claude/plugins"' "generated command searches Claude plugin installs" &&
   assert_contains "$doctor_generated" 'bash "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" doctor --verbose' "generated command runs doctor from resolved root"; then
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

# Pass a SYMLINKED plugin root, not the real one. session-manager.sh:43 resolves
# with `pwd -P` deliberately so the shim records the real install path — a shim
# pointing at a symlink breaks once that link is replaced on upgrade. Handing it
# the physical path (as this case used to) meant `pwd` and `pwd -P` returned the
# same value and the assertion proved nothing; it passed with the resolution
# removed entirely. Verified: reverting `pwd -P` to `pwd` now fails this case.
test_case "session manager writes stable script shims when symlink root is unavailable"
shim_home="$TEST_TMP_DIR/shim-home"
mkdir -p "$shim_home/.claude-octopus/plugin"
linked_root="$TEST_TMP_DIR/linked-plugin-root"
ln -sfn "$PROJECT_ROOT" "$linked_root"
HOME="$shim_home" CLAUDE_PLUGIN_ROOT="$linked_root" bash "$PROJECT_ROOT/scripts/session-manager.sh" export >/dev/null
shim="$shim_home/.claude-octopus/plugin/scripts/orchestrate.sh"
if assert_file_exists "$shim" "orchestrate shim exists" &&
   assert_file_contains "$shim" "$PROJECT_ROOT/scripts/orchestrate.sh" "shim points at real plugin root" &&
   ! grep -q "$linked_root" "$shim"; then
    test_pass
else
    test_fail "shim should record the resolved plugin root, not the symlink it was reached through"
fi

test_summary
