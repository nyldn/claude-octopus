#!/usr/bin/env bash
# Execute the documented freeze activation against synthetic state only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "debug freeze state admission"

if ! command -v python3 >/dev/null 2>&1; then
    test_case "Python required by freeze enforcement is available"
    test_fail "python3 unavailable"
    test_summary
    exit 1
fi

# The override permits meaningful baseline/mutation controls without source edits.
DEBUG_TEST_ROOT="${OCTOPUS_DEBUG_FREEZE_TEST_ROOT:-$PROJECT_ROOT}"
probe_results="$(python3 - "$DEBUG_TEST_ROOT" "$PROJECT_ROOT" <<'PYTEST'
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import uuid

source = Path(sys.argv[1])
hook = Path(sys.argv[2]) / "hooks/freeze-check.sh"
bash = os.environ.get("BASH", "/bin/bash")
mirrors = [".claude/skills/skill-debug/SKILL.md", "skills/skill-debug/SKILL.md"]

with tempfile.TemporaryDirectory(prefix="octo-debug-freeze-test-") as tmp:
    root = Path(tmp)
    module = root / "module"
    module.mkdir()
    other = root / "other"
    other.mkdir()
    for mirror in mirrors:
        text = (source / mirror).read_text()
        section = text.split("## Scoped freeze guard", 1)[1]
        code = re.search(r"```bash\n(.*?)\n```", section, re.S).group(1)
        for case in ["absent", "valid-existing", "opaque-existing", "empty-regular",
                     "filled-symlink", "empty-symlink", "dangling-symlink",
                     "directory", "fifo", "race-regular", "race-symlink",
                     "race-fifo", "race-symlink-fifo", "missing-python"]:
            sid = "regression-" + uuid.uuid4().hex
            legacy_sid = "legacy-" + uuid.uuid4().hex
            state = Path("/tmp/octopus-freeze-" + sid + ".txt")
            legacy = Path("/tmp/octopus-freeze-" + legacy_sid + ".txt")
            target = root / uuid.uuid4().hex
            marker = "SYNTHETIC_NONSECRET_" + sid
            env = dict(os.environ, CLAUDE_CODE_SESSION_ID=sid,
                       CLAUDE_SESSION_ID=legacy_sid)
            prelude = ""
            original = None
            try:
                if case == "valid-existing":
                    state.write_text(str(other) + "\n")
                elif case == "opaque-existing":
                    state.write_text(marker + "\n")
                elif case == "empty-regular":
                    state.write_text("")
                elif case in ("filled-symlink", "empty-symlink"):
                    original = marker + "\n" if case == "filled-symlink" else ""
                    target.write_text(original)
                    state.symlink_to(target)
                elif case == "dangling-symlink":
                    state.symlink_to(target)
                elif case == "directory":
                    state.mkdir()
                elif case == "fifo":
                    os.mkfifo(state)
                elif case.startswith("race-"):
                    if case == "race-symlink-fifo":
                        os.mkfifo(target)
                    else:
                        original = marker + "\n"
                        target.write_text(original)
                    env["RACE_TARGET"] = str(target)
                    # umask runs after absent admission and before exclusive open.
                    actions = {
                        "race-regular": 'printf "%s\\n" SYNTHETIC_PRESEEDED > "$_OCTO_FREEZE_FILE"',
                        "race-symlink": 'ln -s "$RACE_TARGET" "$_OCTO_FREEZE_FILE"',
                        "race-fifo": 'mkfifo "$_OCTO_FREEZE_FILE"',
                        "race-symlink-fifo": 'ln -s "$RACE_TARGET" "$_OCTO_FREEZE_FILE"',
                    }
                    prelude = "umask() { " + actions[case] + '; builtin umask "$@"; }\n'
                elif case == "missing-python":
                    env["PATH"] = str(root / "missing-path")

                worker = subprocess.Popen([bash, "-c", prelude + code.replace(
                    "<module-directory>", str(module))], env=env,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    start_new_session=True)
                try:
                    stdout, stderr = worker.communicate(timeout=2)
                except subprocess.TimeoutExpired:
                    # The new session's group contains only this probe and its children.
                    try:
                        os.killpg(worker.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    worker.communicate()
                    raise AssertionError("activation blocked on synthetic state")
                proc = subprocess.CompletedProcess(worker.args, worker.returncode,
                                                   stdout, stderr)

                assert marker not in proc.stdout + proc.stderr, "state content disclosed"
                assert not legacy.exists(), "legacy ID overrode current Claude session ID"
                if case == "absent":
                    assert proc.returncode == 0, proc.stderr
                    assert state.read_text() == str(module) + "\n"
                    assert state.stat().st_mode & 0o777 == 0o600
                    payload = json.dumps({"tool_name": "Edit", "tool_input": {
                        "file_path": str(other / "outside.py")}, "cwd": str(root)})
                    enforced = subprocess.run([bash, str(hook)], input=payload,
                        env=env, capture_output=True, text=True, timeout=5)
                    assert enforced.returncode == 0
                    assert '"permissionDecision":"deny"' in enforced.stdout
                elif case in ("valid-existing", "opaque-existing"):
                    assert proc.returncode == 0, proc.stderr
                    expected = str(other) + "\n" if case == "valid-existing" else marker + "\n"
                    assert state.read_text() == expected
                    assert proc.stdout == "Freeze already active; left unchanged.\n"
                else:
                    assert proc.returncode != 0, "unsafe/existing raced state admitted"
                    if case == "empty-regular":
                        assert state.read_text() == ""
                    elif case == "dangling-symlink":
                        assert not target.exists()
                    elif case == "race-regular":
                        assert state.read_text() == "SYNTHETIC_PRESEEDED\n"
                    elif case == "missing-python":
                        assert not state.exists()
                    if original is not None:
                        assert target.read_text() == original, "synthetic target overwritten"
                print("PASS\t" + mirror + ": " + case)
            except Exception as error:
                print("FAIL\t" + mirror + ": " + case + ": " + str(error))
            finally:
                if state.is_dir() and not state.is_symlink():
                    state.rmdir()
                else:
                    state.unlink(missing_ok=True)
                legacy.unlink(missing_ok=True)
PYTEST
)"

while IFS="$(printf '\t')" read -r result label; do
    test_case "$label"
    if [[ "$result" == "PASS" ]]; then
        test_pass
    else
        test_fail "$label"
    fi
done <<< "$probe_results"
test_summary
