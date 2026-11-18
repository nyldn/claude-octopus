#!/usr/bin/env bash
# Check dispatch boundaries without launching providers or using authentication.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "Refinement judge dispatch"
test_case "read-only dispatch, timeout reservations, and provider restrictions"
if python3 - "$ROOT" <<'PY'
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
OCTOPUS_CLAUDE_BIN='claude --tools Read,Glob,Grep --strict-mcp-config --restricted --safe-mode'
_validate_claude_agent_command 'claude --tools Read,Glob,Grep --strict-mcp-config --restricted --safe-mode --print --model exact-model --allowed-tools Read,Glob,Grep'
OCTOPUS_CLAUDE_BIN='claude --tools Read,Write --strict-mcp-config'
if _validate_claude_agent_command 'claude --tools Read,Write --strict-mcp-config --print --model exact-model --allowed-tools Read,Glob,Grep'; then exit 1; fi
'''
subprocess.run(["bash", "-eu", "-c", validation, "test", str(root)], check=True)
spec = importlib.util.spec_from_file_location("policy", root / "scripts/helpers/refinement-codex-policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
os.environ["OCTOPUS_REFINEMENT_INPUT_DIR"] = str(root)
flags = policy.flags([{"name": "safe-server", "env": {"SECRET": "must-not-emit"}}])
assert "mcp_servers.safe-server.enabled=false" in flags
assert "must-not-emit" not in str(flags)
assert 'default_permissions="' + policy.profile_name(root) + '"' in flags
assert 'shell_environment_policy.exclude=["*"]' in flags
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
    fixture_spec = importlib.util.spec_from_file_location("fixture", root / "tests/fixtures/refinement-boundary.py")
    fixture_module = importlib.util.module_from_spec(fixture_spec)
    fixture_spec.loader.exec_module(fixture_module)
    binaries = fixture_module.install(root, fixture)
    runner = fixture / "orchestrate.sh"
    runner.write_text('''#!/usr/bin/env python3
import json,os,sys,subprocess
resolver = 'source "$1/scripts/lib/heartbeat.sh"; source "$1/scripts/lib/agent-sync.sh"; source "$1/scripts/lib/spawn.sh"; octopus_effective_agent_timeout "$2" probe researcher'
effective = subprocess.check_output(['bash', '-c', resolver, 'test', os.environ['REFINE_TEST_ROOT'], sys.argv[2]],
    env=dict(os.environ, OCTOPUS_TIMEOUT_EXPLICIT='1', OCTOPUS_TIMEOUT_EXPLICIT_SECS=sys.argv[2]), text=True).strip()
print(json.dumps({"argv":sys.argv[1:], "judge":os.environ["OCTOPUS_REFINEMENT_JUDGE"], "retry":os.environ["OCTOPUS_AUTH_RETRIES"],
 "sandbox":os.environ["OCTOPUS_CODEX_SANDBOX"], "claude":os.environ["OCTOPUS_CLAUDE_BIN"], "effective_timeout":effective,
 "cwd":os.getcwd(), "request":open(sys.argv[6]).read(), "advisor_disabled":os.environ["CLAUDE_CODE_DISABLE_ADVISOR_TOOL"], "advisor":os.environ["OCTOPUS_CLAUDE_ADVISOR"]}))
''')
    runner.chmod(0o755)
    prompt = fixture / "prompt with spaces"
    prompt.write_text("Score the candidate; do not edit it.")
    args = ["bash", str(adapter), "codex:exact-model", "008", str(prompt), "round-0", str(fixture)]
    environment = dict(os.environ, OCTOPUS_AUTH_RETRIES="9", OCTOPUS_CODEX_SANDBOX="danger-full-access",
                       OCTOPUS_CLAUDE_BIN="custom-claude --setting-sources project,local", REFINE_TEST_ROOT=str(root), PATH=binaries+os.pathsep+os.environ["PATH"])
    result = subprocess.run(args, env=environment, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    assert data["judge"] == "true", data
    assert data["advisor_disabled"] == "1" and data["advisor"] == "off", data
    assert data["retry"] == "0" and data["sandbox"] == "read-only", data
    assert data["claude"] == "custom-claude --setting-sources project,local --tools Read,Glob,Grep --strict-mcp-config --restricted --safe-mode", data
    assert data["argv"] == ["--timeout", "8", "probe-single", "codex:exact-model",
                            "--perspective-file", str(Path(data["cwd"])/"request.txt"), "round-0", "--output-dir", str(fixture.resolve())], data
    assert data["request"] == prompt.read_text()
    assert not Path(data["cwd"]).exists(), "staged input leaked after completion"
    denied = subprocess.run(args, env=dict(environment, TEST_BOUNDARY_FAILURE="1"), capture_output=True, text=True)
    assert denied.returncode == 2 and not denied.stdout, denied
    for ambient_timeout in ["600", "0"]:
        result = subprocess.run(args, env=dict(environment, OCTOPUS_AGENT_TIMEOUT=ambient_timeout),
                                capture_output=True, text=True, check=True)
        assert json.loads(result.stdout)["effective_timeout"] == "8", result.stdout
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
PY
then
    test_pass
else
    test_fail "refinement judge dispatch regression"
fi
test_summary
