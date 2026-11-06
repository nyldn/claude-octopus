#!/usr/bin/env python3
"""Bind repository guidance and check the evidence in proposed policy findings.

Policy text belongs in a runtime snapshot, never in portable feature metadata.
This helper checks citations. It does not decide whether an action is a conflict.
"""

import argparse
import errno
import hashlib
import json
import math
import os
import stat
import sys

POLICY_LIMIT = 262144
INPUT_LIMIT = 2097152
PLAN_LIMIT = 1048576
LINE_LIMIT = 10000
FINDING_LIMIT = 256
DEFAULTS = ("AGENTS.md", "CLAUDE.md", "CONTRIBUTING.md", ".github/CONTRIBUTING.md")


class InvalidInput(ValueError):
    pass


def relative_parts(path):
    if not isinstance(path, str) or not path or path.startswith("/") or "\\" in path:
        raise InvalidInput("unsafe-path")
    parts = path.split("/")
    if any(part in ("", ".", "..") or any(ord(c) < 32 for c in part) for part in parts):
        raise InvalidInput("unsafe-path")
    return parts


def directory_fd(path):
    """Open a physical directory without following any component symlink."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open(os.sep, flags)
    try:
        for part in os.path.abspath(path).split(os.sep):
            if part:
                child = os.open(part, flags, dir_fd=fd)
                os.close(fd)
                fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def bounded_read(root_fd, path, limit):
    parts = relative_parts(path)
    parent = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode):
                raise InvalidInput("not-regular-file")
            if not before.st_mode & 0o444:
                raise InvalidInput("unreadable")
            if before.st_size > limit:
                raise InvalidInput("too-large")
            chunks = []
            size = 0
            while size <= limit:
                chunk = os.read(fd, min(65536, limit + 1 - size))
                if not chunk:
                    break
                chunks.append(chunk)
                size += len(chunk)
            if size > limit:
                raise InvalidInput("too-large")
            after = os.fstat(fd)
            if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                raise InvalidInput("changed-during-read")
            return b"".join(chunks)
        finally:
            os.close(fd)
    finally:
        os.close(parent)


def decode(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise InvalidInput("invalid-utf8") from None
    if any((ord(c) < 32 and c not in "\n\r\t") or ord(c) == 127 for c in text):
        raise InvalidInput("invalid-text")
    return text


def lines(text):
    result = text.split("\n")
    if result[-1] == "":
        result.pop()
    if len(result) > LINE_LIMIT:
        raise InvalidInput("too-many-lines")
    return [line[:-1] if line.endswith("\r") else line for line in result]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def reason(exc):
    if isinstance(exc, InvalidInput):
        return str(exc)
    if isinstance(exc, FileNotFoundError):
        return "missing"
    if isinstance(exc, PermissionError):
        return "unreadable"
    if isinstance(exc, OSError) and exc.errno in (errno.ELOOP, errno.ENOTDIR):
        return "unsafe-path"
    return "read-error"


def bind(root, configured=None):
    result = {"schema_version": 1, "source": None, "digest": None, "text": None,
              "passages": [], "candidates": [], "warnings": []}
    paths = [".specify/memory/constitution.md"]
    if configured:
        paths.append(configured)
    paths.extend(DEFAULTS)
    paths = list(dict.fromkeys(paths))
    root_fd = None
    try:
        root_fd = directory_fd(root)
    except (OSError, ValueError) as exc:
        result["warnings"].append("policy root unavailable: " + reason(exc))
    try:
        for path in paths:
            candidate = {"path": path, "status": "skipped"}
            try:
                relative_parts(path)
                if root_fd is None:
                    raise InvalidInput("root-unavailable")
                data = bounded_read(root_fd, path, POLICY_LIMIT)
                text = decode(data)
                source_lines = lines(text)
                if not text.strip():
                    raise InvalidInput("empty")
                if result["source"] is None:
                    candidate["status"] = "selected"
                    result.update(source=path, digest=digest(data), text=text,
                                  passages=[{"line": n, "text": line} for n, line in enumerate(source_lines, 1)])
                else:
                    candidate["status"] = "passed-over"
            except (OSError, ValueError) as exc:
                candidate["reason"] = reason(exc)
                if candidate["reason"] != "missing":
                    result["warnings"].append("policy candidate skipped: " + candidate["reason"] + " (" + path + ")")
            result["candidates"].append(candidate)
    finally:
        if root_fd is not None:
            os.close(root_fd)
    if result["source"] is None:
        result["warnings"].append("no project policy source found")
    return result


def explicit_read(path, limit):
    # These files are explicit runtime inputs. Resolve their caller-owned parent,
    # then confine the file read to that descriptor and reject a leaf symlink.
    parent, leaf = os.path.split(os.path.abspath(path))
    fd = directory_fd(os.path.realpath(parent))
    try:
        return bounded_read(fd, leaf, limit)
    finally:
        os.close(fd)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidInput("duplicate-json-key")
        result[key] = value
    return result


def invalid_constant(_value):
    raise InvalidInput("invalid-json-constant")


def finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise InvalidInput("invalid-json-constant")
    return value


def load_json(path):
    try:
        return json.loads(decode(explicit_read(path, INPUT_LIMIT)),
                          object_pairs_hook=unique_object, parse_constant=invalid_constant,
                          parse_float=finite_float)
    except (json.JSONDecodeError, RecursionError):
        raise InvalidInput("invalid-json") from None


def cited_quote(value, start_key, end_key, quote_key, source_lines):
    start, end, quote = value.get(start_key), value.get(end_key), value.get(quote_key)
    if type(start) is not int or type(end) is not int or not 1 <= start <= end <= len(source_lines):
        return "invalid-line-range"
    if not isinstance(quote, str) or not quote.strip() or quote != "\n".join(source_lines[start - 1:end]):
        return "quotation-mismatch"
    return None


def verify(snapshot, plan_data, observations):
    plan_text = decode(plan_data)
    plan_lines = lines(plan_text)
    plan_digest = digest(plan_data)
    result = {"schema_version": 1, "source": None, "digest": None, "plan_digest": plan_digest,
              "verified_violations": [], "unsupported_observations": [], "warnings": []}
    snapshot_error = None
    policy_lines = []
    if (not isinstance(snapshot, dict) or type(snapshot.get("schema_version")) is not int
            or snapshot.get("schema_version") != 1):
        snapshot_error = "invalid-policy-snapshot"
    elif snapshot.get("source") is None:
        snapshot_error = "no-bound-policy"
        result["warnings"].append("no project policy source found")
    else:
        result["source"] = snapshot.get("source")
        result["digest"] = snapshot.get("digest")
        try:
            relative_parts(result["source"])
            text = snapshot.get("text")
            if not isinstance(text, str) or len(text.encode("utf-8")) > POLICY_LIMIT or not text.strip():
                raise InvalidInput("invalid-policy-snapshot")
            decode(text.encode("utf-8"))
            policy_lines = lines(text)
            expected = [{"line": n, "text": line} for n, line in enumerate(policy_lines, 1)]
            passages = snapshot.get("passages")
            if (snapshot.get("digest") != digest(text.encode("utf-8")) or passages != expected
                    or any(type(item.get("line")) is not int for item in passages)):
                raise InvalidInput("invalid-policy-snapshot")
        except (ValueError, UnicodeError):
            snapshot_error = "invalid-policy-snapshot"
    if isinstance(observations, dict):
        observations = observations.get("findings")
    if not isinstance(observations, list) or len(observations) > FINDING_LIMIT:
        raise InvalidInput("invalid-findings")
    if snapshot_error and snapshot_error != "no-bound-policy":
        result["warnings"].append(snapshot_error)
    for finding in observations:
        rejection = snapshot_error
        if not isinstance(finding, dict):
            rejection = "invalid-finding"
        elif not rejection:
            if finding.get("source") != result["source"]:
                rejection = "policy-source-mismatch"
            elif finding.get("digest") != result["digest"]:
                rejection = "policy-digest-mismatch"
            elif finding.get("plan_digest") != plan_digest:
                rejection = "plan-digest-mismatch"
            else:
                rejection = cited_quote(finding, "line_start", "line_end", "quote", policy_lines)
                if rejection:
                    rejection = "policy-" + rejection
                else:
                    rejection = cited_quote(finding, "plan_line_start", "plan_line_end", "plan_action", plan_lines)
                    if rejection:
                        rejection = "plan-" + rejection
        if rejection:
            result["unsupported_observations"].append({"finding": finding, "reason": rejection})
        else:
            result["verified_violations"].append(finding)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    binding = commands.add_parser("bind")
    binding.add_argument("--root", required=True)
    binding.add_argument("--configured")
    checking = commands.add_parser("verify")
    checking.add_argument("--policy", required=True)
    checking.add_argument("--plan", required=True)
    checking.add_argument("--findings", required=True)
    args = parser.parse_args()
    try:
        if args.command == "bind":
            output = bind(args.root, args.configured)
        else:
            output = verify(load_json(args.policy), explicit_read(args.plan, PLAN_LIMIT), load_json(args.findings))
    except (OSError, ValueError, RecursionError) as exc:
        print(json.dumps({"schema_version": 1, "verified_violations": [], "unsupported_observations": [],
                          "warnings": ["policy verification unavailable: " + reason(exc)], "error": reason(exc)}))
        return 1
    print(json.dumps(output, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
