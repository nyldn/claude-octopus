#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Resumable setup state"

HELPER="$PROJECT_ROOT/scripts/helpers/setup-state.py"
USER_CONFIG="$PROJECT_ROOT/scripts/lib/user-config.sh"

test_case "read is side-effect free and full lifecycle completes last"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path

helper = os.environ["HELPER"]
root = os.environ["PROJECT_ROOT"]
with tempfile.TemporaryDirectory() as home:
    env = dict(os.environ, HOME=home)
    def call(request, expected=0):
        result = subprocess.run([helper, "--input", "-"], input=json.dumps(request), text=True, capture_output=True, env=env)
        assert result.returncode == expected, (result.returncode, result.stderr)
        return json.loads(result.stdout) if result.stdout else None
    common = {"schema_version":1,"host":"codex","plugin_root":root}
    result = call(dict(common, action="read"))
    assert result["status"] == "partial" and result["found"] is False and not Path(home, ".claude-octopus").exists()
    result = call(dict(common, action="record", expected_revision=0, flow="host-only", provider="", stage="selected", verification=None))
    result = call(dict(common, action="record", expected_revision=result["revision"], flow="host-only", provider="", stage="rechecked", verification={"result":"passed","reason_code":"local-verification","checked_at":"2026-09-06T00:00:00Z"}))
    result = call(dict(common, action="record", expected_revision=result["revision"], flow="host-only", provider="", stage="verified", verification={"result":"passed","reason_code":"local-verification","checked_at":"2026-09-06T00:00:00Z"}))
    assert result["status"] == "partial"
    result = call(dict(common, action="complete", expected_revision=result["revision"]))
    assert result["status"] == "complete" and result["record"]["completed"] is True
    same = call(dict(common, action="complete", expected_revision=result["revision"]))
    assert same["revision"] == result["revision"]
    receipt = next(Path(home, ".claude-octopus", "setup").glob("*.json"))
    assert receipt.stat().st_mode & 0o777 == 0o600
    assert receipt.parent.stat().st_mode & 0o777 == 0o700
PYTEST
then
    test_pass
else
    test_fail "receipt lifecycle or private modes failed"
fi

test_case "compare-and-swap rejects a stale writer and preserves valid JSON"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
with tempfile.TemporaryDirectory() as home:
    env=dict(os.environ, HOME=home)
    base={"schema_version":1,"action":"record","host":"claude","plugin_root":root,"expected_revision":0,"flow":"one-provider","provider":"codex","stage":"selected","verification":None}
    first=subprocess.run([helper,"--input","-"],input=json.dumps(base),text=True,capture_output=True,env=env)
    second=subprocess.run([helper,"--input","-"],input=json.dumps(base),text=True,capture_output=True,env=env)
    assert first.returncode == 0 and second.returncode == 4, (first.stderr, second.stderr)
    receipt=next(Path(home,".claude-octopus","setup").glob("*.json"))
    assert json.loads(receipt.read_text())["revision"] == 1
PYTEST
then
    test_pass
else
    test_fail "stale revision did not fail closed"
fi

test_case "selection change invalidates old verification and completion"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
with tempfile.TemporaryDirectory() as home:
    env=dict(os.environ, HOME=home)
    def call(req, expected=0):
        p=subprocess.run([helper,"--input","-"],input=json.dumps(req),text=True,capture_output=True,env=env)
        assert p.returncode == expected, (p.returncode,p.stderr)
        return json.loads(p.stdout) if p.stdout else None
    common={"schema_version":1,"host":"claude","plugin_root":root}
    r=call(dict(common,action="record",expected_revision=0,flow="one-provider",provider="codex",stage="selected",verification=None))
    verification={"result":"passed","reason_code":"ready","checked_at":"2026-09-06T00:00:00Z"}
    r=call(dict(common,action="record",expected_revision=r["revision"],flow="one-provider",provider="codex",stage="rechecked",verification=verification))
    r=call(dict(common,action="record",expected_revision=r["revision"],flow="one-provider",provider="codex",stage="verified",verification=verification))
    r=call(dict(common,action="complete",expected_revision=r["revision"]))
    changed=call(dict(common,action="record",expected_revision=r["revision"],flow="one-provider",provider="agy",stage="selected",verification=None))
    assert changed["record"]["completed"] is False and changed["record"]["verification"] is None
    call(dict(common,action="complete",expected_revision=changed["revision"]),2)
PYTEST
then
    test_pass
else
    test_fail "stale verification survived a selection change"
fi

test_case "failed readiness recheck clears a previously completed flow"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
with tempfile.TemporaryDirectory() as home:
    env=dict(os.environ,HOME=home)
    def call(req):
        p=subprocess.run([helper,"--input","-"],input=json.dumps(req),text=True,capture_output=True,env=env)
        assert p.returncode == 0, p.stderr
        return json.loads(p.stdout)
    common={"schema_version":1,"host":"codex","plugin_root":root}
    good={"result":"passed","reason_code":"ready","checked_at":"2026-09-06T00:00:00Z"}
    r=call(dict(common,action="record",expected_revision=0,flow="one-provider",provider="codex",stage="selected",verification=None))
    r=call(dict(common,action="record",expected_revision=r["revision"],flow="one-provider",provider="codex",stage="rechecked",verification=good))
    r=call(dict(common,action="record",expected_revision=r["revision"],flow="one-provider",provider="codex",stage="verified",verification=good))
    r=call(dict(common,action="complete",expected_revision=r["revision"]))
    failed={"result":"failed","reason_code":"auth-missing","checked_at":"2026-09-06T01:00:00Z"}
    r=call(dict(common,action="record",expected_revision=r["revision"],flow="one-provider",provider="codex",stage="rechecked",verification=failed))
    assert r["status"] == "partial" and r["record"]["completed"] is False and r["next_stage"] == "rechecked"
PYTEST
then
    test_pass
else
    test_fail "expired readiness remained completed"
fi

test_case "malformed legacy config is unchanged while Bash wrapper remains best effort"
if HELPER="$HELPER" USER_CONFIG="$USER_CONFIG" python3 -B - <<'PYTEST'
import os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; library=os.environ["USER_CONFIG"]
with tempfile.TemporaryDirectory() as home:
    config=Path(home,".claude-octopus","user-config.json")
    config.parent.mkdir(mode=0o700)
    original=b'{not-json\n'
    config.write_bytes(original)
    env=dict(os.environ, HOME=home)
    strict=subprocess.run([helper,"--input","-"],input='{"schema_version":1,"action":"legacy-update","key":"setup_complete","value":true}',text=True,capture_output=True,env=env)
    wrapper=subprocess.run(["bash","-c",'source "$1"; octo_config_write setup_complete true',"bash",library],capture_output=True,env=env)
    assert strict.returncode == 3 and wrapper.returncode == 0
    assert config.read_bytes() == original
PYTEST
then
    test_pass
else
    test_fail "malformed config was replaced or wrapper semantics changed"
fi

test_case "symlink and hardlink legacy targets are rejected without modifying referents"
if HELPER="$HELPER" python3 -B - <<'PYTEST'
import os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]
request='{"schema_version":1,"action":"legacy-update","key":"safe","value":true}'
for kind in ("symlink","hardlink"):
    with tempfile.TemporaryDirectory() as home:
        base=Path(home,".claude-octopus"); base.mkdir(mode=0o700)
        outside=Path(home,"outside.json"); outside.write_text('{"keep":true}\n')
        target=base/"user-config.json"
        if kind == "symlink": target.symlink_to(outside)
        else: os.link(outside,target)
        p=subprocess.run([helper,"--input","-"],input=request,text=True,capture_output=True,env=dict(os.environ,HOME=home))
        assert p.returncode == 3 and outside.read_text() == '{"keep":true}\n'
PYTEST
then
    test_pass
else
    test_fail "unsafe legacy target was accepted or its referent changed"
fi

test_case "linked or malformed receipt files fail closed"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
common={"schema_version":1,"host":"claude","plugin_root":root}
record=dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="selected",verification=None)
for kind in ("symlink","hardlink","malformed"):
    with tempfile.TemporaryDirectory() as home:
        env=dict(os.environ,HOME=home)
        made=subprocess.run([helper,"--input","-"],input=json.dumps(record),text=True,capture_output=True,env=env)
        assert made.returncode == 0, made.stderr
        receipt=next(Path(home,".claude-octopus","setup").glob("*.json"))
        outside=Path(home,"outside.json"); outside.write_text(receipt.read_text())
        receipt.unlink()
        if kind == "symlink": receipt.symlink_to(outside)
        elif kind == "hardlink": os.link(outside,receipt)
        else: receipt.write_text('{broken')
        read=subprocess.run([helper,"--input","-"],input=json.dumps(dict(common,action="read")),text=True,capture_output=True,env=env)
        assert read.returncode == 3, (kind,read.returncode,read.stderr)
        if kind != "malformed": assert json.loads(outside.read_text())["revision"] == 1
PYTEST
then
    test_pass
else
    test_fail "unsafe receipt file was trusted or modified"
fi

test_case "stored receipts enforce the same provider selection invariants as writes"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
mutations=[
    {"flow":"one-provider","provider":""},
    {"flow":"one-provider","provider":"x"*129},
    {"flow":"one-provider","provider":"../bad"},
    {"flow":"host-only","provider":"codex"},
]
for mutation in mutations:
    with tempfile.TemporaryDirectory() as home:
        env=dict(os.environ,HOME=home)
        common={"schema_version":1,"host":"claude","plugin_root":root}
        made=subprocess.run(
            [helper,"--input","-"],
            input=json.dumps(dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="selected",verification=None)),
            text=True,capture_output=True,env=env,
        )
        assert made.returncode == 0, made.stderr
        receipt=next(Path(home,".claude-octopus","setup").glob("*.json"))
        stored=json.loads(receipt.read_text())
        stored.update(mutation)
        receipt.write_text(json.dumps(stored))
        read=subprocess.run([helper,"--input","-"],input=json.dumps(dict(common,action="read")),text=True,capture_output=True,env=env)
        assert read.returncode == 3, (mutation,read.returncode,read.stderr)
        assert not read.stdout and "Traceback" not in read.stderr
PYTEST
then
    test_pass
else
    test_fail "stored receipt accepted a provider selection rejected on write"
fi

test_case "concurrent supported legacy writers preserve both keys"
if HELPER="$HELPER" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]
with tempfile.TemporaryDirectory() as home:
    for iteration in range(25):
        iteration_home=Path(home,str(iteration)); iteration_home.mkdir()
        env=dict(os.environ,HOME=str(iteration_home))
        requests=[{"schema_version":1,"action":"legacy-update","key":"alpha","value":1},{"schema_version":1,"action":"legacy-update","key":"beta","value":2}]
        procs=[subprocess.Popen([helper,"--input","-"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env) for _ in requests]
        for proc, req in zip(procs, requests):
            proc.stdin.write(json.dumps(req))
            proc.stdin.close()
        results=[]
        for proc in procs:
            results.append((proc.stdout.read(), proc.stderr.read()))
            proc.wait(timeout=3)
        assert all(proc.returncode == 0 for proc in procs), (iteration,results)
        data=json.loads(Path(iteration_home,".claude-octopus","user-config.json").read_text())
        assert data == {"alpha":1,"beta":2}, (iteration,data)
PYTEST
then
    test_pass
else
    test_fail "concurrent legacy update lost a key"
fi

test_case "protocol types fail with exit 2 and no traceback"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
requests=[
    {"schema_version":True,"action":"read","host":"codex","plugin_root":root},
    {"schema_version":1,"action":"read","host":[],"plugin_root":root},
    {"schema_version":1,"action":"complete","host":"codex","plugin_root":root,"expected_revision":True},
    {"schema_version":1,"action":"read","host":"codex","plugin_root":root+"\0invalid"},
    {"schema_version":1,"action":"read","host":"codex","plugin_root":root+"\ud800"},
]
for request in requests:
    result=subprocess.run([helper,"--input","-"],input=json.dumps(request),text=True,capture_output=True)
    assert result.returncode == 2, (result.returncode,result.stderr)
    assert "Traceback" not in result.stderr
raw_requests=[
    '{"schema_version":' + "9"*5000 + ',"action":"legacy-reset"}',
    '{"schema_version":1,"action":"legacy-update","key":"deep","value":' + "["*1200 + "0" + "]"*1200 + "}",
]
for raw in raw_requests:
    result=subprocess.run([helper,"--input","-"],input=raw,text=True,capture_output=True)
    assert result.returncode == 2, (result.returncode,result.stderr)
    assert not result.stdout and "Traceback" not in result.stderr
PYTEST
then
    test_pass
else
    test_fail "malformed protocol types escaped validation"
fi

test_case "request strings remain compatible with downstream jq parsing"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
common={"schema_version":1,"host":"codex","plugin_root":root}
invalid=[
    dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="rechecked",verification={"result":"passed","reason_code":"\ud800","checked_at":"now"}),
    dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="rechecked",verification={"result":"passed","reason_code":"ready","checked_at":"now\0later"}),
    {"schema_version":1,"action":"legacy-update","key":"bad","value":{"nested":"\udfff"}},
    {"schema_version":1,"action":"legacy-update","key":"bad","value":{"nested":"before\0after"}},
    {"schema_version":1,"action":"legacy-reset","\ud800":True},
]
with tempfile.TemporaryDirectory() as home:
    env=dict(os.environ,HOME=home)
    for request in invalid:
        result=subprocess.run([helper,"--input","-"],input=json.dumps(request),text=True,capture_output=True,env=env)
        assert result.returncode == 2, (result.returncode,result.stderr)
        assert not result.stdout and "Traceback" not in result.stderr
    valid=dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="selected",verification=None)
    result=subprocess.run([helper,"--input","-"],input=json.dumps(valid),text=True,capture_output=True,env=env)
    assert result.returncode == 0, result.stderr
    parsed=subprocess.run(["jq","-e",".revision == 1"],input=result.stdout,text=True,capture_output=True)
    assert parsed.returncode == 0, parsed.stderr
PYTEST
then
    test_pass
else
    test_fail "request validation admitted strings that jq cannot consume"
fi

test_case "parser-limit failures in stored state remain storage errors"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
with tempfile.TemporaryDirectory() as home:
    env=dict(os.environ,HOME=home)
    common={"schema_version":1,"host":"codex","plugin_root":root}
    made=subprocess.run(
        [helper,"--input","-"],
        input=json.dumps(dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="selected",verification=None)),
        text=True,capture_output=True,env=env,
    )
    assert made.returncode == 0, made.stderr
    receipt=next(Path(home,".claude-octopus","setup").glob("*.json"))
    receipt.write_text('{"schema_version":1,"revision":' + "9"*5000 + "}")
    read=subprocess.run([helper,"--input","-"],input=json.dumps(dict(common,action="read")),text=True,capture_output=True,env=env)
    assert read.returncode == 3 and not read.stdout and "Traceback" not in read.stderr

with tempfile.TemporaryDirectory() as home:
    base=Path(home,".claude-octopus"); base.mkdir(mode=0o700)
    config=base/"user-config.json"
    config.write_text('{"deep":' + "["*1200 + "0" + "]"*1200 + "}")
    os.chmod(config,0o600)
    update=subprocess.run(
        [helper,"--input","-"],
        input='{"schema_version":1,"action":"legacy-update","key":"new","value":true}',
        text=True,capture_output=True,env=dict(os.environ,HOME=home),
    )
    assert update.returncode == 3 and not update.stdout and "Traceback" not in update.stderr
PYTEST
then
    test_pass
else
    test_fail "stored parser-limit failures escaped storage-error handling"
fi

test_case "stored state with unsafe Unicode fails closed and preserves bytes"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; root=os.environ["PROJECT_ROOT"]
common={"schema_version":1,"host":"codex","plugin_root":root}
with tempfile.TemporaryDirectory() as home:
    env=dict(os.environ,HOME=home)
    request=dict(common,action="record",expected_revision=0,flow="host-only",provider="",stage="selected",verification=None)
    made=subprocess.run([helper,"--input","-"],input=json.dumps(request),text=True,capture_output=True,env=env)
    assert made.returncode == 0, made.stderr
    receipt=next(Path(home,".claude-octopus","setup").glob("*.json"))
    stored=json.loads(receipt.read_text())
    stored.update(stage="rechecked",verification={"result":"failed","reason_code":"\ud800","checked_at":"now"})
    receipt.write_text(json.dumps(stored))
    before=receipt.read_bytes()
    read=subprocess.run([helper,"--input","-"],input=json.dumps(dict(common,action="read")),text=True,capture_output=True,env=env)
    assert read.returncode == 3 and not read.stdout and "Traceback" not in read.stderr
    assert receipt.read_bytes() == before

for raw in ('{"bad":"before\\u0000after"}', '{"bad":"\\ud800"}', '{broken'):
    for action in ("legacy-update", "legacy-reset"):
        with tempfile.TemporaryDirectory() as home:
            base=Path(home,".claude-octopus"); base.mkdir(mode=0o700)
            config=base/"user-config.json"
            config.write_text(raw); os.chmod(config,0o600)
            before=config.read_bytes()
            request={"schema_version":1,"action":action}
            if action == "legacy-update": request.update(key="new",value=True)
            result=subprocess.run(
                [helper,"--input","-"],input=json.dumps(request),
                text=True,capture_output=True,env=dict(os.environ,HOME=home),
            )
            assert result.returncode == 3 and not result.stdout and "Traceback" not in result.stderr
            assert config.read_bytes() == before
PYTEST
then
    test_pass
else
    test_fail "unsafe stored strings were trusted or existing bytes changed"
fi

test_case "merged legacy configuration remains readable at structural boundaries"
if HELPER="$HELPER" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]

def nested(depth):
    value=0
    for _ in range(depth):
        value=[value]
    return value

def update(home,key,value,expected):
    request={"schema_version":1,"action":"legacy-update","key":key,"value":value}
    result=subprocess.run([helper,"--input","-"],input=json.dumps(request),text=True,capture_output=True,env=dict(os.environ,HOME=home))
    assert result.returncode == expected, (result.returncode,result.stderr)
    assert "Traceback" not in result.stderr
    return result

with tempfile.TemporaryDirectory() as home:
    update(home,"nested",nested(63),0)
    update(home,"round_trip",True,0)
    target=Path(home,".claude-octopus","user-config.json")
    before=target.read_bytes()
    update(home,"too_deep",nested(64),2)
    assert target.read_bytes() == before
    assert json.loads(target.read_text())["round_trip"] is True

with tempfile.TemporaryDirectory() as home:
    update(home,"wide",[0]*99998,0)
    target=Path(home,".claude-octopus","user-config.json")
    before=target.read_bytes()
    update(home,"one_too_many",True,2)
    assert target.read_bytes() == before
    assert len(json.loads(target.read_text())["wide"]) == 99998
PYTEST
then
    test_pass
else
    test_fail "merged configuration crossed a structural limit or lost readable state"
fi

test_case "read does not chmod existing state directories"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import importlib.util, os, tempfile
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location("setup_state_read_only",os.environ["HELPER"])
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as home:
    base=Path(home,".claude-octopus"); setup=base/"setup"
    setup.mkdir(parents=True,mode=0o700); os.chmod(base,0o700); os.chmod(setup,0o700)
    request={"schema_version":1,"action":"read","host":"codex","plugin_root":os.environ["PROJECT_ROOT"]}
    old_home=os.environ.get("HOME")
    os.environ["HOME"]=home
    try:
        with patch.object(module.os,"fchmod",side_effect=AssertionError("read attempted chmod")):
            result=module.operate_receipt(module.validate_request(request))
        assert result["found"] is False
    finally:
        if old_home is None: os.environ.pop("HOME",None)
        else: os.environ["HOME"]=old_home
PYTEST
then
    test_pass
else
    test_fail "receipt read mutated directory permissions"
fi

test_case "FIFO state targets fail closed without blocking"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import hashlib, json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]; root=str(Path(os.environ["PROJECT_ROOT"]).resolve())
with tempfile.TemporaryDirectory() as home:
    base=Path(home,".claude-octopus"); setup=base/"setup"; setup.mkdir(parents=True,mode=0o700)
    os.mkfifo(base/"user-config.json")
    legacy=subprocess.run([helper,"--input","-"],input='{"schema_version":1,"action":"legacy-update","key":"x","value":1}',text=True,capture_output=True,env=dict(os.environ,HOME=home),timeout=1)
    assert legacy.returncode == 3
    name=hashlib.sha256(("codex\0"+root+"\0"+"1").encode()).hexdigest()+".json"
    os.mkfifo(setup/name)
    request={"schema_version":1,"action":"read","host":"codex","plugin_root":root}
    receipt=subprocess.run([helper,"--input","-"],input=json.dumps(request),text=True,capture_output=True,env=dict(os.environ,HOME=home),timeout=1)
    assert receipt.returncode == 3
PYTEST
then
    test_pass
else
    test_fail "FIFO target blocked or was accepted"
fi

test_case "merged legacy output cannot exceed the readable state limit"
if HELPER="$HELPER" python3 -B - <<'PYTEST'
import json, os, subprocess, tempfile
from pathlib import Path
helper=os.environ["HELPER"]
with tempfile.TemporaryDirectory() as home:
    base=Path(home,".claude-octopus"); base.mkdir(mode=0o700)
    target=base/"user-config.json"
    original={"old":"a"*600000}; target.write_text(json.dumps(original)); os.chmod(target,0o600)
    request={"schema_version":1,"action":"legacy-update","key":"new","value":"b"*600000}
    result=subprocess.run([helper,"--input","-"],input=json.dumps(request),text=True,capture_output=True,env=dict(os.environ,HOME=home))
    assert result.returncode == 3, (result.returncode,result.stderr)
    assert json.loads(target.read_text()) == original
PYTEST
then
    test_pass
else
    test_fail "legacy update persisted an unreadable oversized result"
fi

test_case "directory replacement cannot redirect descriptor-relative receipt writes"
if HELPER="$HELPER" PROJECT_ROOT="$PROJECT_ROOT" python3 -B - <<'PYTEST'
import importlib.util, os, tempfile, threading
from pathlib import Path
spec=importlib.util.spec_from_file_location("setup_state_directory_race",os.environ["HELPER"])
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as home:
    base=Path(home,".claude-octopus"); (base/"setup").mkdir(parents=True,mode=0o700)
    old_home=os.environ.get("HOME"); os.environ["HOME"]=home
    real_open=module.os.open; ready=threading.Event(); replaced=threading.Event(); swapped=[False]
    def attacker():
        assert ready.wait(1)
        base.rename(Path(home,"original-octopus"))
        (base/"setup").mkdir(parents=True,mode=0o700)
        replaced.set()
    def guarded_open(path, flags, *args, **kwargs):
        if path == "setup" and kwargs.get("dir_fd") is not None and not swapped[0]:
            swapped[0]=True; ready.set(); assert replaced.wait(1)
        return real_open(path,flags,*args,**kwargs)
    thread=threading.Thread(target=attacker); thread.start()
    request={"schema_version":1,"action":"record","host":"codex","plugin_root":os.environ["PROJECT_ROOT"],"expected_revision":0,"flow":"host-only","provider":"","stage":"selected","verification":None}
    try:
        with __import__("unittest.mock").mock.patch.object(module.os,"open",side_effect=guarded_open):
            result=module.operate_receipt(module.validate_request(request))
        thread.join(timeout=1); assert not thread.is_alive()
        assert result["persisted"] is True and not list((base/"setup").glob("*.json"))
        assert list((Path(home,"original-octopus","setup")).glob("*.json"))
    finally:
        if old_home is None: os.environ.pop("HOME",None)
        else: os.environ["HOME"]=old_home
PYTEST
then
    test_pass
else
    test_fail "path replacement redirected a setup receipt"
fi

test_case "lock contention exits with the documented bounded timeout"
if HELPER="$HELPER" python3 -B - <<'PYTEST'
import fcntl, os, subprocess, tempfile, time
from pathlib import Path
helper=os.environ["HELPER"]
with tempfile.TemporaryDirectory() as home:
    base=Path(home,".claude-octopus"); base.mkdir(mode=0o700)
    lock=base/"user-config.json.lock"
    with lock.open("w") as handle:
        os.chmod(lock,0o600)
        fcntl.flock(handle.fileno(),fcntl.LOCK_EX)
        started=time.monotonic()
        p=subprocess.run([helper,"--input","-"],input='{"schema_version":1,"action":"legacy-update","key":"alpha","value":1}',text=True,capture_output=True,env=dict(os.environ,HOME=home))
        elapsed=time.monotonic()-started
    assert p.returncode == 5 and 0.8 <= elapsed < 2.0, (p.returncode,elapsed,p.stderr)
PYTEST
then
    test_pass
else
    test_fail "lock wait was unbounded or returned the wrong status"
fi

test_summary
