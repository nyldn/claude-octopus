#!/usr/bin/env python3
"""Persist refinement admission and decisions. No provider calls or source edits."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import os
import re
import sys
import time


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def apply_stop(state, reason):
    """Preserve the first stop reason and restore the best saved before recalibration."""
    reason = state["stop_reason"] or reason
    if reason is None:
        return False
    changed = state["stop_reason"] != reason
    state["stop_reason"] = reason
    correction = state.get("correction")
    if correction:
        retained = dict(correction["best"], target_met=False)
        changed = changed or not correction.get("incomplete") or state["best"] != retained
        correction["incomplete"] = True
        state["best"] = retained
    return changed


def scoring():
    """Load the scorer beside this controller, independent of project imports."""
    spec = importlib.util.spec_from_file_location("refinement_score", Path(__file__).with_name("refinement-score.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(condition, message):
    """Reject invalid evidence or transitions before persisting state."""
    if not condition:
        raise ValueError(message)


@contextmanager
def locked(run):
    """Serialize admission and journal changes with the pair dispatch lock."""
    lock = run / ".dispatch-lock"
    lock.mkdir()
    try:
        yield
    finally:
        lock.rmdir()


def calls(run, state):
    """Validate recorded spending against the run's frozen deadline and budget."""
    path = run / "calls.jsonl"
    entries = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
    require(all(type(e.get("calls")) is int and e["calls"] > 0 and
                e.get("deadline") == state["deadline"] and e.get("max_calls") == state["max_calls"]
                for e in entries), "call ledger differs from the frozen run limits")
    return entries


def load(run):
    """Rebuild managed state from the journal and verify the preserved original."""
    path = run / "iterations.jsonl"
    require(path.is_file(), "initialize a managed refinement run before dispatch; legacy evidence stays unchanged")
    records = [json.loads(line) for line in path.read_text().splitlines()]
    require(records and records[0].get("event") == "initialized", "unmanaged or malformed iteration ledger")
    for index, record in enumerate(records):
        require(record.get("sequence") == index and record.get("state", {}).get("schema_version") == 1,
                "malformed iteration sequence")
        for field in ("deadline", "max_calls", "max_rounds", "seats", "original_sha256", "started_at"):
            require(record["state"][field] == records[0]["state"][field], "run limits or original changed")
    state = records[-1]["state"]
    require(digest(run / "original.snapshot") == state["original_sha256"], "preserved original changed")
    calls(run, state)
    return state


def write_trajectory(run, state):
    """Replace the derived round view without changing the authoritative journal."""
    temporary = run / "trajectory.json.tmp"
    temporary.write_text(json.dumps(state["rounds"], indent=2) + "\n")
    temporary.replace(run / "trajectory.json")


def persist(run, state, event):
    """Fsync one state transition before refreshing its derived trajectory."""
    path = run / "iterations.jsonl"
    sequence = len(path.read_text().splitlines()) if path.exists() else 0
    record = dict(event=event, sequence=sequence, time=time.time(), state=state)
    with path.open("a") as stream:
        stream.write(json.dumps(record, allow_nan=False) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    # The journal is authoritative. Status rebuilds a lost derived view.
    write_trajectory(run, state)


def validate_rubric(data):
    """Apply scorer schema checks without consuming a judge call."""
    engine = scoring()
    dummy = {"artifact_sha256": "schema", "judges": [], "guards": []}
    for provider in ("claude", "codex"):
        dummy["judges"].append(dict(
            provider=provider, model=provider, effort="high",
            rubric_sha256="schema", artifact_sha256="schema",
            criteria=[dict(id=c["id"], score=0, evidence="schema check")
                      for c in data["criteria"]], blockers=[]))
    dummy["guards"] = [dict(id=g["id"], status="unverified", evidence="schema check")
                       for g in data["guards"]]
    engine.evaluate(data, dummy, "schema", "schema")


def stop_reason(state):
    """Evaluate persisted and current stop conditions without changing state."""
    if state["stop_reason"]:
        return state["stop_reason"]
    if time.time() >= state["deadline"]:
        return "elapsed time limit"
    if state["stalls"] >= 2:
        return "two-round stall"
    if state["pending"] is None and state["next_round"] > state["max_rounds"]:
        return "improvement round limit"
    return None


def available(state):
    require(stop_reason(state) is None, "refinement stopped: " + str(stop_reason(state)))


def snapshot(path, data, resume=False):
    """Retain read-only evidence; interrupted retries must reproduce its bytes."""
    if path.exists():
        require(resume and path.read_bytes() == data, "snapshot already exists with different or uncommitted inputs")
        return
    path.write_bytes(data)
    path.chmod(0o400)


def initialize(run, original, rubric, deadline, max_calls, max_rounds, seats):
    """Freeze a new run's inputs and limits while refusing existing evidence."""
    require(not (run / "iterations.jsonl").exists() and not (run / "calls.jsonl").exists(),
            "existing run evidence cannot be reinitialized or assigned a new budget")
    require(math.isfinite(deadline) and deadline > time.time(), "future finite deadline required")
    require(max_calls > 0 and 1 <= max_rounds <= 10, "invalid refinement call or round limit")
    for seat, pattern in zip(seats, (r"claude(?:-opus|-sonnet|-opus-fast)?:[^\s:]+", r"codex(?:-standard|-max|-mini|-general|-spark|-reasoning|-large-context)?:[^\s:]+")):
        require(re.fullmatch(pattern, seat["provider"]) and seat["effort"] in ("low", "medium", "high", "xhigh", "max"),
                "explicit supported Claude and Codex model pins and efforts required")
    engine = scoring()
    original_bytes = Path(original).read_bytes()
    rb = Path(rubric).read_bytes()
    data = engine.load_json(rb)
    validate_rubric(data)
    snapshot(run / "original.snapshot", original_bytes)
    snapshot(run / "rubric.snapshot", rb)
    state = dict(schema_version=1, started_at=time.time(), deadline=deadline, max_calls=max_calls,
                 max_rounds=max_rounds, seats=seats, original_sha256=hashlib.sha256(original_bytes).hexdigest(),
                 rubric_path=str(Path(rubric).resolve()), next_round=0, pending=None,
                 rounds=[], best=None, stalls=0, stop_reason=None, correction=None)
    persist(run, state, "initialized")
    return state


def begin(run, state, pair):
    """Open one editing round only when both judge calls still fit."""
    available(state)
    require(state["pending"] is None, "close the pending round before starting another")
    require(re.fullmatch(r"[A-Za-z0-9_-]+", pair), "safe unique pair ID required")
    require(not any(r["pair_id"] == pair for r in state["rounds"]) and not any(e["pair_id"] == pair for e in calls(run, state)) and not (run / pair).exists(), "pair ID already used")
    require(sum(e["calls"] for e in calls(run, state)) + 2 <= state["max_calls"], "reserve two scoring calls before an improvement")
    state["pending"] = dict(round=state["next_round"], pair_id=pair, phase="editing")
    state["next_round"] += 1
    persist(run, state, "round-begun")
    return state


def close(run, state, decision, result=None, accepted=False, baseline=False):
    """Retain the decision and best candidate without charging correction stalls."""
    pending = state["pending"]
    row = dict(round=pending["round"], pair_id=pending["pair_id"], decision=decision,
               accepted=accepted, score=result["score"] if result else None,
               target_met=bool(result and result["target_met"] and (accepted or baseline) and not state.get("correction") and time.time() < state["deadline"]), judges=result["judges"] if result else [],
               artifact_sha256=pending.get("candidate_hash"), rubric_sha256=pending.get("rubric_hash"),
               score_report=pending.get("score_report"), calls_consumed=sum(e["calls"] for e in calls(run, state)),
               elapsed_seconds=time.time() - state["started_at"])
    state["rounds"].append(row)
    if baseline or accepted:
        state["best"] = dict(round=pending["round"], score=result["score"], artifact=pending["candidate"],
                             artifact_sha256=pending["candidate_hash"], rubric_sha256=pending["rubric_hash"],
                             target_met=bool(result["target_met"] and time.time() < state["deadline"]))
    if pending.get("purpose") != "correction-best":
        if accepted:
            state["stalls"] = 0
        elif not baseline and pending["round"] > 0:
            state["stalls"] += 1
    if time.time() >= state["deadline"]:
        apply_stop(state, "elapsed time limit")
        if state["best"]:
            state["best"]["target_met"] = False
    if not state.get("correction") and state["best"] and state["best"].get("target_met"):
        apply_stop(state, "target reached")
        for prior in state["rounds"]:
            if prior["round"] == state["best"]["round"]:
                prior["target_met"] = True
    state["pending"] = None
    apply_stop(state, stop_reason(state))
    persist(run, state, decision)
    return state


def prepare(run, state, candidate, guards, rubric=None):
    """Validate captured bytes before freezing a candidate and guard evidence."""
    available(state)
    pending = state["pending"]
    require(pending and pending["phase"] == "editing", "begin one round before preparing its candidate")
    rubric = Path(rubric or state["rubric_path"])
    candidate_bytes = Path(candidate).read_bytes()
    guard_bytes = Path(guards).read_bytes()
    rubric_bytes = rubric.read_bytes()
    engine = scoring()
    parsed = engine.load_json(rubric_bytes)
    validate_rubric(parsed)
    rows = engine.load_json(guard_bytes)
    require(isinstance(rows, list) and len(rows) == len(parsed["guards"]) and
            {g["id"] for g in rows} == {g["id"] for g in parsed["guards"]} and
            all(g.get("status") in ("pass", "fail", "unverified") and isinstance(g.get("evidence"), str) and g["evidence"].strip() for g in rows),
            "complete guard results and evidence required")
    candidate_hash, rubric_hash = hashlib.sha256(candidate_bytes).hexdigest(), hashlib.sha256(rubric_bytes).hexdigest()
    scored = [e for e in calls(run, state) if e.get("hashes", {}).get("rubric")]
    correction = state.get("correction")
    correcting_original = bool(scored and not correction and candidate_hash == state["original_sha256"] and rubric_hash != scored[-1]["hashes"]["rubric"])
    correcting_best = bool(correction and correction["phase"] == "best")
    if correcting_best:
        require(candidate_hash == correction["best"]["artifact_sha256"] and rubric_hash == correction["rubric_hash"], "rescore the retained best under the corrected rubric before another candidate")
    if correcting_original:
        require(state["next_round"] <= state["max_rounds"] and sum(e["calls"] for e in calls(run, state)) + 4 <= state["max_calls"], "rubric correction needs capacity for both rescores")
    if pending["round"] == 0:
        require(candidate_hash == state["original_sha256"], "baseline must assess the original")
    historical = pending["round"] == 0 or correcting_original or correcting_best
    pending["purpose"] = "correction-original" if correcting_original else "correction-best" if correcting_best else "ordinary"
    directory = run / "candidates" / pending["pair_id"]
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    require({p.name for p in directory.iterdir()} <= {"candidate", "guards", "rubric"}, "unexpected files in pending snapshot")
    for name, data in (("candidate", candidate_bytes), ("guards", guard_bytes), ("rubric", rubric_bytes)):
        snapshot(directory / name, data, resume=True)
    pending.update(phase="prepared", candidate=str(directory / "candidate"), candidate_hash=candidate_hash,
                   guards=str(directory / "guards"), rubric_hash=rubric_hash)
    if not historical and any(g["status"] != "pass" for g in rows):
        return close(run, state, "guard failure")
    elif not historical and any(r["artifact_sha256"] == pending["candidate_hash"] and r["rubric_sha256"] == pending["rubric_hash"] for r in state["rounds"]):
        return close(run, state, "unchanged candidate")
    persist(run, state, "candidate-prepared")
    return state


def admit(run, pair, frozen, deadline, budget, seats, correction=None):
    """Called under the pair helper's dispatch lock before reserving or launching."""
    state = load(run)
    available(state)
    require(deadline == state["deadline"] and budget == state["max_calls"] and seats == state["seats"], "dispatch differs from frozen run limits or panel")
    pending = state["pending"]
    require(pending and pending["pair_id"] == pair and pending["phase"] == "prepared", "prepare and close rounds through refinement-run.py before dispatch")
    require(bool(correction) == (pending.get("purpose") == "correction-original"), "rubric correction must prepare the original candidate explicitly")
    require(frozen["candidate"] == pending["candidate_hash"] and frozen["rubric"] == pending["rubric_hash"], "prepared candidate or rubric changed")
    return state


def dispatched(run, state, manifest):
    """Journal the reservation and retain the prior best during recalibration."""
    if manifest.get("rubric_correction"):
        state["correction"] = dict(phase="original", best=state["best"].copy(), rubric_hash=manifest["hashes"]["rubric"])
    state["pending"]["phase"] = "judging"
    persist(run, state, "pair-reserved")


def abort(run, reason):
    """End a failed pair while preserving the run's first stop reason."""
    with locked(run):
        state = load(run)
        apply_stop(state, stop_reason(state) or reason)
        if state["pending"]:
            close(run, state, state["stop_reason"])
        else:
            persist(run, state, reason)


def record(run, state, assessment):
    """Validate both judges against frozen inputs before retaining a decision."""
    pending = state["pending"]
    require(pending and pending["phase"] == "judging", "no completed pair is awaiting assessment")
    pair = run / pending["pair_id"]
    manifest = json.loads((pair / "manifest.json").read_text())
    require(manifest["state"] == "raw-results" and manifest["exit_codes"] == [0, 0], "both required judges must finish successfully")
    candidate_bytes = (pair / "candidate").read_bytes()
    rubric_bytes = (pair / "rubric").read_bytes()
    require(hashlib.sha256(candidate_bytes).hexdigest() == pending["candidate_hash"] and hashlib.sha256(rubric_bytes).hexdigest() == pending["rubric_hash"], "frozen pair inputs changed")
    engine = scoring()
    assessment_bytes = Path(assessment).read_bytes()
    data = engine.load_json(assessment_bytes)
    require(data["guards"] == engine.load_json(Path(pending["guards"]).read_bytes()), "assessment guards differ from the prepared evidence")
    for judge, seat in zip(sorted(data["judges"], key=lambda j: j["provider"]), state["seats"]):
        require(judge["provider"] == ("claude" if seat["provider"].startswith("claude") else "codex") and
                judge["model"] == seat["provider"].split(":", 1)[1] and judge["effort"] == seat["effort"], "assessment identity differs from the fixed dispatch")
    result = engine.evaluate(engine.load_json(rubric_bytes), data, pending["rubric_hash"], pending["candidate_hash"])
    # Copy assessments so later host edits cannot rewrite the retained decision.
    snapshot(pair / "validated-assessment.json", assessment_bytes, resume=True)
    report = pair / "score.json"
    report.write_text(json.dumps(result, indent=2) + "\n")
    pending["score_report"] = str(report)
    best = state["best"]
    baseline = pending["round"] == 0 or bool(manifest.get("rubric_correction"))
    eligible = not result["criterion_failures"] and not result["blockers"] and not result["failed_guards"] and result["disagreement"] <= 10
    accepted = not baseline and eligible and best is not None and best["rubric_sha256"] == pending["rubric_hash"] and result["score"] > best["score"] and time.time() < state["deadline"]
    if state.get("correction") and stop_reason(state):
        apply_stop(state, stop_reason(state))
    elif manifest.get("rubric_correction"):
        # The original calibrates the new rubric; success waits for the retained
        # best too. If best is original, this pair already assessed both.
        if state["correction"]["best"]["artifact_sha256"] == state["original_sha256"]:
            state["correction"] = None
        else:
            state["correction"]["phase"] = "best"
    elif pending.get("purpose") == "correction-best":
        state["correction"] = None
    return close(run, state, "baseline retained" if baseline else "accepted" if accepted else "rejected", result, accepted, baseline)


def main(argv=None):
    """Apply one CLI transition under the run lock and print journal-backed state."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init")
    init.add_argument("run", type=Path); init.add_argument("original", type=Path); init.add_argument("rubric", type=Path)
    init.add_argument("--deadline", type=float, required=True); init.add_argument("--max-calls", type=int, default=14)
    init.add_argument("--max-rounds", type=int, default=5)
    init.add_argument("--claude", required=True); init.add_argument("--codex", required=True)
    init.add_argument("--claude-effort", default="high"); init.add_argument("--codex-effort", default="high")
    for command in ("begin", "prepare", "record", "status", "reserve", "stop"):
        child = sub.add_parser(command); child.add_argument("run", type=Path)
        if command == "begin": child.add_argument("pair")
        if command == "prepare":
            child.add_argument("candidate", type=Path); child.add_argument("guards", type=Path); child.add_argument("--rubric", type=Path)
        if command == "record": child.add_argument("assessment", type=Path)
        if command == "reserve": child.add_argument("call_id"); child.add_argument("count", type=int)
        if command == "stop": child.add_argument("reason")
    args = parser.parse_args(argv)
    run = args.run.resolve()
    with locked(run):
        if args.command == "init":
            state = initialize(run, args.original, args.rubric, args.deadline, args.max_calls, args.max_rounds,
                               [dict(provider=args.claude, effort=args.claude_effort), dict(provider=args.codex, effort=args.codex_effort)])
        else:
            state = load(run)
            if args.command == "begin": state = begin(run, state, args.pair)
            elif args.command == "prepare": state = prepare(run, state, args.candidate, args.guards, args.rubric)
            elif args.command == "record": state = record(run, state, args.assessment)
            elif args.command == "status": write_trajectory(run, state)
            elif args.command == "stop":
                require(bool(args.reason.strip()), "stop reason is required")
                apply_stop(state, stop_reason(state) or args.reason)
                if state["pending"]:
                    close(run, state, state["stop_reason"])
                else:
                    persist(run, state, "stopped")
            elif args.command == "reserve":
                available(state)
                entries = calls(run, state)
                require(re.fullmatch(r"[A-Za-z0-9_-]+", args.call_id) and args.count > 0 and not (state["pending"] and state["pending"]["pair_id"] == args.call_id) and not any(e["pair_id"] == args.call_id for e in entries), "unique external call ID and positive count required")
                require(sum(e["calls"] for e in entries) + args.count + 2 <= state["max_calls"], "external call would spend reserved scoring capacity")
                with (run / "calls.jsonl").open("a") as stream:
                    stream.write(json.dumps(dict(pair_id=args.call_id, calls=args.count, deadline=state["deadline"], max_calls=state["max_calls"], kind="external")) + "\n")
                    stream.flush(); os.fsync(stream.fileno())
                persist(run, state, "external-call-reserved")
        if apply_stop(state, stop_reason(state)):
            persist(run, state, "stopped")
        print(json.dumps(state, allow_nan=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, TypeError, KeyError, OSError) as error:
        print(f"ERROR: refinement run: {error}", file=sys.stderr)
        sys.exit(1)
