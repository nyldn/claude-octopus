import importlib.util, json
from unittest.mock import patch
from pathlib import Path
path=Path(__file__).resolve().parents[2]/"scripts/helpers/openai-compatible-agent.py"
spec=importlib.util.spec_from_file_location("agent",path)
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
class Resp:
    def __enter__(self): return self
    def __exit__(self,*a): return False
    def read(self): return b'{"choices":[{"message":{"content":"ok"}}]}'
seen=[]
def fake(req,timeout=None):
    seen.append(json.loads(req.data.decode()))
    return Resp()
with patch.object(mod.urllib.request,"urlopen",side_effect=fake):
    mod.api_call("https://example.test","k","m",{},[{"role":"user","content":"x"}],reasoning_effort="medium")
    mod.api_call("https://example.test","k","m",{},[{"role":"user","content":"x"}])
assert seen[0]["reasoning_effort"]=="medium",seen
assert "reasoning_effort" not in seen[1],seen
print("PASS test-openai-reasoning-payload")
