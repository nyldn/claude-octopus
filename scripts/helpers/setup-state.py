#!/usr/bin/env python3
"""Strict persistence for resumable setup and legacy user configuration."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import math
import os
import re
import stat
import sys
import time
import uuid
from pathlib import Path

MAX_INPUT = 1024 * 1024
FLOW_VERSION = 1
KEY_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
HOSTS = {"claude", "codex"}
FLOWS = {"host-only", "one-provider", "advanced"}
STAGES = {"selected", "awaiting-human", "rechecked", "verified"}
MAX_NESTING = 64
MAX_VALUE_NODES = 100000
TRANSITIONS = {
    None: {"selected"},
    "selected": {"selected", "awaiting-human", "rechecked"},
    "awaiting-human": {"awaiting-human", "rechecked"},
    "rechecked": {"rechecked", "verified"},
    "verified": {"rechecked", "verified"},
}


class SetupError(Exception):
    exit_code = 2


class UnsafeStorage(SetupError):
    exit_code = 3


class RevisionConflict(SetupError):
    exit_code = 4


class LockTimeout(SetupError):
    exit_code = 5


def pairs_no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise SetupError("duplicate JSON key")
        result[key] = value
    return result


def reject_constant(_value):
    raise SetupError("non-finite JSON number")


def parse_finite_float(value):
    parsed = float(value)
    if not math.isfinite(parsed):
        raise SetupError("non-finite JSON number")
    return parsed


def validate_json_string(value, field):
    try:
        value.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise SetupError(field + " must contain valid Unicode scalar values") from exc
    if "\0" in value:
        raise SetupError(field + " contains a NUL byte")


def validate_json_strings(value):
    stack = [value]
    while stack:
        item = stack.pop()
        if isinstance(item, str):
            validate_json_string(item, "JSON string")
        elif isinstance(item, list):
            stack.extend(item)
        elif isinstance(item, dict):
            for key, child in item.items():
                validate_json_string(key, "JSON object key")
                stack.append(child)


def read_request(path):
    if path == "-":
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
    else:
        with open(path, "rb") as handle:
            raw = handle.read(MAX_INPUT + 1)
    if len(raw) > MAX_INPUT:
        raise SetupError("input exceeds 1 MiB")
    try:
        text = raw.decode("utf-8", errors="strict")
        value = json.loads(
            text,
            object_pairs_hook=pairs_no_duplicates,
            parse_constant=reject_constant,
            parse_float=parse_finite_float,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, SetupError, ValueError, RecursionError) as exc:
        raise SetupError("input is not one UTF-8 JSON value") from exc
    if not isinstance(value, dict):
        raise SetupError("top-level JSON value must be an object")
    validate_json_strings(value)
    return value


def exact_keys(value, required, optional=()):
    unknown = set(value) - set(required) - set(optional)
    missing = set(required) - set(value)
    if unknown:
        raise SetupError("unknown field: " + sorted(unknown)[0])
    if missing:
        raise SetupError("missing field: " + sorted(missing)[0])


def physical_plugin_root(value):
    if not isinstance(value, str) or not os.path.isabs(value):
        raise SetupError("plugin_root must be an absolute path")
    if "\0" in value:
        raise SetupError("plugin_root contains a NUL byte")
    try:
        value.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise SetupError("plugin_root must be valid UTF-8") from exc
    try:
        root = Path(value).resolve(strict=True)
    except (OSError, ValueError) as exc:
        raise SetupError("plugin_root is not accessible") from exc
    if not root.is_dir():
        raise SetupError("plugin_root must be a directory")
    return str(root)


def validate_common(request, action):
    if type(request.get("schema_version")) is not int or request["schema_version"] != 1:
        raise SetupError("schema_version must be 1")
    if request.get("action") != action:
        raise SetupError("action does not match operation")
    if not isinstance(request.get("host"), str) or request["host"] not in HOSTS:
        raise SetupError("host must be claude or codex")
    request["plugin_root"] = physical_plugin_root(request.get("plugin_root"))


def validate_verification(value, stage):
    if stage in {"selected", "awaiting-human"}:
        if value is not None:
            raise SetupError("verification must be null before recheck")
        return None
    if not isinstance(value, dict):
        raise SetupError("verification is required after recheck")
    exact_keys(value, {"result", "reason_code", "checked_at"})
    if not isinstance(value["result"], str) or value["result"] not in {"passed", "failed"}:
        raise SetupError("verification.result is invalid")
    for field in ("reason_code", "checked_at"):
        if not isinstance(value[field], str) or len(value[field]) > 256:
            raise SetupError("verification." + field + " is invalid")
    if stage == "verified" and value["result"] != "passed":
        raise SetupError("verified stage requires passed verification")
    return dict(value)


def validate_selection(flow, provider):
    if not isinstance(flow, str) or flow not in FLOWS:
        raise SetupError("flow is invalid")
    if (
        not isinstance(provider, str)
        or len(provider) > 128
        or not re.fullmatch(r"[A-Za-z0-9._-]*", provider)
    ):
        raise SetupError("provider is invalid")
    if flow == "one-provider" and not provider:
        raise SetupError("one-provider flow requires provider")
    if flow == "host-only" and provider:
        raise SetupError("host-only flow cannot name a provider")


def validate_record(request):
    exact_keys(
        request,
        {
            "schema_version", "action", "host", "plugin_root",
            "expected_revision", "flow", "provider", "stage", "verification",
        },
    )
    validate_common(request, "record")
    if type(request["expected_revision"]) is not int or request["expected_revision"] < 0:
        raise SetupError("expected_revision must be a nonnegative integer")
    validate_selection(request["flow"], request["provider"])
    if not isinstance(request["stage"], str) or request["stage"] not in STAGES:
        raise SetupError("stage is invalid")
    request["verification"] = validate_verification(request["verification"], request["stage"])


def validate_request(request):
    action = request.get("action")
    if action == "read":
        exact_keys(request, {"schema_version", "action", "host", "plugin_root"})
        validate_common(request, "read")
    elif action == "record":
        validate_record(request)
    elif action == "complete":
        exact_keys(
            request,
            {"schema_version", "action", "host", "plugin_root", "expected_revision"},
        )
        validate_common(request, "complete")
        if type(request["expected_revision"]) is not int or request["expected_revision"] < 1:
            raise SetupError("expected_revision must be a positive integer")
    elif action == "legacy-update":
        exact_keys(request, {"schema_version", "action", "key", "value"})
        if type(request.get("schema_version")) is not int or request["schema_version"] != 1:
            raise SetupError("schema_version must be 1")
        if not isinstance(request.get("key"), str) or not KEY_RE.fullmatch(request["key"]):
            raise SetupError("legacy key is invalid")
        ensure_finite(request["value"])
    elif action == "legacy-reset":
        exact_keys(request, {"schema_version", "action"})
        if type(request.get("schema_version")) is not int or request["schema_version"] != 1:
            raise SetupError("schema_version must be 1")
    else:
        raise SetupError("action is invalid")
    return request


def ensure_finite(value):
    stack = [(value, 0)]
    nodes = 0
    while stack:
        item, depth = stack.pop()
        nodes += 1
        if nodes > MAX_VALUE_NODES:
            raise SetupError("legacy value is too complex")
        if isinstance(item, str):
            validate_json_string(item, "JSON string")
        elif isinstance(item, float) and not math.isfinite(item):
            raise SetupError("legacy value contains a non-finite number")
        if isinstance(item, (list, dict)):
            if depth >= MAX_NESTING:
                raise SetupError("legacy value exceeds maximum nesting")
            if isinstance(item, dict):
                for key in item:
                    validate_json_string(key, "JSON object key")
            children = item if isinstance(item, list) else item.values()
            stack.extend((child, depth + 1) for child in children)


def resolved_home():
    raw = os.environ.get("HOME", "")
    if not raw:
        raise UnsafeStorage("HOME is unavailable")
    try:
        home = Path(raw).resolve(strict=True)
    except OSError as exc:
        raise UnsafeStorage("HOME is inaccessible") from exc
    if not home.is_dir():
        raise UnsafeStorage("HOME is not a directory")
    return home


def directory_open_flags():
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_CLOEXEC", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    return flags


def validate_directory(fd, secure_permissions):
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise UnsafeStorage("state directory is unsafe or has the wrong owner")
    if secure_permissions:
        try:
            os.fchmod(fd, 0o700)
        except OSError as exc:
            raise UnsafeStorage("state directory permissions cannot be secured") from exc


def open_child_directory(parent_fd, name, create):
    for _attempt in range(3):
        try:
            fd = os.open(name, directory_open_flags(), dir_fd=parent_fd)
        except FileNotFoundError:
            if not create:
                return None
            try:
                os.mkdir(name, 0o700, dir_fd=parent_fd)
            except FileExistsError:
                continue
            except OSError as exc:
                raise UnsafeStorage("state directory cannot be created") from exc
            continue
        except OSError as exc:
            raise UnsafeStorage("state directory is inaccessible") from exc
        try:
            validate_directory(fd, create)
            return fd
        except Exception:
            os.close(fd)
            raise
    raise UnsafeStorage("state directory changed during initialization")


def open_state_directory(create, setup):
    home = resolved_home()
    try:
        home_fd = os.open(home, directory_open_flags())
    except OSError as exc:
        raise UnsafeStorage("HOME cannot be opened safely") from exc
    try:
        validate_directory(home_fd, False)
        base_fd = open_child_directory(home_fd, ".claude-octopus", create)
    finally:
        os.close(home_fd)
    if base_fd is None:
        return None
    if not setup:
        return base_fd
    try:
        setup_fd = open_child_directory(base_fd, "setup", create)
    finally:
        os.close(base_fd)
    return setup_fd


def safe_existing_file(dir_fd, name):
    flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(name, flags, dir_fd=dir_fd)
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise UnsafeStorage("state file is unsafe or unreadable") from exc
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        os.close(fd)
        raise UnsafeStorage("state file is not a private regular file")
    return fd


def load_json_file(dir_fd, name, missing):
    fd = safe_existing_file(dir_fd, name)
    if fd is None:
        return missing
    try:
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_INPUT:
                raise UnsafeStorage("state file exceeds 1 MiB")
            chunks.append(chunk)
        raw = b"".join(chunks)
    finally:
        os.close(fd)
    try:
        value = json.loads(
            raw.decode("utf-8", errors="strict"),
            object_pairs_hook=pairs_no_duplicates,
            parse_constant=reject_constant,
            parse_float=parse_finite_float,
        )
    except (
        UnicodeDecodeError,
        json.JSONDecodeError,
        SetupError,
        ValueError,
        RecursionError,
    ) as exc:
        raise UnsafeStorage("state file contains invalid JSON") from exc
    if not isinstance(value, dict):
        raise UnsafeStorage("state file must contain an object")
    try:
        ensure_finite(value)
    except SetupError as exc:
        raise UnsafeStorage("state file exceeds structural limits") from exc
    return value


def validate_lock(fd):
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        raise UnsafeStorage("lock file is unsafe")
    os.fchmod(fd, 0o600)


def acquire_lock(dir_fd, name):
    flags = os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = None
    for _attempt in range(3):
        try:
            fd = os.open(name, flags, dir_fd=dir_fd)
            break
        except FileNotFoundError:
            try:
                fd = os.open(name, flags | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=dir_fd)
                break
            except FileExistsError:
                continue
            except OSError as exc:
                raise UnsafeStorage("lock file cannot be created") from exc
        except OSError as exc:
            raise UnsafeStorage("lock file cannot be opened") from exc
    if fd is None:
        raise UnsafeStorage("lock file changed during initialization")
    try:
        validate_lock(fd)
        deadline = time.monotonic() + 1.0
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LockTimeout("lock acquisition timed out")
                time.sleep(0.02)
    except Exception:
        os.close(fd)
        raise


def atomic_json_write(dir_fd, name, value):
    existing = safe_existing_file(dir_fd, name)
    if existing is not None:
        os.close(existing)
    temp_name = "." + name + ".tmp." + uuid.uuid4().hex
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        ensure_finite(value)
        payload = (
            json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)
            + "\n"
        ).encode("utf-8")
    except (SetupError, UnicodeError, ValueError, RecursionError) as exc:
        raise UnsafeStorage("state update cannot be represented as strict JSON") from exc
    if len(payload) > MAX_INPUT:
        raise UnsafeStorage("state update exceeds 1 MiB")
    fd = os.open(temp_name, flags, 0o600, dir_fd=dir_fd)
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fchmod(fd, 0o600)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(temp_name, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        os.fsync(dir_fd)
    except Exception:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temp_name, dir_fd=dir_fd)
        except OSError:
            pass
        raise


def receipt_name(host, plugin_root):
    identity = (host + "\0" + plugin_root + "\0" + str(FLOW_VERSION)).encode("utf-8")
    return hashlib.sha256(identity).hexdigest() + ".json"


def validate_stored_record(record, host, plugin_root):
    required = {
        "schema_version", "revision", "flow_version", "host", "plugin_root",
        "flow", "provider", "stage", "verification", "completed",
    }
    if set(record) != required:
        raise UnsafeStorage("receipt shape is invalid")
    if (
        type(record["schema_version"]) is not int
        or record["schema_version"] != 1
        or type(record["flow_version"]) is not int
        or record["flow_version"] != FLOW_VERSION
    ):
        raise UnsafeStorage("receipt version is invalid")
    if record["host"] != host or record["plugin_root"] != plugin_root:
        raise UnsafeStorage("receipt identity does not match its filename")
    if type(record["revision"]) is not int or record["revision"] < 1:
        raise UnsafeStorage("receipt revision is invalid")
    if not isinstance(record["stage"], str) or record["stage"] not in STAGES:
        raise UnsafeStorage("receipt state is invalid")
    if not isinstance(record["completed"], bool):
        raise UnsafeStorage("receipt fields are invalid")
    try:
        validate_selection(record["flow"], record["provider"])
        validate_verification(record["verification"], record["stage"])
    except SetupError as exc:
        raise UnsafeStorage("receipt selection or verification is invalid") from exc
    if record["completed"] and (
        record["stage"] != "verified" or record["verification"]["result"] != "passed"
    ):
        raise UnsafeStorage("completed receipt lacks current verification")
    return record


def next_stage(record):
    if record is None:
        return "selected"
    if record["completed"]:
        return "rechecked"
    if record["stage"] == "selected" and record["flow"] == "one-provider":
        return "awaiting-human"
    if record["stage"] in {"selected", "awaiting-human"}:
        return "rechecked"
    if record["stage"] == "rechecked" and record["verification"]["result"] == "passed":
        return "verified"
    if record["stage"] == "verified":
        return "complete"
    return "rechecked"


def receipt_response(record, persisted):
    if record is None:
        return {"schema_version": 1, "status": "partial", "found": False, "revision": 0, "next_stage": "selected", "persisted": False}
    return {
        "schema_version": 1,
        "status": "complete" if record["completed"] else "partial",
        "found": True,
        "revision": record["revision"],
        "next_stage": next_stage(record),
        "persisted": persisted,
        "record": record,
    }


def operate_receipt(request):
    create = request["action"] != "read"
    dir_fd = open_state_directory(create, setup=True)
    if dir_fd is None:
        return receipt_response(None, False)
    name = receipt_name(request["host"], request["plugin_root"])
    try:
        if request["action"] == "read":
            record = load_json_file(dir_fd, name, None)
            if record is not None:
                validate_stored_record(record, request["host"], request["plugin_root"])
            return receipt_response(record, False)
        lock_fd = acquire_lock(dir_fd, name + ".lock")
        try:
            record = load_json_file(dir_fd, name, None)
            if record is not None:
                validate_stored_record(record, request["host"], request["plugin_root"])
            current_revision = 0 if record is None else record["revision"]
            if request["expected_revision"] != current_revision:
                raise RevisionConflict("revision conflict")
            if request["action"] == "record":
                selection_changed = record is not None and (
                    request["flow"] != record["flow"] or request["provider"] != record["provider"]
                )
                previous_stage = None if record is None or selection_changed else record["stage"]
                if selection_changed and request["stage"] != "selected":
                    raise SetupError("selection changes must return to selected stage")
                if request["stage"] not in TRANSITIONS[previous_stage]:
                    raise SetupError("stage transition is invalid")
                verification = None if selection_changed else request["verification"]
                if selection_changed and request["verification"] is not None:
                    raise SetupError("selection change invalidates verification")
                updated = {
                    "schema_version": 1,
                    "revision": current_revision + 1,
                    "flow_version": FLOW_VERSION,
                    "host": request["host"],
                    "plugin_root": request["plugin_root"],
                    "flow": request["flow"],
                    "provider": request["provider"],
                    "stage": request["stage"],
                    "verification": verification,
                    "completed": False,
                }
            else:
                if record is None or record["stage"] != "verified":
                    raise SetupError("complete requires a verified receipt")
                if record["verification"] is None or record["verification"].get("result") != "passed":
                    raise SetupError("complete requires current passed verification")
                if record["completed"]:
                    return receipt_response(record, True)
                updated = dict(record)
                updated["revision"] = current_revision + 1
                updated["completed"] = True
            atomic_json_write(dir_fd, name, updated)
            return receipt_response(updated, True)
        finally:
            os.close(lock_fd)
    finally:
        os.close(dir_fd)


def operate_legacy(request):
    dir_fd = open_state_directory(True, setup=False)
    try:
        lock_fd = acquire_lock(dir_fd, "user-config.json.lock")
        try:
            if request["action"] == "legacy-reset":
                existing = safe_existing_file(dir_fd, "user-config.json")
                if existing is not None:
                    os.close(existing)
                    load_json_file(dir_fd, "user-config.json", {})
                    os.unlink("user-config.json", dir_fd=dir_fd)
                    os.fsync(dir_fd)
                return {"schema_version": 1, "status": "complete", "persisted": True}
            current = load_json_file(dir_fd, "user-config.json", {})
            current[request["key"]] = request["value"]
            ensure_finite(current)
            atomic_json_write(dir_fd, "user-config.json", current)
            return {"schema_version": 1, "status": "complete", "persisted": True}
        finally:
            os.close(lock_fd)
    finally:
        os.close(dir_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    args = parser.parse_args()
    try:
        request = validate_request(read_request(args.input))
        if request["action"] in {"legacy-update", "legacy-reset"}:
            result = operate_legacy(request)
        else:
            result = operate_receipt(request)
        payload = json.dumps(result, separators=(",", ":"), allow_nan=False) + "\n"
        sys.stdout.write(payload)
        return 0
    except SetupError as exc:
        print("setup-state: " + str(exc), file=sys.stderr)
        return exc.exit_code
    except OSError as exc:
        print("setup-state: storage operation failed", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
