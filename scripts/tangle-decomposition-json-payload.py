#!/usr/bin/env python3
from __future__ import annotations
import json
import sys

raw = sys.stdin.read().strip()
if raw.startswith("```"):
    lines = raw.splitlines()
    if lines and lines[0].strip() in {"```", "```json", "```JSON"} and len(lines) >= 2:
        raw = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:]).strip()


SCOPE_KEYS = ("reads", "files", "creates")


def default_omitted_scopes(obj):
    # Providers sometimes drop an empty scope array. Restore it here so every
    # consumer sees the same subtask; other keys and types stay strict.
    subtasks = obj.get("subtasks")
    if not isinstance(subtasks, list):
        return obj
    for subtask in subtasks:
        if isinstance(subtask, dict):
            for key in SCOPE_KEYS:
                subtask.setdefault(key, [])
    return obj


def emit(obj):
    if not isinstance(obj, dict):
        raise SystemExit(1)
    obj = default_omitted_scopes(obj)
    sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")


try:
    emit(json.loads(raw))
    raise SystemExit(0)
except (json.JSONDecodeError, TypeError):
    pass

decoder = json.JSONDecoder()
found = []
for i, ch in enumerate(raw):
    if ch != "{":
        continue
    try:
        obj, end = decoder.raw_decode(raw[i:])
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict):
        found.append((i, i + end, obj))

# Ignore nested objects that are contained in a larger parsed object. This
# preserves exactly-one-top-level-object semantics while still rejecting two
# independent JSON objects in the same response.
maximal = []
for candidate in found:
    start, end, _ = candidate
    if any(
        other_start <= start
        and end <= other_end
        and (other_start, other_end) != (start, end)
        for other_start, other_end, _ in found
    ):
        continue
    maximal.append(candidate)

if len(maximal) != 1:
    raise SystemExit(1)
emit(maximal[0][2])
