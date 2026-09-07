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

    def test_snapshot_is_stable_and_has_real_parent(self):
        child = self.child()
        first = control.snapshot(child.pid)
        second = control.snapshot(child.pid)
        self.assertEqual(first.token, second.token)
        self.assertEqual(first.ppid, os.getpid())

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
