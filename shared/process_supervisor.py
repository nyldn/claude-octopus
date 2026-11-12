"""Bounded subprocess execution shared by provider and preview helpers."""

from __future__ import annotations

import os
import selectors
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Mapping, Optional, Sequence, Tuple, Union

Command = Union[str, Sequence[str]]


class OutputLimitExceeded(RuntimeError):
    """The child emitted more output than the caller allows."""


class IncompleteOutput(RuntimeError):
    """The child exited, but a descendant kept the output stream open."""


def _process_group_exists(process_group: Optional[int]) -> bool:
    if os.name != "posix" or process_group is None:
        return False
    try:
        os.killpg(process_group, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _terminate_process_tree(
    process: subprocess.Popen, process_group: Optional[int], grace: float
) -> None:
    if os.name == "posix" and process_group is not None:
        try:
            os.killpg(process_group, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            try:
                os.killpg(process_group, 0)
            except ProcessLookupError:
                break
            except PermissionError:
                pass
            time.sleep(min(0.02, max(0.0, deadline - time.monotonic())))
        try:
            os.killpg(process_group, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    elif process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(
                    ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            if process.poll() is None:
                process.kill()
    try:
        process.wait(timeout=max(0.1, grace))
    except subprocess.TimeoutExpired:
        if process.poll() is None:
            process.kill()
        process.wait()


def _append_output(
    captured: bytearray, chunk: bytes, output_limit: int, strict_output: bool
) -> bool:
    captured.extend(chunk)
    overflow = len(captured) - output_limit
    if overflow <= 0:
        return False
    if strict_output:
        del captured[output_limit:]
        return True
    del captured[:overflow]
    return False


def _decode(captured: bytearray, strict_output: bool) -> str:
    return bytes(captured).decode(
        "utf-8", errors="strict" if strict_output else "replace"
    )


class _StreamCapture:
    """Share one byte budget while keeping opt-in stderr separate."""

    def __init__(self, stdout, stderr, limit, strict):
        self.stdout, self.stderr = stdout, stderr
        self.limit, self.strict = limit, strict
        self.order = bytearray()

    def append(self, target, chunk):
        if self.stderr is None:
            return _append_output(target, chunk, self.limit, self.strict)
        room = max(0, self.limit - len(self.stdout) - len(self.stderr))
        if self.strict:
            target.extend(chunk[:room])
            return len(chunk) > room
        target.extend(chunk)
        # One tag per retained byte bounds bookkeeping even for alternating
        # single-byte writes. Tags let each stream lose its oldest bytes.
        tag = b"\1" if target is self.stderr else b"\0"
        self.order.extend(tag * len(chunk))
        overflow = len(self.order) - self.limit
        if overflow > 0:
            errors = self.order[:overflow].count(b"\1")
            del self.stderr[:errors]
            del self.stdout[:overflow - errors]
            del self.order[:overflow]
        return False


def _collect_posix_process(
    process: subprocess.Popen,
    command: Command,
    timeout: float,
    output_limit: int,
    kill_grace: float,
    strict_output: bool,
    captured: bytearray,
    stderr_captured: Optional[bytearray] = None,
) -> Tuple[int, str]:
    """Collect bounded POSIX output into the caller's buffer and reap the group."""
    deadline = time.monotonic() + timeout
    drain_deadline = None
    timed_out = False
    overflowed = False
    incomplete = False
    stream = process.stdout
    if stream is None:
        raise RuntimeError("supervised process has no output pipe")
    capture = _StreamCapture(captured, stderr_captured, output_limit, strict_output)
    streams = [(stream, captured)]
    if stderr_captured is not None:
        if process.stderr is None:
            raise RuntimeError("supervised process has no stderr pipe")
        streams.append((process.stderr, stderr_captured))
    selector = selectors.DefaultSelector()
    try:
        for pipe, target in streams:
            os.set_blocking(pipe.fileno(), False)
            selector.register(pipe, selectors.EVENT_READ, target)
        while True:
            now = time.monotonic()
            if now >= deadline:
                timed_out = process.poll() is None
                incomplete = process.poll() is not None and bool(selector.get_map())
                break
            if process.poll() is None:
                pass
            else:
                if drain_deadline is None:
                    drain_deadline = min(deadline, now + kill_grace)
                if not selector.get_map():
                    break
                if now >= drain_deadline:
                    incomplete = True
                    break
            wait_deadline = deadline
            if drain_deadline is not None:
                wait_deadline = min(wait_deadline, drain_deadline)
            wait = min(0.02, max(0.0, wait_deadline - now))
            for key, _ in selector.select(timeout=wait):
                try:
                    chunk = os.read(key.fd, 8192)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if capture.append(key.data, chunk):
                    overflowed = True
                    break
            if overflowed:
                break
    finally:
        selector.close()
        for pipe, _ in streams:
            pipe.close()
        if process.poll() is None or _process_group_exists(process.pid):
            _terminate_process_tree(process, process.pid, kill_grace)
    output = _decode(captured, strict_output)
    if overflowed:
        raise OutputLimitExceeded(f"child output exceeded {output_limit} bytes")
    if timed_out:
        raise subprocess.TimeoutExpired(command, timeout, output=output)
    if incomplete and strict_output:
        raise IncompleteOutput("child output did not reach EOF before its deadline")
    return process.returncode, output


def run_bounded_process(
    command: Command,
    cwd: Path,
    timeout: float,
    *,
    shell: bool,
    output_limit: int,
    env: Optional[Mapping[str, str]] = None,
    kill_grace: float = 0.5,
    strict_output: bool = False,
    _stderr_capture: Optional[bytearray] = None,
) -> Tuple[int, str]:
    """Run one owned process group; collection exceptions retain bounded output.

    _stderr_capture is reserved for run_bounded_process_separate.
    """
    if output_limit < 1:
        raise ValueError("output_limit must be positive")
    if _stderr_capture is not None and _stderr_capture:
        raise ValueError("internal stderr capture must start empty")
    popen_options = {
        "cwd": str(cwd),
        "shell": shell,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE if _stderr_capture is not None else subprocess.STDOUT,
        "text": False,
        "bufsize": 0,
        "env": dict(env) if env is not None else None,
    }
    if os.name == "posix":
        popen_options["start_new_session"] = True
    elif os.name == "nt":
        popen_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP

    captured = bytearray()
    process = subprocess.Popen(command, **popen_options)
    if os.name == "posix":
        try:
            collection = {} if _stderr_capture is None else {"stderr_captured": _stderr_capture}
            return _collect_posix_process(
                process,
                command,
                timeout,
                output_limit,
                kill_grace,
                strict_output,
                captured,
                **collection,
            )
        except BaseException as error:
            if not isinstance(error, Exception) and (
                process.poll() is None or _process_group_exists(process.pid)
            ):
                _terminate_process_tree(process, process.pid, 0)
            error.output = _decode(captured, False)
            if _stderr_capture is not None:
                error.stderr = _decode(_stderr_capture, False)
            raise

    process_group = None
    capture_lock = threading.Lock()
    overflowed = threading.Event()

    capture = _StreamCapture(captured, _stderr_capture, output_limit, strict_output)

    def drain_output(stream, target) -> None:
        if stream is None:
            return
        try:
            while True:
                chunk = stream.read(8192)
                if not chunk:
                    return
                with capture_lock:
                    if capture.append(target, chunk):
                        overflowed.set()
                        return
        except (OSError, ValueError):
            return

    streams = [(process.stdout, captured, "output")]
    if _stderr_capture is not None:
        streams.append((process.stderr, _stderr_capture, "stderr"))
    readers = [threading.Thread(target=drain_output, args=(stream, target),
                               name="octopus-command-" + name, daemon=True)
               for stream, target, name in streams]
    for reader in readers:
        reader.start()
    timed_out = False
    try:
        deadline = time.monotonic() + timeout
        while process.poll() is None and not overflowed.is_set():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            time.sleep(min(0.02, remaining))
        if timed_out or overflowed.is_set():
            _terminate_process_tree(process, process_group, kill_grace)
    except BaseException as error:
        _terminate_process_tree(process, process_group, kill_grace)
        with capture_lock:
            error.output = _decode(captured, False)
            if _stderr_capture is not None:
                error.stderr = _decode(_stderr_capture, False)
        raise

    for reader in readers:
        remaining = max(0.0, deadline - time.monotonic())
        reader.join(timeout=min(kill_grace, remaining))
    incomplete = any(reader.is_alive() for reader in readers)
    if incomplete:
        _terminate_process_tree(process, process_group, kill_grace)
        for stream, _, _ in streams:
            if stream is not None:
                stream.close()
        for reader in readers:
            reader.join(timeout=kill_grace)
    elif _process_group_exists(process_group):
        _terminate_process_tree(process, process_group, kill_grace)
    for stream, _, _ in streams:
        if stream is not None:
            stream.close()

    try:
        with capture_lock:
            output = _decode(captured, strict_output)
        if overflowed.is_set():
            raise OutputLimitExceeded(f"child output exceeded {output_limit} bytes")
        if timed_out:
            raise subprocess.TimeoutExpired(command, timeout, output=output)
        if incomplete and strict_output:
            raise IncompleteOutput("child output did not reach EOF before its deadline")
        return process.returncode, output
    except BaseException as error:
        with capture_lock:
            error.output = _decode(captured, False)
            if _stderr_capture is not None:
                error.stderr = _decode(_stderr_capture, False)
        raise


def run_bounded_process_separate(
    command: Command,
    cwd: Path,
    timeout: float,
    *,
    shell: bool,
    output_limit: int,
    env: Optional[Mapping[str, str]] = None,
    kill_grace: float = 0.5,
    strict_output: bool = False,
) -> Tuple[int, str, str]:
    """Capture separate streams under the same combined byte and process limits."""
    errors = bytearray()
    output = ""
    try:
        code, output = run_bounded_process(
            command, cwd, timeout, shell=shell, output_limit=output_limit,
            env=env, kill_grace=kill_grace, strict_output=strict_output,
            _stderr_capture=errors,
        )
        return code, output, _decode(errors, strict_output)
    except BaseException as error:
        if not hasattr(error, "output"):
            error.output = output
        error.stderr = _decode(errors, False)
        raise
