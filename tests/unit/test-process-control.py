#!/usr/bin/env python3
"""Test cancellation contracts without attempting to force OS PID reuse."""

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HELPER = Path(__file__).resolve().parents[2] / "scripts/helpers/process_control.py"
control = None
if HELPER.exists():
    spec = importlib.util.spec_from_file_location("process_control", HELPER)
    control = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = control
    spec.loader.exec_module(control)


class Availability(unittest.TestCase):
    def test_identity_bound_teardown_is_packaged(self):
        self.assertTrue(HELPER.is_file(), "shared identity-bound teardown is missing")


@unittest.skipIf(control is None, "implementation not present yet")
class ProcessControlTests(unittest.TestCase):
    def setUp(self):
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=3)

    def child(self, code="import time; time.sleep(30)"):
        child = subprocess.Popen([sys.executable, "-c", code])
        self.children.append(child)
        return child

    def _private_group_leader(self):
        """Return a fixture only after its private session is established."""
        root = self.child("import os,time; os.setsid(); time.sleep(30)")
        deadline = time.monotonic() + 3
        while os.getpgid(root.pid) != root.pid and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertEqual(os.getpgid(root.pid), root.pid)
        return root

    def test_snapshot_is_stable_and_has_real_parent(self):
        child = self.child()
        first = control.snapshot(child.pid)
        second = control.snapshot(child.pid)
        self.assertEqual(first.token, second.token)
        self.assertEqual(first.ppid, os.getpid())

    def test_handoff_enumeration_failure_resumes_the_caller(self):
        root = self._private_group_leader()
        with mock.patch.object(control, "children", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                control.handoff_to_children(root.pid)
        self.assertFalse(control.snapshot(root.pid).stopped)
        self.assertIsNone(root.poll())

    def test_handoff_rejects_a_changed_caller_identity_without_signalling(self):
        root = self._private_group_leader()
        with mock.patch.object(control.Process, "send") as send:
            with self.assertRaises(control.StaleProcess):
                control.handoff_to_children(root.pid, "wrong-birth")
            send.assert_not_called()

    def test_handoff_cannot_freeze_its_own_process(self):
        with mock.patch.object(control.Process, "send") as send:
            with self.assertRaises(ValueError):
                control.handoff_to_children(os.getpid())
            send.assert_not_called()

    def test_quota_callback_requires_the_registered_worker_identity(self):
        """A delayed watcher must not signal a replacement worker or its child."""
        for expected in ("wrong-birth", ""):
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temporary:
                marker = Path(temporary) / "child"
                root = self.child(
                    "import pathlib,subprocess,sys,time; "
                    "p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                    f"pathlib.Path({str(marker) + '.tmp'!r}).write_text(str(p.pid)); "
                    f"pathlib.Path({str(marker) + '.tmp'!r}).replace({str(marker)!r}); time.sleep(30)"
                )
                deadline = time.monotonic() + 3
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(marker.exists())
                with control.Process(int(marker.read_text())) as child:
                    try:
                        result = subprocess.run(
                            ["bash", "-c", 'source "$1/scripts/lib/spawn.sh"; '
                             'log() { printf "%s\\n" "$2"; }; quota_watcher_kill_spawn_children "$2" "$3"',
                             "_", str(HELPER.parents[2]), str(root.pid), expected],
                            capture_output=True, text=True, timeout=10,
                        )
                        self.assertNotEqual(result.returncode, 0, result.stderr)
                        refusal = ("worker identity no longer matches registration" if expected
                                   else "worker registration identity is missing")
                        self.assertIn(refusal, result.stderr if expected else result.stdout)
                        self.assertTrue(child.running(), "unregistered child's process was signalled")
                        self.assertFalse(control.snapshot(root.pid).stopped)
                    finally:
                        child.send(signal.SIGKILL)

    def test_handoff_does_not_kill_a_supervisor_that_still_owns_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="octo-handoff-test-") as temporary:
            marker = Path(temporary) / "child"
            child_code = ("import os,pathlib,signal,time; "
                          "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                          f"pathlib.Path({str(marker) + '.tmp'!r}).write_text(str(os.getpid())); "
                          f"pathlib.Path({str(marker) + '.tmp'!r}).replace({str(marker)!r}); "
                          "time.sleep(30)")
            root = self.child(
                "import subprocess,sys,time; "
                f"p=subprocess.Popen([sys.executable,'-c',{child_code!r}]); "
                "time.sleep(30)"
            )
            deadline = time.monotonic() + 3
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(marker.exists())
            with control.Process(int(marker.read_text())) as child:
                try:
                    with mock.patch.object(control, "_wait", return_value=False):
                        self.assertEqual(control.handoff_to_children(root.pid), "survived")
                    self.assertTrue(child.running())
                    self.assertFalse(control.snapshot(root.pid).stopped)
                finally:
                    child.send(signal.SIGKILL)

    def test_expected_identity_is_required_before_binding(self):
        child = self.child()
        with self.assertRaises(control.StaleProcess):
            control.Process(child.pid, expected="not-this-process")
        self.assertIsNone(child.poll())

    def test_parent_must_match_before_admitting_descendant(self):
        child = self.child()
        with self.assertRaises(control.StaleProcess):
            control.Process(child.pid, parent=1)
        self.assertIsNone(child.poll())

    def test_bound_signal_terminates_owned_child(self):
        child = self.child()
        with control.Process(child.pid) as handle:
            self.assertTrue(handle.send(signal.SIGTERM))
            child.wait(timeout=3)
            self.assertFalse(handle.running())
            self.assertFalse(handle.send(signal.SIGKILL))

    def test_graceful_exit_does_not_pay_full_grace_delay(self):
        child = self.child()
        start = time.monotonic()
        self.assertEqual(control.terminate(child.pid, grace=3), "terminated")
        self.assertLess(time.monotonic() - start, 1.5)
        child.wait(timeout=3)

    def test_invalid_and_ancestor_roots_are_not_signalled(self):
        with mock.patch.object(control.Process, "send") as send:
            for pid in (0, 1, -1, os.getpid(), os.getppid()):
                with self.assertRaises(ValueError):
                    control.terminate(pid)
            send.assert_not_called()

    def test_out_of_range_pids_never_reach_native_conversion(self):
        with mock.patch.object(sys, "platform", "darwin"), \
             mock.patch.object(control, "_darwin_info", side_effect=AssertionError("invalid PID reached native API")):
            for pid in (2**31, 2**32, 2**63, 1.5):
                with self.assertRaises(ValueError):
                    control.snapshot(pid)

    def test_disappeared_root_is_not_replaced_by_numeric_group_kill(self):
        child = self.child()
        child.kill()
        child.wait(timeout=3)
        with mock.patch.object(os, "kill") as kill, mock.patch.object(os, "killpg") as killpg:
            self.assertEqual(control.terminate(child.pid, frozen=True), "already-exited")
            kill.assert_not_called()
            killpg.assert_not_called()

    def test_native_boundary_never_falls_back_to_numeric_kill(self):
        child = self.child()
        with control.Process(child.pid) as handle:
            with mock.patch.object(handle, "_send_native", side_effect=PermissionError("denied")), \
                 mock.patch.object(os, "kill") as kill:
                with self.assertRaises(PermissionError):
                    handle.send(signal.SIGSTOP)
                kill.assert_not_called()

    def test_terminated_tree_includes_term_ignoring_descendant(self):
        with tempfile.TemporaryDirectory(prefix="octo-control-test-") as temporary:
            marker = Path(temporary) / "child"
            root = self.child(
                "import subprocess,sys,time,pathlib,signal; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                "p=subprocess.Popen([sys.executable,'-c',"
                "'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)']); "
                f"pathlib.Path({str(marker) + '.tmp'!r}).write_text(str(p.pid)); "
                f"pathlib.Path({str(marker) + '.tmp'!r}).replace({str(marker)!r}); "
                "time.sleep(30)"
            )
            deadline = time.monotonic() + 3
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(marker.exists())
            with control.Process(int(marker.read_text())) as descendant:
                try:
                    self.assertEqual(control.terminate(root.pid, grace=0.05), "terminated")
                    self.assertFalse(descendant.running())
                finally:
                    descendant.send(signal.SIGKILL)

    def test_owned_group_captures_orphan_without_signalling_another_group(self):
        """A double-forked helper stays owned by its still-live private leader."""
        unrelated = self.child()
        with tempfile.TemporaryDirectory(prefix="octo-group-test-") as temporary:
            marker = Path(temporary) / "helper"
            ready = Path(temporary) / "ready"
            root = self.child(
                "import os,pathlib,signal,time; os.setsid(); p=os.fork(); "
                "\nif p == 0:"
                "\n if os.fork() != 0: os._exit(0)"
                "\n signal.signal(signal.SIGTERM,signal.SIG_IGN)"
                f"\n pathlib.Path({str(marker) + '.tmp'!r}).write_text(str(os.getpid()))"
                f"\n pathlib.Path({str(marker) + '.tmp'!r}).replace({str(marker)!r})"
                "\n while True: time.sleep(1)"
                # Force the helper to publish before its parent reaps the
                # intermediate child. Its PID alone is not fixture readiness.
                "\ntime.sleep(0.25); os.waitpid(p,0)"
                f"\npathlib.Path({str(ready)!r}).touch()"
                "\ntime.sleep(30)"
            )
            deadline = time.monotonic() + 3
            while not (marker.exists() and ready.exists()) and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(marker.exists())
            self.assertTrue(ready.exists(), "fixture parent did not finish reaping")
            with control.Process(int(marker.read_text())) as orphan:
                try:
                    self.assertNotEqual(orphan.info.ppid, root.pid)
                    self.assertEqual(os.getpgid(orphan.info.pid), root.pid)
                    scans = []

                    def changing_groups():
                        scans.append(control.snapshot(root.pid).stopped)
                        if len(scans) == 1:
                            yield 2**30, root.pid
                        # This fixture tests native admission and signalling.
                        # Global procfs churn is covered by separate scan tests.
                        yield root.pid, root.pid
                        yield orphan.info.pid, root.pid

                    with mock.patch.object(os, "kill") as kill, \
                         mock.patch.object(os, "killpg") as killpg, \
                         mock.patch.object(control, "_process_groups", changing_groups):
                        self.assertEqual(control.terminate(root.pid, frozen=True, owned_groups=True),
                                         "terminated")
                        kill.assert_not_called()
                        killpg.assert_not_called()
                    self.assertEqual(scans, [True, True])
                    self.assertFalse(orphan.running())
                    self.assertIsNone(unrelated.poll())
                finally:
                    orphan.send(signal.SIGKILL)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux procfs scheduling barrier")
    def test_owned_group_fork_exit_during_stat_read_cannot_hide_newborn(self):
        """A real fork after directory capture cannot yield false cleanup success."""
        unrelated = self.child()
        real_read = Path.read_bytes
        real_scan = os.scandir
        for state in ("zombie", "reaped"):
            with self.subTest(state=state), tempfile.TemporaryDirectory(prefix="octo-scan-race-") as temporary:
                directory = Path(temporary)
                root = self.child(
                    "import os,pathlib,signal,time; os.setsid(); p=os.fork()"
                    "\nif p == 0:"
                    "\n if os.fork() != 0: os._exit(0)"
                    f"\n d=pathlib.Path({temporary!r})"
                    "\n (d/'parent.tmp').write_text(str(os.getpid()))"
                    "\n (d/'parent.tmp').replace(d/'parent')"
                    "\n while not (d/'fork').exists(): time.sleep(0.005)"
                    "\n if os.fork() != 0: os._exit(0)"
                    "\n signal.signal(signal.SIGTERM,signal.SIG_IGN)"
                    "\n (d/'newborn.tmp').write_text(str(os.getpid()))"
                    "\n (d/'newborn.tmp').replace(d/'newborn')"
                    "\n while True: time.sleep(1)"
                    # An unreaped intermediate child refuses admission before
                    # the barrier. Publish readiness only after reaping it.
                    "\ntime.sleep(0.25); os.waitpid(p,0)"
                    f"\npathlib.Path({temporary!r}, 'ready').touch()"
                    "\ntime.sleep(30)"
                )
                deadline = time.monotonic() + 3
                while not ((directory / "parent").exists() and (directory / "ready").exists()) \
                        and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue((directory / "parent").exists())
                self.assertTrue((directory / "ready").exists(), "fixture parent did not finish reaping")
                parent = int((directory / "parent").read_text())
                triggered = []
                group_scan = []
                real_groups = control._process_groups

                def owned_group_scan():
                    group_scan.append(True)
                    try:
                        yield from real_groups()
                    finally:
                        group_scan.pop()

                def captured_directory(path):
                    # Freeze this directory iteration before allowing the fork.
                    # A newborn need not appear in a scan already in progress.
                    with real_scan(path) as entries:
                        captured = list(entries)
                    result = mock.MagicMock()
                    result.__enter__.return_value = captured
                    return result

                def fork_before_read(path):
                    if group_scan and str(path) == f"/proc/{parent}/stat" and not triggered:
                        triggered.append(control.snapshot(root.pid).stopped)
                        (directory / "fork").touch()
                        deadline = time.monotonic() + 3
                        while time.monotonic() < deadline:
                            try:
                                fields = real_read(path).rsplit(b")", 1)[1].split()
                                exited = fields[0] in (b"Z", b"X")
                            except FileNotFoundError:
                                exited = True
                            if exited and (directory / "newborn").exists():
                                break
                            time.sleep(0.005)
                        else:
                            self.fail("fork/exit barrier did not complete")
                        if state == "reaped":
                            # A reaped stat read has no remaining PGID evidence.
                            raise FileNotFoundError("enumerated member reaped")
                    return real_read(path)

                refused = False
                try:
                    with mock.patch.object(os, "scandir", captured_directory), \
                         mock.patch.object(control, "_process_groups", owned_group_scan), \
                         mock.patch.object(Path, "read_bytes", fork_before_read):
                        try:
                            result = control.terminate(root.pid, frozen=True, owned_groups=True)
                            self.assertEqual(result, "terminated")
                        except control.StaleProcess:
                            refused = True
                    self.assertEqual(triggered, [True], "leader must stay stopped at the barrier")
                    try:
                        with control.Process(int((directory / "newborn").read_text())) as newborn:
                            try:
                                self.assertTrue(refused or not newborn.running(),
                                                "cleanup succeeded while the unseen newborn survived")
                            finally:
                                newborn.send(signal.SIGKILL)
                    except ProcessLookupError:
                        pass  # A complete rescan is also allowed to cancel the newborn.
                    if refused:
                        deadline = time.monotonic() + 1
                        while control.snapshot(root.pid).stopped and time.monotonic() < deadline:
                            time.sleep(0.01)
                        self.assertFalse(control.snapshot(root.pid).stopped)
                    self.assertIsNone(unrelated.poll())
                finally:
                    # Also clean the orphan if a test assertion failed early.
                    for marker in ("newborn", "parent"):
                        if (directory / marker).exists():
                            try:
                                with control.Process(int((directory / marker).read_text())) as remaining:
                                    remaining.send(signal.SIGKILL)
                            except ProcessLookupError:
                                pass

    def test_owned_group_requires_live_original_leader_before_enumeration(self):
        """An exited or changed leader cannot authorize numeric group recovery."""
        leader = mock.Mock()
        leader.info.pid = 4242
        for running, pgid in [(False, 4242), (True, 4343)]:
            leader.running.return_value = running
            with mock.patch.object(os, "getpgid", return_value=pgid), \
                 mock.patch.object(control, "_process_groups") as scan:
                with self.assertRaises(control.StaleProcess):
                    list(control._owned_group_candidates([leader]))
                scan.assert_not_called()

    def test_descendant_exit_before_binding_refuses_owned_group_teardown(self):
        """A vanished private leader must not let its supervisor be killed."""
        root = self._private_group_leader()
        real_process = control.Process
        with mock.patch.object(control, "children", return_value=[2**30]), \
             mock.patch.object(control, "Process", side_effect=lambda pid, **kw:
                               real_process(pid, **kw)), \
             mock.patch.object(os, "kill") as kill, mock.patch.object(os, "killpg") as killpg:
            with self.assertRaisesRegex(control.StaleProcess, "descendant.*admission"):
                control.terminate(root.pid, frozen=True, owned_groups=True)
            kill.assert_not_called()
            killpg.assert_not_called()
        self.assertIsNone(root.poll())
        deadline = time.monotonic() + 1
        while control.snapshot(root.pid).stopped and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(control.snapshot(root.pid).stopped)

    def test_darwin_zombie_lookup_is_explicit(self):
        lib = mock.Mock()
        lib.proc_pidinfo.side_effect = lambda pid, flavor, arg, info, size: size
        with mock.patch.object(control, "_darwin", return_value=lib):
            control._darwin_info(4242, 13, control._ShortInfo)
            self.assertEqual(lib.proc_pidinfo.call_args.args[2], 0)
            control._darwin_info(4242, 13, control._ShortInfo, include_zombies=True)
            self.assertEqual(lib.proc_pidinfo.call_args.args[2], 1)

    @unittest.skipUnless(sys.platform == "darwin", "native macOS zombie lookup")
    def test_darwin_persistent_zombie_identity(self):
        root = self.child("import os,time; os.setsid(); time.sleep(0.1)")
        # Do not poll/wait: the direct child must remain an unreaped zombie.
        deadline = time.monotonic() + 3
        identity = None
        while identity is None and time.monotonic() < deadline:
            identity = control._zombie_group_identity(root.pid, root.pid)
            time.sleep(0.01)
        self.assertIsNotNone(identity)
        self.assertEqual(control._zombie_group_identity(root.pid, root.pid), identity)

    def test_owned_group_member_must_still_belong_to_bound_leader(self):
        """Membership races refuse admission before any signal is delivered."""
        leader, member = mock.Mock(), mock.Mock()
        leader.info.pid = 4242
        member.running.return_value = True
        handles = []
        with mock.patch.object(control, "_owned_group_candidates", return_value=[(4343, leader)]), \
             mock.patch.object(control, "Process", return_value=member), \
             mock.patch.object(os, "getpgid", return_value=4444), \
             mock.patch.object(os, "kill") as kill, mock.patch.object(os, "killpg") as killpg:
            with self.assertRaises(control.StaleProcess):
                control._admit_owned_group_members([leader], handles, set(), set())
            member.send.assert_not_called()
            kill.assert_not_called()
            killpg.assert_not_called()
        self.assertEqual(handles, [member], "caller retains the handle for final cleanup")

    def test_group_scan_preserves_exited_members_for_rescan(self):
        """A zombie snapshot row must not disappear before group admission."""
        leader = mock.Mock()
        leader.info.pid = 4242
        result = subprocess.CompletedProcess([], 0, stdout=b"4343 4242 Z\n4444 4444 S\n")
        records = [(4343, [b"Z", b"1", b"4242"]), (4444, [b"S", b"1", b"4444"])]
        for platform in ("linux", "darwin"):
            with self.subTest(platform=platform), \
                 mock.patch.object(sys, "platform", platform), \
                 mock.patch.object(subprocess, "run", return_value=result), \
                 mock.patch.object(control, "_linux_proc_records", return_value=records), \
                 mock.patch.object(os, "getpgid", return_value=4242), \
                 mock.patch.object(control, "Process", side_effect=ProcessLookupError()), \
                 mock.patch.object(control, "_zombie_group_identity", return_value=None):
                self.assertEqual(control._admit_owned_group_members([leader], [], set(), set()),
                                 ([], True))

    def test_group_member_disappearance_cannot_report_successful_admission(self):
        """A listed process may leave a child behind before its identity binds."""
        leader = mock.Mock()
        leader.info.pid = 4242
        with mock.patch.object(control, "_owned_group_candidates", return_value=[(4343, leader)]), \
             mock.patch.object(control, "Process", side_effect=ProcessLookupError()):
            self.assertEqual(control._admit_owned_group_members([leader], [], set(), set()),
                             ([], True))

    def test_owned_group_rescans_after_exit_without_resuming_the_leader(self):
        """Transient group churn retains the stopped owner until a complete scan."""
        root = self._private_group_leader()
        scans = []

        def groups():
            scans.append(control.snapshot(root.pid).stopped)
            if len(scans) == 1:
                yield 2**30, root.pid

        with mock.patch.object(control, "_process_groups", groups):
            self.assertEqual(control.terminate(root.pid, frozen=True, owned_groups=True), "terminated")
        self.assertEqual(scans, [True, True])

    def test_owned_group_persistent_churn_is_bounded_and_resumes_the_leader(self):
        """Exhausted rescans refuse safely and resume the same stopped process."""
        root = self._private_group_leader()
        scans = []

        def groups():
            scans.append(control.snapshot(root.pid).stopped)
            yield 2**30, root.pid

        with mock.patch.object(control, "_process_groups", groups):
            with self.assertRaisesRegex(control.StaleProcess, "kept changing"):
                control.terminate(root.pid, frozen=True, owned_groups=True)
        self.assertEqual(scans, [True] * 5)
        deadline = time.monotonic() + 1
        while control.snapshot(root.pid).stopped and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(control.snapshot(root.pid).stopped)
        self.assertIsNone(root.poll())

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux procfs enumeration")
    def test_owned_group_cleanup_on_linux_does_not_require_ps(self):
        """Minimal Linux hosts need only the existing readable procfs contract."""
        root = self._private_group_leader()
        # Global procfs churn is covered by separate scan tests.
        records = [(root.pid, [b"T", str(os.getpid()).encode(), str(root.pid).encode()])]
        with mock.patch.object(subprocess, "run", side_effect=FileNotFoundError("ps")), \
             mock.patch.object(control, "_linux_proc_records", side_effect=lambda **_: iter(records)) as scan:
            self.assertEqual(control.terminate(root.pid, frozen=True, owned_groups=True), "terminated")
        scan.assert_called_with(require_complete=True)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux complete snapshot retries")
    def test_incomplete_group_snapshot_retries_before_exposing_candidates(self):
        """Discard partial rows and bound retry while retaining a complete next scan."""
        def partial():
            yield 4343, [b"S", b"1", b"4242"]
            raise control.StaleProcess("vanished record")

        complete = [(4444, [b"S", b"1", b"4242"])]
        with mock.patch.object(control, "_linux_proc_records", side_effect=[partial(), complete]) as scan:
            self.assertEqual(list(control._process_groups()), [(4444, 4242)])
            self.assertEqual(scan.call_count, 2)
        with mock.patch.object(control, "_linux_proc_records", side_effect=control.StaleProcess()) as scan:
            with self.assertRaises(control.StaleProcess):
                list(control._process_groups())
            self.assertEqual(scan.call_count, 5)

    def test_linux_zombie_identity_requires_dead_state_and_owned_group(self):
        """Only an atomic dead-state, group and birth record can be remembered."""
        for state, pgid, expected in ((b"Z", b"4242", (4343, b"123")),
                                      (b"S", b"4242", None), (b"Z", b"4444", None)):
            fields = [state, b"1", pgid] + [b"0"] * 16 + [b"123"]
            with mock.patch.object(sys, "platform", "linux"), \
                 mock.patch.object(Path, "read_bytes", return_value=b"4343 (helper) " + b" ".join(fields)):
                self.assertEqual(control._zombie_group_identity(4343, 4242), expected)
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(Path, "read_bytes", side_effect=PermissionError()):
            with self.assertRaises(PermissionError):
                control._zombie_group_identity(4343, 4242)

    def test_darwin_zombie_identity_requires_stable_birth_and_owned_group(self):
        """A reused PID or live native record cannot authorize skipping an exit."""
        for status, pgid, birth, expected in ((5, 4242, 100, (4343, 100)),
                                             (2, 4242, 100, None),
                                             (5, 4444, 100, None), (5, 4242, 101, None)):
            with mock.patch.object(sys, "platform", "darwin"), \
                 mock.patch.object(control, "_darwin_info", side_effect=[
                     mock.Mock(unique=100), mock.Mock(status=status, pgid=pgid), mock.Mock(unique=birth)]):
                self.assertEqual(control._zombie_group_identity(4343, 4242), expected)

    def test_confirmed_persistent_zombie_allows_cleanup_after_rescan(self):
        """An unchanged zombie cannot fork again and must not starve teardown."""
        root = self._private_group_leader()
        scans = []

        def groups():
            scans.append(control.snapshot(root.pid).stopped)
            yield 2**30, root.pid

        with mock.patch.object(control, "_process_groups", groups), \
             mock.patch.object(control, "_zombie_group_identity", return_value=(2**30, "same-birth"), create=True):
            self.assertEqual(control.terminate(root.pid, frozen=True, owned_groups=True), "terminated")
        self.assertEqual(scans, [True, True])
        root.wait(timeout=3)

    def test_changed_zombie_identity_still_requires_bounded_rescans(self):
        """PID reuse or successive exits cannot borrow an earlier dead identity."""
        root = self._private_group_leader()
        scans = []

        def groups():
            scans.append(control.snapshot(root.pid).stopped)
            yield 2**30, root.pid

        with mock.patch.object(control, "_process_groups", groups), \
             mock.patch.object(control, "_zombie_group_identity",
                               side_effect=[(2**30, birth) for birth in range(5)], create=True):
            with self.assertRaisesRegex(control.StaleProcess, "kept changing"):
                control.terminate(root.pid, frozen=True, owned_groups=True)
        self.assertEqual(scans, [True] * 5)
        self.assertIsNone(root.poll())

    def test_owned_group_scan_failure_resumes_bound_leader(self):
        """Unavailable group metadata refuses cleanup without stranding STOP."""
        root = self._private_group_leader()
        with mock.patch.object(control, "_process_groups", side_effect=PermissionError("group scan")):
            with self.assertRaises(PermissionError):
                control.terminate(root.pid, frozen=True, owned_groups=True)
        deadline = time.monotonic() + 1
        while control.snapshot(root.pid).stopped and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(control.snapshot(root.pid).stopped)
        self.assertIsNone(root.poll())

    def test_stop_confirmation_retries_the_identity_bound_signal(self):
        handle = mock.Mock()
        handle.info = control.ProcessInfo(4242, 20, "original", 0, False)
        handle.running.return_value = True
        stop_attempts = 0
        clock = 0.0

        def send(signum):
            nonlocal stop_attempts
            if signum == signal.SIGSTOP:
                stop_attempts += 1
            return True

        def snapshot(_pid):
            return handle.info._replace(stopped=stop_attempts >= 2)

        def monotonic():
            nonlocal clock
            current = clock
            clock += 0.2
            return current

        handle.send.side_effect = send

        with mock.patch.object(control, "_ancestors", return_value=set()), \
             mock.patch.object(control, "Process", return_value=handle), \
             mock.patch.object(control, "snapshot", side_effect=snapshot), \
             mock.patch.object(control, "children", return_value=[]), \
             mock.patch.object(control, "_wait", return_value=True), \
             mock.patch.object(control.time, "monotonic", side_effect=monotonic), \
             mock.patch.object(control.time, "sleep"):
            self.assertEqual(control.terminate(4242, frozen=True), "terminated")

    def test_linux_missing_task_children_uses_proc_stat_fallback(self):
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(Path, "glob", return_value=[]), \
             mock.patch.object(control, "_linux_proc_children", return_value=[4343]) as fallback:
            self.assertEqual(control.children(4242), [4343])
        fallback.assert_called_once_with(4242)

    def test_linux_byte_stat_preserves_stopped_and_zombie_states(self):
        for state in [b"T", b"t", b"Z", b"X"]:
            record = b"4242 (bad\xff) " + state + b" 20 " + b"0 " * 17 + b"12345"
            with mock.patch.object(sys, "platform", "linux"), \
                 mock.patch.object(Path, "read_bytes", return_value=record), \
                 mock.patch.object(control, "_boot_id", return_value="test-boot"):
                if state in [b"Z", b"X"]:
                    with self.assertRaises(ProcessLookupError):
                        control.snapshot(4242)
                else:
                    snapshot = control.snapshot(4242)
                    self.assertTrue(snapshot.stopped)
                    self.assertEqual(snapshot.ppid, 20)
                    expected = control.hashlib.sha256(b"test-boot:4242:12345").hexdigest()
                    self.assertEqual(snapshot.token, expected)

    def test_linux_proc_scan_accepts_invalid_utf8_process_names(self):
        entries = [mock.Mock(name="entry") for _ in range(2)]
        entries[0].name, entries[0].path = "4343", "/proc/4343"
        entries[1].name, entries[1].path = "4444", "/proc/4444"
        scan = mock.MagicMock()
        scan.__enter__.return_value = entries
        records = [b"1 (self) R 0", b"4343 (child) S 4242", b"4444 (bad\xff) R 7"]
        with mock.patch.object(control.os, "scandir", return_value=scan), \
             mock.patch.object(Path, "read_bytes", side_effect=records):
            self.assertEqual(control._linux_proc_children(4242), [4343])

    def test_linux_fallback_failure_is_not_an_empty_child_list(self):
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(Path, "glob", return_value=[]), \
             mock.patch.object(control, "_linux_proc_children", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                control.children(4242)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux procfs enumeration")
    def test_linux_proc_scan_skips_only_disappeared_records(self):
        """Child scans skip exits; complete group scans cannot discard unknown PGIDs."""
        gone = mock.Mock()
        gone.name, gone.path = "4343", "/proc/4343"
        live = mock.Mock()
        live.name, live.path = "4444", "/proc/4444"
        scan = mock.MagicMock()
        scan.__enter__.return_value = [gone, live]
        for error in (FileNotFoundError(), ProcessLookupError()):
            with self.subTest(error=type(error).__name__), \
                 mock.patch.object(control.os, "scandir", return_value=scan), \
                 mock.patch.object(Path, "read_bytes", side_effect=[
                     b"1 (self) R 0", error, b"4444 (live) S 4242 4242"]):
                self.assertEqual(control._linux_proc_children(4242), [4444])
            with self.subTest(error=type(error).__name__, complete=True), \
                 mock.patch.object(control.os, "scandir", return_value=scan), \
                 mock.patch.object(Path, "read_bytes", side_effect=[b"1 (self) R 0", error] * 5):
                with self.assertRaisesRegex(control.StaleProcess, "during group enumeration"):
                    list(control._process_groups())
        with mock.patch.object(control.os, "scandir", return_value=scan), \
             mock.patch.object(Path, "read_bytes", side_effect=[b"1 (self) R 0", PermissionError()]):
            with self.assertRaises(PermissionError):
                list(control._linux_proc_records())

    def test_linux_handle_is_closed_if_post_open_identity_changes(self):
        info = control.ProcessInfo(4242, 20, "before", 0, False)
        replacement = control.ProcessInfo(4242, 20, "after", 0, False)
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(control, "snapshot", side_effect=[info, replacement]), \
             mock.patch.object(os, "pidfd_open", return_value=123, create=True), \
             mock.patch.object(signal, "pidfd_send_signal", create=True), \
             mock.patch.object(os, "close") as close:
            with self.assertRaises(control.StaleProcess):
                control.Process(4242)
            close.assert_called_once_with(123)

    def test_missing_linux_pidfd_support_fails_closed(self):
        info = control.ProcessInfo(4242, 20, "original", 0, False)
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(control, "snapshot", return_value=info), \
             mock.patch.object(os, "pidfd_open", None, create=True):
            with self.assertRaises(control.UnsupportedPlatform):
                control.Process(4242)

    def test_linux_capability_check_requires_both_pidfd_primitives(self):
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(os, "pidfd_open", mock.Mock(), create=True), \
             mock.patch.object(signal, "pidfd_send_signal", None, create=True):
            with self.assertRaisesRegex(control.UnsupportedPlatform, "CPython build"):
                control.require_native_cancellation_support()

        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(os, "pidfd_open", return_value=123, create=True), \
             mock.patch.object(signal, "pidfd_send_signal", mock.Mock(), create=True), \
             mock.patch.object(os, "close"):
            control.require_native_cancellation_support()

    def test_linux_capability_check_requires_working_pidfd_syscalls(self):
        with mock.patch.object(sys, "platform", "linux"), \
             mock.patch.object(os, "pidfd_open", return_value=123, create=True), \
             mock.patch.object(signal, "pidfd_send_signal",
                               side_effect=PermissionError("blocked"), create=True), \
             mock.patch.object(os, "close") as close:
            with self.assertRaisesRegex(control.UnsupportedPlatform, "cannot use pidfd"):
                control.require_native_cancellation_support()
            close.assert_called_once_with(123)

    def test_linux_escalation_uses_the_retained_handle(self):
        handle = control.Process.__new__(control.Process)
        handle.fd = 123
        handle.info = control.ProcessInfo(4242, 20, "original", 0, False)
        with mock.patch.object(signal, "pidfd_send_signal", create=True) as send, \
             mock.patch.object(control, "snapshot") as snapshot, \
             mock.patch.object(os, "kill") as kill:
            handle.send(signal.SIGTERM)
            handle.send(signal.SIGKILL)
            self.assertEqual(send.call_args_list, [mock.call(123, signal.SIGTERM),
                                                   mock.call(123, signal.SIGKILL)])
            snapshot.assert_not_called()
            kill.assert_not_called()

    def test_darwin_refreshes_exec_version_only_for_same_birth(self):
        handle = control.Process.__new__(control.Process)
        handle.fd = None
        handle.info = control.ProcessInfo(4242, 20, "original", 7, False)
        records = [handle.info, handle.info._replace(version=8)]
        sent = []

        def native(audit, signum):
            sent.append((audit[5], audit[7], signum))
            return 3 if len(sent) == 1 else 0  # ESRCH on the superseded exec version.

        lib = mock.Mock()
        lib.proc_signal_with_audittoken.side_effect = native
        with mock.patch.object(control, "snapshot", side_effect=records), \
             mock.patch.object(control, "_darwin", return_value=lib):
            self.assertTrue(handle.send(signal.SIGKILL))
        self.assertEqual(sent, [(4242, 7, signal.SIGKILL), (4242, 8, signal.SIGKILL)])

    def test_darwin_does_not_refresh_a_replacement_process(self):
        handle = control.Process.__new__(control.Process)
        handle.fd = None
        handle.info = control.ProcessInfo(4242, 20, "original", 7, False)
        with mock.patch.object(control, "snapshot", return_value=handle.info._replace(token="replacement")), \
             mock.patch.object(control, "_darwin") as lib, \
             mock.patch.object(os, "kill") as kill:
            self.assertFalse(handle.send(signal.SIGKILL))
            lib.assert_not_called()
            kill.assert_not_called()

    def test_darwin_permission_race_is_exited_when_identity_disappears(self):
        handle = control.Process.__new__(control.Process)
        handle.fd = None
        handle.info = control.ProcessInfo(4242, 20, "original", 7, False)
        lib = mock.Mock()
        lib.proc_signal_with_audittoken.return_value = 1  # EPERM
        with mock.patch.object(control, "snapshot",
                               side_effect=[handle.info, ProcessLookupError()]), \
             mock.patch.object(control, "_darwin", return_value=lib):
            self.assertFalse(handle.send(signal.SIGCONT))

    def test_darwin_unrelated_permission_error_is_not_misclassified_as_exited(self):
        # A generic OSError from the confirming snapshot() (e.g. EPERM/EACCES
        # reading a still-live process this caller can no longer introspect)
        # is not proof the process exited. It must propagate as itself so the
        # caller ends up at the documented "unverified" outcome, not be
        # silently collapsed into a false "already exited" success.
        handle = control.Process.__new__(control.Process)
        handle.fd = None
        handle.info = control.ProcessInfo(4242, 20, "original", 7, False)
        lib = mock.Mock()
        lib.proc_signal_with_audittoken.return_value = 1  # EPERM
        with mock.patch.object(control, "snapshot",
                               side_effect=[handle.info, PermissionError("denied")]), \
             mock.patch.object(control, "_darwin", return_value=lib):
            with self.assertRaises(PermissionError):
                handle.send(signal.SIGCONT)

    def test_enumeration_failure_resumes_only_processes_stopped_here(self):
        child = self.child()
        with mock.patch.object(control, "children", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                control.terminate(child.pid, frozen=True)
        deadline = time.monotonic() + 1
        while control.snapshot(child.pid).stopped and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(control.snapshot(child.pid).stopped)

    def test_frozen_cancellation_uses_no_external_probes(self):
        child = self.child()
        with mock.patch.object(subprocess, "Popen") as launch:
            self.assertEqual(control.terminate(child.pid, frozen=True), "terminated")
            launch.assert_not_called()

    def test_interruption_after_stop_delivery_still_resumes_worker(self):
        child = self.child()
        original = control.Process.send

        def send(handle, signum):
            result = original(handle, signum)
            if signum == signal.SIGSTOP:
                raise InterruptedError("interrupted after delivery")
            return result

        with mock.patch.object(control.Process, "send", send):
            with self.assertRaises(InterruptedError):
                control.terminate(child.pid, frozen=True)
        deadline = time.monotonic() + 1
        while control.snapshot(child.pid).stopped and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(control.snapshot(child.pid).stopped)

    def test_exit_during_stop_confirmation_is_local_to_that_member(self):
        handle = mock.Mock()
        handle.info = control.ProcessInfo(4242, 20, "original", 0, False)
        with mock.patch.object(control, "_ancestors", return_value=set()), \
             mock.patch.object(control, "Process", return_value=handle), \
             mock.patch.object(control, "snapshot", side_effect=ProcessLookupError()), \
             mock.patch.object(control, "_wait", return_value=True):
            self.assertEqual(control.terminate(4242, frozen=True), "terminated")
        handle.close.assert_called_once()

    def test_registration_requires_native_cancellation_support(self):
        spec = importlib.util.spec_from_file_location("pid_ledger", HELPER.with_name("pid-ledger.py"))
        ledger = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ledger)
        with tempfile.TemporaryDirectory(prefix="octo-admission-") as temporary:
            path = Path(temporary) / "pids"
            argv = ["pid-ledger.py", "register", str(path), str(os.getpid()), "codex", "task"]
            with mock.patch.object(sys, "argv", argv), \
                 mock.patch.object(ledger, "Process", create=True,
                                   side_effect=control.UnsupportedPlatform("unavailable")):
                with self.assertRaises(control.UnsupportedPlatform):
                    ledger.main()
            self.assertFalse(path.exists())

    def test_uncertain_parent_during_admission_is_not_reported_as_terminated(self):
        root, member = mock.Mock(), mock.Mock()
        root.info = control.ProcessInfo(4242, 20, "root", 0, False)
        root.running.side_effect = [True, True, False]
        member.info = control.ProcessInfo(4343, 4242, "member", 0, False)
        with mock.patch.object(control, "_ancestors", return_value=set()), \
             mock.patch.object(control, "Process", side_effect=[root, member]), \
             mock.patch.object(control, "snapshot", return_value=root.info._replace(stopped=True)), \
             mock.patch.object(control, "children", return_value=[4343]), \
             mock.patch.object(control, "_wait", return_value=True):
            with self.assertRaises(control.StaleProcess):
                control.terminate(4242, frozen=True)
        member.send.assert_not_called()
        member.close.assert_called_once()


if __name__ == "__main__":
    unittest.main(verbosity=2)
