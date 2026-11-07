#!/usr/bin/env python3
"""Exercise both claim publication interleavings with the actual executor."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("claims", ROOT / "scripts/helpers/output-claim.py")
claims = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(claims)

RUNNER = r'''
set -euo pipefail
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"
log() { :; }
aggregate_results() { :; }
mkdir() {
    command mkdir "$@" || return
    if [[ "$PAUSE_FALLBACK" == 1 && "${!#}" == "$RESULTS_DIR/.codex-race.claim" ]]; then
        : > "$READY"
        while [[ ! -e "$RESUME" ]]; do sleep 0.01; done
    fi
}
spawn_agent_capture_pid() {
    printf 'active fallback answer\n' > "$RESULTS_DIR/codex-race.md"
    : > "$DISPATCHED"
    : > "$READY"
    sleep 30 >/dev/null 2>&1 &
    printf '%s\n' "$!"
}
AVAILABLE_AGENTS=codex MAX_PARALLEL=1 SUPPORTS_DISABLE_CRON_ENV=false DRY_RUN=false
TIMEOUT=1 GREEN='' NC=''
exec 7>"$WORKSPACE_DIR/caller-fd"
parallel_execute "$TASKS"
'''


class StaleClaimRetirement(unittest.TestCase):
    def test_killed_stale_retirement_does_not_strand_public_claim(self):
        with tempfile.TemporaryDirectory(prefix="claim-retirement-") as directory:
            root = Path(directory)
            claim = root / ".answer.claim"
            claim.mkdir()
            old_owner = root / ".parallel-owner.old"
            new_owner = root / ".parallel-owner.new"
            old_owner.touch()
            new_owner.touch()
            (claim / "owner").write_text(str(old_owner) + "\n")
            code = r'''
import importlib.util, os, signal, sys
spec = importlib.util.spec_from_file_location("claims", sys.argv[1])
claims = importlib.util.module_from_spec(spec)
spec.loader.exec_module(claims)
original = os.unlink
def interrupt(path, *args, **kwargs):
    original(path, *args, **kwargs)
    if os.path.basename(path) == "owner":
        os.kill(os.getpid(), signal.SIGKILL)
claims.os.unlink = interrupt
claims.acquire(sys.argv[2], sys.argv[3])
'''
            killed = subprocess.run(["python3", "-c", code, str(ROOT / "scripts/helpers/output-claim.py"),
                                     str(claim), str(new_owner)], timeout=5)
            self.assertEqual(killed.returncode, -signal.SIGKILL)
            self.assertIn(claims.acquire(str(claim), str(new_owner)),
                          (claims.ACQUIRED, claims.RECLAIMED))
            self.assertEqual((claim / "owner").read_text().strip(), str(new_owner))

    def test_failed_retirement_preserves_owner_and_retry(self):
        with tempfile.TemporaryDirectory(prefix="claim-removal-") as directory:
            root = Path(directory)
            claim = root / ".answer.claim"
            claim.mkdir()
            old_owner = root / ".parallel-owner.old"
            new_owner = root / ".parallel-owner.new"
            old_owner.touch()
            new_owner.touch()
            (claim / "owner").write_text(str(old_owner) + "\n")
            with patch.object(claims.os, "rename", side_effect=OSError("injected retirement failure")) as retire:
                self.assertEqual(claims.acquire(str(claim), str(new_owner)), claims.OWNED)
                retire.assert_called_once()
                self.assertEqual(Path(retire.call_args.args[0]), claim)
                self.assertEqual((claim / "owner").read_text().strip(), str(old_owner))
            self.assertEqual(claims.acquire(str(claim), str(new_owner)), claims.RECLAIMED)
            self.assertEqual((claim / "owner").read_text().strip(), str(new_owner))


class ClaimRaces(unittest.TestCase):
    def exercise(self, pause_fallback):
        with tempfile.TemporaryDirectory(prefix="claim-race-") as directory:
            root = Path(directory)
            workspace, results = root / "workspace", root / "results"
            workspace.mkdir()
            results.mkdir()
            claim = results / ".codex-race.claim"
            owner = results / ".parallel-owner.publisher"
            owner.touch()
            output = results / "codex-race.md"
            output.write_text("saved answer\n")
            tasks = root / "tasks.json"
            tasks.write_text(json.dumps({"tasks": [{"id": "race", "agent": "codex", "prompt": "inert"}]}))
            ready, resume, dispatched = (root / name for name in ("ready", "resume", "dispatched"))
            env = dict(os.environ, PROJECT_ROOT=str(ROOT), WORKSPACE_DIR=str(workspace),
                       RESULTS_DIR=str(results), TASKS=str(tasks), READY=str(ready),
                       RESUME=str(resume), DISPATCHED=str(dispatched),
                       OCTOPUS_RUN_ID="claim-race", OCTOPUS_SKIP_PROVIDER_PROBES="true",
                       PAUSE_FALLBACK="1" if pause_fallback else "0")
            process = None
            rename = os.rename

            def publish_after_fallback(*args):
                nonlocal process
                process = subprocess.Popen(["bash", "-c", RUNNER], env=env,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                           start_new_session=True)
                deadline = time.monotonic() + 5
                while not ready.exists():
                    self.assertIsNone(process.poll(), "fallback exited before the controlled interleaving")
                    self.assertLess(time.monotonic(), deadline, "fallback did not reach publication boundary")
                    time.sleep(0.01)
                rename(*args)
                resume.touch()

            try:
                with patch.object(claims.os, "rename", publish_after_fallback):
                    if pause_fallback:
                        self.assertEqual(claims.acquire(str(claim), str(owner)), claims.ACQUIRED)
                    else:
                        with self.assertRaises(OSError):
                            claims.acquire(str(claim), str(owner))
                if pause_fallback:
                    self.assertIsNotNone(process)
                    deadline = time.monotonic() + 5
                    while process.poll() is None and not dispatched.exists():
                        self.assertLess(time.monotonic(), deadline, "fallback did not finish admission")
                        time.sleep(0.01)
                    self.assertFalse(dispatched.exists(), "fallback dispatched into the Python owner's output")
                    self.assertEqual(output.read_text(), "saved answer\n")
                    self.assertEqual((claim / "owner").read_text().strip(), str(owner))
                else:
                    self.assertTrue(dispatched.exists())
                    self.assertEqual(output.read_text(), "active fallback answer\n")
                    self.assertEqual((claim / "owner").read_text().strip(), "fallback")
            finally:
                if process is not None:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        process.wait(timeout=5)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)

    def test_live_fallback_prevents_python_publication(self):
        self.exercise(False)

    def test_python_publication_prevents_late_fallback_admission(self):
        self.exercise(True)


class ControllerClaimRetirement(unittest.TestCase):
    """Keep both controller cleanup paths recoverable across interruptions."""

    def exercise(self, unregistered, failure):
        """Interrupt the real cleanup path, then reclaim without a running seat."""
        with tempfile.TemporaryDirectory(prefix="controller-retirement-") as directory:
            root = Path(directory)
            workspace, results = root / "workspace", root / "results"
            workspace.mkdir()
            results.mkdir()
            tasks = root / "tasks.json"
            tasks.write_text(json.dumps({"tasks": [{"id": "race", "agent": "codex", "prompt": "inert"}]}))
            wrapper = root / "python-wrapper"
            wrapper.write_text(r'''#!/usr/bin/env python3
import os, runpy, signal, sys
from pathlib import Path
controller = int(os.environ["CONTROLLER_PID"])
operation = sys.argv[2]
original_rename, original_unlink = os.rename, os.unlink
def rename(source, destination, *args, **kwargs):
    if operation == "release" and os.environ["FAILURE"] == "rename":
        Path(os.environ["INJECTED"]).touch()
        raise OSError("injected retirement failure")
    result = original_rename(source, destination, *args, **kwargs)
    if operation == "acquire" and os.environ["UNREGISTERED"] == "1" and str(source).split("/")[-1].startswith(".output-claim."):
        os.kill(controller, signal.SIGTERM)
    return result
def unlink(path, *args, **kwargs):
    result = original_unlink(path, *args, **kwargs)
    if operation == "release" and os.path.basename(path) == "owner" and os.environ["FAILURE"] == "kill":
        Path(os.environ["INJECTED"]).touch()
        os.kill(controller, signal.SIGKILL)
    return result
os.rename, os.unlink = rename, unlink
sys.argv = sys.argv[1:]
try:
    runpy.run_path(sys.argv[0], run_name="__main__")
finally:
    if operation == "release":
        Path(os.environ["HELPER_FINISHED"]).touch()
''')
            wrapper.chmod(0o755)
            runner = r'''
set -euo pipefail
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"
export CONTROLLER_PID=$BASHPID
octopus_pid_python_resolve() { printf '%s\n' "$PYTHON_WRAPPER"; }
log() { :; }
aggregate_results() { :; }
spawn_agent_capture_pid() { return 1; }
rm() {
    command rm "$@" || return
    if [[ "$*" == *'.codex-race.claim/owner'* ]]; then
        touch "$INJECTED"
        [[ "$FAILURE" != kill ]] || kill -KILL "$BASHPID"
    fi
}
rmdir() {
    if [[ "$FAILURE" == rename && "$*" == *'.codex-race.claim'* ]]; then return 1; fi
    command rmdir "$@"
}
AVAILABLE_AGENTS=codex MAX_PARALLEL=1 SUPPORTS_DISABLE_CRON_ENV=false DRY_RUN=false
TIMEOUT=1 GREEN='' NC=''
parallel_execute "$TASKS"
'''
            injected, finished = root / "injected", root / "finished"
            env = dict(os.environ, PROJECT_ROOT=str(ROOT), WORKSPACE_DIR=str(workspace),
                       RESULTS_DIR=str(results), TASKS=str(tasks), PYTHON_WRAPPER=str(wrapper),
                       INJECTED=str(injected), HELPER_FINISHED=str(finished), FAILURE=failure,
                       UNREGISTERED="1" if unregistered else "0", OCTOPUS_RUN_ID="retirement")
            process = subprocess.run(["bash", "-c", runner], env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            self.assertTrue(injected.exists(), process.stderr.decode())
            if failure == "kill":
                self.assertEqual(process.returncode, -signal.SIGKILL, process.stderr.decode())
            claim = results / ".codex-race.claim"
            if failure == "rename":
                self.assertTrue((claim / "owner").is_file(), "failed retirement destroyed the owner record")
                self.assertTrue(Path((claim / "owner").read_text().strip()).is_file(), "failed release unlinked the owner lock")
            else:
                deadline = time.monotonic() + 5
                while not finished.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
            new_owner = results / ".parallel-owner.retry"
            new_owner.touch()
            self.assertIn(claims.acquire(str(claim), str(new_owner)), (claims.ACQUIRED, claims.RECLAIMED))

    def test_registered_cleanup_survives_kill(self):
        """A killed release cannot leave an ownerless registered public claim."""
        self.exercise(False, "kill")

    def test_unregistered_cleanup_survives_kill(self):
        """Signal reconciliation must retire an unregistered claim atomically."""
        self.exercise(True, "kill")

    def test_registered_cleanup_preserves_failed_retirement(self):
        """A failed registered release retains its owner record and lock."""
        self.exercise(False, "rename")

    def test_unregistered_cleanup_preserves_failed_retirement(self):
        """A failed unregistered release retains enough state for reclamation."""
        self.exercise(True, "rename")

    def test_release_cannot_retire_another_owner(self):
        """An old controller must not delete a replacement owner's claim."""
        with tempfile.TemporaryDirectory(prefix="claim-owner-check-") as directory:
            root = Path(directory)
            claim = root / ".answer.claim"
            owner = root / ".parallel-owner.current"
            previous = root / ".parallel-owner.previous"
            owner.touch()
            previous.touch()
            self.assertEqual(claims.acquire(str(claim), str(owner)), claims.ACQUIRED)
            self.assertEqual(claims.release(str(claim), str(previous)), claims.OWNED)
            self.assertEqual((claim / "owner").read_text().strip(), str(owner))
            self.assertEqual(claims.release(str(claim), str(owner)), claims.ACQUIRED)
            self.assertFalse(claim.exists())


if __name__ == "__main__":
    unittest.main()
