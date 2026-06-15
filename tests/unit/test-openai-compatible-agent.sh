#!/usr/bin/env bash
# Tests for OpenAI-compatible tool-loop agent dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OpenAI-compatible tool-loop agent"

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

TEST_HOME="$TEST_TMP_DIR/home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"
source "$DISPATCH"

export PLUGIN_DIR="$PROJECT_ROOT"

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
mod.urllib.request.urlopen = fake_urlopen
mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=0, request_timeout=1, max_retries=1)
assert "max_tokens" not in seen[-1], seen[-1]
mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=123, request_timeout=1, max_retries=1)
assert seen[-1]["max_tokens"] == 123, seen[-1]
PYTEST
then
    test_pass
else
    test_fail "expected max_tokens=0 to omit max_tokens from request payload"
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
mod.urllib.request.urlopen = fake_urlopen
result = mod.api_call("https://example.invalid/v1", "key", "model", {}, [{"role":"user","content":"hi"}], max_tokens=0, request_timeout=1, max_retries=2)
assert calls["n"] == 2, calls
assert result["choices"][0]["message"]["content"] == "ok"
PYTEST
then
    test_pass
else
    test_fail "expected transient HTTP failure to be retried"
fi


test_summary
