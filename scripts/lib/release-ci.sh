#!/usr/bin/env bash
# Helpers for release CI polling.

octo_pr_check_state() {
    local checks_json="$1"
    local check_name="$2"

    python3 - "$check_name" "$checks_json" <<'PY'
import json
import sys

check_name = sys.argv[1]
raw = sys.argv[2]

try:
    checks = json.loads(raw)
except Exception:
    print("pending")
    raise SystemExit(0)

state_map = {
    "SUCCESS": "pass",
    "FAILURE": "fail",
    "ERROR": "fail",
    "CANCELLED": "fail",
    "TIMED_OUT": "fail",
    "ACTION_REQUIRED": "fail",
    "SKIPPED": "skip",
    "NEUTRAL": "skip",
    "PENDING": "pending",
    "QUEUED": "pending",
    "IN_PROGRESS": "pending",
    "REQUESTED": "pending",
    "WAITING": "pending",
}

for check in checks:
    if check.get("name") == check_name:
        state = str(check.get("state") or "PENDING").upper()
        print(state_map.get(state, state.lower()))
        break
else:
    print("pending")
PY
}
