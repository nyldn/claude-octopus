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


# Match the official npm launcher's platform package lookup, including its
# fallback to the wrapper package's own vendor directory.
NPM_CODEX_BINARY = """
const { existsSync } = require("node:fs");
const { createRequire } = require("node:module");
const path = require("node:path");
const launcher = process.argv[1];
const architecture = { x64: "x86_64", arm64: "aarch64" }[process.arch];
if (!architecture) process.exit(1);
let packageRoot = path.dirname(path.dirname(launcher));
try {
    const manifest = createRequire(launcher).resolve(
        "@openai/codex-linux-" + process.arch + "/package.json");
    packageRoot = path.dirname(manifest);
} catch {
    // Older releases can ship the runtime in the launcher package itself.
}
const target = path.join(packageRoot, "vendor", architecture + "-unknown-linux-musl");
const binary = path.join(target, "bin", "codex");
process.stdout.write(JSON.stringify(existsSync(binary) ? binary : path.join(target, "codex", "codex")));
"""


def linux_runtime_files():
    """Identify exact executable paths needed to start the inner sandbox."""
    command = shutil.which("codex")
    if command is None:
        raise ValueError("Codex executable not found")
    binary = Path(command).resolve(strict=True)
    if binary.parts[-4:] == ("@openai", "codex", "bin", "codex.js"):
        result = subprocess.run(["node", "-e", NPM_CODEX_BINARY, str(binary)],
                                capture_output=True, text=True, timeout=5, check=True)
        binary = Path(json.loads(result.stdout)).resolve(strict=True)
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise ValueError("Codex native executable not found")
    paths = [str(binary)] + [str(helper.resolve(strict=True)) for helper in (
        binary.with_name("codex-linux-sandbox"),
        binary.parent.parent / "codex-resources" / "codex-linux-sandbox",
    ) if helper.is_file() and os.access(helper, os.X_OK)]
    return list(dict.fromkeys(paths))


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
        readable.extend(linux_runtime_files())
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
