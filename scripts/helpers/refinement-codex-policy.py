#!/usr/bin/env python3
"""Emit per-server disable overrides without reading or exposing credentials."""
import json
import hashlib
import re
import os
import shlex
import shutil
from pathlib import Path
import subprocess
import sys


def profile_name(directory):
    """Keep this invocation's profile separate from ambient named profiles."""
    return "octopus_refine_" + hashlib.sha256(str(directory).encode()).hexdigest()[:24]


def flags(servers):
    """Build disable overrides from safely named MCP inventory entries."""
    if not isinstance(servers, list):
        raise ValueError("invalid MCP inventory")
    directory = Path(os.environ["OCTOPUS_REFINEMENT_INPUT_DIR"]).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("missing private judge input directory")
    readable = [":minimal", str(directory)]
    shell_environment = "{}"
    if sys.platform == "linux":
        # Codex uses PATH to locate the distro's Bubblewrap. Its inner
        # sandbox process re-execs the CLI at its canonical path.
        launcher = shutil.which("codex")
        if launcher is None:
            raise ValueError("Codex executable not found")
        readable.append(str(Path(launcher).resolve(strict=True)))
        shell_environment = '{PATH="/usr/bin:/bin"}'
    profile = "{" + ",".join(json.dumps(path) + '="read"' for path in readable) + "}"
    name = profile_name(directory)
    settings = [
        'default_permissions=' + json.dumps(name),
        'permissions.' + name + '={filesystem=' + profile + ',network={enabled=false}}',
        'approval_policy="never"', 'project_doc_max_bytes=0',
        'shell_environment_policy.inherit="none"',
        'shell_environment_policy.exclude=["*"]', 'shell_environment_policy.set=' + shell_environment,
        'web_search="disabled"',
    ]
    settings += [f"features.{name}=false" for name in (
        "apps", "plugins", "hooks", "memories", "multi_agent", "multi_agent_v2",
        "browser_use", "computer_use", "in_app_browser", "code_mode", "code_mode_host",
        "request_permissions_tool", "shell_snapshot", "view_image")]
    result = [part for setting in settings for part in ("-c", setting)]
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
        print(shlex.join(flags(json.loads(result.stdout))))
    except (KeyError, ValueError, OSError, subprocess.SubprocessError):
        # Inventory output may contain credential configuration. Never echo it.
        print("ERROR: cannot establish a Codex judge MCP boundary", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
