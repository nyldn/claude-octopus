#!/usr/bin/env python3
"""Score review strategies from artifact-grounded outcomes, not agreement."""

import argparse
import json
import math
import statistics
import sys
from collections import defaultdict


def non_negative(value, cast):
    try:
        parsed = cast(value)
    except (TypeError, ValueError):
        return cast(0)
    if isinstance(parsed, float) and not math.isfinite(parsed):
        return 0.0
    return max(cast(0), parsed)


def score(payload):
    ground_truth = set(map(str, payload["ground_truth_finding_ids"]))
    groups = defaultdict(list)
    for run in payload.get("runs", []):
        groups[str(run.get("strategy", "unknown"))].append(run)

    strategies = []
    for name in sorted(groups):
        runs = groups[name]
        validated = set()
        surfaced = set()
        unresolved_minority = set()
        for run in runs:
            for finding in run.get("findings", []):
                if not finding.get("validated"):
                    continue
                finding_id = str(finding.get("id", ""))
                if not finding_id:
                    continue
                validated.add(finding_id)
                reviewers = set(map(str, finding.get("reviewers", [])))
                if finding.get("included"):
                    surfaced.add(finding_id)
                elif len(reviewers) == 1:
                    unresolved_minority.add(finding_id)
        latencies = [non_negative(run.get("latency_ms", 0), int) for run in runs]
        tokens = sum(non_negative(run.get("tokens", 0), int) for run in runs)
        cost = sum(non_negative(run.get("cost_usd", 0), float) for run in runs)
        strategies.append(
            {
                "strategy": name,
                "runs": len(runs),
                "ground_truth_findings": len(ground_truth),
                "unique_validated_findings": len(validated),
                "surfaced_validated_findings": len(surfaced),
                "validated_finding_recall": round(
                    len(surfaced & ground_truth) / len(ground_truth), 4
                ),
                "unresolved_minority_findings": len(unresolved_minority),
                "median_latency_ms": int(statistics.median(latencies)) if latencies else 0,
                "total_tokens": tokens,
                "total_cost_usd": round(cost, 6),
            }
        )
    return {"schema_version": 1, "strategies": strategies}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", help="JSON input; stdin when omitted")
    args = parser.parse_args()
    with open(args.input, encoding="utf-8") if args.input else sys.stdin as stream:
        payload = json.load(stream)
    ground_truth = payload.get("ground_truth_finding_ids")
    runs = payload.get("runs")
    malformed_runs = isinstance(runs, list) and any(
        not isinstance(run, dict)
        or not isinstance(run.get("findings", []), list)
        or any(
            not isinstance(finding, dict)
            or not isinstance(finding.get("reviewers", []), list)
            for finding in run.get("findings", [])
        )
        for run in runs
    )
    if (
        payload.get("schema_version") != 1
        or not isinstance(runs, list)
        or malformed_runs
        or not isinstance(ground_truth, list)
        or not ground_truth
        or any(not isinstance(item, str) or not item for item in ground_truth)
        or len(set(ground_truth)) != len(ground_truth)
    ):
        raise SystemExit(
            "expected schema_version 1, well-formed runs, and unique ground_truth_finding_ids"
        )
    print(json.dumps(score(payload), separators=(",", ":"), sort_keys=True))


if __name__ == "__main__":
    main()
