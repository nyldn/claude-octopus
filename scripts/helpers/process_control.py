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
import subprocess
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


def _darwin_info(pid, flavor, kind, include_zombies=False):
    info = kind()
    size = ctypes.sizeof(info)
    copied = _darwin().proc_pidinfo(pid, flavor, int(include_zombies), ctypes.byref(info), size)
    if copied != size:
        code = ctypes.get_errno() if copied <= 0 else errno.EIO
        raise OSError(code or errno.ESRCH, "cannot read process identity")
    return info


def _validate_pid(pid):
    # pid_t is signed 32-bit on both supported platforms. Validate before ctypes
    # conversion so an oversized integer cannot be narrowed to another PID.
    if not isinstance(pid, int) or not 1 < pid <= 2**31 - 1:
        raise ValueError("process ID must be an integer between 2 and 2147483647")


def require_native_cancellation_support(probe_runtime=True):
    """Fail unless this interpreter exposes the host's identity-bound signal API."""
    if sys.platform.startswith("linux"):
        if not callable(getattr(os, "pidfd_open", None)) or not callable(
                getattr(signal, "pidfd_send_signal", None)):
            raise UnsupportedPlatform(
                "Linux cancellation requires a CPython build with os.pidfd_open "
                "and signal.pidfd_send_signal"
            )
        if not probe_runtime:
            return
        descriptor = None
        try:
            descriptor = os.pidfd_open(os.getpid())
            signal.pidfd_send_signal(descriptor, 0)
        except OSError as error:
            raise UnsupportedPlatform(
                f"Linux cancellation cannot use pidfd syscalls: {error}"
            ) from error
        finally:
            if descriptor is not None:
                os.close(descriptor)
        return
    if sys.platform == "darwin":
        _darwin()
        return
    raise UnsupportedPlatform("identity-bound cancellation supports Linux and macOS")


def snapshot(pid):
    _validate_pid(pid)
    if sys.platform.startswith("linux"):
        try:
            fields = Path(f"/proc/{pid}/stat").read_bytes().rsplit(b")", 1)[1].split()
        except FileNotFoundError as error:
            raise ProcessLookupError(errno.ESRCH, "process exited") from error
        if fields[0] in (b"Z", b"X"):
            raise ProcessLookupError(errno.ESRCH, "process exited")
        birth, parent, version, stopped = fields[19].decode("ascii"), int(fields[1]), 0, fields[0] in (b"T", b"t")
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


def _linux_proc_records(require_complete=False):
    """Yield stat records, refusing incomplete snapshots when ownership needs them."""
    Path("/proc/self/stat").read_bytes()
    with os.scandir("/proc") as entries:
        for entry in entries:
            if not entry.name.isdigit():
                continue
            try:
                fields = Path(entry.path, "stat").read_bytes().rsplit(b")", 1)[1].split()
            except (FileNotFoundError, ProcessLookupError) as error:
                if require_complete:
                    # It may have forked into a private group after scandir.
                    # With its stat gone, even the former PGID is unknown.
                    raise StaleProcess("process exited during group enumeration") from error
                continue
            yield int(entry.name), fields


def _linux_proc_children(pid):
    """Enumerate direct children from mandatory process stat records."""
    return sorted(child for child, fields in _linux_proc_records() if int(fields[1]) == pid)


def children(pid):
    if sys.platform.startswith("linux"):
        result = set()
        supported = False
        # Children can be forked by any thread, not only the thread-group leader.
        for task in Path(f"/proc/{pid}/task").glob("*"):
            try:
                result.update(int(value) for value in (task / "children").read_text().split())
                supported = True
            except FileNotFoundError:
                continue
        if supported:
            return sorted(result)
        # CONFIG_CHECKPOINT_RESTORE controls the per-thread children file on
        # some kernels. Fall back to the universally supported PPID field and
        # propagate scan errors so cancellation cannot claim false success.
        return _linux_proc_children(pid)
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
        require_native_cancellation_support(probe_runtime=False)
        self.info = snapshot(pid)
        if expected is not None and self.info.token != expected:
            raise StaleProcess("worker identity no longer matches registration")
        if parent is not None and self.info.ppid != parent:
            raise StaleProcess("process no longer belongs to this parent")
        if sys.platform.startswith("linux"):
            self.fd = os.pidfd_open(pid)
            try:
                signal.pidfd_send_signal(self.fd, 0)
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
                try:
                    after = snapshot(self.info.pid)
                except (ProcessLookupError, StaleProcess):
                    raise ProcessLookupError(errno.ESRCH, "original process exited")
                # Deliberately narrow: only a confirmed process-gone signal
                # collapses to "exited" here. A bare OSError from
                # _darwin_info (e.g. EPERM reading a still-live process this
                # caller can no longer introspect) must propagate as itself,
                # not be reinterpreted as "exited" — main()'s own top-level
                # `except (OSError, ...)` already converts an uncaught OSError
                # into the documented "unverified" result (see
                # docs/PLUGIN-COMPATIBILITY.md: "permission failures stop
                # cleanup with an unverified result"). Catching OSError here
                # instead would silently misclassify a live-but-inaccessible
                # process as cleaned up while it keeps running unmanaged —
                # exactly the fail-closed guarantee this module exists for.
                if after.token != self.info.token:
                    raise ProcessLookupError(errno.ESRCH, "original process exited")
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


def _process_groups():
    """Enumerate groups without discarding evidence of a member exit."""
    if sys.platform.startswith("linux"):
        # Retry an incomplete snapshot before exposing any of its candidates.
        # The owner stays stopped; a missing record may have forked a newborn.
        for attempt in range(5):
            try:
                groups = [(pid, int(fields[2])) for pid, fields in
                          _linux_proc_records(require_complete=True)]
                break
            except StaleProcess:
                if attempt == 4:
                    raise
        # Keep zombies: admission must rescan or refuse before teardown.
        yield from groups
        return
    # macOS supplies this numeric PID/group view. Failure is not an empty group.
    result = subprocess.run(["/bin/ps", "-axo", "pid=,pgid=,stat="], check=True,
                            stdout=subprocess.PIPE, timeout=2)
    for row in result.stdout.splitlines():
        pid, pgid, _state = row.split()
        yield int(pid), int(pgid)


def _owned_group_candidates(leaders):
    """Enumerate members only while a bound, stopped private leader is alive."""
    if not leaders:
        return
    active = {}
    for leader in leaders:
        pid = leader.info.pid
        if not leader.running() or os.getpgid(pid) != pid:
            raise StaleProcess("private group leader exited during group admission")
        active[pid] = leader
    for pid, pgid in _process_groups():
        if pgid in active:
            yield pid, active[pgid]


def _zombie_group_identity(pid, pgid):
    """Return a birth identity only for a confirmed zombie in the owned group."""
    try:
        if sys.platform.startswith("linux"):
            fields = Path(f"/proc/{pid}/stat").read_bytes().rsplit(b")", 1)[1].split()
            if fields[0] in (b"Z", b"X") and int(fields[2]) == pgid:
                return pid, fields[19]
        else:
            # XNU only searches its zombie list when proc_pidinfo's arg is 1.
            before = _darwin_info(pid, 17, _UniqueInfo, include_zombies=True)
            short = _darwin_info(pid, 13, _ShortInfo, include_zombies=True)
            after = _darwin_info(pid, 17, _UniqueInfo, include_zombies=True)
            if before.unique == after.unique and short.status == 5 and short.pgid == pgid:
                return pid, after.unique
    except (FileNotFoundError, ProcessLookupError):
        pass
    return None


def _admit_owned_group_members(leaders, handles, seen, excluded, exited=None):
    """Return newly bound members and whether exits require another scan."""
    admitted = []
    rescan = False
    if exited is None:
        exited = set()
    for child, leader in _owned_group_candidates(leaders):
        if child in seen or child in excluded:
            continue
        if len(handles) >= 4096:
            raise OSError(errno.EOVERFLOW, "process tree exceeds cancellation limit")
        try:
            member = Process(child)
        except (ProcessLookupError, StaleProcess):
            # A forked child keeps this PGID. Rescan before leader teardown,
            # retaining already stopped processes instead of restarting them.
            zombie = _zombie_group_identity(child, leader.info.pid)
            if zombie is None or zombie not in exited:
                rescan = True
            if zombie is not None:
                exited.add(zombie)
            continue
        handles.append(member)
        try:
            same_group = os.getpgid(child) == leader.info.pid
        except ProcessLookupError as error:
            raise StaleProcess("group member exited before membership verification") from error
        if not member.running():
            raise StaleProcess("group member exited before freezing")
        if not same_group or not leader.running():
            raise StaleProcess("private group changed during member admission")
        seen.add(child)
        admitted.append((member, True))
    return admitted, rescan


def terminate(pid, grace=1, frozen=False, descendants=False, expected=None, owned_groups=False):
    """Cancel bound processes, including still-owned private groups when requested."""
    _validate_pid(pid)
    excluded = _ancestors()
    if pid in excluded and not descendants:
        raise ValueError("refusing to terminate self, an ancestor, or an invalid PID")
    handles, stopped = [], []
    try:
        try:
            root = Process(pid, expected=expected)
        except ProcessLookupError:
            return "already-exited"
        handles.append(root)
        pending = [None, (root, not descendants)] if owned_groups else [(root, not descendants)]
        group_leaders = []
        group_rescans = 0
        exited = set()
        seen = {pid}
        while pending:
            entry = pending.pop()
            if entry is None:
                admitted, rescan = _admit_owned_group_members(group_leaders, handles, seen, excluded, exited)
                if rescan:
                    group_rescans += 1
                    if group_rescans >= 5:
                        raise StaleProcess("owned group kept changing during admission")
                # Members can fork before STOP. Rescan after freezing every new
                # member, until the still-owned groups contain no unseen process.
                if admitted or rescan:
                    pending.extend([None, *admitted])
                continue
            handle, freeze = entry
            if freeze:
                # Record responsibility before delivery: a signal handler can
                # interrupt Python immediately after the native STOP succeeds.
                if not handle.info.stopped:
                    stopped.append(handle)
                if not handle.send(signal.SIGSTOP):
                    if owned_groups:
                        raise StaleProcess("descendant exited before freezing; cleanup incomplete")
                    continue
                # STOP delivery is asynchronous. Enumerate only once it cannot fork.
                # XNU queues psignal asynchronously even when the identity-
                # bound API succeeds. Under scheduler pressure a queued stop
                # can remain unobserved; retry against the same verified
                # process instance while retaining the bounded fail-closed
                # deadline.
                started = time.monotonic()
                deadline = started + 1
                retry_at = started + 0.25
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
                    now = time.monotonic()
                    if now >= deadline:
                        raise TimeoutError("worker did not stop before enumeration")
                    if now >= retry_at:
                        if not handle.send(signal.SIGSTOP):
                            disappeared = True
                            break
                        retry_at = now + 0.25
                    time.sleep(0.01)
                if disappeared:
                    if owned_groups:
                        raise StaleProcess("descendant exited during freezing; cleanup incomplete")
                    continue
            if not handle.running():
                if owned_groups:
                    raise StaleProcess("descendant exited before enumeration; cleanup incomplete")
                continue
            if owned_groups and freeze and os.getpgid(handle.info.pid) == handle.info.pid:
                group_leaders.append(handle)
            for child in children(handle.info.pid):
                if child in seen or child in excluded:
                    continue
                seen.add(child)
                if len(handles) >= 4096:
                    raise OSError(errno.EOVERFLOW, "process tree exceeds cancellation limit")
                try:
                    member = Process(child, parent=handle.info.pid)
                except (ProcessLookupError, StaleProcess) as error:
                    if owned_groups:
                        # An unbound private leader may leave reparented helpers.
                        # Keep its supervisor alive to perform its own cleanup.
                        raise StaleProcess("descendant exited during admission; cleanup incomplete") from error
                    continue
                if not handle.running():
                    member.close()
                    # The numeric PPID alone cannot prove which parent instance
                    # admitted this child. Do not signal it or claim full cleanup.
                    raise StaleProcess("parent exited during descendant admission; cleanup incomplete")
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


def handoff_to_children(pid, expected=None):
    """Ask bound supervision children to clean up, without killing their handlers."""
    if pid == os.getpid():
        raise ValueError("refusing to freeze self for supervisor handoff")
    excluded = _ancestors()
    with Process(pid, expected=expected) as root:
        handles = []
        stopped = False
        try:
            if not root.info.stopped:
                # Freeze only the caller, not the supervision children whose
                # TERM handlers own private groups, including orphaned helpers.
                stopped = True
                if not root.send(signal.SIGSTOP):
                    raise StaleProcess("caller exited before supervisor handoff")
                deadline = time.monotonic() + 1
                while not snapshot(pid).stopped:
                    if time.monotonic() >= deadline:
                        raise TimeoutError("caller did not stop before supervisor handoff")
                    time.sleep(0.01)
            for child in children(pid):
                if child in excluded:
                    continue
                if len(handles) >= 4096:
                    raise OSError(errno.EOVERFLOW, "supervision children exceed cancellation limit")
                try:
                    handle = Process(child, parent=pid)
                except ProcessLookupError:
                    continue
                handles.append(handle)
            if not root.running() or not handles:
                raise StaleProcess("no live supervision child could be bound")
            for handle in handles:
                handle.send(signal.SIGTERM)
            # Never escalate to KILL: the child may still own group cleanup.
            return "terminated" if _wait(handles, 5) else "survived"
        finally:
            previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
            try:
                if stopped:
                    root.send(signal.SIGCONT)
            finally:
                try:
                    for handle in handles:
                        handle.close()
                finally:
                    signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)


def main():
    """Expose native cleanup and report incomplete ownership verification."""
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
    parser.add_argument("--owned-groups", action="store_true")
    parser.add_argument("--supervisor-handoff", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.grace <= 60:
        parser.error("grace must be between 0 and 60 seconds")
    try:
        if args.supervisor_handoff:
            if args.frozen or args.descendants or args.owned_groups:
                parser.error("supervisor handoff cannot be combined with tree teardown")
            result = handoff_to_children(args.pid, args.identity)
        else:
            result = terminate(args.pid, args.grace, args.frozen, args.descendants, args.identity, args.owned_groups)
        print(result)
        return int(result == "survived")
    except (OSError, StaleProcess, UnsupportedPlatform, ValueError, subprocess.SubprocessError) as error:
        print(f"Process cleanup refused: {error}", file=sys.stderr)
        print("unverified")
        return 1


if __name__ == "__main__":
    sys.exit(main())
