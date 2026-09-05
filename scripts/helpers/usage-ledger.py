#!/usr/bin/env python3
"""Append and reconcile Claude Octopus usage events."""

import argparse
import csv
import json
import os
import sys
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path


TERMINAL_STATES = {"completed", "failed", "cancelled", "timeout"}


def nullable_int(value):
    if value in (None, "", "null", "unknown"):
        return None
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed >= 0 else None


def nullable_float(value):
    if value in (None, "", "null", "unknown"):
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed >= 0 else None


def read_lines_from_fd(fd):
    os.lseek(fd, 0, os.SEEK_SET)
    chunks = []
    while True:
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks).decode("utf-8", errors="replace").splitlines()


def append_event(args):
    path = Path(args.file)
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_CREAT | os.O_RDWR | os.O_APPEND
    fd = os.open(path, flags, 0o600)
    try:
        try:
            import fcntl
        except ImportError:
            fcntl = None
        if fcntl is not None:
            fcntl.flock(fd, fcntl.LOCK_EX)

        # Reservations and terminal events are idempotent by call ID. The first
        # terminal event is authoritative so a delayed duplicate cannot mutate
        # totals after the caller has already observed completion.
        seen_reservation = False
        seen_terminal = False
        for line in read_lines_from_fd(fd):
            if not line.startswith("{"):
                continue
            try:
                existing = json.loads(line)
            except (TypeError, ValueError):
                continue
            if existing.get("call_id") != args.call_id:
                continue
            state = existing.get("state")
            seen_reservation = seen_reservation or state == "reserved"
            seen_terminal = seen_terminal or state in TERMINAL_STATES
        if (args.state == "reserved" and seen_reservation) or (
            args.state in TERMINAL_STATES and seen_terminal
        ):
            return 0

        usage = {
            "input_uncached": nullable_int(args.input_tokens),
            "input_cached": nullable_int(args.cached_input_tokens),
            "cache_write": nullable_int(args.cache_write_tokens),
            "output": nullable_int(args.output_tokens),
            "reasoning": nullable_int(args.reasoning_tokens),
            "total": nullable_int(args.total_tokens),
        }
        event = {
            "schema": "octopus/usage-event-v2",
            "timestamp": args.timestamp
            or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "state": args.state,
            "call_id": args.call_id,
            "agent": args.agent or None,
            "model": args.model or None,
            "phase": args.phase or None,
            "role": args.role or None,
            "usage": usage,
            "usage_source": args.usage_source or None,
            "cost_usd": nullable_float(args.cost),
            "cost_status": args.cost_status or None,
            "duration_ms": nullable_int(args.duration_ms),
            "tool_uses": nullable_int(args.tool_uses),
            "billing_mode": args.billing_mode or "unknown",
            "tariff_version": args.tariff_version or None,
            "failure_reason": args.failure_reason or None,
        }
        encoded = (json.dumps(event, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
        os.lseek(fd, 0, os.SEEK_END)
        os.write(fd, encoded)
        os.fsync(fd)
    finally:
        os.close(fd)
    return 0


def structured_record(event):
    usage = event.get("usage") if isinstance(event.get("usage"), dict) else {}
    return {
        "call_id": event.get("call_id"),
        "timestamp": event.get("timestamp"),
        "agent": event.get("agent"),
        "model": event.get("model"),
        "phase": event.get("phase"),
        "role": event.get("role"),
        "state": event.get("state"),
        "usage_source": event.get("usage_source"),
        "input_tokens": nullable_int(usage.get("input_uncached")),
        "cached_input_tokens": nullable_int(usage.get("input_cached")),
        "cache_write_tokens": nullable_int(usage.get("cache_write")),
        "output_tokens": nullable_int(usage.get("output")),
        "reasoning_tokens": nullable_int(usage.get("reasoning")),
        "total_tokens": nullable_int(usage.get("total")),
        "cost_usd": nullable_float(event.get("cost_usd")),
        "cost_status": event.get("cost_status"),
        "duration_ms": nullable_int(event.get("duration_ms")),
        "tool_uses": nullable_int(event.get("tool_uses")),
        "billing_mode": event.get("billing_mode") or "unknown",
        "tariff_version": event.get("tariff_version"),
        "failure_reason": event.get("failure_reason"),
    }


def legacy_record(line, index):
    fields = line.split("|")
    fields += [""] * (11 - len(fields))
    timestamp, agent, model, phase, role = fields[:5]
    call_id = fields[10] or f"legacy-{index}"
    return {
        "call_id": call_id,
        "timestamp": timestamp or None,
        "agent": agent or None,
        "model": model or None,
        "phase": phase or None,
        "role": role or None,
        "state": "legacy",
        "usage_source": "actual" if role == "actual" else "estimated",
        "input_tokens": nullable_int(fields[5]),
        "cached_input_tokens": None,
        "cache_write_tokens": None,
        "output_tokens": nullable_int(fields[6]),
        "reasoning_tokens": None,
        "total_tokens": nullable_int(fields[7]),
        "cost_usd": nullable_float(fields[8]),
        "cost_status": "legacy",
        "duration_ms": nullable_int(fields[9]),
        "tool_uses": None,
        "billing_mode": "unknown",
        "tariff_version": None,
        "failure_reason": None,
    }


def reconcile(path):
    records = OrderedDict()
    if not path.exists():
        return []
    for index, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if not line.startswith("{"):
            record = legacy_record(line, index)
            # Legacy IDs were not guaranteed unique. Preserve every row rather
            # than claiming unrelated historical events are one call.
            key = f"legacy-row-{index}"
            records[key] = record
            continue
        try:
            event = json.loads(line)
        except (TypeError, ValueError):
            continue
        if event.get("schema") != "octopus/usage-event-v2" or not event.get("call_id"):
            continue
        call_id = event["call_id"]
        current = records.get(call_id)
        incoming = structured_record(event)
        if current is None:
            records[call_id] = incoming
        elif event.get("state") in TERMINAL_STATES and current.get("state") not in TERMINAL_STATES:
            if event.get("state") == "completed":
                for key, value in incoming.items():
                    if key not in {"call_id", "timestamp", "agent", "model", "phase"} or value is not None:
                        current[key] = value
            else:
                current["state"] = incoming["state"]
                current["duration_ms"] = incoming["duration_ms"]
                current["failure_reason"] = incoming["failure_reason"]
        # Duplicate terminal events are ignored; append_event also prevents new
        # ones, but reconciliation remains idempotent for externally written logs.
    return list(records.values())


def load_session(path):
    if not path:
        return {}
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def report_json(records, session):
    costs = [record["cost_usd"] for record in records if record["cost_usd"] is not None]
    return {
        "schema": "octopus/usage-report-v2",
        "session_id": session.get("session_id"),
        "started_at": session.get("started_at"),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "totals": {
            "calls": len(records),
            "tokens": sum(record["total_tokens"] or 0 for record in records),
            "cost_usd": round(sum(costs), 6),
            "unknown_cost_calls": sum(record["cost_usd"] is None for record in records),
        },
        "calls": records,
    }


def emit_report(args):
    records = reconcile(Path(args.file))
    report = report_json(records, load_session(args.session_file))
    if args.format == "json":
        json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
    elif args.format == "csv":
        writer = csv.writer(sys.stdout)
        fields = [
            "call_id", "timestamp", "agent", "model", "phase", "role", "state",
            "input_tokens", "cached_input_tokens", "cache_write_tokens", "output_tokens",
            "reasoning_tokens", "total_tokens", "cost_usd", "duration_ms", "billing_mode",
            "tariff_version",
        ]
        writer.writerow(fields)
        for record in records:
            writer.writerow([record.get(field) for field in fields])
    elif args.format == "providers":
        grouped = OrderedDict()
        for record in records:
            provider = (record.get("agent") or "unknown").split("-", 1)[0]
            row = grouped.setdefault(provider, {"calls": 0, "tokens": 0, "cost": 0.0, "unknown": 0})
            row["calls"] += 1
            row["tokens"] += record.get("total_tokens") or 0
            if record.get("cost_usd") is None:
                row["unknown"] += 1
            else:
                row["cost"] += record["cost_usd"]
        print("Provider Breakdown:")
        for provider, row in grouped.items():
            suffix = f", {row['unknown']} unknown" if row["unknown"] else ""
            print(f"  {provider:16} {row['calls']:6} calls {row['tokens']:8} tokens ${row['cost']:.6f}{suffix}")
    elif args.format == "phases":
        grouped = OrderedDict()
        for record in records:
            key = (record.get("phase") or "unknown", record.get("model") or "unknown")
            row = grouped.setdefault(key, {"calls": 0, "tokens": 0, "cost": 0.0, "unknown": 0})
            row["calls"] += 1
            row["tokens"] += record.get("total_tokens") or 0
            if record.get("cost_usd") is None:
                row["unknown"] += 1
            else:
                row["cost"] += record["cost_usd"]
        print("Per-Phase Cost Breakdown:")
        for (phase, model), row in grouped.items():
            suffix = f", {row['unknown']} unknown" if row["unknown"] else ""
            print(f"  {phase:16} {model:28} {row['tokens']:8} tokens ${row['cost']:.6f}{suffix}")
    else:
        totals = report["totals"]
        print("USAGE REPORT")
        print(f"Total Calls:  {totals['calls']}")
        print(f"Total Tokens: {totals['tokens']}")
        print(f"Total Cost:   ${totals['cost_usd']:.6f}")
        if totals["unknown_cost_calls"]:
            print(f"Unknown Cost: {totals['unknown_cost_calls']} call(s)")
        for record in records:
            cost = "unknown" if record["cost_usd"] is None else f"${record['cost_usd']:.6f}"
            print(
                f"{record.get('agent') or 'unknown':20} "
                f"{record.get('model') or 'unknown':28} "
                f"{record.get('total_tokens') or 0:8} {cost:>12} "
                f"{record.get('state') or 'unknown'}"
            )
    return 0


def parser():
    root = argparse.ArgumentParser()
    subparsers = root.add_subparsers(dest="command", required=True)
    append = subparsers.add_parser("append")
    append.add_argument("--file", required=True)
    append.add_argument("--state", choices=["reserved", *sorted(TERMINAL_STATES)], required=True)
    append.add_argument("--call-id", required=True)
    for name in (
        "timestamp", "agent", "model", "phase", "role", "input-tokens",
        "cached-input-tokens", "cache-write-tokens", "output-tokens",
        "reasoning-tokens", "total-tokens", "usage-source", "cost", "cost-status",
        "duration-ms", "tool-uses", "billing-mode", "tariff-version", "failure-reason",
    ):
        append.add_argument(f"--{name}", default="")
    append.set_defaults(func=append_event)

    report = subparsers.add_parser("report")
    report.add_argument("--file", required=True)
    report.add_argument("--session-file", default="")
    report.add_argument(
        "--format", choices=["json", "csv", "table", "providers", "phases"], default="json"
    )
    report.set_defaults(func=emit_report)
    return root


def main(argv):
    args = parser().parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
