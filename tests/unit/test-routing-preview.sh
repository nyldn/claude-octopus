#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Offline routing preview"

HELPER="$PROJECT_ROOT/scripts/helpers/preview-routing.py"
SUPERVISOR="$PROJECT_ROOT/shared/process_supervisor.py"

run_preview() {
    printf '%s\n' "$1" | python3 "$HELPER" --input -
}

test_case "policy preview preserves resolver result and denies dispatch verification"
policy_request='{"schema_version":1,"kind":"policy","prompt":"review this change","role":"reviewer","phase":"deliver","policy":"eval","user_pin":"","project_pin":"","requires_independent":true,"author_model":"gpt-5.6-sol","candidate_verifier":"claude-opus-5","observations":[]}'
if output="$(run_preview "$policy_request")" &&
   jq -e '.preview_kind == "policy" and
          .decision.task_class == "review" and
          .decision.model == "claude-opus-5" and
          .production_dispatch_verified == false and
          .dispatch_admissibility == "not_checked"' <<<"$output" >/dev/null; then
    test_pass
else
    test_fail "policy preview did not preserve its limited guarantee: ${output:-no output}"
fi

test_case "unknown author family cannot establish independent coverage"
unknown_request="${policy_request/\"gpt-5.6-sol\"/\"opaque-model\"}"
if output="$(run_preview "$unknown_request")" &&
   jq -e '.decision.coverage == "independent" and
          .independence_qualified == false and
          (.limitations | index("independence-not-established-author-family-unknown"))' <<<"$output" >/dev/null; then
    test_pass
else
    test_fail "raw resolver independence was not qualified"
fi

test_case "workflow preview matches production precedence without resolving a model"
workflow_request='{"schema_version":1,"kind":"workflow-provider","phase":"tangle","operation":"coding","role":"implementer","default_provider":"claude-sonnet","config":{"routing":{"roles":{"implementer":"ollama:local-model"},"phases":{}}},"environment":{"OCTOPUS_TANGLE_CODING_AGENT":"agy"},"available_binaries":["codex"],"observations":[]}'
if output="$(run_preview "$workflow_request")" &&
   jq -e '.decision.provider == "agy" and .decision.effective_model == null and
          .production_dispatch_verified == false' <<<"$output" >/dev/null; then
    test_pass
else
    test_fail "phase-operation precedence or model honesty drifted: ${output:-no output}"
fi

test_case "caller-supplied effective reviewer choice reaches production selector"
review_request='{"schema_version":1,"kind":"workflow-provider","phase":"deliver","operation":"review","role":"reviewer","default_provider":"codex-review","config":{"routing":{"roles":{},"phases":{}}},"environment":{},"available_binaries":["codex"],"effective_preferences":{"reviewer_flip":"claude"},"observations":[]}'
if output="$(run_preview "$review_request")" &&
   jq -e '.decision.provider == "claude-opus" and
          .decision.reviewer_choice_source == "caller-supplied-effective-choice"' <<<"$output" >/dev/null; then
    test_pass
else
    test_fail "effective reviewer choice was dropped: ${output:-no output}"
fi

test_case "environment override outranks supplied effective preference"
override_request='{"schema_version":1,"kind":"workflow-provider","phase":"deliver","operation":"review","role":"reviewer","default_provider":"codex-review","config":{"routing":{"roles":{},"phases":{}}},"environment":{"OCTOPUS_REVIEWER_FLIP":"codex"},"available_binaries":["codex"],"effective_preferences":{"reviewer_flip":"claude"},"observations":[]}'
if output="$(run_preview "$override_request")" &&
   jq -e '.decision.provider == "codex-review" and
          .decision.reviewer_choice_source == "request-environment-override"' <<<"$output" >/dev/null; then
    test_pass
else
    test_fail "request environment precedence drifted: ${output:-no output}"
fi

test_case "credentials and duplicate keys fail closed without value reflection"
secret='octopus-routing-secret-sentinel'
bad='{"schema_version":1,"schema_version":1,"kind":"workflow-provider","OPENAI_API_KEY":"octopus-routing-secret-sentinel"}'
set +e
error="$(run_preview "$bad" 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 2 && "$error" != *"$secret"* ]]; then
    test_pass
else
    test_fail "invalid protocol rc=$rc error=$error"
fi

test_case "malformed and oversized input fails closed while shell metacharacters remain prompt data"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json
import os
import subprocess
import tempfile
from pathlib import Path

helper = os.environ["HELPER"]
root = Path(os.environ["PROJECT_ROOT"])
base = {
    "schema_version": 1,
    "kind": "policy",
    "prompt": "$(touch routing-preview-escape); review",
    "role": "reviewer",
    "phase": "deliver",
    "policy": "eval",
    "user_pin": "",
    "project_pin": "",
    "requires_independent": False,
    "author_model": "",
    "candidate_verifier": "",
    "observations": [],
}
ok = subprocess.run([helper, "--input", "-"], input=json.dumps(base), text=True, capture_output=True, cwd=root)
assert ok.returncode == 0, ok.stderr
assert not (root / "routing-preview-escape").exists()
oversized = subprocess.run([helper, "--input", "-"], input="x" * (1024 * 1024 + 1), text=True, capture_output=True)
assert oversized.returncode == 2
bad_version = dict(base, schema_version=2)
invalid = subprocess.run([helper, "--input", "-"], input=json.dumps(bad_version), text=True, capture_output=True)
assert invalid.returncode == 2
boolean_version = dict(base, schema_version=True)
invalid = subprocess.run([helper, "--input", "-"], input=json.dumps(boolean_version), text=True, capture_output=True)
assert invalid.returncode == 2

observation = {
    "provider": "codex",
    "readiness": "available",
    "billing_mode": "subscription",
    "checked_at": "2026-09-06T00:00:00Z",
    "source": "test",
}
malformed = [
    dict(base, policy=[]),
    dict(base, prompt="\ud800"),
    dict(base, prompt="prefix\0suffix"),
    dict(base, observations=[dict(observation, readiness=[])]),
    dict(base, observations=[dict(observation, billing_mode=[])]),
]
for request in malformed:
    invalid = subprocess.run(
        [helper, "--input", "-"],
        input=json.dumps(request),
        text=True,
        capture_output=True,
    )
    assert invalid.returncode == 2, (request, invalid.returncode, invalid.stderr)
    assert "Traceback" not in invalid.stderr
huge_integer = json.dumps(base).replace('"schema_version": 1', '"schema_version": ' + "9" * 5000, 1)
invalid = subprocess.run([helper, "--input", "-"], input=huge_integer, text=True, capture_output=True)
assert invalid.returncode == 2 and not invalid.stdout and "Traceback" not in invalid.stderr

workflow = {
    "schema_version": 1,
    "kind": "workflow-provider",
    "phase": "deliver",
    "operation": "review",
    "role": "reviewer",
    "default_provider": "codex-review",
    "config": {"routing": {"roles": {}, "phases": {}}},
    "environment": {},
    "available_binaries": [],
    "effective_preferences": {"reviewer_flip": None},
    "observations": [],
}
invalid = subprocess.run([helper, "--input", "-"], input=json.dumps(workflow), text=True, capture_output=True)
assert invalid.returncode == 2 and "Traceback" not in invalid.stderr
workflow["effective_preferences"]["reviewer_flip"] = []
invalid = subprocess.run([helper, "--input", "-"], input=json.dumps(workflow), text=True, capture_output=True)
assert invalid.returncode == 2 and "Traceback" not in invalid.stderr
PYTEST
then
    test_pass
else
    test_fail "input validation, size bound, or prompt transport failed"
fi

test_case "ambient credentials are not propagated and binary markers are not invoked"
if output="$(OPENAI_API_KEY=octopus-routing-secret AWS_SECRET_ACCESS_KEY=octopus-aws-secret run_preview "$workflow_request")" &&
   jq -e '.status == "complete"' <<<"$output" >/dev/null &&
   [[ "$output" != *octopus-routing-secret* && "$output" != *octopus-aws-secret* ]]; then
    test_pass
else
    test_fail "preview leaked ambient credentials or invoked a marker"
fi

test_case "strict supervisor rejects diagnostics truncated before valid JSON"
if SUPERVISOR="$SUPERVISOR" python3 -B - <<'PYTEST'
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("preview_supervisor_test", os.environ["SUPERVISOR"])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    try:
        module.run_bounded_process(
            [sys.executable, "-c", 'print("D" * 4096 + "{}")'],
            Path(directory), 2, shell=False, output_limit=16, strict_output=True,
        )
    except module.OutputLimitExceeded:
        pass
    else:
        raise AssertionError("overflow ending in valid JSON was accepted")
PYTEST
then
    test_pass
else
    test_fail "strict output overflow was not rejected"
fi

test_case "strict supervisor rejects output that never reaches EOF within its deadline"
if SUPERVISOR="$SUPERVISOR" python3 -B - <<'PYTEST'
import importlib.util
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

if os.name != "posix":
    raise SystemExit(0)
spec = importlib.util.spec_from_file_location("preview_incomplete_output", os.environ["SUPERVISOR"])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('{}',flush=True); time.sleep(2)"
launcher = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',%r]); time.sleep(0.18)" % child
with tempfile.TemporaryDirectory() as directory:
    started = time.monotonic()
    try:
        module.run_bounded_process(
            [sys.executable, "-c", launcher], Path(directory), 0.2,
            shell=False, output_limit=1024, kill_grace=0.1, strict_output=True,
        )
    except (subprocess.TimeoutExpired, module.IncompleteOutput):
        pass
    else:
        raise AssertionError("a valid prefix without EOF was accepted")
    assert time.monotonic() - started < 0.55
PYTEST
then
    test_pass
else
    test_fail "strict preview accepted an incompletely drained JSON prefix"
fi

test_case "SIGTERM exits cleanly and removes the helper-owned temporary directory"
if HELPER="$HELPER" python3 -B - <<'PYTEST'
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

helper = os.environ["HELPER"]
with tempfile.TemporaryDirectory() as directory:
    request = Path(directory, "request.json")
    marker = Path(directory, "temp-path")
    request.write_text('{"schema_version":1,"kind":"policy","prompt":"review","role":"reviewer","phase":"deliver","policy":"off","user_pin":"","project_pin":"","requires_independent":false,"author_model":"","candidate_verifier":"","observations":[]}')
    program = r'''
import importlib.util, sys, time
from pathlib import Path
helper_path, request_path, marker_path = sys.argv[1:4]
spec=importlib.util.spec_from_file_location("preview_sigterm", helper_path)
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
def slow(_request, temp_root):
    Path(marker_path).write_text(str(temp_root))
    while True: time.sleep(0.05)
mod.preview_policy=slow
sys.argv=[helper_path, "--input", request_path]
raise SystemExit(mod.main())
    '''
    process = subprocess.Popen([sys.executable, "-c", program, helper, str(request), str(marker)])
    deadline = time.monotonic() + 2
    while not marker.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert marker.exists(), "preview did not enter temporary workspace"
    temp_path = Path(marker.read_text())
    process.send_signal(signal.SIGTERM)
    assert process.wait(timeout=2) == 130
    assert not temp_path.exists(), temp_path
PYTEST
then
    test_pass
else
    test_fail "SIGTERM left preview temporary state behind"
fi

test_summary
