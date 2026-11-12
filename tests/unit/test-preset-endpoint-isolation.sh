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
test_case "named preset models ignore generic-slot pins and preserve explicit choices"
if python3 - "$SCRIPT_DIR/../../scripts/helpers/openai-compatible-agent.py" <<'PYTEST'
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
model_envs = {"atlascloud": "ATLASCLOUD_MODEL", "cheaperinference": "CHEAPER_INFERENCE_MODEL",
              "uberllm": "UBERLLM_MODEL", "api-route": "API_ROUTE_MODEL", "litellm": "LITELLM_MODEL"}
for provider, cfg in module.PROVIDERS.items():
    for mode in ("generic-only", "provider", "octopus", "explicit"):
        env = {"OPENAI_COMPAT_MODEL": "generic/model", "OPENAI_COMPAT_BASE_URL": "https://generic.invalid/v1",
               cfg["api_key_env"]: "fixture"}
        argv = ["helper", "--provider", provider, "--cwd", str(Path.cwd()), "--prompt", "inert fixture"]
        expected = "generic/model" if provider == "generic" else None
        if mode in ("provider", "explicit") and provider != "generic":
            env[model_envs[provider]] = "preset/model"
            expected = "preset/model"
        if mode == "octopus" and provider != "generic":
            env["OCTOPUS_" + provider.upper().replace("-", "_") + "_MODEL"] = "preset/model"
            expected = "preset/model"
        if mode == "explicit":
            argv += ["--model", "explicit/model"]
            expected = "explicit/model"
        calls = []
        def fake_call(base_url, key, model, *args, **kwargs):
            calls.append(model)
            return {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}
        err = io.StringIO()
        with patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", argv), \
                patch.object(module, "api_call", fake_call), contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(err):
            rc = module.main()
        assert (rc, calls) == ((0, [expected]) if expected else (2, [])), (provider, mode, rc, calls)
        if expected is None:
            assert "OPENAI_COMPAT_MODEL" not in err.getvalue(), err.getvalue()
print("24 generic/preset/explicit model cases passed without network access")
PYTEST
then test_pass; else test_fail "generic model crossed preset boundary"; fi
for preset_pair in atlascloud:ATLASCLOUD_API_KEY cheaperinference:CHEAPER_INFERENCE_API_KEY uberllm:UBERLLM_API_KEY api-route:API_ROUTE_API_KEY; do
    preset="${preset_pair%%:*}"; key_name="${preset_pair#*:}"
    test_case "$preset admissions reject a model configured only for the generic slot"
    if env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/empty-home" "PLUGIN_DIR=$SCRIPT_DIR/../.." \
            "OCTO_ALLOWED_PROVIDERS=$preset" "${key_name}=fixture" OPENAI_COMPAT_MODEL=generic/model \
            bash -c '
        source "$PLUGIN_DIR/scripts/lib/model-resolver.sh"
        source "$PLUGIN_DIR/scripts/lib/dispatch.sh"
        source "$PLUGIN_DIR/scripts/lib/preflight.sh"
        log() { :; }
        resolve_provider_env() { return 1; }
        preset="$1"
        ! get_agent_command "$preset-agent" review code-reviewer >/dev/null 2>&1 &&
        ! is_agent_available_v2 "$preset-agent" &&
        ! check_provider_health "$preset" >/dev/null 2>&1 &&
        [[ "$(_octo_provider_static_readiness "$preset")" != available\|ready\|* ]] &&
        [[ "$(detect_providers 2>/dev/null)" != *"$preset:api-key"* ]]
    ' _ "$preset"; then test_pass; else test_fail "generic pin admitted $preset"; fi
done
test_summary
