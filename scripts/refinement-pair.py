#!/usr/bin/env python3
"""Reserve and overlap two judge calls. Raw output is not a validated score.

Usage: refinement-pair.py RUN_DIR PAIR_ID PROMPT CANDIDATE RUBRIC DEADLINE MAX_CALLS
       CLAUDE_SPEC CLAUDE_EFFORT CODEX_SPEC CODEX_EFFORT
       [--rubric-correction PREVIOUS_SHA256 REASON]
DEADLINE is the absolute Unix deadline for the whole run, reused on resume.
Before any other external call, append a reservation with its calls to calls.jsonl
under the same .dispatch-lock. Reservations count even after failure/cancellation.
"""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


def digest(path):
    """Hash artifact bytes to bind both judges to the same input."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, data):
    """Publish a JSON record through an atomic rename."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def terminate_owned_children(children):
    # Unreaped leaders reserve their PIDs and process-group IDs. Reaping a leader
    # before the final group signal could target a subsequently reused group ID.
    """Signal owned process groups before reaping their session leaders."""
    for child in children:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if children:
        time.sleep(0.2)
    for child in children:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    for child in children:
        child.wait(timeout=1)


def rubric_transition(entries, frozen, correction):
    """Require an explicit correction and rescore the original at a new version."""
    scored = [entry for entry in entries if entry.get("hashes", {}).get("rubric")]
    if not scored:
        if correction is not None:
            raise ValueError("rubric correction requires a prior scored rubric")
        return {"rubric_version": 1}
    previous = scored[-1]
    version = previous.get("rubric_version", 1)
    if type(version) is not int or version < 1:
        raise ValueError("malformed rubric version in ledger")
    old_hash = previous["hashes"]["rubric"]
    if frozen["rubric"] == old_hash:
        if correction is not None:
            raise ValueError("rubric correction requires changed rubric bytes")
        return {"rubric_version": version}
    if correction is None:
        raise ValueError("resume cannot change rubric without --rubric-correction")
    expected, reason = correction
    if expected != old_hash or not reason.strip() or len(reason) > 2000:
        raise ValueError("rubric correction requires the current hash and a bounded reason")
    if frozen["candidate"] != scored[0]["hashes"]["candidate"]:
        raise ValueError("rubric correction must rescore the original candidate first")
    return {"rubric_version": version + 1, "rubric_correction": {
        "previous_sha256": old_hash, "new_sha256": frozen["rubric"], "reason": reason}}


def main():
    """Reserve both calls and preserve paired raw results within the run budget."""
    args = sys.argv[1:]
    correction = None
    if len(args) == 14 and args[11] == "--rubric-correction":
        correction = args[12:]
        args = args[:11]
    if len(args) != 11:
        raise ValueError(__doc__)
    directory, pair, prompt, candidate, rubric, deadline, budget, claude, ce, codex, xe = args
    run = Path(directory).resolve()
    if not run.is_dir() or not re.fullmatch(r"[A-Za-z0-9_-]+", pair):
        raise ValueError("existing private run directory and safe pair ID required")
    deadline, budget = float(deadline), int(budget)
    if not math.isfinite(deadline) or deadline <= time.time() or budget < 2:
        raise ValueError("pair has insufficient time/call budget")
    if not re.fullmatch(r"claude(?:-opus|-sonnet|-opus-fast)?:[^\s:]+", claude) or not re.fullmatch(r"codex(?:-standard|-max|-mini|-general|-spark|-reasoning|-large-context)?:[^\s:]+", codex):
        raise ValueError("explicit Claude and Codex model pins required")
    if ce not in ("low", "medium", "high", "xhigh", "max") or xe not in ("low", "medium", "high", "xhigh", "max"):
        raise ValueError("explicit supported efforts required")
    frozen = {"prompt": digest(prompt), "candidate": digest(candidate), "rubric": digest(rubric)}
    control_spec = importlib.util.spec_from_file_location("refinement_run", Path(__file__).with_name("refinement-run.py"))
    control = importlib.util.module_from_spec(control_spec)
    control_spec.loader.exec_module(control)
    lock = run / ".dispatch-lock"
    lock.mkdir()  # Concurrent reservations fail closed; stale locks need inspection.
    try:
        seats = [dict(provider=claude, effort=ce), dict(provider=codex, effort=xe)]
        run_state = control.admit(run, pair, frozen, deadline, budget, seats, correction)
        ledger = run / "calls.jsonl"
        entries = [json.loads(line) for line in ledger.read_text().splitlines()] if ledger.exists() else []
        if any(e["pair_id"] == pair for e in entries):
            raise ValueError("pair already reserved; inspect saved results, never redispatch")
        seats = [dict(provider=claude, effort=ce), dict(provider=codex, effort=xe)]
        if any(e.get("seats", seats) != seats for e in entries):
            raise ValueError("resume cannot change panel, models, or efforts")
        if any(e["deadline"] != deadline or e["max_calls"] != budget for e in entries):
            raise ValueError("resume cannot reset run budget or deadline")
        revision = rubric_transition(entries, frozen, correction)
        required_calls = 4 if correction is not None else 2
        if any(type(e["calls"]) is not int or e["calls"] < 1 for e in entries) or sum(e["calls"] for e in entries) + required_calls > budget:
            raise ValueError("call budget exhausted or malformed")
        output = run / pair
        output.mkdir(mode=0o700)
        # Freeze a single prompt file for both seats before either launches.
        request = output / "request.txt"
        request.write_bytes(Path(prompt).read_bytes())
        if digest(request) != frozen["prompt"]:
            raise ValueError("prompt changed while freezing")
        request.chmod(0o400)
        for name, source in (("candidate", candidate), ("rubric", rubric)):
            snapshot = output / name
            snapshot.write_bytes(Path(source).read_bytes())
            snapshot.chmod(0o400)
            if digest(snapshot) != frozen[name]:
                raise ValueError(f"{name} changed while freezing")
        manifest = dict(pair_id=pair, calls=2, deadline=deadline, max_calls=budget,
                        hashes=frozen, seats=seats, **revision,
                        state="reserved", score_validated=False)
        with ledger.open("a") as stream:
            stream.write(json.dumps(manifest) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        save(output / "manifest.json", manifest)
        control.dispatched(run, run_state, manifest)
    finally:
        lock.rmdir()
    children, streams, statuses = [], [], []
    def cancel(signum, frame):
        """Enter finalization so every owned judge process is stopped."""
        raise InterruptedError("paired dispatch cancelled")
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGHUP, cancel)
    try:
        for index, (provider, effort) in enumerate(((claude, ce), (codex, xe))):
            remaining = min(3600, int(deadline - time.time()))
            if remaining < 1:
                raise TimeoutError("shared deadline exhausted before launch")
            seat = output / str(index)
            seat.mkdir()
            stdout, stderr = (open(seat / name, "wb") for name in ("stdout", "stderr"))
            streams.extend((stdout, stderr))
            env = {key: value for key, value in os.environ.items()
                   if not (key.startswith("OCTOPUS_") and key.endswith("_REASONING"))}
            env.update(OCTOPUS_EFFORT_OVERRIDE=effort, OCTOPUS_REASONING_LEVEL=effort,
                       OCTOPUS_PROBE_RESEARCHER_REASONING=effort, OCTOPUS_REASONING_POLICY="strict",
                       OCTOPUS_AUTH_RETRIES="0", OCTOPUS_FABLE5_NO_RETRY="1",
                       OCTOPUS_PREFLIGHT_PROVIDERS="claude,codex")
            status = seat / "exit-status"
            statuses.append(status)
            env["OCTOPUS_REFINEMENT_EXIT_FILE"] = str(status)
            # The session leader stays alive after publishing its result.
            # This also avoids macOS rejecting signals to zombie-only groups.
            # Arguments remain separate argv entries, never shell source.
            wrapper = ('trap ":" TERM INT HUP; "$@"; seat_status=$?; '
                       'printf "%s\\n" "$seat_status" > "$OCTOPUS_REFINEMENT_EXIT_FILE.tmp" && '
                       'mv "$OCTOPUS_REFINEMENT_EXIT_FILE.tmp" "$OCTOPUS_REFINEMENT_EXIT_FILE"; '
                       'while :; do sleep 60; done')
            children.append(subprocess.Popen(["/bin/sh", "-c", wrapper, "refinement-seat",
                str(Path(__file__).with_name("refinement-judge.sh")), provider,
                str(remaining), str(request), f"{pair}-{index}", str(seat)], env=env,
                stdout=stdout, stderr=stderr, start_new_session=True))
        while True:
            codes = [int(path.read_text()) if path.exists() else None for path in statuses]
            if any(code is not None and code != 0 for code in codes) or all(code is not None for code in codes):
                break
            if time.time() >= deadline:
                raise TimeoutError("shared judge deadline exhausted")
            time.sleep(min(0.05, max(0.001, deadline - time.time())))
        manifest.update(state="raw-results" if codes == [0, 0] else "failed", exit_codes=codes)
        if codes != [0, 0]:
            raise RuntimeError("both judge calls must complete; no passing pair exists")
    except BaseException:
        manifest["state"] = "failed"
        raise
    finally:
        for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(signum, signal.SIG_IGN)
        try:
            terminate_owned_children(children)
        except (OSError, subprocess.TimeoutExpired):
            manifest["state"] = "failed"
            raise
        finally:
            for stream in streams:
                stream.close()
            save(output / "manifest.json", manifest)
            if manifest["state"] == "failed":
                control.abort(run, "required provider failure or cancellation")
    print(output / "manifest.json")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, TypeError, KeyError, OSError, RuntimeError, TimeoutError, InterruptedError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: refinement pair: {error}", file=sys.stderr)
        sys.exit(1)
