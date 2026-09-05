#!/usr/bin/env python3
import importlib.util
import io
import json
import urllib.error
from pathlib import Path
from unittest.mock import patch

path = Path(__file__).resolve().parents[2] / "scripts/helpers/openai-compatible-agent.py"
spec = importlib.util.spec_from_file_location("agent", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class Resp:
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return b'{"choices":[{"message":{"content":"ok"}}]}'


seen = []


def fake(req, timeout=None):
    del timeout
    seen.append(json.loads(req.data.decode()))
    return Resp()


with patch.object(mod.urllib.request, "urlopen", side_effect=fake):
    mod.api_call(
        "https://example.test",
        "k",
        "m",
        {},
        [{"role": "user", "content": "x"}],
        reasoning_effort="medium",
    )
    mod.api_call(
        "https://example.test",
        "k",
        "m",
        {},
        [{"role": "user", "content": "x"}],
    )

assert seen[0]["reasoning_effort"] == "medium", seen
assert "reasoning_effort" not in seen[1], seen
assert mod.normalize_reasoning_effort("xhigh") == "high"
assert mod.normalize_reasoning_effort("max") == "high"
assert mod.normalize_reasoning_effort("medium") == "medium"

with patch.object(mod.urllib.request, "urlopen") as mocked:
    try:
        mod.api_call(
            "http://example.test",
            "k",
            "m",
            {},
            [{"role": "user", "content": "x"}],
        )
    except ValueError as exc:
        assert "must use HTTPS" in str(exc), exc
    else:
        raise AssertionError("credentialed remote HTTP adapter request was accepted")
    mocked.assert_not_called()

loopback_seen = []


def fake_loopback(req, timeout=None):
    del timeout
    loopback_seen.append(req.full_url)
    return Resp()


with patch.object(mod.urllib.request, "urlopen", side_effect=fake_loopback):
    mod.api_call(
        "http://127.0.0.1:8000/v1",
        "k",
        "m",
        {},
        [{"role": "user", "content": "x"}],
    )

assert loopback_seen == ["http://127.0.0.1:8000/v1/chat/completions"], loopback_seen

# Astra's full tool path requires the Responses API. The generic adapter still
# uses Chat Completions, so it may run no-tool review prompts but must fail
# before transport when tools are requested.
with patch.object(mod.urllib.request, "urlopen") as mocked:
    try:
        mod.api_call(
            "https://example.test",
            "k",
            "gpt-6-astra",
            {},
            [{"role": "user", "content": "x"}],
            tool_policy="auto",
        )
    except ValueError as exc:
        assert "Responses API" in str(exc), exc
    else:
        raise AssertionError("Astra tools were sent through Chat Completions")
    mocked.assert_not_called()

astra_seen = []


def fake_astra(req, timeout=None):
    del timeout
    astra_seen.append(json.loads(req.data.decode()))
    return Resp()


with patch.object(mod.urllib.request, "urlopen", side_effect=fake_astra):
    mod.api_call(
        "https://example.test",
        "k",
        "gpt-6-astra",
        {},
        [{"role": "user", "content": "x"}],
        tool_policy="none",
        reasoning_effort="high",
    )

assert "tools" not in astra_seen[0], astra_seen
assert "temperature" not in astra_seen[0], astra_seen
assert astra_seen[0]["reasoning_effort"] == "high", astra_seen

# A field-named value error must not be mistaken for rejection of the field and
# retried without it.
for generic_body in (
    b'{"error":"invalid reasoning_effort value"}',
    b'{"error":"unsupported value for reasoning_effort"}',
    b'{"error":"unsupported field: reasoning_effort_mode"}',
):
    error = urllib.error.HTTPError(
        "https://example.test/chat/completions",
        400,
        "bad request",
        {},
        io.BytesIO(generic_body),
    )
    with patch.object(mod.urllib.request, "urlopen", side_effect=error) as mocked:
        try:
            mod.api_call(
                "https://example.test",
                "k",
                "m",
                {},
                [{"role": "user", "content": "x"}],
                reasoning_effort="medium",
                reasoning_policy="best_effort",
            )
        except RuntimeError:
            pass
        else:
            raise AssertionError("generic reasoning error unexpectedly triggered fallback")
    assert mocked.call_count == 1, (generic_body, mocked.call_count)

# A 400 response that explicitly rejects the reasoning_effort field retries
# once without that field when best-effort reasoning is enabled.
field_error = urllib.error.HTTPError(
    "https://example.test/chat/completions",
    400,
    "bad request",
    {},
    io.BytesIO(b'{"error":"unsupported field: reasoning_effort"}'),
)
fallback_seen = []


def fake_reasoning_fallback(req, timeout=None):
    del timeout
    fallback_seen.append(json.loads(req.data.decode()))
    if len(fallback_seen) == 1:
        raise field_error
    return Resp()


with patch.object(
    mod.urllib.request, "urlopen", side_effect=fake_reasoning_fallback
) as mocked:
    result = mod.api_call(
        "https://example.test",
        "k",
        "m",
        {},
        [{"role": "user", "content": "x"}],
        reasoning_effort="medium",
        reasoning_policy="best_effort",
    )

assert result["choices"][0]["message"]["content"] == "ok", result
assert mocked.call_count == 2, mocked.call_count
assert fallback_seen[0]["reasoning_effort"] == "medium", fallback_seen
assert "reasoning_effort" not in fallback_seen[1], fallback_seen

print("PASS test-openai-reasoning-payload")
