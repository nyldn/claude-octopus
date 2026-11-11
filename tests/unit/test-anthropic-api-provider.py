import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("anthropic_api", ROOT / "scripts/helpers/anthropic-api.py")
api = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(api)

class Response(io.BytesIO):
    pass

class AnthropicAPI(unittest.TestCase):
    def invoke(self, *, effort="high", thinking="auto", model="claude-sonnet-5-5", response=None, env=None):
        received = []
        result = response or {"content": [{"type": "thinking", "thinking": "", "signature": "signed"}, {"type": "text", "text": "answer"}], "stop_reason": "end_turn"}
        def transport(request, timeout):
            received.append((request, timeout))
            return Response(json.dumps(result).encode())
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "inert-fixture", **(env or {})}, clear=True), patch.object(api, "urlopen", side_effect=transport):
            text = api.execute("supplied evidence", model=model, effort=effort, thinking=thinking)
        return text, received

    def test_between_tools_reaches_the_messages_transport(self):
        text, requests = self.invoke()
        request, timeout = requests[0]
        payload = json.loads(request.data)
        self.assertEqual(payload["thinking"], {"type": "between_tools"})
        self.assertEqual(payload["output_config"], {"effort": "high"})
        self.assertEqual(payload["model"], "claude-sonnet-5-5")
        self.assertEqual(payload["messages"], [{"role": "user", "content": "supplied evidence"}])
        self.assertEqual(request.full_url, "https://api.anthropic.com/v1/messages")
        self.assertEqual(request.get_header("X-api-key"), "inert-fixture")
        self.assertEqual(request.get_header("Anthropic-version"), "2023-06-01")
        self.assertGreater(timeout, 0)
        self.assertEqual(text, "answer")
        for absent in ("tools", "tool_choice", "temperature", "top_p", "top_k"):
            self.assertNotIn(absent, payload)
        self.assertIsNone(request.get_header("Anthropic-beta"))

    def test_effort_modes_and_opus_preserve_adaptive_thinking(self):
        for effort in ("low", "medium", "high", "xhigh", "max"):
            text, requests = self.invoke(effort=effort)
            payload = json.loads(requests[0][0].data)
            expected = "between_tools" if effort in ("low", "medium", "high") else "adaptive"
            self.assertEqual(payload["thinking"], {"type": expected})
            self.assertEqual(payload["output_config"]["effort"], effort)
        _, requests = self.invoke(model="claude-opus-5-5")
        self.assertEqual(json.loads(requests[0][0].data)["thinking"], {"type": "adaptive"})

    def test_automatic_effort_leaves_the_api_parameter_unset(self):
        for model in api.MODELS:
            with self.subTest(model=model):
                _, requests = self.invoke(model=model, effort="auto")
                payload = json.loads(requests[0][0].data)
                self.assertNotIn("output_config", payload)
                self.assertEqual(payload["thinking"], {"type": "adaptive"})

    def test_automatic_effort_rejects_explicit_between_tools_before_transport(self):
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "inert-fixture"}, clear=True), patch.object(api, "urlopen") as transport:
            with self.assertRaises(ValueError):
                api.execute("prompt", effort="auto", thinking="between_tools")
            transport.assert_not_called()

    def test_invalid_configuration_never_contacts_transport(self):
        for config in ({"effort": "max", "thinking": "between_tools"}, {"effort": "xhigh", "thinking": "between_tools"}, {"model": "claude-opus-5-5", "thinking": "between_tools"}, {"thinking": "disabled"}, {"model": "claude-sonnet-5"}, {"effort": "bogus"}):
            with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "inert-fixture"}, clear=True), patch.object(api, "urlopen") as transport:
                with self.assertRaises(ValueError):
                    api.execute("prompt", **config)
                transport.assert_not_called()

    def test_missing_key_empty_prompt_and_invalid_transport_settings_fail_before_http(self):
        for env, prompt in (({}, "p"), ({"ANTHROPIC_API_KEY": " "}, "p"), ({"ANTHROPIC_API_KEY": "k"}, " "), ({"ANTHROPIC_API_KEY": "k", "OCTOPUS_ANTHROPIC_API_TIMEOUT": "nan"}, "p"), ({"ANTHROPIC_API_KEY": "k", "OCTOPUS_ANTHROPIC_API_TIMEOUT": "0"}, "p"), ({"ANTHROPIC_API_KEY": "k", "OCTOPUS_ANTHROPIC_API_MAX_TOKENS": "0"}, "p")):
            with patch.dict(os.environ, env, clear=True), patch.object(api, "urlopen") as transport:
                with self.assertRaises(ValueError):
                    api.execute(prompt)
                transport.assert_not_called()

    def test_no_redirect_can_forward_the_api_key(self):
        handler = api.NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 307, "redirect", {}, "https://other.example/messages"))

    def test_http_error_is_redacted(self):
        error = urllib.error.HTTPError("url", 401, "failed", {}, io.BytesIO(b"secret response"))
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "inert-fixture"}, clear=True), patch.object(api, "urlopen", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, "HTTP 401") as result:
                api.execute("p")
            self.assertNotIn("secret response", str(result.exception))
            self.assertNotIn("inert-fixture", str(result.exception))

    def test_refusal_tool_calls_truncation_empty_and_malformed_responses_fail(self):
        for response in ({"stop_reason": "refusal", "content": [{"type": "text", "text": "refused"}]}, {"stop_reason": "max_tokens", "content": [{"type": "text", "text": "cut"}]}, {"stop_reason": "tool_use", "content": [{"type": "tool_use", "id": "call"}]}, {"stop_reason": "end_turn", "content": [{"type": "thinking", "thinking": "", "signature": "s"}]}, {"stop_reason": "end_turn", "content": "wrong"}):
            with self.assertRaises(RuntimeError):
                self.invoke(response=response)

    def test_adaptive_pin_is_sent_unchanged(self):
        _, requests = self.invoke(thinking="adaptive", effort="medium")
        self.assertEqual(json.loads(requests[0][0].data)["thinking"], {"type": "adaptive"})

if __name__ == "__main__":
    unittest.main()
