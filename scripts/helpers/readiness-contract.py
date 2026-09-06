#!/usr/bin/env python3
"""Strictly validate and normalize a static provider-readiness report."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys

MAX_INPUT = 1024 * 1024
MAX_NESTING = 64
MAX_NODES = 100000
PROVIDER_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
STATUSES = {"available", "degraded", "missing", "unknown"}


class ReadinessError(ValueError):
    pass


def no_duplicate_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ReadinessError("duplicate JSON key")
        result[key] = value
    return result


def reject_constant(_value):
    raise ReadinessError("non-finite JSON number")


def parse_float(value):
    result = float(value)
    if not math.isfinite(result):
        raise ReadinessError("non-finite JSON number")
    return result


def read_report(path):
    if path == "-":
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
    else:
        with open(path, "rb") as handle:
            raw = handle.read(MAX_INPUT + 1)
    if len(raw) > MAX_INPUT:
        raise ReadinessError("input exceeds 1 MiB")
    try:
        report = json.loads(
            raw.decode("utf-8", errors="strict"),
            object_pairs_hook=no_duplicate_pairs,
            parse_constant=reject_constant,
            parse_float=parse_float,
        )
    except (UnicodeError, ValueError, RecursionError) as exc:
        raise ReadinessError("input is not one UTF-8 JSON value") from exc
    if not isinstance(report, dict):
        raise ReadinessError("report must be an object")
    return report


def bounded_string(value, field, maximum):
    if not isinstance(value, str) or len(value) > maximum:
        raise ReadinessError(field + " is invalid")
    try:
        value.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise ReadinessError(field + " is not valid UTF-8") from exc
    if "\0" in value:
        raise ReadinessError(field + " contains a NUL byte")
    return value


def validate_tree(value):
    stack = [(value, 0)]
    nodes = 0
    while stack:
        item, depth = stack.pop()
        nodes += 1
        if nodes > MAX_NODES:
            raise ReadinessError("report is too complex")
        if isinstance(item, str):
            bounded_string(item, "string", MAX_INPUT)
        elif isinstance(item, list):
            if depth >= MAX_NESTING:
                raise ReadinessError("report exceeds maximum nesting")
            stack.extend((child, depth + 1) for child in item)
        elif isinstance(item, dict):
            if depth >= MAX_NESTING:
                raise ReadinessError("report exceeds maximum nesting")
            for key, child in item.items():
                bounded_string(key, "object key", MAX_INPUT)
                stack.append((child, depth + 1))


def validate_report(report):
    validate_tree(report)
    if report.get("check_kind") != "static":
        raise ReadinessError("check_kind must be static")
    results = report.get("results")
    if not isinstance(results, list) or not results or len(results) > 64:
        raise ReadinessError("results must be a nonempty bounded array")
    providers = set()
    normalized_results = []
    required = {
        "provider", "status", "reason_code", "checked_at", "duration_ms",
        "remediation",
    }
    for item in results:
        if not isinstance(item, dict) or not required.issubset(item):
            raise ReadinessError("readiness result is incomplete")
        provider = item["provider"]
        if not isinstance(provider, str) or not PROVIDER_RE.fullmatch(provider):
            raise ReadinessError("provider is invalid")
        if provider in providers:
            raise ReadinessError("provider is duplicated")
        providers.add(provider)
        if not isinstance(item["status"], str) or item["status"] not in STATUSES:
            raise ReadinessError("status is invalid")
        bounded_string(item["reason_code"], "reason_code", 256)
        bounded_string(item["checked_at"], "checked_at", 256)
        bounded_string(item["remediation"], "remediation", 4096)
        duration = item["duration_ms"]
        if isinstance(duration, bool) or not isinstance(duration, (int, float)) or duration < 0:
            raise ReadinessError("duration_ms is invalid")
        if isinstance(duration, float) and not math.isfinite(duration):
            raise ReadinessError("duration_ms is invalid")
        normalized_results.append({key: item[key] for key in sorted(required)})
    return {"check_kind": "static", "results": normalized_results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    args = parser.parse_args()
    try:
        report = validate_report(read_report(args.input))
        payload = json.dumps(report, separators=(",", ":"), allow_nan=False) + "\n"
        sys.stdout.write(payload)
        return 0
    except (ReadinessError, UnicodeError, ValueError, RecursionError) as exc:
        print("readiness-contract: invalid input: " + str(exc), file=sys.stderr)
        return 2
    except OSError:
        print("readiness-contract: input is unavailable", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
