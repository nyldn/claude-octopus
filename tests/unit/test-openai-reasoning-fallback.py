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
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self): return b'{"choices":[{"message":{"content":"ok"}}]}'

seen = []
def fallback_urlopen(req, timeout=None):
    payload = json.loads(req.data.decode())
    seen.append(payload)
    if "reasoning_effort" in payload:
        raise urllib.error.HTTPError(
            req.full_url, 400, "bad request", {},
            io.BytesIO(b'{"error":"unknown field reasoning_effort"}')
        )
    return Resp()

with patch.object(mod.urllib.request, "urlopen", side_effect=fallback_urlopen):
    result = mod.api_call(
        "https://example.test", "k", "m", {}, [{"role":"user","content":"x"}],
        max_retries=1, reasoning_effort="medium", reasoning_policy="best_effort"
    )
assert result["choices"][0]["message"]["content"] == "ok"
assert len(seen) == 2, seen
assert seen[0]["reasoning_effort"] == "medium"
assert "reasoning_effort" not in seen[1]

strict_seen = []
def strict_urlopen(req, timeout=None):
    strict_seen.append(json.loads(req.data.decode()))
    raise urllib.error.HTTPError(
        req.full_url, 400, "bad request", {},
        io.BytesIO(b'{"error":"unknown field reasoning_effort"}')
    )

with patch.object(mod.urllib.request, "urlopen", side_effect=strict_urlopen):
    try:
        mod.api_call(
            "https://example.test", "k", "m", {}, [{"role":"user","content":"x"}],
            max_retries=1, reasoning_effort="medium", reasoning_policy="strict"
        )
    except RuntimeError as exc:
        assert "HTTP 400" in str(exc)
    else:
        raise AssertionError("strict policy should not fall back")
assert len(strict_seen) == 1, strict_seen
print("PASS test-openai-reasoning-fallback")
