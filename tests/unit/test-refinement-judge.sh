#!/usr/bin/env bash
# Check dispatch boundaries without launching providers or using authentication.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
validation = r'''
source "$1/scripts/lib/utils.sh"
OCTOPUS_CLAUDE_BIN='claude --tools Read,Glob,Grep --strict-mcp-config'
_validate_claude_agent_command 'claude --tools Read,Glob,Grep --strict-mcp-config --print --model exact-model --allowed-tools Read,Glob,Grep'
OCTOPUS_CLAUDE_BIN='claude --tools Read,Write --strict-mcp-config'
if _validate_claude_agent_command 'claude --tools Read,Write --strict-mcp-config --print --model exact-model --allowed-tools Read,Glob,Grep'; then exit 1; fi
'''
subprocess.run(["bash", "-eu", "-c", validation, "test", str(root)], check=True)
spec = importlib.util.spec_from_file_location("policy", root / "scripts/helpers/refinement-codex-policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
assert policy.flags([{"name": "safe-server", "env": {"SECRET": "must-not-emit"}}]) == [
    "-c", "features.apps=false", "-c", "features.plugins=false", "-c", "mcp_servers.safe-server.enabled=false"]
for bad in [[{"name": "unsafe.name"}], [{"name": "server;exit"}], {"name": "not-a-list"}]:
    try:
        policy.flags(bad)
    except ValueError:
        pass
    else:
        raise AssertionError("unsafe inventory accepted")
with tempfile.TemporaryDirectory(prefix="refinement-judge-") as temporary:
    fixture = Path(temporary)
    adapter = fixture / "refinement-judge.sh"
    shutil.copyfile(root / "scripts/refinement-judge.sh", adapter)
    runner = fixture / "orchestrate.sh"
    runner.write_text('''#!/usr/bin/env python3
import json,os,sys
print(json.dumps({"argv":sys.argv[1:], "judge":os.environ["OCTOPUS_REFINEMENT_JUDGE"], "retry":os.environ["OCTOPUS_AUTH_RETRIES"],
 "sandbox":os.environ["OCTOPUS_CODEX_SANDBOX"], "claude":os.environ["OCTOPUS_CLAUDE_BIN"]}))
''')
    runner.chmod(0o755)
    prompt = fixture / "prompt with spaces"
    prompt.write_text("Score the candidate; do not edit it.")
    args = ["bash", str(adapter), "codex:exact-model", "008", str(prompt), "round-0", str(fixture)]
    environment = dict(os.environ, OCTOPUS_AUTH_RETRIES="9", OCTOPUS_CODEX_SANDBOX="danger-full-access",
                       OCTOPUS_CLAUDE_BIN="custom-claude --setting-sources project,local")
    result = subprocess.run(args, env=environment, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    assert data["judge"] == "true", data
    assert data["retry"] == "0" and data["sandbox"] == "read-only", data
    assert data["claude"] == "custom-claude --setting-sources project,local --tools Read,Glob,Grep --strict-mcp-config", data
    assert data["argv"] == ["--timeout", "8", "probe-single", "codex:exact-model",
                            "--perspective-file", str(prompt), "round-0", "--output-dir", str(fixture)], data
    for provider in ["claude-opus:exact-model", "claude-sonnet", "codex"]:
        args[2] = provider
        subprocess.run(args, env=environment, capture_output=True, text=True, check=True)
    for provider in ["qwen", "agy", "openrouter:model", "unknown"]:
        args[2] = provider
        denied = subprocess.run(args, env=environment, capture_output=True, text=True)
        assert denied.returncode == 2 and not denied.stdout, denied
    args[2] = "codex"
    for timeout in ["0", "-1", "1.5", "3601", "999999999999999999", "abc"]:
        args[3] = timeout
        denied = subprocess.run(args, env=environment, capture_output=True, text=True)
        assert denied.returncode == 2 and not denied.stdout, denied
    args[3] = "10"
    denied = subprocess.run(args, env=dict(environment, OCTOPUS_CLAUDE_BIN="claude --mcp-config unsafe.json"),
                            capture_output=True, text=True)
    assert denied.returncode == 2 and not denied.stdout, denied
print("PASS: constrained dispatch, exact pins, no retries, unsupported providers and invalid timeouts")
PY
