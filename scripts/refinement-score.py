#!/usr/bin/env python3
"""Validate two independent assessments and compute a frozen rubric's score."""

import hashlib
import json
from decimal import Decimal
from fractions import Fraction
from pathlib import Path
import sys


def require(condition, message):
    """Reject a violated input contract with a readable error."""
    if not condition:
        raise ValueError(message)


def number(value, low, high, label):
    """Validate a finite numeric field and preserve its exact decimal value."""
    require(type(value) in (int, float, Decimal), f"{label} must be a number")
    decimal = Decimal(str(value))
    require(decimal.is_finite() and low <= decimal <= high,
            f"{label} must be finite and in {low}..{high}")
    return Fraction(decimal)


def text(value, label):
    """Require nonempty evidence or metadata text."""
    require(isinstance(value, str) and bool(value.strip()), f"{label} is required")
    return value


def object_value(value, label):
    """Require an object before reading its fields."""
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def indexed(values, label):
    """Index entries by unique nonempty IDs."""
    require(isinstance(values, list), f"{label} must be an array")
    result = {}
    for value in values:
        object_value(value, label)
        key = text(value.get("id"), f"{label} id")
        require(key not in result, f"duplicate {label} id: {key}")
        result[key] = value
    return result


def evaluate(rubric, assessment, rubric_hash, artifact_hash):
    """Validate both assessments and compute target eligibility from exact scores."""
    object_value(rubric, "rubric")
    object_value(assessment, "assessment")
    require(type(rubric.get("schema_version")) is int and rubric["schema_version"] == 1,
            "unsupported rubric schema_version")
    target = number(rubric.get("target"), 0, 100, "target")
    criteria = indexed(rubric.get("criteria"), "rubric criteria")
    require(bool(criteria), "rubric needs at least one criterion")
    weights, minimums = {}, {}
    for key, criterion in criteria.items():
        text(criterion.get("description"), f"{key} description")
        weights[key] = number(criterion.get("weight"), 0, 100, f"{key} weight")
        require(weights[key] > 0, f"{key} weight must be positive")
        minimums[key] = number(criterion.get("minimum"), 0, 4, f"{key} minimum")
        anchors = object_value(criterion.get("anchors"), f"{key} anchors")
        require(set(anchors) == {"0", "1", "2", "3", "4"}, f"{key} needs anchors 0..4")
        for anchor, description in anchors.items():
            text(description, f"{key} anchor {anchor}")
    require(sum(weights.values()) == 100, "weights must total 100")
    required_guards = indexed(rubric.get("guards"), "rubric guards")
    for key, guard in required_guards.items():
        text(guard.get("description"), f"{key} guard description")
    require(assessment.get("artifact_sha256") == artifact_hash, "assessment artifact hash mismatch")
    judges = assessment.get("judges")
    require(isinstance(judges, list) and len(judges) == 2, "exactly two judges are required")
    providers, models, totals, failures, blockers = set(), set(), [], [], []
    for judge in judges:
        object_value(judge, "judge")
        provider = text(judge.get("provider"), "judge provider")
        require(provider in {"claude", "codex"},
                "judge provider must be canonical claude or codex from dispatch metadata")
        model = text(judge.get("model"), "judge model")
        text(judge.get("effort"), "judge effort")
        require(provider not in providers and model not in models,
                "judges must use distinct providers and models")
        providers.add(provider)
        models.add(model)
        require(judge.get("rubric_sha256") == rubric_hash, "judge rubric hash mismatch")
        require(judge.get("artifact_sha256") == artifact_hash, "judge artifact hash mismatch")
        scores = indexed(judge.get("criteria"), "judge criteria")
        require(set(scores) == set(criteria), "judge criteria must exactly match rubric")
        total = 0
        for key, criterion in criteria.items():
            score = number(scores[key].get("score"), 0, 4, f"{key} score")
            text(scores[key].get("evidence"), f"{key} evidence")
            total += weights[key] * score / 4
            if score < minimums[key]:
                failures.append({"provider": provider, "id": key, "score": float(score),
                                 "minimum": float(minimums[key])})
        findings = judge.get("blockers")
        require(isinstance(findings, list), "judge blockers must be an array")
        for finding in findings:
            blockers.append({"provider": provider, "finding": text(finding, "blocker")})
        totals.append({"provider": provider, "model": model, "score": total})
    guards = indexed(assessment.get("guards"), "assessment guards")
    require(set(guards) == set(required_guards), "assessment guards must exactly match rubric")
    failed_guards = []
    for key, guard in guards.items():
        require(guard.get("status") in ("pass", "fail", "unverified"), f"{key} invalid guard status")
        text(guard.get("evidence"), f"{key} guard evidence")
        if guard["status"] != "pass":
            failed_guards.append(key)
    score = min(t["score"] for t in totals)
    disagreement = max(t["score"] for t in totals) - score
    # Compare the unrounded values. Display rounding must never create a pass.
    met = (score >= target and not failures and not blockers and
           not failed_guards and disagreement <= 10)
    return {"valid": True, "rubric_sha256": rubric_hash, "artifact_sha256": artifact_hash,
            "score": float(round(score, 6)), "target": float(target), "target_met": met,
            "judges": [dict(t, score=float(round(t["score"], 6))) for t in totals],
            "criterion_failures": failures, "blockers": blockers,
            "failed_guards": failed_guards, "disagreement": float(round(disagreement, 6))}


def unique_object(pairs):
    """Reject duplicate JSON keys rather than silently replacing a value."""
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(data):
    """Parse decimal scores exactly and reject duplicate keys."""
    return json.loads(data, object_pairs_hook=unique_object, parse_float=Decimal)


def main(argv):
    """Read snapshots, validate their hashes, and print the score result."""
    if len(argv) != 4:
        print("Usage: refinement-score.py RUBRIC ARTIFACT ASSESSMENT", file=sys.stderr)
        return 2
    try:
        rubric_bytes = Path(argv[1]).read_bytes()
        artifact_bytes = Path(argv[2]).read_bytes()
        result = evaluate(load_json(rubric_bytes), load_json(Path(argv[3]).read_bytes()),
                          hashlib.sha256(rubric_bytes).hexdigest(),
                          hashlib.sha256(artifact_bytes).hexdigest())
    except (ValueError, OSError, TypeError, OverflowError) as error:
        print(json.dumps({"valid": False, "target_met": False, "error": str(error)}))
        return 2
    print(json.dumps(result, allow_nan=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
