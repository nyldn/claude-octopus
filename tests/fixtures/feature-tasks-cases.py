#!/usr/bin/env python3
"""Exercise task identity and scheduling with disposable Git repositories."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import signal
import unittest
import uuid

PLUGIN = Path(sys.argv.pop(1)).resolve()
spec = importlib.util.spec_from_file_location("feature_tasks", PLUGIN / "scripts/helpers/feature-tasks.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
FID = "cb796828-bdc3-4a2a-aea4-bf5f74722f61"

RUNTIME_SHELL = r'''
set -u
source "$PLUGIN/scripts/lib/testing.sh"
source "$PLUGIN/scripts/lib/workflows.sh"
source "$PLUGIN/scripts/lib/parallel.sh"
source "$PLUGIN/scripts/lib/feature-scheduler.sh"
cd "$EXEC_ROOT" || exit 1
PROJECT_ROOT="$EXEC_ROOT"
WORKSPACE_DIR="$FIXTURE_RUNTIME/workspace"
PID_FILE="$WORKSPACE_DIR/pids"
RESULTS_DIR="$FIXTURE_RUNTIME/results"
FEATURE_RUNTIME_DIR="$FIXTURE_RUNTIME/features"
FEATURE_SOURCE_ROOT="$EXEC_ROOT"
FEATURE_TASK_CONTRACT="$FIXTURE_RUNTIME/contract.json"
TMUX_MODE=false; DRY_RUN=false; SUPPORTS_PARALLEL_FILE_SAFETY=false
SUPPORTS_DISABLE_CRON_ENV=false; AVAILABLE_AGENTS='codex agy'; MAX_PARALLEL="${FIXTURE_MAX_PARALLEL:-6}"
CYAN=; MAGENTA=; GREEN=; YELLOW=; RED=; NC=
OCTOPUS_TANGLE_CODE_REVIEW=false
OCTOPUS_TANGLE_MISSING_MARKER_GRACE=0
mkdir -p "$WORKSPACE_DIR/.octo/agents" "$RESULTS_DIR"
export PROJECT_ROOT WORKSPACE_DIR RESULTS_DIR FEATURE_RUNTIME_DIR FEATURE_SOURCE_ROOT FEATURE_TASK_CONTRACT PID_FILE
log() { printf '%s\n' "$*" >> "$FIXTURE_RUNTIME/log"; }
octopus_phase_banner() { :; }
design_review_ceremony() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
tangle_require_execution_boundary() { printf 'boundary\n' >> "$FIXTURE_RUNTIME/gates"; }
build_tangle_subtask_prompt() { printf '%s\n' "$2"; }
tangle_decomposition_adequacy_review() { printf 'adequacy\n' >> "$FIXTURE_RUNTIME/gates"; printf 'VERDICT: PASS\nSCOPE_REVIEW: NONE\nREASONS: scoped fixture\n'; }
tangle_contextual_review_gate() { printf 'contextual\n' >> "$FIXTURE_RUNTIME/gates"; return "${7:-1}"; }
tangle_validate_results_with_scope_contract() {
    printf 'validation\n' >> "$FIXTURE_RUNTIME/gates"
    local task_id
    while IFS= read -r task_id; do
        [[ -n "$task_id" ]] || continue
        local result="$RESULTS_DIR/codex-${task_id}.md"
        [[ "$(octo_result_launcher_status "$result")" == '## Status: SUCCESS' ]] || return 1
    done <<< "${8:-}"
    return 0
}
snapshot_tangle_worktree_paths() { git diff --name-only; }
snapshot_tangle_worktree_state() { git diff; }
aggregate_results() { :; }
feature_workflow_gate() {
    if [[ "${FIXTURE_MUTATE_GATE_ID:-}" == "${2:-}" ]]; then printf 'user gate change\n' > "$EXEC_ROOT/src/file1.py"; fi
    [[ "${FIXTURE_BLOCK_ID:-}" != "${2:-}" ]]
}
run_agent_sync_consultative() {
    printf '%s\n' "$2" >> "$FIXTURE_RUNTIME/reasoning-prompts"
    [[ "${FIXTURE_REASONING_EMPTY:-false}" == true ]] || printf 'Verified reasoning fixture result\n'
}
spawn_agent_capture_pid() {
    local id="$3"
    if [[ -n "${FIXTURE_LAUNCH_DELAY:-}" ]]; then sleep "$FIXTURE_LAUNCH_DELAY"; fi
    python3 "$FIXTURE_RUNTIME/worker.py" "$id" "$OCTOPUS_FEATURE_WAVE_JSON" "$EXEC_ROOT" "$FIXTURE_RUNTIME" "$WORKSPACE_DIR" "$RESULTS_DIR" > /dev/null 2>&1 &
    local worker_pid="$!"
    octopus_pid_register "$worker_pid" codex "$id" >/dev/null || return 1
    printf '%s\n' "$worker_pid"
}
if [[ "${MUTATE_NEXT:-false}" == true ]]; then
    eval "$(declare -f _feature_tasks_capture_wave | sed '1s/_feature_tasks_capture_wave/_fixture_capture/')"
    _feature_tasks_capture_wave() {
        _fixture_capture "$@" || return $?
        if [[ "$3" == completed ]]; then printf 'user change\n' > "$EXEC_ROOT/src/file2.py"; fi
    }
fi
if [[ -n "${FEATURE_TASK_HISTORY_COMPLETION:-}" && "${FIXTURE_RESUME_VERIFIER:-pass}" != unavailable ]]; then
    feature_workflow_verify_resume() {
        printf 'verify\n' >> "$FIXTURE_RUNTIME/resume-verifications"
        [[ "${FIXTURE_RESUME_VERIFIER:-pass}" != fail ]] || return 1
        python3 - "$1" "$EXEC_ROOT" <<'VERIFY'
import json,sys
from pathlib import Path
candidates=json.load(open(sys.argv[1]))
assert candidates["tasks"] and Path(sys.argv[2], "src/file1.py").read_text()=="validated T001\n"
VERIFY
        local rc=$?
        if [[ "${FIXTURE_RESUME_MUTATE:-false}" == true ]]; then printf 'user after verify\n' > "$EXEC_ROOT/src/file1.py"; fi
        return "$rc"
    }
fi
if [[ -n "${FIXTURE_REQUIREMENT_GATE_PLUGIN:-}" ]]; then
    source "$FIXTURE_REQUIREMENT_GATE_PLUGIN/scripts/lib/feature-workflow.sh"
    FEATURE_ACTIVE=true; FEATURE_SELECTED=; FEATURE_POLICY_SNAPSHOT=
    mkdir -p "$FEATURE_RUNTIME_DIR"
    cp "$FIXTURE_REQUIREMENT_MARKERS" "$FEATURE_RUNTIME_DIR/clarifications.json"
fi
feature_workflow_tasks_completed() { cp "$1" "$FIXTURE_RUNTIME/published-completion.json"; }
rc=0
if [[ "$EXEC_MODE" == tangle ]]; then
    _tangle_develop_in_workspace 'Implement portable fixture tasks' '' runtime-fixture || rc=$?
else
    parallel_execute "${FIXTURE_PASSED_CONTRACT:-$FEATURE_TASK_CONTRACT}" || rc=$?
fi
printf 'rc=%s\n' "$rc"
exit "$rc"
'''

WORKER = r'''
import fcntl,json,os,sys,time
from pathlib import Path
task_id,wave_path,root,runtime,workspace,results=sys.argv[1:]
tid=task_id.rsplit("-",1)[-1]
task=next(item for item in json.load(open(wave_path))["selected"] if item["id"]==tid)
def event(kind):
    with open(Path(runtime)/"events.jsonl", "a") as handle:
        fcntl.flock(handle,fcntl.LOCK_EX)
        handle.write(json.dumps({"event":kind,"id":task_id,"pid":os.getpid(),"time":time.monotonic()})+"\n")
        handle.flush()
def rendezvous():
    expected=int(os.environ.get("FIXTURE_EXPECTED_CONCURRENCY", "0"))
    if not expected:
        return True
    state_path=Path(runtime)/"rendezvous.json"
    lock_path=Path(runtime)/"rendezvous.lock"
    joined=False
    while True:
        with open(lock_path, "a") as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            state=json.loads(state_path.read_text()) if state_path.exists() else {
                "participants":[], "deadline":time.monotonic()+8, "released":False, "failed":False}
            if not joined:
                state["participants"].append({"id":task_id, "pid":os.getpid()})
                joined=True
            if not state["released"] and time.monotonic() >= state["deadline"]:
                state["failed"]=True
            if not state["failed"] and len(state["participants"]) == expected:
                state["released"]=True
            state_path.write_text(json.dumps(state))
        if state["failed"] or state["released"]:
            return state["released"] and not state["failed"]
        time.sleep(0.02)
if os.environ.get("FIXTURE_STALL_ID")==tid:
    time.sleep(9)
event("start")
# Keep real workers alive until the whole six-task wave has started. A slow
# launcher must not turn the capacity assertion into a 1.2-second race.
ready=rendezvous()
if ready:
    time.sleep(1.2)
failed=not ready or os.environ.get("FIXTURE_FAIL_ID")==tid
if not failed:
    target=Path(root)/(task["files"] or task["creates"])[0]
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text("validated "+tid+"\n")
result=Path(results)/("codex-"+task_id+".md")
result.write_text("# Agent: codex\n# Prompt-Format: octopus-length-v1\n# Prompt-Bytes: 7\nfixture\n# Started: fixture\n<!-- BEGIN-UNTRUSTED:provider=codex:nonce=0123456789abcdef0123456789abcdef -->\n## Output\nsubstantive result\n<!-- END-UNTRUSTED:provider=codex:nonce=0123456789abcdef0123456789abcdef -->\n## Status: "+("FAILED" if failed else "SUCCESS")+"\n")
event("end")
marker=Path(workspace)/".octo/agents"/(task_id+".done")
marker.write_text("1" if failed else "0")
'''

REAL_RUNTIME = r'''
source "$PLUGIN/scripts/lib/testing.sh"
source "$PLUGIN/scripts/lib/workflows.sh"
source "$PLUGIN/scripts/lib/parallel.sh"
source "$PLUGIN/scripts/lib/spawn.sh"
source "$PLUGIN/scripts/lib/validation.sh"
source "$PLUGIN/scripts/lib/utils.sh"
source "$PLUGIN/scripts/lib/quality.sh"
source "$PLUGIN/scripts/lib/feature-scheduler.sh"
PROJECT_ROOT="$OCTOPUS_PROJECT_DIR"; PLUGIN_DIR="$PLUGIN"
WORKSPACE_DIR="$FIXTURE_RUNTIME/workspace"; RESULTS_DIR="$FIXTURE_RUNTIME/results"
LOGS_DIR="$FIXTURE_RUNTIME/logs"; PID_FILE="$WORKSPACE_DIR/pids"
FEATURE_RUNTIME_DIR="$FIXTURE_RUNTIME/feature"; FEATURE_SOURCE_ROOT="$PROJECT_ROOT"
OCTOPUS_RUN_ID="$RUN_ID"; TIMEOUT=30; MAX_PARALLEL=1
TMUX_MODE=false; DRY_RUN=false; LOOP_UNTIL_APPROVED=false; SUPPORTS_PARALLEL_FILE_SAFETY=false
SUPPORTS_DISABLE_CRON_ENV=false; SUPPORTS_STABLE_AUTH=true; OCTOPUS_BACKEND=api
OCTOPUS_ANTISYCOPHANCY=false; OCTOPUS_ENGINEERING_METHODS=off
OCTOPUS_TANGLE_CODE_REVIEW=false; OCTOPUS_TANGLE_MISSING_MARKER_GRACE=0
MAX_QUALITY_RETRIES=0; AUTONOMY_MODE=autonomous
OCTOPUS_GATE_TANGLE=100; QUALITY_THRESHOLD=100; ON_FAIL_ACTION=auto
CLAUDE_TASK_ID=; CODEX_SUBAGENT_PREAMBLE=; PROVIDER_ENV_ARRAY=()
AVAILABLE_AGENTS=codex; CYAN=; MAGENTA=; GREEN=; YELLOW=; RED=; NC=; DIM=
mkdir -p "$WORKSPACE_DIR/.octo/agents" "$RESULTS_DIR" "$LOGS_DIR"
export PROJECT_ROOT WORKSPACE_DIR RESULTS_DIR LOGS_DIR PID_FILE OCTOPUS_RUN_ID
export FEATURE_RUNTIME_DIR FEATURE_SOURCE_ROOT OCTOPUS_ANTISYCOPHANCY
log() { printf '%s\n' "$*" >> "$FIXTURE_RUNTIME/log"; }
get_agent_model() { printf '%s\n' fixture-model; }
get_agent_command() { printf 'python3 %q\n' "$PROVIDER"; }
validate_agent_command() { [[ "$1" == "python3 "* ]]; }
classify_task() { printf '%s\n' standard; }
get_role_for_context() { printf '%s\n' implementer; }
match_routing_rule() { :; }
load_agent_checkpoint() { :; }
apply_persona() { printf '%s' "$2"; }
load_earned_skills() { :; }
build_provider_context() { :; }
enforce_context_budget() { printf '%s' "$1"; }
should_use_agent_teams() { return 1; }
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
# This fixture tests dispatch and parent validation, not OS sandbox support.
octopus_tangle_apply_execution_boundary() { return 0; }
octopus_capture_provider_output() {
    local prompt="$1" input="$3" output="$4" errors="$5"
    shift 5
    printf '%s' "$prompt" > "$input"
    "$@" < "$input" > "$output" 2> "$errors"
}
start_quota_watcher() { :; }; stop_quota_watcher() { :; }
quota_watcher_mark_after_exit() { :; }
octo_provider_identity_from_agent_type() { printf '%s\n' codex; }
octo_append_runtime_identity() { :; }
record_agent_call() { :; }; record_agent_start() { :; }; record_agent_failure() { :; }
update_metrics() { :; }; bridge_register_task() { :; }; update_agent_status() { :; }
write_agent_status() { :; }; append_provider_history() { :; }; record_outcome() { :; }
record_success() { :; }; record_failure() { :; }; record_run_pattern() { :; }
record_task_metric() { :; }; run_drift_check() { :; }; record_error() { :; }
save_agent_checkpoint() { :; }; record_result_hash() { :; }
start_heartbeat_monitor() { :; }; cleanup_heartbeat() { :; }; _octopus_agent_lifecycle_event() { :; }
aggregate_results() { :; }; render_agent_summary() { :; }
octopus_phase_banner() { :; }; reset_provider_lockouts() { :; }
fleet_dispatch_begin() { :; }; fleet_dispatch_end() { :; }
FEATURE_TASK_CONTRACT="$FIXTURE_RUNTIME/contract.json"
export FEATURE_TASK_CONTRACT FEATURE_RUNTIME_DIR FEATURE_SOURCE_ROOT
cd "$PROJECT_ROOT" || exit 1
rc=0
feature_tasks_parallel_execute "$FEATURE_TASK_CONTRACT" || rc=$?
printf 'rc=%s\n' "$rc"
exit "$rc"
'''
REAL_PROVIDER = r'''
import json,os,sys
from pathlib import Path
prompt=sys.stdin.read()
wave=json.loads(Path(os.environ['OCTOPUS_FEATURE_WAVE_JSON']).read_text())
assert len(wave['selected']) == 1
task=wave['selected'][0]
root=Path(os.environ['OCTOPUS_PROJECT_DIR'])
with open(Path(os.environ['FIXTURE_RUNTIME'])/'dispatches.jsonl','a') as out:
    out.write(json.dumps({'id':task['id'],'prompt':prompt})+'\n')
if os.environ.get('FAIL_TASK') == task['id']:
    print('Fixture intentionally stopped this task.',file=sys.stderr)
    sys.exit(42)
target=root/os.environ.get('UNAUTHORIZED_TARGET',(task['files'] or task['creates'])[0])
target.parent.mkdir(parents=True,exist_ok=True)
if os.environ.get('NO_CHANGES') != 'true':
    target.write_text('validated '+task['id']+'\n')
print('Implemented '+str(target.relative_to(root))+' for '+task['id']+'. Verified the requested fixture content.')
'''

class TaskCases(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="octopus-feature-tasks-")
        self.root = Path(self.temp.name) / "source"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.root / "src").mkdir()
        for index in range(1, 8):
            (self.root / "src" / ("file%d.py" % index)).write_text("pass\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def task(self, index, **changes):
        return {"id": "T%03d" % index, "title": "Task %d" % index, "requirements": ["FR-%03d" % index],
                "files": ["src/file%d.py" % index], "parallel_hint": True, **changes}

    def contract(self, *tasks):
        return helper.reconcile(None, {"schema_version": 1, "feature_id": FID, "tasks": list(tasks)})

    def wave(self, contract, completed=None, source=None):
        return helper.wave(self.root, source, contract, completed or {}, 6)

    def proof(self, contract, *ids, **changes):
        return {"contract_digest": contract["contract_digest"], "tasks": [
            {"id": task["id"], "identity": task["identity"], "contract_digest": contract["contract_digest"],
             "parent_verified": True, "status": "completed", "evidence": "commit:fixture", **changes}
            for task in contract["tasks"] if task["id"] in ids]}

    def test_six_disjoint_tasks_and_strict_adapter(self):
        contract = self.contract(*(self.task(index) for index in range(1, 7)))
        wave = self.wave(contract)
        self.assertEqual(wave["ready_ids"], ["T%03d" % index for index in range(1, 7)])
        self.assertEqual(len(wave["selected"]), 6)
        self.assertEqual(set(wave["decomposition"]), {"schema_version", "subtasks"})
        self.assertEqual([item["id"] for item in wave["decomposition"]["subtasks"]], list(range(1, 7)))
        self.assertEqual(set(wave["decomposition"]["subtasks"][0]), {"id", "kind", "title", "reads", "files", "creates", "task"})
        self.assertEqual(self.wave(contract)["snapshot_digest"], wave["snapshot_digest"])

    def test_planned_case_aliases_serialize_without_rewriting_authority(self):
        (self.root / "out").mkdir()
        contract = self.contract(self.task(1, files=[], creates=["out/Foo.py"]),
                                 self.task(2, files=[], creates=["out/foo.py"]))
        wave = self.wave(contract)
        self.assertEqual([task["id"] for task in wave["selected"]], ["T001"])
        self.assertTrue(wave["serial_reasons"])
        self.assertEqual(wave["selected"][0]["creates"], ["out/Foo.py"])
        self.assertEqual(contract["tasks"][1]["creates"], ["out/foo.py"])

    def test_collision_keys_never_widen_exact_path_authority(self):
        claim = lambda path, directory=False: {"path": path, "directory": directory, "inode": None}
        self.assertTrue(helper.overlap(claim("out/Foo.py"), claim("out/foo.py")))
        self.assertTrue(helper.overlap(claim("out/Caf\u00e9.py"), claim("out/Cafe\u0301.py")))
        self.assertTrue(helper.overlap(claim("OUT", True), claim("out/foo.py")))
        self.assertFalse(helper.overlap(claim("out/foo.py"), claim("out/foobar.py")))
        self.assertFalse(helper.path_matches("out/foo.py", "out/Foo.py"))
        self.assertFalse(helper.path_matches("out/Cafe\u0301.py", "out/Caf\u00e9.py"))
        self.assertFalse(helper.path_matches("src/File1.py", "src/file1.py"))

    def test_resume_rejects_case_folded_scope_evidence_even_when_bytes_match(self):
        contract = self.contract(self.task(1))
        history, target, baseline = self.portable_history(contract)
        exact = history["tasks"][0]["evidence"]["files"][0]
        history["tasks"][0]["evidence"]["files"].append({**exact, "relativepath": "src/File1.py"})
        result = helper.resume(self.root, None, contract, history, baseline)
        self.assertEqual(result["tasks"], [])
        self.assertEqual([item["id"] for item in result["rejected"]], ["T001"])

    def test_reorder_reword_preserves_ids_and_retirement_never_recycles(self):
        old = self.contract(self.task(1), self.task(2))
        incoming = {"schema_version": 1, "feature_id": FID, "tasks": [self.task(2, title="Reworded"), self.task(1)]}
        reordered = helper.reconcile(old, incoming)
        self.assertEqual([item["identity"] for item in reordered["tasks"]], [item["identity"] for item in reversed(old["tasks"])])
        replaced = helper.reconcile(reordered, {"schema_version": 1, "feature_id": FID, "tasks": [self.task(2), self.task(9)]})
        self.assertEqual([item["id"] for item in replaced["tasks"]], ["T002", "T003"])
        self.assertEqual(replaced["tombstones"][0]["id"], "T001")
        with self.assertRaises(helper.Invalid):
            helper.reconcile(replaced, {"schema_version": 1, "feature_id": FID, "tasks": [self.task(1)]})

    def test_first_import_reserves_later_declared_ids(self):
        missing, another_missing = self.task(2), self.task(3)
        missing.pop("id")
        another_missing.pop("id")
        for records in ([missing, self.task(1)], [missing, self.task(7), another_missing]):
            with self.subTest(records=records):
                contract = self.contract(*records)
                helper.normalize(contract, FID, True)
                self.assertEqual(len(self.wave(contract)["selected"]), len(records))
                self.assertEqual(len({task["id"] for task in contract["tasks"]}), len(records))
                declared = max(int(task["id"][1:]) for task in records if task.get("id"))
                allocated = [int(task["id"][1:]) for task, record in zip(contract["tasks"], records) if not record.get("id")]
                self.assertTrue(all(number > declared for number in allocated))

    def workflow_adapter(self, *args):
        home = Path(self.temp.name) / "workflow-home"
        home.mkdir(exist_ok=True)
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("FEATURE_", "GIT_", "OCTOPUS_FEATURE", "OCTOPUS_WORKFLOW_STATE"))}
        environment.update(HOME=str(home), OCTOPUS_PROJECT_DIR=str(self.root),
                           CLAUDE_OCTOPUS_WORKSPACE=str(Path(self.temp.name) / "workflow-runtime"))
        result = subprocess.run(["/bin/bash", str(PLUGIN / "scripts/helpers/feature-workflow.sh"), *args],
                                cwd=self.root, env=environment, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")][-1]

    def test_actual_adapter_replans_add_edit_reorder_delete_and_preserve_history(self):
        context = self.workflow_adapter("prepare", "spec", "replan")
        spec_path = Path(self.temp.name) / "spec-draft.md"
        spec_path.write_text("# Replan fixture\n## Purpose\nTest task history.\n## Actors\n- User: requests edits.\n"
                             "## Behaviors\n### FR-001: Edit data\nPostcondition: saved edits exist.\n"
                             "## Constraints\nPreserve scope.\n## Dependencies\nNone.\n"
                             "## Acceptance Definition\nGiven data\nWhen edited\nThen saved edits exist.\n")
        self.workflow_adapter("save", "spec", str(spec_path), "claude", "unknown", "fixture-spec", context["feature"])
        plan = Path(self.temp.name) / "accepted-plan.md"
        manifest = self.root / context["feature"] / "feature.json"

        def save(*tasks):
            plan.write_text("# Plan\n```octopus-tasks\n" + json.dumps({"schema_version": 1,
                            "feature_id": context["feature_id"], "tasks": list(tasks)}) + "\n```\n")
            self.workflow_adapter("save", "plan", str(plan), "claude", "unknown", "fixture-plan", context["feature"])
            history = json.loads(manifest.read_text())["task_history"]
            helper.normalize(history, context["feature_id"], True)
            return history

        initial = save(self.task(1))
        added = save(self.task(1), self.task(2))
        self.assertEqual([task["id"] for task in added["tasks"]], ["T001", "T002"])
        self.assertEqual(added["tasks"][0]["identity"], initial["tasks"][0]["identity"])
        edited = save(self.task(2, title="Reword task two"), self.task(1))
        self.assertEqual([task["id"] for task in edited["tasks"]], ["T002", "T001"])
        self.assertEqual(edited["tasks"][0]["identity"], added["tasks"][1]["identity"])
        retained = dict(edited["tasks"][0], files=["src/file2.py", "src/file3.py"])
        deleted = save(retained)
        self.assertEqual(deleted["tasks"][0]["identity"], retained["identity"])
        self.assertEqual([task["id"] for task in deleted["tombstones"]], ["T001"])
        self.assertEqual(deleted["high_watermark"], 2)
        appended = save(retained, self.task(7))
        self.assertEqual([task["id"] for task in appended["tasks"]], ["T002", "T003"])
        self.assertEqual(appended["tombstones"], deleted["tombstones"])
        self.assertEqual(appended["high_watermark"], 3)

    def test_inactive_plan_completion_needs_no_feature_identity(self):
        environment = {**os.environ, "PLUGIN": str(PLUGIN)}
        result = subprocess.run(["/bin/bash"], input='''set -eu
source "$PLUGIN/scripts/lib/feature-workflow.sh"
FEATURE_ACTIVE=false
unset FEATURE_ID
feature_workflow_plan_completed unused claude fixture
printf 'inactive-safe\\n'
''', env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "inactive-safe\n")

    def test_actual_parallel_uses_passed_contract_with_unrelated_active_contract(self):
        inherited = self.contract(self.task(1, kind="reasoning", files=[]))
        passed = self.contract(self.task(2, kind="reasoning", files=[]))
        target = Path(self.temp.name) / "passed-contract.json"
        target.write_text(json.dumps(passed))
        result, runtime, events = self.run_dispatcher(inherited, mode="parallel", FIXTURE_PASSED_CONTRACT=str(target))
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(events, [])
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual([task["id"] for task in summary["completed"]], ["T002"])
        self.assertIn('"id":"T002"', (runtime / "reasoning-prompts").read_text())

    def test_actual_parallel_keeps_legacy_tasks_despite_inherited_contract(self):
        inherited = self.contract(self.task(1, kind="reasoning", files=[]))
        target = Path(self.temp.name) / "legacy-tasks.json"
        target.write_text('{"tasks":[]}')
        result, runtime, events = self.run_dispatcher(inherited, mode="parallel", FIXTURE_PASSED_CONTRACT=str(target))
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(events, [])
        self.assertFalse((runtime / "reasoning-prompts").exists())
        report = json.loads((runtime / "workspace/state/parallel-report.json").read_text())
        self.assertEqual(report["results"], [])
        self.assertEqual(report["counts"]["total"], 0)

    def test_split_gets_new_ids_and_explicit_supersedes(self):
        old = self.contract(self.task(1))
        incoming = {"schema_version": 1, "feature_id": FID, "tasks": [self.task(2, supersedes=["T001"]), self.task(3, supersedes=["T001"])]}
        split = helper.reconcile(old, incoming)
        self.assertEqual([item["id"] for item in split["tasks"]], ["T002", "T003"])
        self.assertEqual(split["tombstones"][0]["id"], "T001")
        self.assertTrue(all(item["identity"] != old["tasks"][0]["identity"] for item in split["tasks"]))

    def test_unrelated_id_reuse_is_rejected(self):
        old = self.contract(self.task(1))
        with self.assertRaises(helper.Invalid):
            helper.reconcile(old, {"schema_version": 1, "feature_id": FID, "tasks": [self.task(1, files=["src/file2.py"], requirements=["OTHER"])]})
        with self.assertRaises(helper.Invalid):
            helper.reconcile(old, {"schema_version": 1, "feature_id": FID, "tasks": [self.task(1, identity=old["tasks"][0]["identity"], files=["src/file2.py"], requirements=["OTHER"])]})

    def test_fenced_and_spec_kit_parsing_are_repeatable(self):
        tasks = self.root / "tasks.md"
        tasks.write_text("# Tasks\n- [x] T001 [P] [US1] Edit `src/file1.py`\n- [ ] T002 [US2] Edit `src/file2.py`\n")
        parsed = helper.parse_tasks(tasks, FID)
        self.assertEqual(parsed["tasks"][0]["requirements"], ["US1"])
        self.assertTrue(parsed["tasks"][0]["parallel_hint"])
        self.assertEqual(helper.parse_tasks(tasks, FID)["tasks"][0]["identity"], parsed["tasks"][0]["identity"])
        self.assertEqual(self.wave(parsed)["completed_ids"], [])
        tasks.write_text("```octopus-tasks\n" + json.dumps(parsed) + "\n```\n")
        reread = helper.parse_tasks(tasks, FID)
        self.assertEqual(reread["tasks"], parsed["tasks"])
        self.assertEqual(reread["contract_digest"], parsed["contract_digest"])
        tasks.write_text("# Unsupported tasks\nDo the work.\n")
        self.assertTrue(helper.parse_tasks(tasks, FID)["legacy"])

    def test_raw_parse_preserves_declarations_without_allocating_identities(self):
        tasks = Path(self.temp.name) / "raw-tasks.md"
        for text in ("```octopus-tasks\n" + json.dumps({"schema_version": 1, "feature_id": FID,
                     "tasks": [self.task(1), self.task(2)]}) + "\n```\n",
                     "- [ ] T001 [P] [FR-001] Edit `src/file1.py`\n- [ ] T002 [FR-002] Edit `src/file2.py`\n"):
            with self.subTest(text=text):
                tasks.write_text(text)
                result = subprocess.run([sys.executable, str(PLUGIN / "scripts/helpers/feature-tasks.py"),
                                         "parse", "--tasks", str(tasks), "--feature-id", FID, "--raw"],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                raw = json.loads(result.stdout)
                self.assertTrue(all("identity" not in task for task in raw["tasks"]))
                prior = self.contract(self.task(1))
                reconciled = helper.reconcile(prior, raw)
                self.assertEqual(reconciled["tasks"][0]["identity"], prior["tasks"][0]["identity"])
                self.assertEqual([task["id"] for task in reconciled["tasks"]], ["T001", "T002"])

    def test_raw_parse_keeps_explicit_identity_and_published_digest_validation(self):
        prior = self.contract(self.task(1))
        tasks = Path(self.temp.name) / "explicit-tasks.md"
        claimed = self.task(2, identity=str(uuid.uuid4()))
        tasks.write_text("```octopus-tasks\n" + json.dumps({"schema_version": 1, "feature_id": FID,
                         "tasks": [self.task(1), claimed]}) + "\n```\n")
        raw = helper.parse_tasks(tasks, FID, raw=True)
        self.assertEqual(raw["tasks"][1]["identity"], claimed["identity"])
        with self.assertRaises(helper.Invalid):
            helper.reconcile(prior, raw)
        forged = {**prior, "contract_digest": "sha256:" + "0" * 64}
        tasks.write_text("```octopus-tasks\n" + json.dumps(forged) + "\n```\n")
        with self.assertRaises(helper.Invalid):
            helper.parse_tasks(tasks, FID, raw=True)

    def test_dependency_proofs_require_parent_digest_and_identity(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
        self.assertEqual(self.wave(contract)["ready_ids"], ["T001"])
        for change in ({"parent_verified": False}, {"contract_digest": "old"}, {"identity": str(uuid.uuid4())}, {"evidence": ""}):
            self.assertEqual(self.wave(contract, self.proof(contract, "T001", **change))["ready_ids"], ["T001"])
        self.assertEqual(self.wave(contract, self.proof(contract, "T001", status="failed"))["ready_ids"], [])
        valid = self.wave(contract, self.proof(contract, "T001"))
        self.assertEqual(valid["ready_ids"], ["T002"])
        self.assertEqual(valid["completed_ids"], ["T001"])

    def test_cycles_missing_and_transitive_failed_dependencies(self):
        contract = self.contract(self.task(1, dependencies=["T002"]), self.task(2, dependencies=["T001"]))
        self.assertEqual(self.wave(contract)["selected"], [])
        contract = self.contract(self.task(1, dependencies=["T009"]), self.task(2, dependencies=["T001"]))
        self.assertEqual(self.wave(contract)["selected"], [])
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]), self.task(3, dependencies=["T002"]))
        self.assertEqual(self.wave(contract, self.proof(contract, "T002"))["ready_ids"], ["T001"])

    def test_hint_cannot_widen_shared_path_and_false_hint_narrows(self):
        shared = self.contract(self.task(1), self.task(2, files=["src/file1.py"]))
        wave = self.wave(shared)
        self.assertEqual(len(wave["selected"]), 1)
        self.assertTrue(any("overlaps" in item["reason"] for item in wave["serial_reasons"]))
        narrowed = self.contract(self.task(1, parallel_hint=False), self.task(2))
        self.assertEqual(len(self.wave(narrowed)["selected"]), 1)

    def test_globs_directories_creates_and_empty_directory_claims(self):
        contract = self.contract(self.task(1, files=["src/*.py"]), self.task(2))
        self.assertEqual(len(self.wave(contract)["selected"]), 1)
        contract = self.contract(self.task(1, files=["src/"]), self.task(2, files=[], creates=["src/new.py"]))
        self.assertEqual(len(self.wave(contract)["selected"]), 1)
        (self.root / "empty").mkdir()
        contract = self.contract(self.task(1, files=["empty"]), self.task(2, files=[], creates=["empty/new.py"]))
        self.assertEqual(len(self.wave(contract)["selected"]), 1)
        (self.root / "deep").mkdir()
        (self.root / "deep/a").mkdir()
        (self.root / "deep/a/value.py").write_text("pass\n")
        self.git("add", "deep")
        self.git("commit", "-qm", "deep")
        contract = self.contract(self.task(1, files=["deep/**/*.py"]))
        self.assertIn("deep/a/value.py", self.wave(contract)["selected"][0]["files"])

    def test_hardlink_alias_symlink_and_missing_authority(self):
        os.link(self.root / "src/file1.py", self.root / "src/alias.py")
        self.git("add", "src/alias.py")
        self.git("commit", "-qm", "alias")
        contract = self.contract(self.task(1), self.task(2, files=["src/alias.py"]))
        self.assertEqual(len(self.wave(contract)["selected"]), 1)
        (self.root / "linked").symlink_to(self.root / "src", target_is_directory=True)
        contract = self.contract(self.task(1, files=[], creates=["linked/new.py"]))
        self.assertEqual(self.wave(contract)["selected"], [])
        for path in ("src/missing.py", "src/no*.py", "../escape", ".git/config", "/tmp/file"):
            contract = self.contract(self.task(1, files=[path]))
            self.assertEqual(self.wave(contract)["selected"], [])
        contract = self.contract(self.task(1, files=[], creates=["new/deep/file.py"]))
        self.assertEqual(self.wave(contract)["selected"][0]["creates"], ["new/deep/file.py"])

    def test_staged_unstaged_untracked_rename_and_mutation_between_waves(self):
        contract = self.contract(self.task(1), self.task(2))
        initial = self.wave(contract)
        (self.root / "src/file1.py").write_text("changed\n")
        self.assertEqual(self.wave(contract)["ready_ids"], ["T002"])
        self.git("add", "src/file1.py")
        self.assertEqual(self.wave(contract)["ready_ids"], ["T002"])
        self.git("reset", "--hard", "-q", "HEAD")
        self.git("mv", "src/file1.py", "src/moved.py")
        moved = self.contract(self.task(1, files=[], creates=["src/file1.py"]), self.task(2, files=["src/moved.py"]))
        self.assertEqual(self.wave(moved)["selected"], [])
        self.git("reset", "--hard", "-q", "HEAD")
        (self.root / "src/user file.py").write_text("private\n")
        folder = self.contract(self.task(1, files=["src"]))
        self.assertEqual(self.wave(folder)["selected"], [])
        self.assertNotEqual(self.wave(contract)["snapshot_digest"], initial["snapshot_digest"])

    def test_dirty_original_checkout_is_protected_with_isolation(self):
        execution = Path(self.temp.name) / "execution"
        self.git("worktree", "add", "--detach", "-q", str(execution))
        original = self.root
        contract = self.contract(self.task(1), self.task(2))
        (original / "src/file1.py").write_text("user edit\n")
        self.root = execution
        wave = self.wave(contract, source=original)
        self.assertEqual(wave["ready_ids"], ["T002"])
        self.assertTrue(any("source checkout" in reason for item in wave["blocked_pending"] for reason in item["reasons"]))
        (execution / "src/file2.py").write_text("execution edit\n")
        self.assertEqual(self.wave(contract, source=original)["selected"], [])
        self.root = original

    def test_declared_reader_waits_for_producer_and_missing_edge_is_reported(self):
        contract = self.contract(self.task(1), self.task(2, reads=["src/file1.py"], dependencies=["T001"]))
        self.assertEqual(self.wave(contract)["ready_ids"], ["T001"])
        self.assertEqual(self.wave(contract, self.proof(contract, "T001"))["ready_ids"], ["T002"])
        missing_edge = self.contract(self.task(1), self.task(2, reads=["src/file1.py"]))
        self.assertEqual(self.wave(missing_edge)["ready_ids"], ["T001"])
        self.assertIn("no declared dependency", self.wave(missing_edge)["blocked_pending"][0]["reasons"][0])

    def test_scan_bounds_and_contract_tampering(self):
        contract = self.contract(self.task(1, files=["src/*.py"]))
        original = helper.MAX_PATHS
        try:
            helper.MAX_PATHS = 3
            self.assertEqual(self.wave(contract)["selected"], [])
        finally:
            helper.MAX_PATHS = original
        contract["tasks"][0]["files"] = ["src/file2.py"]
        with self.assertRaises(helper.Invalid):
            self.wave(contract)

    def test_parent_capture_allows_same_run_edits_but_detects_later_mutation(self):
        contract = self.contract(self.task(1), self.task(2, files=["src/file1.py"], dependencies=["T001"]))
        first = self.wave(contract)
        (self.root / "src/file1.py").write_text("validated output\n")
        completed = helper.capture(self.root, contract, first, helper.digest(first), {}, "completed", "run:fixture")
        self.assertEqual(self.wave(contract, completed)["ready_ids"], ["T002"])
        (self.root / "src/file1.py").write_text("later user mutation\n")
        self.assertEqual(self.wave(contract, completed)["selected"], [])
        with self.assertRaises(helper.Invalid):
            helper.capture(self.root, contract, first, "sha256:forged", {}, "completed", "run:fixture")

    def test_execution_evidence_never_exempts_separate_original_user_dirt(self):
        execution = Path(self.temp.name) / "execution"
        self.git("worktree", "add", "--detach", "-q", str(execution))
        original = self.root
        self.root = execution
        contract = self.contract(self.task(1), self.task(2, files=["src/file1.py"], dependencies=["T001"]))
        first = self.wave(contract, source=original)
        (execution / "src/file1.py").write_text("validated output\n")
        completed = helper.capture(execution, contract, first, helper.digest(first), {}, "completed", "run:fixture")
        self.assertEqual(self.wave(contract, completed, source=original)["ready_ids"], ["T002"])
        (original / "src/file1.py").write_text("user edit\n")
        self.assertEqual(self.wave(contract, completed, source=original)["selected"], [])
        self.root = original

    def test_directory_authority_supports_filenames_outside_v1_path_alphabet(self):
        (self.root / "src/space name.py").write_text("pass\n")
        self.git("add", "src/space name.py")
        self.git("commit", "-qm", "space name")
        contract = self.contract(self.task(1, files=["src"]))
        wave = self.wave(contract)
        self.assertEqual(wave["ready_ids"], ["T001"])
        self.assertIn("src/space name.py", wave["selected"][0]["expanded_files"])
        self.assertNotIn("src/space name.py", wave["decomposition"]["subtasks"][0]["files"])
        self.assertIn("src", wave["decomposition"]["subtasks"][0]["files"])

    def test_untracked_user_hardlink_alias_is_protected(self):
        os.link(self.root / "src/file1.py", self.root / "user-alias.py")
        contract = self.contract(self.task(1), self.task(2))
        self.assertEqual(self.wave(contract)["ready_ids"], ["T002"])

    def test_inconsistent_retirement_history_cannot_recycle_live_identity(self):
        contract = self.contract(self.task(1))
        contract["tombstones"] = [{"id": "T001", "identity": contract["tasks"][0]["identity"], "status": "retired"}]
        contract = helper.seal(contract)
        with self.assertRaises(helper.Invalid):
            self.wave(contract)

    def test_cli_rejects_invalid_metadata_with_json_and_no_input_echo(self):
        tasks = self.root / "tasks.md"
        tasks.write_text('```octopus-tasks\n{"schema_version":9,"private":"DO-NOT-ECHO"}\n```\n')
        result = subprocess.run([sys.executable, str(PLUGIN / "scripts/helpers/feature-tasks.py"), "parse", "--tasks", str(tasks), "--feature-id", FID], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["error"], "invalid-task-metadata")
        self.assertNotIn(b"DO-NOT-ECHO", result.stdout + result.stderr)

    def run_dispatcher(self, contract, mode="tangle", **changes):
        runtime = Path(self.temp.name) / ("runtime-" + mode)
        runtime.mkdir(exist_ok=True)
        (runtime / "contract.json").write_text(json.dumps(contract))
        (runtime / "worker.py").write_text(WORKER)
        environment = {**os.environ, "PLUGIN": str(PLUGIN), "EXEC_ROOT": str(self.root),
                       "FIXTURE_RUNTIME": str(runtime), "EXEC_MODE": mode, **changes}
        result = subprocess.run(["/bin/bash"], input=RUNTIME_SHELL.encode(), env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=35)
        events = [json.loads(line) for line in (runtime / "events.jsonl").read_text().splitlines()] if (runtime / "events.jsonl").exists() else []
        return result, runtime, events

    def concurrent_max(self, events):
        active = maximum = 0
        for event in sorted(events, key=lambda item: item["time"]):
            active += 1 if event["event"] == "start" else -1
            maximum = max(maximum, active)
        return maximum

    def portable_history(self, contract):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        (self.root / "src/file1.py").write_text("validated T001\n")
        state = helper.path_state(self.root, "src/file1.py")
        self.git("add", "src/file1.py")
        self.git("commit", "-qm", "completed portable task")
        task = contract["tasks"][0]
        record = {"id": task["id"], "identity": task["identity"], "status": "completed", "contract_digest": contract["contract_digest"],
                  "evidence": {"run_id": "prior-home-run-T001", "baseline_commit": baseline,
                               "files": [{"relativepath": "src/file1.py", **state}]}}
        history = {"schema_version": 1, "contract_digest": contract["contract_digest"], "tasks": [record]}
        target = Path(self.temp.name) / "portable-history.json"
        target.write_text(json.dumps(history))
        return history, target, self.git("rev-parse", "HEAD").decode().strip()

    def test_actual_fresh_home_resume_verifies_once_and_only_dispatches_pending_dependency(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
        history, target, baseline = self.portable_history(contract)
        fresh = Path(self.temp.name) / "fresh-home"
        fresh.mkdir()
        result, runtime, events = self.run_dispatcher(contract, HOME=str(fresh), FEATURE_TASK_HISTORY_COMPLETION=str(target), FEATURE_RESUME_BASELINE=baseline)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T002"])
        self.assertEqual((runtime / "resume-verifications").read_text(), "verify\n")
        published = json.loads((runtime / "published-completion.json").read_text())
        first = next(record for record in published["tasks"] if record["id"] == "T001")
        self.assertTrue(first["parent_verified"])
        self.assertIn("historical_evidence", first)
        self.assertNotIn("write_evidence", first)

    def test_forged_history_bytes_and_failed_or_missing_verifier_do_not_skip_tasks(self):
        for verifier in ("mismatched-bytes", "fail", "unavailable"):
            with self.subTest(verifier=verifier):
                contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
                if not (Path(self.temp.name) / "portable-history.json").exists():
                    history, target, baseline = self.portable_history(contract)
                else:
                    target = Path(self.temp.name) / "portable-history.json"
                    history = json.loads(target.read_text())
                    baseline = self.git("rev-parse", "HEAD").decode().strip()
                if verifier == "mismatched-bytes":
                    history["tasks"][0]["evidence"]["files"][0]["digest"] = "sha256:" + "0" * 64
                    target.write_text(json.dumps(history))
                else:
                    history["tasks"][0]["evidence"]["files"][0].update(helper.path_state(self.root, "src/file1.py"))
                    target.write_text(json.dumps(history))
                self.git("add", ".")
                self.git("commit", "--allow-empty", "-qm", "fresh resume fixture baseline")
                baseline = self.git("rev-parse", "HEAD").decode().strip()
                result, runtime, events = self.run_dispatcher(contract, FEATURE_TASK_HISTORY_COMPLETION=str(target), FEATURE_RESUME_BASELINE=baseline,
                    FIXTURE_RESUME_VERIFIER="pass" if verifier == "mismatched-bytes" else verifier)
                self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
                starts = [event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"]
                self.assertEqual(starts[-2:], ["T001", "T002"])

    def test_resume_rechecks_after_verifier_and_never_exempts_new_user_dirt(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
        history, target, baseline = self.portable_history(contract)
        result, runtime, events = self.run_dispatcher(contract, FEATURE_TASK_HISTORY_COMPLETION=str(target), FEATURE_RESUME_BASELINE=baseline, FIXTURE_RESUME_MUTATE="true")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, [])
        self.assertEqual((self.root / "src/file1.py").read_text(), "user after verify\n")
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual(summary["completed"], [])

    def test_resume_rejects_assume_unchanged_bytes_not_in_committed_tree(self):
        contract = self.contract(self.task(1))
        history, target, baseline = self.portable_history(contract)
        self.git("update-index", "--assume-unchanged", "src/file1.py")
        (self.root / "src/file1.py").write_text("forged committed bytes\n")
        history["tasks"][0]["evidence"]["files"][0].update(helper.path_state(self.root, "src/file1.py"))
        self.assertEqual(helper.resume(self.root, None, contract, history, baseline)["tasks"], [])

    def test_resume_requires_complete_scope_and_protects_dirty_original_with_isolation(self):
        contract = self.contract(self.task(1, files=["src/"]))
        history, target, baseline = self.portable_history(contract)
        self.assertEqual(helper.resume(self.root, None, contract, history, baseline)["tasks"], [])
        contract = self.contract(self.task(1))
        history["contract_digest"] = contract["contract_digest"]
        history["tasks"][0].update(identity=contract["tasks"][0]["identity"], contract_digest=contract["contract_digest"], parent_verified=True)
        execution = Path(self.temp.name) / "isolated"
        self.git("worktree", "add", "--detach", str(execution), baseline)
        (self.root / "src/file1.py").write_text("original user changes\n")
        candidates = helper.resume(execution, self.root, contract, history, baseline)
        self.assertEqual(candidates["tasks"], [])
        self.assertEqual((execution / "src/file1.py").read_text(), "validated T001\n")

    def test_resume_revalidates_read_context_confinement(self):
        contract = self.contract(self.task(1, reads=["/outside/authority.py"]))
        history, target, baseline = self.portable_history(contract)
        self.assertEqual(helper.resume(self.root, None, contract, history, baseline)["tasks"], [])

    def test_resume_requires_matching_head_and_ancestor_baseline(self):
        contract = self.contract(self.task(1))
        history, target, baseline = self.portable_history(contract)
        with self.assertRaises(helper.Invalid):
            helper.resume(self.root, None, contract, history, "0" * 40)
        history["tasks"][0]["evidence"]["baseline_commit"] = "0" * 40
        self.assertEqual(helper.resume(self.root, None, contract, history, baseline)["tasks"], [])

    def test_actual_reasoning_wave_requires_nonempty_result_and_preserves_context(self):
        contract = self.contract(self.task(1, kind="reasoning", files=[], reads=["src/file1.py"]))
        result, runtime, events = self.run_dispatcher(contract)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(events, [])
        prompt = (runtime / "reasoning-prompts").read_text()
        self.assertIn("Original feature intent: Implement portable fixture tasks", prompt)
        self.assertIn('"id":"T001"', prompt)
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual(summary["completed"][0]["id"], "T001")
        result, runtime, events = self.run_dispatcher(contract, FIXTURE_REASONING_EMPTY="true")
        self.assertNotEqual(result.returncode, 0)
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual(summary["completed"], [])

    def test_actual_reasoning_wave_revalidates_after_task_gate(self):
        contract = self.contract(self.task(1, kind="reasoning", files=[], reads=["src/file1.py"]))
        result, runtime, events = self.run_dispatcher(contract, FIXTURE_MUTATE_GATE_ID="T001")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((runtime / "reasoning-prompts").exists())
        self.assertEqual((self.root / "src/file1.py").read_text(), "user gate change\n")

    def test_actual_tangle_dispatches_six_workers_with_stable_result_ids(self):
        contract = self.contract(*(self.task(index) for index in range(1, 7)))
        result, runtime, events = self.run_dispatcher(
            contract, FIXTURE_EXPECTED_CONCURRENCY="6", FIXTURE_LAUNCH_DELAY="0.45")
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(self.concurrent_max(events), 6)
        self.assertEqual(len([event for event in events if event["event"] == "start"]), 6)
        self.assertTrue(all(TASK_ID in str(path) for TASK_ID, path in zip(["T%03d" % i for i in range(1,7)], sorted((runtime / "results").glob("codex-*.md")))))
        gates = (runtime / "gates").read_text()
        for gate in ("adequacy", "boundary", "validation", "contextual"):
            self.assertIn(gate, gates)

    def test_actual_tangle_overlap_is_serial_and_failed_predecessor_never_runs(self):
        contract = self.contract(self.task(1), self.task(2, files=["src/file1.py"]))
        result, runtime, events = self.run_dispatcher(contract)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(self.concurrent_max(events), 1)
        self.assertEqual(len([event for event in events if event["event"] == "start"]), 2)

    def test_actual_tangle_failed_dependencies_and_between_wave_mutation_stay_pending(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
        result, runtime, events = self.run_dispatcher(contract, FIXTURE_FAIL_ID="T001")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T001"])
        self.assertIn('"status": "partial"', next((runtime / "features/task-runs").glob("*/summary.json")).read_text())

    def test_actual_tangle_revalidates_next_wave_against_new_user_dirt(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
        result, runtime, events = self.run_dispatcher(contract, MUTATE_NEXT="true")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T001"])
        self.assertEqual((self.root / "src/file2.py").read_text(), "user change\n")

    def run_real_dispatcher(self, **changes):
        runtime = Path(self.temp.name) / "real-launcher-runtime"
        runtime.mkdir()
        home = Path(self.temp.name) / "real-launcher-home"
        home.mkdir()
        contract = self.contract(self.task(1))
        (runtime / "contract.json").write_text(json.dumps(contract))
        provider = runtime / "provider.py"
        provider.write_text(REAL_PROVIDER)
        environment = {key: value for key, value in os.environ.items() if not key.startswith(("FEATURE_", "GIT_", "OCTOPUS_", "CLAUDE_", "CODEX_", "AGY_", "GEMINI_", "ANTHROPIC_", "OPENAI_")) and not key.endswith(("_API_KEY", "_TOKEN"))}
        environment.update(PLUGIN=str(PLUGIN), HOME=str(home), FIXTURE_RUNTIME=str(runtime), OCTOPUS_PROJECT_DIR=str(self.root), PROVIDER=str(provider), RUN_ID="actual-launcher-fixture", **changes)
        result = subprocess.run(["/bin/bash"], input=REAL_RUNTIME.encode(), env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=35)
        return result, runtime

    def test_real_launcher_and_parent_validator_accept_matching_stable_parallel_ids(self):
        result, runtime = self.run_real_dispatcher()
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        reports = list((runtime / "results").glob("tangle-validation-*.md"))
        self.assertEqual(len(reports), 1)
        self.assertIn("Successful: 1/1 result files", reports[0].read_text())
        self.assertIn("Terminal Outcomes: 1 succeeded", reports[0].read_text())
        self.assertIn("Tangle produced worktree changes:", reports[0].read_text())
        results = list((runtime / "results").glob("codex-tangle-*-T001.md"))
        self.assertEqual(len(results), 1)
        self.assertIn("nonce=", results[0].read_text())
        proof = json.loads(next((runtime / "feature/task-runs").glob("*/completed.json")).read_text())
        self.assertEqual(proof["tasks"][0]["status"], "completed")

    def test_real_parent_validator_rejects_success_without_coding_changes(self):
        result, runtime = self.run_real_dispatcher(NO_CHANGES="true")
        self.assertNotEqual(result.returncode, 0)
        report = next((runtime / "results").glob("tangle-validation-*.md")).read_text()
        self.assertIn("Missing Worktree Changes", report)
        proof = json.loads(next((runtime / "feature/task-runs").glob("*/completed.json")).read_text())
        self.assertEqual(proof["tasks"][0]["status"], "failed")
        self.assertEqual((self.root / "src/file1.py").read_text(), "pass\n")

    def test_actual_generic_parallel_uses_the_same_six_task_validator(self):
        contract = self.contract(*(self.task(index) for index in range(1, 7)))
        result, runtime, events = self.run_dispatcher(
            contract, mode="parallel", FIXTURE_EXPECTED_CONCURRENCY="6", FIXTURE_LAUNCH_DELAY="0.45")
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(self.concurrent_max(events), 6)
        self.assertEqual(len([event for event in events if event["event"] == "start"]), 6)
        self.assertIn("validation", (runtime / "gates").read_text())

    def assert_six_worker_rendezvous_rejects(self, **changes):
        contract = self.contract(*(self.task(index) for index in range(1, 7)))
        result, runtime, events = self.run_dispatcher(
            contract, mode="parallel", FIXTURE_EXPECTED_CONCURRENCY="6", **changes)
        self.assertNotEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        state = json.loads((runtime / "rendezvous.json").read_text())
        self.assertTrue(state["failed"])
        self.assertFalse(state["released"])
        self.assertLess(self.concurrent_max(events), 6)
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual(summary["completed"], [])

    def test_six_worker_rendezvous_rejects_four_worker_waves(self):
        self.assert_six_worker_rendezvous_rejects(FIXTURE_MAX_PARALLEL="4")

    def test_six_worker_rendezvous_rejects_serial_dispatch(self):
        self.assert_six_worker_rendezvous_rejects(FIXTURE_MAX_PARALLEL="1")

    def test_six_worker_rendezvous_rejects_stalled_launch(self):
        self.assert_six_worker_rendezvous_rejects(FIXTURE_STALL_ID="T006")

    def test_actual_generic_parallel_serializes_overlap(self):
        contract = self.contract(self.task(1), self.task(2, files=["src/file1.py"]))
        result, runtime, events = self.run_dispatcher(contract, mode="parallel")
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual(self.concurrent_max(events), 1)
        self.assertEqual(len([event for event in events if event["event"] == "start"]), 2)

    def assert_case_alias_dispatch_is_serial(self, mode):
        (self.root / "out").mkdir()
        contract = self.contract(self.task(1, files=[], creates=["out/Foo.py"]),
                                 self.task(2, files=[], creates=["out/foo.py"]))
        result, runtime, events = self.run_dispatcher(contract, mode=mode)
        starts = [event["id"].rsplit("-", 1)[-1] for event in events if event["event"] == "start"]
        self.assertEqual(self.concurrent_max(events), 1)
        self.assertEqual(starts[0], "T001")
        upper, lower = self.root / "out/Foo.py", self.root / "out/foo.py"
        proof = json.loads(next((runtime / "features/task-runs").glob("*/completed.json")).read_text())
        if lower.exists() and os.path.samefile(upper, lower):
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(starts, ["T001"])
            self.assertEqual(upper.read_text(), "validated T001\n")
            self.assertFalse(any(item["id"] == "T002" and item["status"] == "completed" for item in proof["tasks"]))
        else:
            self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
            self.assertEqual(starts, ["T001", "T002"])
            self.assertEqual(upper.read_text(), "validated T001\n")
            self.assertEqual(lower.read_text(), "validated T002\n")
            self.assertTrue(all(item["status"] == "completed" for item in proof["tasks"]))

    def test_actual_generic_parallel_serializes_planned_case_aliases(self):
        self.assert_case_alias_dispatch_is_serial("parallel")

    def test_actual_tangle_serializes_planned_case_aliases(self):
        self.assert_case_alias_dispatch_is_serial("tangle")

    def test_real_parent_rejects_case_distinct_unauthorized_write(self):
        probe = Path(self.temp.name) / "CaseProbe"
        probe.write_text("fixture\n")
        if probe.with_name("caseprobe").exists() and os.path.samefile(probe, probe.with_name("caseprobe")):
            self.skipTest("physical case-distinct files require a case-sensitive filesystem")
        result, runtime = self.run_real_dispatcher(UNAUTHORIZED_TARGET="src/File1.py")
        self.assertNotEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual((self.root / "src/file1.py").read_text(), "pass\n")
        self.assertEqual((self.root / "src/File1.py").read_text(), "validated T001\n")
        proof = json.loads(next((runtime / "feature/task-runs").glob("*/completed.json")).read_text())
        self.assertFalse(any(item["status"] == "completed" for item in proof["tasks"]))

    def test_actual_generic_parallel_does_not_unlock_failed_dependency(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]))
        result, runtime, events = self.run_dispatcher(contract, mode="parallel", FIXTURE_FAIL_ID="T001")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T001"])

    def run_requirement_gate(self, *tasks):
        gate_plugin = Path(os.environ.get("OCTOPUS_FEATURE_GATE_TEST_ROOT", str(PLUGIN))).resolve()
        gate_adapter = gate_plugin / "scripts/lib/feature-workflow.sh"
        clarification_helper = gate_plugin / "scripts/helpers/feature-clarifications.py"
        if not gate_adapter.exists() or not clarification_helper.exists():
            self.skipTest("Feature workflow integration is absent in this checkout")
        specification = Path(self.temp.name) / "requirement-marker-spec.md"
        specification.write_text("""# Export
## Behaviors
FR-001: Export in a user-selected format.
[NEEDS CLARIFICATION: Which format?]
```octopus-clarifications
[{"kind":"user_decision","id":"C001","question":"Which format?","requirements":["FR-001"],"phases":["develop"],"blocking_phases":["develop"],"blocking_reason":"The output contract depends on the format."}]
```
""")
        marker_result = subprocess.run([sys.executable, str(clarification_helper), "collect", "--spec", str(specification)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertEqual(marker_result.returncode, 0, marker_result.stderr.decode())
        markers = json.loads(marker_result.stdout)
        self.assertEqual(markers["markers"][0]["requirements"], ["FR-001"])
        self.assertEqual(markers["markers"][0]["task_ids"], [])
        marker_path = Path(self.temp.name) / "requirement-only-markers.json"
        marker_path.write_text(json.dumps(markers))
        contract = self.contract(*(tasks or (self.task(1), self.task(2))))
        return self.run_dispatcher(contract,
            FIXTURE_REQUIREMENT_GATE_PLUGIN=str(gate_plugin), FIXTURE_REQUIREMENT_MARKERS=str(marker_path))

    def test_actual_requirement_only_clarification_gate_blocks_matching_task_not_unrelated_task(self):
        result, runtime, events = self.run_requirement_gate()
        self.assertNotEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T002"])
        self.assertEqual((self.root / "src/file1.py").read_text(), "pass\n")
        self.assertEqual((self.root / "src/file2.py").read_text(), "validated T002\n")
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual(summary["status"], "partial")
        self.assertEqual([record["id"] for record in summary["completed"]], ["T002"])
        self.assertEqual({record["id"]: record["status"] for record in summary["completion_records"]}, {"T001": "blocked", "T002": "completed"})
        retained = json.loads((runtime / "features/clarifications.json").read_text())
        self.assertEqual(retained["markers"][0]["status"], "open")

    def test_actual_malformed_requirement_gate_defers_task_without_blocking_unrelated_task(self):
        result, runtime, events = self.run_requirement_gate(self.task(1, requirements=["--phase"]), self.task(2))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T002"])
        self.assertEqual((self.root / "src/file1.py").read_text(), "pass\n")
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual({record["id"]: record["status"] for record in summary["completion_records"]}, {"T001": "blocked", "T002": "completed"})
        self.assertIn("deferring", result.stderr.decode())

    def test_actual_requirement_values_cannot_override_the_gated_phase(self):
        result, runtime, events = self.run_requirement_gate(self.task(1, requirements=["FR-001", "--phase", "plan"]), self.task(2))
        self.assertNotEqual(result.returncode, 0, (result.stdout + result.stderr).decode())
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T002"])
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual({record["id"]: record["status"] for record in summary["completion_records"]}, {"T001": "blocked", "T002": "completed"})

    def test_actual_task_gate_keeps_dependent_work_pending_and_runs_unaffected_task(self):
        contract = self.contract(self.task(1), self.task(2, dependencies=["T001"]), self.task(3))
        result, runtime, events = self.run_dispatcher(contract, FIXTURE_BLOCK_ID="T001")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["id"].rsplit("-",1)[-1] for event in events if event["event"] == "start"], ["T003"])
        summary = json.loads(next((runtime / "features/task-runs").glob("*/summary.json")).read_text())
        self.assertEqual(summary["status"], "partial")
        self.assertEqual([record["id"] for record in summary["completed"]], ["T003"])

    def test_actual_tangle_cancellation_preserves_stable_marker_mapping(self):
        runtime = Path(self.temp.name) / "runtime-cancel"
        runtime.mkdir()
        contract = self.contract(self.task(1), self.task(2))
        (runtime / "contract.json").write_text(json.dumps(contract))
        (runtime / "worker.py").write_text(WORKER)
        environment = {**os.environ, "PLUGIN": str(PLUGIN), "EXEC_ROOT": str(self.root),
                       "FIXTURE_RUNTIME": str(runtime), "EXEC_MODE": "tangle"}
        process = subprocess.Popen(["/bin/bash"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env=environment)
        process.stdin.write(RUNTIME_SHELL.encode())
        process.stdin.close()
        deadline = time.monotonic() + 8
        event_file = runtime / "events.jsonl"
        while time.monotonic() < deadline and not event_file.exists():
            time.sleep(0.02)
        if not event_file.exists():
            process.kill()
            process.wait()
            self.fail("worker did not start before cancellation")
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=12)
        output = process.stdout.read() + process.stderr.read()
        self.assertNotEqual(process.returncode, 0, output.decode())
        markers = list((runtime / "workspace/.octo/agents").glob("*.done"))
        self.assertTrue(markers, output.decode())
        self.assertTrue(all(path.name.endswith(("-T001.done", "-T002.done")) for path in markers))
        self.assertTrue(any(path.read_text().strip() == "cancelled" for path in markers))
        completions = list((runtime / "features/task-runs").glob("*/completed.json"))
        self.assertTrue(completions)
        self.assertEqual(json.loads(completions[0].read_text())["tasks"], [])
        process.stdout.close()
        process.stderr.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
