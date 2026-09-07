#!/usr/bin/env python3
"""Identity-bound cancellation for Linux and macOS, without numeric kill fallbacks."""

import argparse
from collections import namedtuple
import ctypes
import errno
from functools import lru_cache
import hashlib
import os
from pathlib import Path
import select
import signal
import sys
import time

ProcessInfo = namedtuple("ProcessInfo", "pid ppid token version stopped")


class StaleProcess(Exception):
    """A registration or parent relationship no longer identifies this process."""


class UnsupportedPlatform(Exception):
    """The host cannot bind signal delivery to a process instance."""


class _UniqueInfo(ctypes.Structure):
    # XNU proc_info_private.h, PROC_PIDUNIQIDENTIFIERINFO (17), 56-byte API.
    _fields_ = [("uuid", ctypes.c_uint8 * 16), ("unique", ctypes.c_uint64),
                ("parent_unique", ctypes.c_uint64), ("version", ctypes.c_uint32),
                ("parent_version", ctypes.c_uint32), ("reserved", ctypes.c_uint64 * 2)]


class _ShortInfo(ctypes.Structure):
    # SDK sys/proc_info.h, PROC_PIDT_SHORTBSDINFO (13).
    _fields_ = [("pid", ctypes.c_uint32), ("ppid", ctypes.c_uint32),
                ("pgid", ctypes.c_uint32), ("status", ctypes.c_uint32),
                ("comm", ctypes.c_char * 16), ("rest", ctypes.c_uint32 * 8)]


@lru_cache(maxsize=1)
def _darwin():
    lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                ctypes.c_void_p, ctypes.c_int]
    lib.proc_pidinfo.restype = ctypes.c_int
    lib.proc_listchildpids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
    lib.proc_listchildpids.restype = ctypes.c_int
    try:
        lib.proc_signal_with_audittoken.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.proc_signal_with_audittoken.restype = ctypes.c_int
    except AttributeError as error:
        raise UnsupportedPlatform("macOS lacks proc_signal_with_audittoken") from error
    return lib


@lru_cache(maxsize=1)
def _boot_id():
    if sys.platform.startswith("linux"):
        return Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    lib = ctypes.CDLL(None, use_errno=True)
    lib.sysctlbyname.argtypes = [ctypes.c_char_p, ctypes.c_void_p,
                                ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p,
                                ctypes.c_size_t]
    lib.sysctlbyname.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(128)
    size = ctypes.c_size_t(len(buffer))
    if lib.sysctlbyname(b"kern.bootsessionuuid", buffer, ctypes.byref(size), None, 0):
        raise OSError(ctypes.get_errno(), "cannot read boot identity")
    return buffer.value.decode("ascii")


def _darwin_info(pid, flavor, kind):
    info = kind()
    size = ctypes.sizeof(info)
    copied = _darwin().proc_pidinfo(pid, flavor, 0, ctypes.byref(info), size)
    if copied != size:
        code = ctypes.get_errno() if copied <= 0 else errno.EIO
        raise OSError(code or errno.ESRCH, "cannot read process identity")
    return info


def snapshot(pid):
    if pid <= 1:
        raise ValueError("process ID must be greater than one")
    if sys.platform.startswith("linux"):
        try:
            fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        except FileNotFoundError as error:
            raise ProcessLookupError(errno.ESRCH, "process exited") from error
        if fields[0] in ("Z", "X"):
            raise ProcessLookupError(errno.ESRCH, "process exited")
        birth, parent, version, stopped = fields[19], int(fields[1]), 0, fields[0] in ("T", "t")
    elif sys.platform == "darwin":
        before = _darwin_info(pid, 17, _UniqueInfo)
        short = _darwin_info(pid, 13, _ShortInfo)
        after = _darwin_info(pid, 17, _UniqueInfo)
        if before.unique != after.unique:
            raise StaleProcess("process changed while reading its identity")
        if short.status == 5:  # SZOMB
            raise ProcessLookupError(errno.ESRCH, "process exited")
        birth, parent, version, stopped = after.unique, short.ppid, after.version, short.status == 4
    else:
        raise UnsupportedPlatform("identity-bound cancellation supports Linux and macOS")
    token = hashlib.sha256(f"{_boot_id()}:{pid}:{birth}".encode()).hexdigest()
    return ProcessInfo(pid, parent, token, version, stopped)


def children(pid):
    if sys.platform.startswith("linux"):
        result = set()
        # Children can be forked by any thread, not only the thread-group leader.
        for task in Path(f"/proc/{pid}/task").glob("*"):
            try:
                result.update(int(value) for value in (task / "children").read_text().split())
            except FileNotFoundError:
                continue
        return sorted(result)
    lib = _darwin()
    capacity = max(16, lib.proc_listchildpids(pid, None, 0) + 16)
    for _ in range(4):
        buffer = (ctypes.c_int * capacity)()
        count = lib.proc_listchildpids(pid, buffer, ctypes.sizeof(buffer))
        if count < 0:
            raise OSError(ctypes.get_errno(), "cannot enumerate children")
        if count < capacity:
            return [child for child in buffer[:count] if child > 1]
        capacity *= 2
    raise OSError(errno.EOVERFLOW, "child list kept growing")


class Process:
    def __init__(self, pid, expected=None, parent=None):
        self.fd = None
        self.info = snapshot(pid)
        if expected is not None and self.info.token != expected:
            raise StaleProcess("worker identity no longer matches registration")
        if parent is not None and self.info.ppid != parent:
            raise StaleProcess("process no longer belongs to this parent")
        if sys.platform.startswith("linux"):
            if not callable(getattr(os, "pidfd_open", None)) or not callable(
                    getattr(signal, "pidfd_send_signal", None)):
                raise UnsupportedPlatform("Linux cancellation requires Python 3.9+ with pidfd support")
            self.fd = os.pidfd_open(pid)
            try:
                after = snapshot(pid)
                if after.token != self.info.token or (parent is not None and after.ppid != parent):
                    raise StaleProcess("process changed while acquiring its handle")
                if not self.running():
                    raise ProcessLookupError(errno.ESRCH, "process exited")
            except BaseException:
                self.close()
                raise

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def running(self):
        if self.fd is not None:
            poll = select.poll()
            poll.register(self.fd, select.POLLIN)
            return not poll.poll(0)
        try:
            return snapshot(self.info.pid).token == self.info.token
        except (ProcessLookupError, StaleProcess):
            return False

    def _send_native(self, signum):
        if self.fd is not None:
            signal.pidfd_send_signal(self.fd, signum)
            return
        # XNU checks PID + version and retains the matching process reference
        # through signal delivery. The API returns an errno value, not -1.
        for _ in range(3):
            current = snapshot(self.info.pid)
            if current.token != self.info.token:
                raise ProcessLookupError(errno.ESRCH, "original process exited")
            audit = (ctypes.c_uint32 * 8)()
            audit[5], audit[7] = self.info.pid, current.version
            code = _darwin().proc_signal_with_audittoken(audit, signum)
            if code == 0:
                return
            if code != errno.ESRCH:
                raise OSError(code, "identity-bound signal rejected")
            # exec changes the version but not the birth identity. Refresh only
            # that same process, never a replacement that reused its PID.
        raise ProcessLookupError(errno.ESRCH, "process exited or kept executing")

    def send(self, signum):
        try:
            self._send_native(signum)
            return True
        except (ProcessLookupError, StaleProcess):
            return False


def _ancestors():
    result, pid = set(), os.getpid()
    while pid > 1 and pid not in result:
        result.add(pid)
        pid = snapshot(pid).ppid
    return result


def _wait(handles, seconds):
    deadline = time.monotonic() + seconds
    while any(handle.running() for handle in handles):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(0.02, remaining))
    return True


def terminate(pid, grace=1, frozen=False, descendants=False, expected=None):
    excluded = _ancestors()
    if pid <= 1 or (pid in excluded and not descendants):
        raise ValueError("refusing to terminate self, an ancestor, or an invalid PID")
    handles, stopped = [], []
    try:
        try:
            root = Process(pid, expected=expected)
        except ProcessLookupError:
            return "already-exited"
        handles.append(root)
        pending = [(root, not descendants)]
        seen = {pid}
        while pending:
            handle, freeze = pending.pop()
            if freeze:
                # Record responsibility before delivery: a signal handler can
                # interrupt Python immediately after the native STOP succeeds.
                if not handle.info.stopped:
                    stopped.append(handle)
                if not handle.send(signal.SIGSTOP):
                    continue
                # STOP delivery is asynchronous. Enumerate only once it cannot fork.
                deadline = time.monotonic() + 1
                disappeared = False
                while handle.running():
                    try:
                        current = snapshot(handle.info.pid)
                    except (ProcessLookupError, StaleProcess):
                        disappeared = True
                        break
                    if current.token != handle.info.token:
                        break
                    if current.stopped:
                        break
                    if time.monotonic() >= deadline:
                        raise TimeoutError("worker did not stop before enumeration")
                    time.sleep(0.01)
                if disappeared:
                    continue
            if not handle.running():
                continue
            for child in children(handle.info.pid):
                if child in seen or child in excluded:
                    continue
                seen.add(child)
                if len(handles) >= 4096:
                    raise OSError(errno.EOVERFLOW, "process tree exceeds cancellation limit")
                try:
                    member = Process(child, parent=handle.info.pid)
                except (ProcessLookupError, StaleProcess):
                    continue
                if not handle.running():
                    member.close()
                    continue
                handles.append(member)
                pending.append((member, True))
        targets = list(reversed(handles[1:] if descendants else handles))
        if not frozen:
            for handle in targets:
                handle.send(signal.SIGTERM)
                if handle in stopped:
                    handle.send(signal.SIGCONT)
            if _wait(targets, grace):
                return "terminated"
        for handle in targets:
            handle.send(signal.SIGKILL)
        return "terminated" if _wait(targets, 5) else "survived"
    finally:
        # Partial enumeration, permission errors and interruption must not strand
        # a process we stopped. Resume only that same bound process instance.
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
        try:
            for handle in reversed(stopped):
                try:
                    handle.send(signal.SIGCONT)
                except OSError:
                    pass
        finally:
            try:
                for handle in handles:
                    handle.close()
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)


def main():
    def interrupted(signum, _frame):
        raise InterruptedError(f"cleanup interrupted by signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pid", type=int)
    parser.add_argument("--identity")
    parser.add_argument("--grace", type=float, default=1)
    parser.add_argument("--frozen", action="store_true")
    parser.add_argument("--descendants", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.grace <= 60:
        parser.error("grace must be between 0 and 60 seconds")
    try:
        result = terminate(args.pid, args.grace, args.frozen, args.descendants, args.identity)
        print(result)
        return int(result == "survived")
    except (OSError, StaleProcess, UnsupportedPlatform, ValueError) as error:
        print(f"Process cleanup refused: {error}", file=sys.stderr)
        print("unverified")
        return 1


if __name__ == "__main__":
    sys.exit(main())
