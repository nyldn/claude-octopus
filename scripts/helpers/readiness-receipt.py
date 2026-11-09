#!/usr/bin/env python3
"""Validate short-lived selection evidence. Never authorize a dispatch."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import sys
import time


def state():
    """Fingerprint selection metadata without reading credential values."""
    root = Path(__file__).resolve().parents[2]
    paths = list((root / "scripts/lib").glob("*.sh")) + list((root / "config").glob("*"))
    home = Path.home() / ".claude-octopus"
    for name, value in os.environ.items():
        if name in ("OCTOPUS_CONFIG_DIR", "OCTOPUS_PROVIDERS_CONFIG"):
            location = Path(value)
            paths.extend(location.rglob("*") if location.is_dir() else [location])
    workspace = Path(os.environ.get("WORKSPACE_DIR", str(home)))
    paths.extend([workspace / "state/.provider-quota-dead", workspace / "state/.provider-quota-dead.meta"])
    for directory in (home / "config", home / "quota"):
        if directory.exists():
            paths.extend(directory.rglob("*"))
    # Store only file identity/mtime/size, never credential values or digests.
    commands = {"claude", "codex", "agy", "qwen", "opencode", "ollama", "gh", "cmd", "agent"}
    registry = root / "scripts/lib/provider-registry.sh"
    if registry.exists():
        for line in registry.read_text().splitlines():
            fields = line.split("|")
            if len(fields) == 5 and "dispatch" in fields[4]:
                commands.add(fields[2])
    for name, value in os.environ.items():
        if name.startswith("OCTOPUS_") and name.endswith("_BIN") and value.strip():
            commands.add(shlex.split(value)[0])
    for command in commands:
        binary = shutil.which(command)
        if binary:
            paths.append(Path(binary).resolve())
    metadata = []
    for path in sorted(set(paths)):
        try:
            st = path.stat()
            metadata.append((str(path), st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns))
        except FileNotFoundError:
            pass
    policy = {k: v for k, v in os.environ.items() if (k.startswith("OCTOPUS_") or k == "OCTO_ALLOWED_PROVIDERS") and not k.startswith("OCTOPUS_PREFLIGHT_") and not any(secret in k for secret in ("KEY", "TOKEN", "SECRET", "PASSWORD")) and
              any(word in k for word in ("MODEL", "EFFORT", "PROVIDERS", "ALLOWLIST", "QUOTA", "POLICY", "_BIN", "CONFIG"))}
    return hashlib.sha256(json.dumps([metadata, policy, os.environ.get("PATH", ""),
        [os.environ.get(k, "") for k in ("CLAUDE_CODE_SESSION_ID", "OCTOPUS_SESSION_ID", "CLAUDE_SESSION_ID")]], sort_keys=True).encode()).hexdigest()


def main():
    """Compare fresh checks with saved evidence and optionally create a receipt."""
    run, kind, scope, source, destination = sys.argv[1:]
    results = json.load(sys.stdin)  # Always produced by fresh per-provider checks.
    scope = json.loads(scope)
    if not run or kind not in ("static", "live") or not isinstance(results, list):
        raise ValueError("invalid receipt request")
    required = {"provider", "status", "reason_code", "check_kind", "checked_at", "duration_ms", "remediation"}
    for row in results:
        if not isinstance(row, dict) or set(row) != required or row["check_kind"] != kind:
            raise ValueError("malformed readiness result")
    stable = [{k: r[k] for k in ("provider", "status", "reason_code", "check_kind")} for r in results]
    receipt = dict(version=1, run_id=run, scope=scope, check_kind=kind, state=state(), results=stable)
    if source:
        old = json.loads(Path(source).read_text())
        if set(old) != set(receipt) | {"created_at"}:
            raise ValueError("malformed receipt")
        age = time.time() - old.pop("created_at")
        if not 0 <= age <= 120 or old != receipt:
            raise ValueError("stale or changed readiness receipt")
    if destination:
        receipt["created_at"] = time.time()
        # Exclusive creation prevents accidental replacement of run evidence.
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(receipt, stream)
    print(json.dumps(results))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, TypeError, KeyError, OSError) as error:
        print(f"ERROR: readiness receipt rejected: {error}", file=sys.stderr)
        sys.exit(2)
