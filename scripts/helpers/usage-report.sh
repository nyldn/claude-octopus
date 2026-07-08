#!/usr/bin/env bash
# Usage report (v9.50.0) — per-provider / per-skill / per-MCP-server cost and
# token breakdown for /octo:usage, matching Claude Code's /usage schema.
#
# Reads JSONL usage records from ${OCTOPUS_WORKSPACE:-~/.claude-octopus}/usage/
# (written by hooks/subagent-stop-gate.sh and any provider adapters) plus
# summary.json artifacts under the results dir.
#
# Usage: usage-report.sh [--format table|json] [--usage-dir DIR] [--results-dir DIR]
set -euo pipefail

FORMAT="table"
WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}"
USAGE_DIR="${WORKSPACE_DIR}/usage"
RESULTS_DIR="${WORKSPACE_DIR}/results"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)      FORMAT="${2:-table}"; shift 2 ;;
        --usage-dir)   USAGE_DIR="${2:?}"; shift 2 ;;
        --results-dir) RESULTS_DIR="${2:?}"; shift 2 ;;
        *) echo "usage-report: unknown argument: $1" >&2; exit 64 ;;
    esac
done

if [[ "$FORMAT" != "table" && "$FORMAT" != "json" ]]; then
    echo "usage-report: --format must be 'table' or 'json'" >&2
    exit 64
fi

if ! command -v python3 &>/dev/null; then
    echo "usage-report: python3 is required" >&2
    exit 69
fi

_OCTOPUS_USAGE_DIR="$USAGE_DIR" \
_OCTOPUS_RESULTS_DIR="$RESULTS_DIR" \
_OCTOPUS_FORMAT="$FORMAT" \
python3 - <<'PYEOF'
import glob, json, os, sys
from collections import defaultdict

usage_dir = os.environ["_OCTOPUS_USAGE_DIR"]
results_dir = os.environ["_OCTOPUS_RESULTS_DIR"]
fmt = os.environ["_OCTOPUS_FORMAT"]

# $/MTok (input, output) — keep in sync with cost table in CLAUDE.md
RATES = {
    "claude":       (5.00, 25.00),   # Opus 4.8 default seat
    "claude-sdk":   (5.00, 25.00),   # Agent SDK, Opus 4.8
    "codex":        (5.00, 30.00),   # GPT-5.5 premium default
    "agy":          (0.00, 0.00),    # included with Antigravity access
    "gemini":       (0.00, 0.00),    # sunset; legacy records only
    "perplexity":   (3.00, 15.00),   # Sonar Pro
    "openrouter":   (2.00, 8.00),    # blended estimate
    "atlascloud":   (2.00, 8.00),    # blended estimate
    "openai-compatible-agent": (2.00, 8.00),
    "ollama":       (0.00, 0.00),    # local
    "copilot":      (0.00, 0.00),    # subscription
    "qwen":         (0.00, 0.00),    # oauth/free tier
    "grok":         (3.00, 15.00),
    "cursor-agent": (0.00, 0.00),    # subscription
    "opencode":     (0.00, 0.00),    # native models free
    "vibe":         (0.00, 0.00),
}
DEFAULT_RATE = (2.00, 8.00)

records = []
for path in sorted(glob.glob(os.path.join(usage_dir, "*.jsonl"))):
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except Exception:
                    continue
    except Exception:
        continue

# Fold in council/workflow summary.json artifacts (queries only, no tokens)
for path in sorted(glob.glob(os.path.join(results_dir, "**", "summary.json"),
                             recursive=True)):
    try:
        d = json.load(open(path))
    except Exception:
        continue
    for seat in d.get("roster", d.get("seats", [])) or []:
        prov = (seat.get("provider") or "").lower()
        if prov:
            records.append({"provider": prov, "skill": d.get("workflow", ""),
                            "est_tokens_in": 0, "est_tokens_out": 0,
                            "source": "results-summary"})

def bucket():
    return {"queries": 0, "tokens_in": 0, "tokens_out": 0, "est_cost_usd": 0.0}

by_provider = defaultdict(bucket)
by_skill = defaultdict(bucket)
by_mcp = defaultdict(bucket)
totals = bucket()

for r in records:
    prov = (r.get("provider") or "unknown").lower()
    tin = int(r.get("est_tokens_in") or r.get("tokens_in") or 0)
    tout = int(r.get("est_tokens_out") or r.get("tokens_out") or 0)
    rate = RATES.get(prov, DEFAULT_RATE)
    cost = tin / 1e6 * rate[0] + tout / 1e6 * rate[1]
    for target in (by_provider[prov], totals):
        target["queries"] += 1
        target["tokens_in"] += tin
        target["tokens_out"] += tout
        target["est_cost_usd"] += cost
    skill = r.get("skill") or r.get("workflow") or ""
    if skill:
        b = by_skill[skill]
        b["queries"] += 1; b["tokens_in"] += tin
        b["tokens_out"] += tout; b["est_cost_usd"] += cost
    mcp = r.get("mcp_server") or ""
    if mcp:
        b = by_mcp[mcp]
        b["queries"] += 1; b["tokens_in"] += tin
        b["tokens_out"] += tout; b["est_cost_usd"] += cost

def rows(d):
    return [dict(name=k, **{kk: (round(vv, 4) if kk == "est_cost_usd" else vv)
                            for kk, vv in v.items()})
            for k, v in sorted(d.items(), key=lambda kv: -kv[1]["est_cost_usd"])]

report = {
    "schema": "claude-code/usage-v1",
    "totals": {**totals, "est_cost_usd": round(totals["est_cost_usd"], 4)},
    "byProvider": rows(by_provider),
    "bySkill": rows(by_skill),
    "byMcpServer": rows(by_mcp),
}

if fmt == "json":
    print(json.dumps(report, indent=2))
    sys.exit(0)

def table(title, items):
    print(title)
    print("=" * 64)
    print(f"{'Name':<28}{'Queries':>8}{'Tok In':>10}{'Tok Out':>10}{'Est Cost':>10}")
    print("-" * 64)
    for it in items:
        print(f"{it['name'][:27]:<28}{it['queries']:>8}{it['tokens_in']:>10}"
              f"{it['tokens_out']:>10}{'$%.2f' % it['est_cost_usd']:>10}")
    print("-" * 64)

if not records:
    print("No usage records found in", usage_dir)
    sys.exit(0)

table("Provider Usage Breakdown", report["byProvider"])
if report["bySkill"]:
    table("Skill Usage Breakdown", report["bySkill"])
if report["byMcpServer"]:
    table("MCP Server Usage Breakdown", report["byMcpServer"])
t = report["totals"]
print(f"TOTAL: {t['queries']} queries, {t['tokens_in']} in / "
      f"{t['tokens_out']} out tokens, est ${t['est_cost_usd']:.2f}")
PYEOF
