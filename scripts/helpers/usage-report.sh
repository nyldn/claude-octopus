#!/usr/bin/env bash
# Usage report (v9.50.0) — per-provider / per-skill / per-MCP-server cost and
# token breakdown for /octo:usage, matching Claude Code's /usage schema.
#
# Reads JSONL usage records from ${OCTOPUS_WORKSPACE:-~/.claude-octopus}/usage/
# (written by hooks/subagent-stop-gate.sh and any provider adapters) plus
# summary.json artifacts under the results dir.
#
# Usage: usage-report.sh [--view usage|costs] [--format table|json|csv]
#                        [--usage-dir DIR] [--results-dir DIR]
set -euo pipefail

FORMAT="table"
VIEW="usage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_PRICING_FILE="${OCTOPUS_MODEL_PRICING_FILE:-${SCRIPT_DIR}/../../config/model-pricing.tsv}"
WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}"
USAGE_DIR="${WORKSPACE_DIR}/usage"
RESULTS_DIR="${WORKSPACE_DIR}/results"

log() {
    local level="$1"
    shift
    printf 'usage-report: %s\n' "$*" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)      FORMAT="${2:-table}"; shift 2 ;;
        --view)        VIEW="${2:-usage}"; shift 2 ;;
        --usage-dir)   USAGE_DIR="${2:?}"; shift 2 ;;
        --results-dir) RESULTS_DIR="${2:?}"; shift 2 ;;
        *) log ERROR "unknown argument: $1"; exit 64 ;;
    esac
done

if [[ "$FORMAT" != "table" && "$FORMAT" != "json" && "$FORMAT" != "csv" ]]; then
    log ERROR "--format must be 'table', 'json', or 'csv'"
    exit 64
fi
if [[ "$VIEW" != "usage" && "$VIEW" != "costs" ]]; then
    log ERROR "--view must be 'usage' or 'costs'"
    exit 64
fi

if ! command -v python3 &>/dev/null; then
    log ERROR "python3 is required"
    exit 69
fi
if [[ ! -r "$MODEL_PRICING_FILE" ]]; then
    log ERROR "pricing table not found: $MODEL_PRICING_FILE"
    exit 69
fi

env \
"_OCTOPUS_USAGE_DIR=${USAGE_DIR}" \
"_OCTOPUS_RESULTS_DIR=${RESULTS_DIR}" \
"_OCTOPUS_FORMAT=${FORMAT}" \
"_OCTOPUS_VIEW=${VIEW}" \
"_OCTOPUS_MODEL_PRICING_FILE=${MODEL_PRICING_FILE}" \
python3 - <<'PYEOF'
import csv, glob, json, os, sys
from collections import defaultdict

usage_dir = os.environ["_OCTOPUS_USAGE_DIR"]
results_dir = os.environ["_OCTOPUS_RESULTS_DIR"]
fmt = os.environ["_OCTOPUS_FORMAT"]
view = os.environ["_OCTOPUS_VIEW"]
pricing_file = os.environ["_OCTOPUS_MODEL_PRICING_FILE"]

# One checked-in table is shared with scripts/lib/cost.sh. Model-specific rates
# take precedence; provider rows cover legacy records without model identifiers.
RATES = {}
MODEL_RATES = {}
PROVIDER_OVERRIDES = {}
REQUEST_RULES = {}
DEFAULT_RATE = (1.00, 5.00)
with open(pricing_file, encoding="utf-8") as pricing:
    for raw in pricing:
        if not raw.strip() or raw.startswith("#"):
            continue
        fields = raw.rstrip("\n").split("\t")
        kind, ident, input_rate, output_rate = fields[:4]
        if kind == "request-rule":
            REQUEST_RULES[ident.lower()] = (
                int(input_rate), float(output_rate), float(fields[4]))
            continue
        rate = (float(input_rate), float(output_rate))
        if kind == "model":
            MODEL_RATES[ident.lower()] = rate
        elif kind == "provider-override":
            PROVIDER_OVERRIDES[ident.lower()] = rate
        elif kind == "provider" and ident == "default":
            DEFAULT_RATE = rate
        elif kind == "provider":
            RATES[ident.lower()] = rate

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
            records.append({"provider": prov,
                            "model": (seat.get("model") or "").lower(),
                            "skill": d.get("workflow", ""),
                            "est_tokens_in": 0, "est_tokens_out": 0,
                            "source": "results-summary"})

def bucket():
    return {"queries": 0, "tokens_in": 0, "tokens_out": 0, "est_cost_usd": 0.0}

def pricing_provider(provider):
    """Match the provider-family normalization used by scripts/lib/cost.sh."""
    provider = provider.lower().replace("_", "-")
    prefixes = (
        ("claude-sdk", "claude-sdk"),
        ("claude", "claude"),
        ("codex", "codex"),
        ("agy", "agy"),
        ("gemini", "agy"),
        ("openrouter", "openrouter"),
        ("openai-compatible", "openai-compatible-agent"),
        ("atlascloud", "atlascloud"),
        ("perplexity", "perplexity"),
        ("cursor-agent", "cursor-agent"),
        ("copilot", "copilot"),
        ("ollama", "ollama"),
        ("qwen", "qwen"),
        ("grok", "grok"),
        ("opencode", "opencode"),
        ("vibe", "vibe"),
        ("kimi", "kimi"),
    )
    if provider in ("antigravity",):
        return "agy"
    if provider in ("openai-tools",):
        return "openai-compatible-agent"
    for prefix, canonical in prefixes:
        if provider.startswith(prefix):
            return canonical
    return provider

by_provider = defaultdict(bucket)
by_skill = defaultdict(bucket)
by_mcp = defaultdict(bucket)
totals = bucket()

for r in records:
    prov = (r.get("provider") or "unknown").lower()
    price_prov = pricing_provider(prov)
    model = (r.get("model") or "").lower()
    tin = int(r.get("est_tokens_in") or r.get("tokens_in") or 0)
    tout = int(r.get("est_tokens_out") or r.get("tokens_out") or 0)
    rate = PROVIDER_OVERRIDES.get(
        price_prov, MODEL_RATES.get(model, RATES.get(price_prov, DEFAULT_RATE)))
    threshold, input_multiplier, output_multiplier = REQUEST_RULES.get(
        model, (None, 1.0, 1.0))
    if threshold is not None and tin > threshold:
        rate = (rate[0] * input_multiplier, rate[1] * output_multiplier)
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
    "view": view,
    "totals": {**totals, "est_cost_usd": round(totals["est_cost_usd"], 4)},
    "byProvider": rows(by_provider),
    "bySkill": rows(by_skill),
    "byMcpServer": rows(by_mcp),
}

if fmt == "json":
    print(json.dumps(report, indent=2))
    sys.exit(0)

if fmt == "csv":
    writer = csv.writer(sys.stdout, lineterminator="\n")
    writer.writerow(["group", "name", "queries", "tokens_in", "tokens_out", "est_cost_usd"])
    for group, items in (("provider", report["byProvider"]),
                         ("skill", report["bySkill"]),
                         ("mcp", report["byMcpServer"])):
        for item in items:
            writer.writerow([group, item["name"], item["queries"],
                             item["tokens_in"], item["tokens_out"],
                             f'{item["est_cost_usd"]:.4f}'])
    total = report["totals"]
    writer.writerow(["total", "", total["queries"], total["tokens_in"],
                     total["tokens_out"], f'{total["est_cost_usd"]:.4f}'])
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

provider_title = "Provider Cost Breakdown" if view == "costs" else "Provider Usage Breakdown"
skill_title = "Workflow Cost Breakdown" if view == "costs" else "Skill Usage Breakdown"
table(provider_title, report["byProvider"])
if report["bySkill"]:
    table(skill_title, report["bySkill"])
if report["byMcpServer"]:
    table("MCP Server Usage Breakdown", report["byMcpServer"])
t = report["totals"]
print(f"TOTAL: {t['queries']} queries, {t['tokens_in']} in / "
      f"{t['tokens_out']} out tokens, est ${t['est_cost_usd']:.2f}")
PYEOF
