#!/usr/bin/env python3
"""Own factory inputs, result paths and evaluation evidence for one invocation."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import uuid

PLUGIN_ROOT = Path(__file__).resolve().parents[2]
MAX_INPUT = 1_048_576
WEIGHTS = {"behavior_coverage": .40, "constraint_adherence": .20,
           "holdout_pass_rate": .25, "quality": .15}


def read_text(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_INPUT:
        raise ValueError("Missing, linked or oversized factory evidence: " + str(path))
    return path.read_text()


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Factory scores must be numbers")
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError("Factory scores must be finite and between zero and one")
    return value


def field(text, name):
    matches = re.findall(r"\b" + re.escape(name) +
                         r"\s*[:=]\s*([^\s,;]+)", text.replace("**", ""), re.I)
    if len(matches) != 1:
        raise ValueError("Expected one measured " + name)
    return number(float(matches[0]))


def score(run_dir, target):
    output = run_dir / "satisfaction-scores.json"
    output.unlink(missing_ok=True)
    measured = read_text(run_dir / "satisfaction-evaluation.txt")
    scores = {name: field(measured, name) for name in
              ("behavior_coverage", "constraint_adherence", "quality")}
    scores["holdout_pass_rate"] = measured_holdout(run_dir)
    target = number(target)
    composite = round(sum(scores[name] * weight for name, weight in WEIGHTS.items()), 2)
    verdict = "PASS" if composite >= target else "WARN" if composite >= target - .05 else "FAIL"
    write_json(output, dict(scores, composite=composite, satisfaction_target=target,
                            verdict=verdict, weights=WEIGHTS,
                            scored_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")))
    print(str(composite) + "|" + verdict)
    return 0


def measured_holdout(run_dir):
    text = read_text(run_dir / "holdout-results.md")
    if re.search(r"\bscore\s*[:=]", text.replace("**", ""), re.I):
        return field(text, "score")
    verdicts = re.findall(r"^\s*(?:-\s*)?Verdict\s*:\s*(PASS|PARTIAL|FAIL)\b",
                          text.replace("**", ""), re.I | re.M)
    if not verdicts:
        raise ValueError("Holdout evaluation has no measured score or scenario verdicts")
    return round(sum({"PASS": 1, "PARTIAL": .5, "FAIL": 0}[v.upper()]
                     for v in verdicts) / len(verdicts), 2)


def coverage(run_dir, response=None, skipped=None):
    if skipped:
        result = {"status": skipped, "verdict": None}
    else:
        text = read_text(response).strip()
        fence = chr(96) * 3
        if text.startswith(fence + "json\n") and text.endswith("\n" + fence):
            text = text[8:-4]
        result = json.loads(text)
        if (not isinstance(result, dict)
                or result.get("verdict") not in ("SUFFICIENT", "GAPS-FOUND", "CRITICAL-GAPS")
                or not isinstance(result.get("gaps"), list)
                or any(not isinstance(gap, str) for gap in result["gaps"])):
            raise ValueError("Coverage review did not provide a valid verdict and gaps")
        result["status"] = "reviewed"
    write_json(run_dir / "coverage-review.json", result)
    print(result["verdict"] or result["status"])
    return 1 if result["verdict"] == "CRITICAL-GAPS" else 0


def run(args):
    if args.approval == "decline":
        print(json.dumps({"status": "declined"}))
        return 2
    target = args.target
    if target is not None and (not math.isfinite(target) or not .80 <= target <= .99):
        raise ValueError("The selected target must be between 0.80 and 0.99")
    if not 1 <= args.timeout <= 86400:
        raise ValueError("Factory timeout must be between one second and one day")
    if args.holdout_ratio is not None and (not math.isfinite(args.holdout_ratio) or not 0 <= args.holdout_ratio < 1):
        raise ValueError("Holdout ratio must be between zero inclusive and one exclusive")
    if args.max_retries is not None and not 0 <= args.max_retries <= 5:
        raise ValueError("Factory retry limit must be between zero and five")
    project = args.project.resolve(strict=True)
    plugin = (args.plugin_root or PLUGIN_ROOT).resolve(strict=True)
    orchestrator = plugin / "scripts/orchestrate.sh"
    if not project.is_dir() or not orchestrator.is_file():
        raise ValueError("Project or loaded plugin root is invalid")
    if args.inline:
        specification = sys.stdin.buffer.read(MAX_INPUT + 1)
    else:
        spec = args.spec.resolve(strict=True)
        if not spec.is_file() or spec.stat().st_size > MAX_INPUT:
            raise ValueError("Specification is missing or oversized")
        specification = spec.read_bytes()
    if not specification.strip() or len(specification) > MAX_INPUT:
        raise ValueError("Specification is empty or oversized")
    parent = project / ".octo/factory"
    if not parent.resolve().is_relative_to(project):
        raise ValueError("Factory state must remain inside the project")
    parent.mkdir(parents=True, exist_ok=True)
    request = Path(tempfile.mkdtemp(prefix="request-", dir=parent))
    request.chmod(0o700)
    spec = request / "spec.md"
    spec.write_bytes(specification)
    spec.chmod(0o600)
    run_id = "factory-" + uuid.uuid4().hex
    run_dir = parent / run_id
    context = {"run_id": run_id, "run_dir": str(run_dir), "request_dir": str(request),
               "spec_sha256": hashlib.sha256(specification).hexdigest(),
               "selected_target": target, "status": "running"}
    context_path = request / "result.json"
    write_json(context_path, context)
    print("Factory evidence: " + str(context_path), file=sys.stderr, flush=True)
    env = dict(os.environ)
    env["OCTOPUS_FACTORY_RUN_ID"] = run_id
    env["OCTOPUS_FACTORY_COVERAGE_REVIEW"] = "0" if args.fast else "1"
    env.pop("OCTOPUS_FACTORY_SATISFACTION_TARGET", None)
    if target is not None:
        env["OCTOPUS_FACTORY_SATISFACTION_TARGET"] = str(target)
    command = [str(orchestrator), "factory", "--spec", str(spec)]
    if args.holdout_ratio is not None:
        command.extend(["--holdout-ratio", str(args.holdout_ratio)])
    if args.max_retries is not None:
        command.extend(["--max-retries", str(args.max_retries)])
    if args.approval == "ci":
        command.append("--ci")
    sys.path.insert(0, str(PLUGIN_ROOT / "shared"))
    from process_supervisor import run_bounded_process

    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, interrupted)
    try:
        rc, output = run_bounded_process(command, project, args.timeout, shell=False,
                                         output_limit=16 * 1024 * 1024, env=env)
        (request / "factory.log").write_text(output)
        if rc:
            raise ValueError("Factory command failed with status " + str(rc))
        manifest = json.loads(read_text(run_dir / "session.json"))
        scores = json.loads(read_text(run_dir / "satisfaction-scores.json"))
        report = read_text(run_dir / "factory-report.md")
        review = json.loads(read_text(run_dir / "coverage-review.json"))
        if (not isinstance(review, dict)
                or review.get("status") not in ("reviewed", "skipped-fast", "skipped-unavailable")
                or (review["status"] == "reviewed"
                    and review.get("verdict") not in ("SUFFICIENT", "GAPS-FOUND"))
                or (review["status"] == "skipped-fast" and not args.fast)):
            raise ValueError("Factory coverage evidence is missing or inconsistent")
        if manifest.get("run_id") != run_id or not report.strip():
            raise ValueError("Factory artifacts do not identify this run")
        if (run_dir / "spec.md").read_bytes() != specification:
            raise ValueError("Factory specification changed during execution")
        for name in (*WEIGHTS, "composite", "satisfaction_target"):
            number(scores[name])
        if (scores.get("verdict") not in ("PASS", "WARN", "FAIL")
                or manifest.get("satisfaction_target") != scores["satisfaction_target"]
                or (target is not None and scores["satisfaction_target"] != target)):
            raise ValueError("Factory verdict or target is inconsistent")
        context.update(status="completed", report=str(run_dir / "factory-report.md"),
                       scores=scores, coverage_review=review)
    except BaseException as error:
        if hasattr(error, "output"):
            (request / "factory.log").write_text(error.output)
        context.update(status="failed", error=str(error))
        write_json(context_path, context)
        print(json.dumps(context))
        if not isinstance(error, Exception):
            raise
        return 1
    write_json(context_path, context)
    print(json.dumps(context))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    execute = modes.add_parser("run")
    execute.add_argument("--project", type=Path, default=Path.cwd())
    execute.add_argument("--plugin-root", type=Path)
    execute.add_argument("--approval", choices=("approve", "ci", "decline"), default="decline")
    specification = execute.add_mutually_exclusive_group(required=True)
    specification.add_argument("--spec", type=Path)
    specification.add_argument("--inline", action="store_true")
    execute.add_argument("--target", type=float)
    execute.add_argument("--holdout-ratio", type=float)
    execute.add_argument("--max-retries", type=int)
    execute.add_argument("--fast", action="store_true")
    execute.add_argument("--timeout", type=float, default=1800)
    evaluation = modes.add_parser("score")
    evaluation.add_argument("--run-dir", type=Path, required=True)
    evaluation.add_argument("--target", type=float, required=True)
    holdout = modes.add_parser("holdout")
    holdout.add_argument("--run-dir", type=Path, required=True)
    review = modes.add_parser("coverage")
    review.add_argument("--run-dir", type=Path, required=True)
    review.add_argument("--response", type=Path)
    review.add_argument("--skipped", choices=("skipped-fast", "skipped-unavailable"))
    args = parser.parse_args()
    try:
        if args.mode == "run":
            return run(args)
        if args.mode == "score":
            return score(args.run_dir, args.target)
        if args.mode == "holdout":
            print(measured_holdout(args.run_dir))
            return 0
        if not args.skipped and args.response is None:
            raise ValueError("Coverage review requires a response")
        return coverage(args.run_dir, args.response, args.skipped)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("factory-run: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
