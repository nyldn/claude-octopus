#!/usr/bin/env python3
"""Offline admission and credential-isolation regressions for custom presets."""

import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts/helpers" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


config_module = load_module("custom_provider_config", "custom_provider_config.py")
agent = load_module("custom_provider_agent", "openai-compatible-agent.py")


class CustomProviderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config_path = Path(self.tmp.name) / "providers.json"
        self.preset = {
            "type": "openai-compatible", "base_url": "https://vendor.invalid/v1",
            "api_key_env": "VENDOR_API_KEY", "default_model": "vendor/model",
            "allowed_models": ["vendor/model", "vendor/other"], "council": False,
            "pricing": {"input": 1.0, "output": 5.0},
        }
        self.env = {
            "OCTOPUS_PROVIDERS_CONFIG": str(self.config_path),
            "VENDOR_API_KEY": "selected-fixture", "OTHER_API_KEY": "unrelated-fixture",
            "OPENAI_COMPAT_BASE_URL": "https://other.invalid/v1",
            "OPENAI_COMPAT_MODEL": "other/model", "OPENAI_COMPAT_API_KEY_ENV": "OTHER_API_KEY",
            "BASH_ENV": "/untrusted/fixture", "PYTHONPATH": "/untrusted/python",
            "PATH": os.environ["PATH"], "HOME": self.tmp.name,
        }
        self.write_config()

    def write_config(self, preset=None):
        self.config_path.write_text(json.dumps({"custom_providers": {
            "vendor": self.preset if preset is None else preset,
        }}), encoding="utf-8")

    def invoke(self, *flags, env=None, response=None):
        calls = []

        def transport(base_url, key, model, *args, **kwargs):
            calls.append((base_url, key, model, dict(os.environ), kwargs))
            return response or {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}

        output, errors = io.StringIO(), io.StringIO()
        argv = ["helper", "--custom-provider", "vendor", "--cwd", self.tmp.name,
                "--prompt", "inert fixture", *flags]
        with patch.dict(os.environ, self.env if env is None else env, clear=True), \
                patch.object(sys, "argv", argv), patch.object(agent, "api_call", transport), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = agent.main()
        return result, calls, output.getvalue(), errors.getvalue()

    def test_default_and_explicit_models_use_only_selected_credential(self):
        for flags, model in (((), "vendor/model"), (("--model", "vendor/other"), "vendor/other")):
            with self.subTest(model=model):
                result, calls, output, errors = self.invoke(*flags)
                self.assertEqual(result, 0)
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0][:3], (self.preset["base_url"], "selected-fixture", model))
                self.assertEqual(set(calls[0][3]), {"VENDOR_API_KEY", "PATH", "HOME"})
                self.assertIn("provider=vendor", errors)
                self.assertIn("done", output)
                self.assertNotIn("selected-fixture", output + errors)

    def test_rejects_cross_vendor_overrides_without_transport(self):
        for flags in (("--model", "other/model"), ("--base-url", "https://other.invalid/v1"),
                      ("--api-key-env", "OTHER_API_KEY")):
            with self.subTest(flags=flags):
                result, calls, _, _ = self.invoke(*flags)
                self.assertEqual((result, calls), (2, []))

    def test_missing_or_whitespace_key_does_not_call_transport(self):
        for key in (None, "", " \t\n"):
            env = dict(self.env)
            if key is None:
                env.pop("VENDOR_API_KEY")
            else:
                env["VENDOR_API_KEY"] = key
            with self.subTest(key=key):
                self.assertEqual(self.invoke(env=env)[:2], (2, []))

    def test_invalid_presets_fail_before_transport(self):
        invalid = {
            "type": [None, "shell", 1],
            "base_url": [None, "http://remote.invalid/v1", "https://user:secret@remote.invalid/v1",
                         "http://localhost@remote.invalid/v1", "https://remote.invalid/v1?key=secret",
                         "https://remote.invalid/v1#secret", "https://remote.invalid:99999/v1",
                         "https://remote.invalid/\nheader", "file:///tmp/fixture"],
            "api_key_env": [None, "PATH", "BASH_ENV", "BAD-KEY", "KEENABLE_API_KEY"],
            "allowed_models": [None, [], ["a", "a"], ["vendor/model", "a,b"],
                               ["vendor/model", "a b"], ["vendor/model", "$(shell)"], [True]],
            "default_model": [None, "other/model", True],
            "council": [True, 1, "false"],
            "pricing": [{}, {"input": True, "output": 1}, {"input": -1, "output": 1},
                        {"input": float("nan"), "output": 1}, {"input": 1, "output": float("inf")}],
        }
        for field, values in invalid.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    preset = copy.deepcopy(self.preset)
                    preset[field] = value
                    self.write_config(preset)
                    result, calls, output, errors = self.invoke()
                    self.assertEqual((result, calls), (2, []))
                    self.assertNotIn("secret", output + errors)

    def test_loopback_http_and_absent_pricing_are_admitted(self):
        for url in ("http://localhost:4000/v1", "http://127.0.0.1:4000/v1"):
            with self.subTest(url=url):
                preset = dict(self.preset, base_url=url)
                preset.pop("pricing")
                self.write_config(preset)
                self.assertEqual(self.invoke()[0], 0)

    def test_admission_matches_real_transport_endpoint_policy(self):
        for url, expected in (("https://vendor.invalid/v1", 0),
                              ("http://localhost:4000/v1", 0),
                              ("http://127.0.0.1:4000/v1", 0),
                              ("http://[::1]:4000/v1", 2)):
            with self.subTest(url=url):
                self.write_config(dict(self.preset, base_url=url))
                if expected != 0:
                    with patch.dict(os.environ, self.env, clear=True), self.assertRaises(ValueError):
                        config_module.load_custom_provider("vendor")
                argv = ["helper", "--custom-provider", "vendor", "--cwd", self.tmp.name,
                        "--prompt", "fixture", "--tool-policy", "none"]
                response = {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}
                with patch.dict(os.environ, self.env, clear=True), patch.object(sys, "argv", argv), \
                        patch.object(agent, "open_credentialed_request", return_value=io.BytesIO(json.dumps(response).encode())) as opener, \
                        contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(agent.main(), expected)
                self.assertEqual(opener.call_count, 1 if expected == 0 else 0)
                if expected == 0:
                    request = opener.call_args.args[0]
                    self.assertEqual(request.full_url, url + "/chat/completions")
                    self.assertEqual(request.get_header("Authorization"), "Bearer selected-fixture")
                    self.assertEqual(json.loads(request.data)["model"], "vendor/model")

    def test_missing_malformed_or_unconfigured_files_fail_closed(self):
        for contents in ("{", "[]", "{}", '{"custom_providers": []}', '{"custom_providers": {}}'):
            with self.subTest(contents=contents):
                self.config_path.write_text(contents, encoding="utf-8")
                self.assertEqual(self.invoke()[:2], (2, []))
        self.config_path.unlink()
        self.assertEqual(self.invoke()[:2], (2, []))

    def test_bad_names_are_rejected(self):
        with patch.dict(os.environ, self.env, clear=True):
            for name in ("../vendor", "vendor-agent:other", "vendor;cmd", "", "UPPER", "a" * 64):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    config_module.load_custom_provider(name)

    def test_builtin_path_does_not_read_custom_config(self):
        argv = ["helper", "--provider", "atlascloud", "--model", "vendor/model",
                "--cwd", self.tmp.name, "--prompt", "fixture"]
        response = {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}
        with patch.dict(os.environ, {"ATLASCLOUD_API_KEY": "fixture"}, clear=True), \
                patch.object(sys, "argv", argv), patch.object(agent, "api_call", return_value=response) as call, \
                patch.object(Path, "open", side_effect=AssertionError("unexpected config read")), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(agent.main(), 0)
            self.assertEqual(call.call_args.args[:3], (agent.PROVIDERS["atlascloud"]["base_url"], "fixture", "vendor/model"))

    def test_tool_subprocess_inherits_only_selected_key(self):
        # Exercise the real tool subprocess, rather than just inspecting env construction.
        environments = []
        count = 0

        def transport(*args, **kwargs):
            nonlocal count
            count += 1
            if count == 1:
                return {"choices": [{"message": {"tool_calls": [{"id": "fixture", "type": "function",
                    "function": {"name": "run_command", "arguments": json.dumps({
                        "command": "python3 -c 'import os; print(sorted(k for k in os.environ if k.endswith(\"_KEY\")))'"
                    })}}]}, "finish_reason": "tool_calls"}]}
            environments.append(args[4][-1]["content"])
            return {"choices": [{"message": {"content": "done"}, "finish_reason": "stop"}]}

        argv = ["helper", "--custom-provider", "vendor", "--cwd", self.tmp.name, "--prompt", "fixture"]
        with patch.dict(os.environ, self.env, clear=True), patch.object(sys, "argv", argv), \
                patch.object(agent, "api_call", transport), contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(agent.main(), 0)
        self.assertEqual(len(environments), 1)
        self.assertIn("['VENDOR_API_KEY']", environments[0])
        self.assertNotIn("OTHER_API_KEY", environments[0])


if __name__ == "__main__":
    unittest.main()
