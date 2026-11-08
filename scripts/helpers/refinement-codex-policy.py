#!/usr/bin/env python3
"""Emit per-server disable overrides without reading or exposing credentials."""
import json
import re
import subprocess
import sys


def flags(servers):
    """Build disable overrides from safely named MCP inventory entries."""
    if not isinstance(servers, list):
        raise ValueError("invalid MCP inventory")
    result = ["-c", "features.apps=false", "-c", "features.plugins=false"]
    for server in servers:
        name = server.get("name") if isinstance(server, dict) else None
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            raise ValueError("MCP server name cannot be safely overridden")
        result.extend(["-c", f"mcp_servers.{name}.enabled=false"])
    return result


def main():
    """Read the local inventory and emit flags without exposing credentials."""
    try:
        result = subprocess.run(["codex", "mcp", "list", "--json", "-c", "features.apps=false",
                                 "-c", "features.plugins=false"],
                                capture_output=True, text=True, timeout=15, check=True)
        print(" ".join(flags(json.loads(result.stdout))))
    except (ValueError, OSError, subprocess.SubprocessError):
        # Inventory output may contain credential configuration. Never echo it.
        print("ERROR: cannot establish a Codex judge MCP boundary", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
