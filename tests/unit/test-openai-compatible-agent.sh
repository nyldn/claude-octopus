#!/usr/bin/env bash
# Tests for OpenAI-compatible tool-loop agent dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OpenAI-compatible tool-loop agent"

# Keep cache-key assertions independent of the caller's configured cost mode.
unset OCTOPUS_COST_MODE

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
DISPATCH="$PROJECT_ROOT/scripts/lib/dispatch.sh"
HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py"

log() { :; }
migrate_provider_config() { :; }
validate_model_allowed() { return 0; }
opus_default_model() { echo "claude-opus-4.8"; }
PROVIDER_CODEX_INSTALLED="false"

if bash -n "$DISPATCH" "$MODEL_RESOLVER" && python3 -m py_compile "$HELPER"; then
    pass "agent scripts have valid syntax"
else
    fail "agent scripts have valid syntax" "syntax error"
fi

test_case "openai-compatible agent blocks quoted home-directory deletes"
if python3 - "$HELPER" <<'PY'
import importlib.util
from pathlib import Path
import sys

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("openai_compatible_agent", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

blocked = (
    'rm -rf "$HOME"',
    "rm -rf '${HOME}'",
    'rm -fr "${HOME}/cache"',
    'rm -rf "$HOME"/cache',
    'rm -rf "${HOME}"/cache',
    "rm --recursive --force /Users/example",
)
assert all(module.command_is_blocked(command) for command in blocked)
assert module.command_is_blocked("rm -rf relative-cache") is None
PY
then
    test_pass
else
    test_fail "quoted or braced home-directory delete bypassed the command guardrail"
fi

TEST_HOME="$TEST_TMP_DIR/home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"
source "$DISPATCH"

export PLUGIN_DIR="$PROJECT_ROOT"
export OPENAI_COMPAT_BASE_URL="https://example.invalid/v1"
export OPENAI_API_KEY="test-key"

test_case "openai-compatible-agent honors OPENAI_COMPAT_MODEL"
model=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-agent" OPENAI_COMPAT_MODEL="vendor/model-pro" get_agent_model openai-compatible-agent 2>/dev/null)
if [[ "$model" == "vendor/model-pro" ]]; then
    test_pass
else
    test_fail "expected vendor/model-pro, got ${model:-<empty>}"
fi

test_case "openai-compatible-agent is available with default OPENAI_API_KEY"
if OPENAI_COMPAT_BASE_URL="https://example.invalid/v1" OPENAI_API_KEY="test-key" is_agent_available_v2 openai-compatible-agent; then
    test_pass
else
    test_fail "expected default OPENAI_API_KEY configuration to be available"
fi

test_case "openai-compatible-agent dispatch uses generic helper and cwd"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-cmd" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-compatible-agent 2>/dev/null)
if assert_contains "$cmd" "scripts/helpers/openai-compatible-agent.py" "helper path" &&
   assert_contains "$cmd" "--provider generic" "generic provider" &&
   assert_contains "$cmd" "--model vendor/model-fast" "configured model" &&
   assert_contains "$cmd" "--cwd /tmp/octo-cwd" "cwd flag"; then
    test_pass
fi

test_case "qualified openai-compatible seat uses provider-file runtime config and exact model"
CONFIG_ONLY_HOME="$TEST_TMP_DIR/config-only-home"
mkdir -p "$CONFIG_ONLY_HOME/.claude-octopus/config"
cat > "$CONFIG_ONLY_HOME/.claude-octopus/config/providers.json" <<'JSON'
{
  "version": "3.0",
  "providers": {
    "openai-compatible-agent": {
      "base_url": "https://config-only.invalid/v1",
      "api_key_env": "CONFIG_ONLY_COMPAT_KEY"
    }
  }
}
JSON
qualified_cmd="$({
    unset OPENAI_COMPAT_BASE_URL OPENAI_COMPAT_API_KEY_ENV OPENAI_API_KEY
    HOME="$CONFIG_ONLY_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-qualified" \
      CONFIG_ONLY_COMPAT_KEY="config-key" \
      get_agent_command 'openai-compatible-agent:vendor/exact-model' review code-reviewer
} 2>/dev/null || true)"
if assert_contains "$qualified_cmd" "--base-url https://config-only.invalid/v1" "provider-file base URL" &&
   assert_contains "$qualified_cmd" "--api-key-env CONFIG_ONLY_COMPAT_KEY" "provider-file credential name" &&
   assert_contains "$qualified_cmd" "--model vendor/exact-model" "exact qualified model"; then
    test_pass
fi

test_case "openai-compatible review dispatch disables model tools"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-review-no-tools" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-compatible-agent review code-reviewer 2>/dev/null)
if assert_contains "$cmd" "--tool-policy none" "review tool policy"; then
    test_pass
fi

test_case "OpenAI-compatible constrained role disables model tools outside review"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-role-no-tools" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-compatible-agent implementation code-reviewer 2>/dev/null)
if assert_contains "$cmd" "--tool-policy none" "constrained role tool policy"; then
    test_pass
fi

test_case "Atlas review dispatch disables model tools"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="atlas-review-no-tools" PWD="/tmp/octo-cwd" ATLASCLOUD_MODEL="qwen/model" get_agent_command atlascloud-agent review code-reviewer 2>/dev/null)
if assert_contains "$cmd" "--provider atlascloud" "Atlas provider" &&
   assert_contains "$cmd" "--tool-policy none" "Atlas review tool policy"; then
    test_pass
fi

test_case "Atlas readonly persona disables model tools outside review"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="atlas-role-no-tools" PWD="/tmp/octo-cwd" ATLASCLOUD_MODEL="qwen/model" get_agent_command atlascloud-agent implementation backend-architect 2>/dev/null)
if assert_contains "$cmd" "--tool-policy none" "Atlas readonly persona policy"; then
    test_pass
fi

test_case "write-capable tool-loop roles retain tools"
generic_cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-write-tools" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-compatible-agent implementation implementer 2>/dev/null)
atlas_cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="atlas-write-tools" PWD="/tmp/octo-cwd" ATLASCLOUD_MODEL="qwen/model" get_agent_command atlascloud-agent implementation implementer 2>/dev/null)
if [[ "$generic_cmd" == *"--tool-policy none"* || "$atlas_cmd" == *"--tool-policy none"* ]]; then
    test_fail "write-capable implementer unexpectedly lost tool access"
else
    test_pass
fi


test_case "openai-compatible-agent rejects unsafe model names before dispatch"
if HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-cmd-unsafe" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="bad;touch" get_agent_command openai-compatible-agent unsafe-phase >/dev/null 2>&1; then
    test_fail "expected unsafe OPENAI_COMPAT_MODEL to be rejected"
else
    test_pass
fi


test_case "openai-compatible-agent rejects unsafe cwd before dispatch"
if HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-cwd-unsafe" PWD="/tmp/octo cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-compatible-agent cwd-phase >/dev/null 2>&1; then
    test_fail "expected unsafe PWD to be rejected"
else
    test_pass
fi


test_case "openai-compatible-agent rejects model env override metacharacters"
if HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-env-unsafe" OCTOPUS_OPENAI_COMPATIBLE_AGENT_MODEL="bad;touch" get_agent_model openai-compatible-agent env-phase >/dev/null 2>&1; then
    test_fail "expected unsafe OCTOPUS_OPENAI_COMPATIBLE_AGENT_MODEL to be rejected"
else
    test_pass
fi


test_case "openai-compatible-agent rejects invalid allowlist fallback model"
if HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-fallback-unsafe" OPENAI_COMPAT_MODEL="vendor/model-fast" OPENAI_COMPAT_ALLOWED_MODELS="/tmp/model" get_agent_model openai-compatible-agent fallback-phase >/dev/null 2>&1; then
    test_fail "expected invalid allowlist fallback model to be rejected"
else
    test_pass
fi


test_case "openai-compatible-agent reads valid memory cache and clears unsafe entries"
cache_key="MC_openai_compatible_agent_A_openai_compatible_agent_P_memcache_R__M_standard_RP_off_TC_none_C_no_config"
cache_var="_OCTO_MODEL_CACHE_${cache_key}"
out_file="$TEST_TMP_DIR/openai-compatible-memory-cache-model.out"
printf -v "$cache_var" "%s" "vendor/model-fast"
if ! HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-memcache" resolve_octopus_model openai-compatible-agent openai-compatible-agent memcache "" >"$out_file" 2>/dev/null; then
    test_fail "expected resolver to read valid memory cache entry"
elif [[ "$(cat "$out_file")" != "vendor/model-fast" ]]; then
    test_fail "expected resolver to return the seeded valid memory cache entry"
else
    printf -v "$cache_var" "%s" "bad;touch"
    if HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-memcache" resolve_octopus_model openai-compatible-agent openai-compatible-agent memcache "" >"$out_file" 2>/dev/null; then
        test_fail "expected resolver to fail closed after rejecting an unsafe cache entry without an explicit generic model"
    elif [[ "$(cat "$out_file")" == "bad;touch" ]]; then
        test_fail "expected unsafe memory cache model not to be returned"
    elif [[ -n "${!cache_var:-}" ]]; then
        test_fail "expected unsafe memory cache entry to be cleared after being read"
    else
        test_pass
    fi
fi
unset "$cache_var" 2>/dev/null || true


test_case "openai-compatible-agent rejects model names with backslashes"
if HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-backslash" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL='vendor/model\' get_agent_command openai-compatible-agent backslash-phase >/dev/null 2>&1; then
    test_fail "expected model ending in backslash to be rejected"
else
    test_pass
fi


test_case "openai-compatible-agent omits max_tokens when configured as provider default"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, json, os
helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
seen = []
class Response:
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"ok"}}]}'
def fake_urlopen(req, timeout):
    seen.append(json.loads(req.data.decode()))
    return Response()
mod.open_credentialed_request = fake_urlopen
mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], request_timeout=1, max_retries=1)
assert "max_tokens" not in seen[-1], seen[-1]
mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=0, request_timeout=1, max_retries=1)
assert "max_tokens" not in seen[-1], seen[-1]
mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=123, request_timeout=1, max_retries=1)
assert seen[-1]["max_tokens"] == 123, seen[-1]
PYTEST
then
    test_pass
else
    test_fail "expected provider-default and max_tokens=0 to omit max_tokens from request payload"
fi

test_case "openai-compatible-agent omits tools in no-tools mode"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, json, os
helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent_no_tools", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
seen = []
class Response:
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"ok"}}]}'
def fake_urlopen(req, timeout):
    seen.append(json.loads(req.data.decode()))
    return Response()
mod.open_credentialed_request = fake_urlopen
messages = [{"role":"user","content":"review"}]
mod.api_call("https://example.invalid/v1", "key", "model", {}, messages, request_timeout=1, max_retries=1, tool_policy="none")
assert "tools" not in seen[-1], seen[-1]
assert "tool_choice" not in seen[-1], seen[-1]
mod.api_call("https://example.invalid/v1", "key", "model", {}, messages, request_timeout=1, max_retries=1, tool_policy="auto")
assert seen[-1]["tools"], seen[-1]
assert seen[-1]["tool_choice"] == "auto", seen[-1]
PYTEST
then
    test_pass
else
    test_fail "no-tools mode still exposed file or shell tools to the review model"
fi

test_case "OpenAI-compatible Astra guard recognizes provider namespaces"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, os
helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent_astra", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.is_astra_model("gpt-6-astra")
assert mod.is_astra_model("openai/gpt-6-astra")
assert mod.is_astra_model("openrouter:openai/gpt-6-astra")
assert not mod.is_astra_model("gpt-6-astra-preview")
PYTEST
then
    test_pass
else
    test_fail "provider namespace bypassed the Astra Chat Completions guard"
fi


test_case "openai-compatible-agent main treats unset and zero as provider default"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, os, pathlib, sys, tempfile

helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent_main_tokens", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

seen = []
def fake_api_call(*args, **kwargs):
    seen.append(kwargs.get("max_tokens"))
    return {"choices": [{"message": {"content": "ok"}, "finish_reason": "stop"}]}
mod.api_call = fake_api_call

with tempfile.TemporaryDirectory() as cwd:
    base_argv = [
        "openai-compatible-agent.py",
        "--provider", "generic",
        "--base-url", "https://example.invalid/v1",
        "--api-key-env", "TEST_PROVIDER_KEY",
        "--model", "vendor/model",
        "--cwd", cwd,
        "--prompt", "verify",
    ]
    old_argv = sys.argv[:]
    old_key = os.environ.get("TEST_PROVIDER_KEY")
    old_limit = os.environ.get("OPENAI_COMPAT_MAX_TOKENS")
    try:
        os.environ["TEST_PROVIDER_KEY"] = "test-key"

        os.environ.pop("OPENAI_COMPAT_MAX_TOKENS", None)
        sys.argv = base_argv
        assert mod.main() == 0
        assert seen[-1] == 0, seen

        os.environ["OPENAI_COMPAT_MAX_TOKENS"] = "0"
        sys.argv = base_argv
        assert mod.main() == 0
        assert seen[-1] == 0, seen

        os.environ["OPENAI_COMPAT_MAX_TOKENS"] = "4096"
        sys.argv = base_argv
        assert mod.main() == 0
        assert seen[-1] == 4096, seen
    finally:
        sys.argv = old_argv
        if old_key is None:
            os.environ.pop("TEST_PROVIDER_KEY", None)
        else:
            os.environ["TEST_PROVIDER_KEY"] = old_key
        if old_limit is None:
            os.environ.pop("OPENAI_COMPAT_MAX_TOKENS", None)
        else:
            os.environ["OPENAI_COMPAT_MAX_TOKENS"] = old_limit
PYTEST
then
    test_pass
else
    test_fail "expected main() to omit provider limit for unset/0 and forward positive overrides"
fi

test_case "openai-compatible-agent does not impose an Octopus turn cap"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, os, sys, tempfile

helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent_no_turn_cap", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

calls = {"n": 0}
def fake_api_call(*args, **kwargs):
    calls["n"] += 1
    if calls["n"] <= 25:
        return {
            "choices": [{
                "message": {
                    "content": "",
                    "tool_calls": [{
                        "id": "call-" + str(calls["n"]),
                        "function": {"name": "git_diff", "arguments": "{}"},
                    }],
                },
                "finish_reason": "tool_calls",
            }]
        }
    return {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}

mod.api_call = fake_api_call
mod.tool_exec = lambda *args, **kwargs: "ok"

with tempfile.TemporaryDirectory() as cwd:
    old_argv = sys.argv[:]
    old_key = os.environ.get("TEST_PROVIDER_KEY")
    try:
        os.environ["TEST_PROVIDER_KEY"] = "test-key"
        sys.argv = [
            "openai-compatible-agent.py",
            "--provider", "generic",
            "--base-url", "https://example.invalid/v1",
            "--api-key-env", "TEST_PROVIDER_KEY",
            "--model", "vendor/model",
            "--cwd", cwd,
            "--prompt", "verify",
        ]
        assert mod.main() == 0
        assert calls["n"] == 26, calls
    finally:
        sys.argv = old_argv
        if old_key is None:
            os.environ.pop("TEST_PROVIDER_KEY", None)
        else:
            os.environ["TEST_PROVIDER_KEY"] = old_key
PYTEST
then
    test_pass
else
    test_fail "expected the provider loop to continue past the former 20-turn Octopus cap"
fi

test_case "openai-compatible-agent retries transient HTTP errors"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, io, os, urllib.error
helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.time.sleep = lambda _seconds: None
calls = {"n": 0}
class Response:
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"ok"}}]}'
def fake_urlopen(req, timeout):
    calls["n"] += 1
    if calls["n"] == 1:
        raise urllib.error.HTTPError(req.full_url, 503, "unavailable", {}, io.BytesIO(b'temporary'))
    return Response()
mod.open_credentialed_request = fake_urlopen
result = mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=0, request_timeout=1, max_retries=2)
assert calls["n"] == 2, calls
assert result["choices"][0]["message"]["content"] == "ok"
PYTEST
then
    test_pass
else
    test_fail "expected transient HTTP failure to be retried"
fi


test_case "openai-compatible-agent rejects unsafe non-loopback URLs before transport"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util, os
helper_path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("openai_compatible_agent", helper_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for base_url, expected in (
    ("http://example.invalid/v1", "must use HTTPS"),
    ("file:///tmp/octopus", "unsupported OPENAI-compatible base URL scheme"),
):
    try:
        mod.api_call(base_url, "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=0, request_timeout=1, max_retries=1)
    except ValueError as exc:
        assert expected in str(exc), exc
    else:
        raise AssertionError(f"expected ValueError for {base_url}")
PYTEST
then
    test_pass
else
    test_fail "expected remote HTTP and non-HTTP base URLs to be rejected"
fi



test_case "OpenAI-compatible aliases are in AVAILABLE_AGENTS"
if grep "AVAILABLE_AGENTS=" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q " openai-compatible " && \
   grep "AVAILABLE_AGENTS=" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q " openai-tools "; then
    test_pass
else
    test_fail "expected openai-compatible and openai-tools aliases in AVAILABLE_AGENTS"
fi

test_case "openai-tools alias dispatches through generic helper"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-tools-alias" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-tools 2>/dev/null)
if assert_contains "$cmd" "scripts/helpers/openai-compatible-agent.py" "helper path" &&
   assert_contains "$cmd" "--provider generic" "generic provider" &&
   assert_contains "$cmd" "--model vendor/model-fast" "configured model"; then
    test_pass
fi

test_case "openai-compatible-agent forwards CLI reasoning policy"
if grep -q 'reasoning_policy=args.reasoning_policy' "$HELPER"; then
    test_pass
else
    test_fail "expected CLI reasoning policy to be forwarded to api_call"
fi

test_case "openai-compatible-agent logs requested reasoning safely"
if grep -q 'chat_reasoning requested=' "$HELPER"; then
    test_pass
else
    test_fail "expected reasoning request marker in stderr"
fi

test_case "run_command completes normally under process supervision"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util
import os
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("openai_compatible_agent_process_ok", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as cwd:
    result = mod.tool_exec(Path(cwd), "run_command", {"command": "printf supervised"})
assert result == "exit=0\nsupervised", result
PYTEST
then
    test_pass
else
    test_fail "normal command did not complete through the supervisor"
fi

test_case "run_command timeout prevents descendant late writes"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util
import os
import shlex
import sys
import tempfile
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location("openai_compatible_agent_process_late", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
old_timeout = os.environ.get("OPENAI_COMPAT_COMMAND_TIMEOUT")
try:
    os.environ["OPENAI_COMPAT_COMMAND_TIMEOUT"] = "0.1"
    with tempfile.TemporaryDirectory() as cwd:
        marker = Path(cwd, "late-write")
        child = "import time; from pathlib import Path; time.sleep(0.6); Path('late-write').write_text('late')"
        command = f"{shlex.quote(sys.executable)} -c {shlex.quote(child)} & sleep 5"
        result = mod.tool_exec(Path(cwd), "run_command", {"command": command})
        assert result.startswith("ERROR: TimeoutExpired:"), result
        time.sleep(0.8)
        assert not marker.exists(), marker
finally:
    if old_timeout is None:
        os.environ.pop("OPENAI_COMPAT_COMMAND_TIMEOUT", None)
    else:
        os.environ["OPENAI_COMPAT_COMMAND_TIMEOUT"] = old_timeout
PYTEST
then
    test_pass
else
    test_fail "timed-out descendant wrote after the tool returned"
fi

test_case "run_command escalates and reaps a TERM-resistant descendant"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util
import os
import shlex
import sys
import tempfile
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location("openai_compatible_agent_process_resistant", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
old_timeout = os.environ.get("OPENAI_COMPAT_COMMAND_TIMEOUT")
old_grace = os.environ.get("OPENAI_COMPAT_COMMAND_KILL_GRACE")
try:
    os.environ["OPENAI_COMPAT_COMMAND_TIMEOUT"] = "0.1"
    os.environ["OPENAI_COMPAT_COMMAND_KILL_GRACE"] = "0.1"
    with tempfile.TemporaryDirectory() as cwd:
        marker = Path(cwd, "resistant-write")
        child = (
            "import signal,time; from pathlib import Path; "
            "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "time.sleep(0.6); Path('resistant-write').write_text('late')"
        )
        command = f"{shlex.quote(sys.executable)} -c {shlex.quote(child)} & sleep 5"
        started = time.monotonic()
        result = mod.tool_exec(Path(cwd), "run_command", {"command": command})
        elapsed = time.monotonic() - started
        assert result.startswith("ERROR: TimeoutExpired:"), result
        assert elapsed < 1.5, elapsed
        time.sleep(0.8)
        assert not marker.exists(), marker
finally:
    if old_timeout is None:
        os.environ.pop("OPENAI_COMPAT_COMMAND_TIMEOUT", None)
    else:
        os.environ["OPENAI_COMPAT_COMMAND_TIMEOUT"] = old_timeout
    if old_grace is None:
        os.environ.pop("OPENAI_COMPAT_COMMAND_KILL_GRACE", None)
    else:
        os.environ["OPENAI_COMPAT_COMMAND_KILL_GRACE"] = old_grace
PYTEST
then
    test_pass
else
    test_fail "TERM-resistant descendant survived timeout escalation"
fi

test_case "process supervisor bounds output while preserving the tail"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util
import os
import shlex
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("openai_compatible_agent_process_output", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as cwd:
    script = "import sys; sys.stdout.write('x' * 100000 + 'TAIL'); sys.stdout.flush()"
    command = f"{shlex.quote(sys.executable)} -c {shlex.quote(script)}"
    returncode, output = mod.run_bounded_process(command, Path(cwd), 2, shell=True, output_limit=1024)
assert returncode == 0, returncode
assert len(output.encode("utf-8")) <= 1024, len(output)
assert output.endswith("TAIL"), output[-20:]
PYTEST
then
    test_pass
else
    test_fail "process output was not bounded during execution"
fi

test_case "normal shell exit does not orphan a detached-output descendant"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util
import os
import shlex
import sys
import tempfile
import time
from pathlib import Path

if os.name != "posix":
    raise SystemExit(0)
spec = importlib.util.spec_from_file_location("openai_compatible_agent_process_orphan", os.environ["HELPER"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as cwd:
    child = "import time; from pathlib import Path; time.sleep(0.5); Path('orphan-write').write_text('late')"
    launcher = (
        "import subprocess,sys; "
        f"subprocess.Popen([sys.executable, '-c', {child!r}], "
        "stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)"
    )
    command = f"{shlex.quote(sys.executable)} -c {shlex.quote(launcher)}"
    returncode, _ = mod.run_bounded_process(command, Path(cwd), 2, shell=True, output_limit=1024)
    assert returncode == 0, returncode
    time.sleep(0.7)
    assert not Path(cwd, "orphan-write").exists()
PYTEST
then
    test_pass
else
    test_fail "successful shell exit left a descendant running"
fi

test_case "caller interruption cancels an output-producing descendant"
if HELPER="$HELPER" python3 - <<'PYTEST'
import importlib.util
import os
import shlex
import signal
import sys
import tempfile
import time
from pathlib import Path

if os.name != "posix":
    raise SystemExit(0)
helper = os.environ["HELPER"]

with tempfile.TemporaryDirectory() as cwd:
    worker = os.fork()
    if worker == 0:
        spec = importlib.util.spec_from_file_location("openai_compatible_agent_process_interrupt", helper)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        child = """
import sys
import time
from pathlib import Path

Path("ready").write_text("1")
for _ in range(200):
    sys.stdout.write("chunk\\n")
    sys.stdout.flush()
    time.sleep(0.01)
Path("late-interrupt").write_text("late")
"""
        command = f"{shlex.quote(sys.executable)} -c {shlex.quote(child)}"
        try:
            mod.run_bounded_process(command, Path(cwd), 10, shell=True, output_limit=1024)
        except KeyboardInterrupt:
            os._exit(42)
        os._exit(0)
    ready = Path(cwd, "ready")
    deadline = time.monotonic() + 2
    while not ready.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert ready.exists(), "supervised child did not start"
    os.kill(worker, signal.SIGINT)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        waited, status = os.waitpid(worker, os.WNOHANG)
        if waited:
            break
        time.sleep(0.01)
    else:
        os.kill(worker, signal.SIGKILL)
        os.waitpid(worker, 0)
        raise AssertionError("supervisor did not exit after interruption")
    assert os.waitstatus_to_exitcode(status) == 42, status
    time.sleep(0.5)
    assert not Path(cwd, "late-interrupt").exists()
PYTEST
then
    test_pass
else
    test_fail "caller interruption left a descendant running"
fi

test_summary
