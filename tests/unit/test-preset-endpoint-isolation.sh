#!/usr/bin/env bash
# Exercise actual helper argument/env selection without a network request.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Named preset endpoint isolation"
test_case "preset endpoint and credentials ignore generic-slot configuration"
if python3 - "$SCRIPT_DIR/../../scripts/helpers/openai-compatible-agent.py" <<'PY'
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("compat_agent", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for provider, cfg in module.PROVIDERS.items():
    for explicit in (False, True):
        env = {"OPENAI_COMPAT_BASE_URL": "https://generic.invalid/v1",
               "OPENAI_COMPAT_API_KEY_ENV": "GENERIC_TEST_KEY",
               "GENERIC_TEST_KEY": "generic-fixture",
               cfg["api_key_env"]: "preset-fixture",
               "EXPLICIT_TEST_KEY": "explicit-fixture"}
        expected_url = cfg["base_url"] if provider != "generic" else env["OPENAI_COMPAT_BASE_URL"]
        expected_key = "preset-fixture" if provider != "generic" else "generic-fixture"
        argv = ["helper", "--provider", provider, "--cwd", str(Path.cwd()),
                "--prompt", "inert fixture", "--model", "vendor/model"]
        if explicit:
            argv += ["--base-url", "https://explicit.invalid/v1", "--api-key-env", "EXPLICIT_TEST_KEY"]
            expected_url, expected_key = "https://explicit.invalid/v1", "explicit-fixture"
        calls = []
        def fake_call(base_url, key, *args, **kwargs):
            calls.append((base_url, key))
            return {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}
        with patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", argv), \
                patch.object(module, "api_call", fake_call), contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            assert module.main() == 0, provider
        assert calls == [(expected_url, expected_key)], (provider, explicit, calls)
print("12 preset/generic/explicit cases passed")
PY
then test_pass; else test_fail "generic configuration crossed preset boundary"; fi
test_summary
