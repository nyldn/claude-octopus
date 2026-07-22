#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT_DIR/scripts/helpers/openai-compatible-agent.py"

log() { :; }
migrate_provider_config() { :; }
validate_model_allowed() { return 0; }
opus_default_model() { echo "claude-opus-4.8"; }
PROVIDER_CODEX_INSTALLED=false
PLUGIN_DIR="$ROOT_DIR"
PWD="/tmp/octopus-review"

source "$ROOT_DIR/scripts/lib/model-resolver.sh"
source "$ROOT_DIR/scripts/lib/dispatch.sh"
source "$ROOT_DIR/scripts/lib/utils.sh"

"$ROOT_DIR/scripts/helpers/openai-compatible-agent.sh" --help >/dev/null || {
    echo "FAIL: Git Bash wrapper did not translate its MSYS helper path for native Python" >&2
    exit 1
}

glm_cmd="$(get_agent_command openrouter-glm52 review reviewer)"
kimi_cmd="$(get_agent_command openrouter-kimi-k3 review reviewer)"

for spec in \
    "$glm_cmd|z-ai/glm-5.2" \
    "$kimi_cmd|moonshotai/kimi-k3"; do
    cmd="${spec%%|*}"
    model="${spec#*|}"
    [[ "$cmd" == *"scripts/helpers/openai-compatible-agent.sh"* ]] || {
        echo "FAIL: OpenRouter $model does not use the structured tool-loop helper" >&2
        exit 1
    }
    [[ "$cmd" == *"--provider openrouter"* ]] || {
        echo "FAIL: OpenRouter $model does not select the OpenRouter transport" >&2
        exit 1
    }
    [[ "$cmd" == *"--model $model"* ]] || {
        echo "FAIL: OpenRouter command lost exact model $model" >&2
        exit 1
    }
    [[ "$cmd" == *"--tool-mode readonly"* ]] || {
        echo "FAIL: OpenRouter review alias is not fail-closed read-only" >&2
        exit 1
    }
    validate_agent_command "$cmd" || {
        echo "FAIL: generated OpenRouter tool-loop command is rejected by command validation" >&2
        exit 1
    }
done

case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*) PYTHON_BIN=python ;;
    *) PYTHON_BIN=python3 ;;
esac

HELPER="$HELPER" "$PYTHON_BIN" - <<'PYTEST'
import importlib.util
import os

path = os.environ["HELPER"]
spec = importlib.util.spec_from_file_location("octopus_openrouter_agent", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert mod.PROVIDERS["openrouter"]["base_url"] == "https://openrouter.ai/api/v1"
assert mod.PROVIDERS["openrouter"]["api_key_env"] == "OPENROUTER_API_KEY"
if os.name == "nt":
    assert mod.normalize_cli_path("/c/Users/Wado/project") == r"C:\Users\Wado\project"
    assert mod.normalize_cli_path("/cygdrive/d/work") == r"D:\work"
else:
    assert mod.normalize_cli_path("/c/Users/Wado/project") == "/c/Users/Wado/project"

readonly_names = {
    item["function"]["name"] for item in mod.tools_for_mode("readonly")
}
assert {"read_file", "list_files", "git_status", "git_diff"} <= readonly_names
assert "write_file" not in readonly_names
assert "run_command" not in readonly_names

assert mod.is_unevaluated_tool_text(
    "I'll inspect the diff now.<tool_call>Bashgit diff --stat"
)
assert not mod.is_unevaluated_tool_text(
    "P1 src/app.py:10: boundary condition is inverted."
)

# Exercise main's recovery path: plain-text pseudo call -> structured read tool
# -> visible verdict. This is the exact shape of the live GLM failure.
import contextlib
import io
import sys
import tempfile

responses = [
    {"choices": [{"message": {"content": "I'll inspect now.<tool_call>Bashgit status"}, "finish_reason": "stop"}]},
    {"choices": [{"message": {"content": "", "tool_calls": [{"id": "call-1", "type": "function", "function": {"name": "git_status", "arguments": "{}"}}]}, "finish_reason": "tool_calls"}]},
    {"choices": [{"message": {"content": "NO FINDINGS"}, "finish_reason": "stop"}]},
]
seen_tools = []

def fake_api_call(*args, **kwargs):
    seen_tools.append({item["function"]["name"] for item in kwargs["tools"]})
    return responses.pop(0)

mod.api_call = fake_api_call
os.environ["OPENROUTER_API_KEY"] = "test-key"
with tempfile.TemporaryDirectory() as cwd:
    old_argv = sys.argv
    sys.argv = [
        "openai-compatible-agent.py", "--provider", "openrouter",
        "--model", "z-ai/glm-5.2", "--cwd", cwd,
        "--tool-mode", "readonly", "--max-turns", "4",
        "--prompt", "Review the current diff.",
    ]
    stdout = io.StringIO()
    try:
        with contextlib.redirect_stdout(stdout):
            rc = mod.main()
    finally:
        sys.argv = old_argv

assert rc == 0
assert stdout.getvalue().strip() == "NO FINDINGS"
assert len(seen_tools) == 3
assert all("git_status" in names for names in seen_tools)
assert all("write_file" not in names and "run_command" not in names for names in seen_tools)

# Windows redirected stdout defaults to a legacy code page on some systems.
# Kimi commonly returns symbols outside cp1252; the helper must emit UTF-8.
raw = io.BytesIO()
legacy_stdout = io.TextIOWrapper(raw, encoding="cp1252")
mod.configure_utf8_stdio(legacy_stdout)
legacy_stdout.write("Kimi verdict: ❌")
legacy_stdout.flush()
assert raw.getvalue().decode("utf-8") == "Kimi verdict: ❌"

prompt_bytes = io.BytesIO("Prompt marker: ❌".encode("utf-8"))
legacy_stdin = io.TextIOWrapper(prompt_bytes, encoding="cp1252")
mod.configure_utf8_stdio(legacy_stdin)
assert legacy_stdin.read() == "Prompt marker: ❌"
PYTEST

source "$ROOT_DIR/scripts/lib/error-tracking.sh"
pseudo_output="$(mktemp)"
trap 'rm -f "$pseudo_output"' EXIT
printf '%s\n' "I'll inspect the diff now.<tool_call>Bashgit diff --stat" > "$pseudo_output"
classification="$(classify_agent_output "$pseudo_output" 0 openrouter-glm52)"
if [[ "$classification" != failed:* ]]; then
    echo "FAIL: unevaluated OpenRouter tool text was classified as $classification" >&2
    exit 1
fi

grep -q "tr -d '\\\\000'.*grep -a -v" "$ROOT_DIR/scripts/lib/spawn.sh" || {
    echo "FAIL: spawn output filtering can replace Unicode provider output with a binary-file notice" >&2
    exit 1
}

echo "PASS: OpenRouter aliases use a read-only structured tool loop"
