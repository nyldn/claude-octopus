#!/bin/bash
# Claude Octopus Performance Gate Hook (v8.6.0, enhanced v8.8.0)
# Domain-specific quality gate for performance-engineer persona
# Validates: Quantified metrics (ms/MB/req/s), before/after benchmarks
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
# v8.8: Writes human-readable stderr on block (displayed by Claude Code v2.1.41+)
set -euo pipefail

# Read tool output from stdin
output=$(cat 2>/dev/null || true)

# If no output or very short, continue (likely non-analysis command)
if [[ ${#output} -lt 100 ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

issues=()

# Check 1: Quantified metrics with units
metrics_found=0
for pattern in "[0-9]+\s*ms" "[0-9]+\s*MB" "[0-9]+\s*KB" "[0-9]+\s*GB" \
               "[0-9]+\s*req/s" "[0-9]+\s*rps" "[0-9]+\s*ops/s" "[0-9]+\s*QPS" \
               "[0-9]+\s*%"  "p50" "p95" "p99" "latency" "throughput" \
               "[0-9]+\s*seconds?" "[0-9]+\s*bytes"; do
    if echo "$output" | grep -qiE "$pattern"; then
        metrics_found=$((metrics_found + 1))
    fi
done

if [[ $metrics_found -lt 1 ]]; then
    issues+=("Missing quantified metrics (ms, MB, req/s, p95, etc.)")
fi

# Check 2: Before/after or baseline comparison
comparison_found=false
for pattern in "before" "after" "baseline" "current" "improved" "degraded" \
               "improvement" "regression" "compared to" "vs\." "from.*to" \
               "benchmark" "profil"; do
    if echo "$output" | grep -qiE "$pattern"; then
        comparison_found=true
        break
    fi
done

if [[ "$comparison_found" != "true" ]]; then
    issues+=("Missing before/after comparison or baseline benchmarks")
fi

# Check 3: Specific optimization recommendations
optimization_found=false
for pattern in "optimiz" "cache" "index" "batch" "lazy" "prefetch" "compress" \
               "pool" "async" "parallel" "reduce" "eliminat" "bottleneck" "hotspot"; do
    if echo "$output" | grep -qiE "$pattern"; then
        optimization_found=true
        break
    fi
done

if [[ "$optimization_found" != "true" ]]; then
    issues+=("Missing specific optimization recommendations")
fi

# Decision
if [[ ${#issues[@]} -gt 1 ]]; then
    reason=$(printf '%s; ' "${issues[@]}")
    reason="${reason%; }"
    # v8.8: Write stderr so Claude Code v2.1.41+ displays blocking reason to user
    echo "⚡ Performance gate BLOCKED: ${reason}" >&2
    echo "   Fix: Include quantified metrics (ms/MB/req/s), before/after comparisons, and optimization recommendations." >&2
    echo "{\"decision\": \"block\", \"reason\": \"Performance analysis incomplete: ${reason}\"}"
elif [[ ${#issues[@]} -eq 1 ]]; then
    echo "⚡ Performance gate warning: ${issues[0]}" >&2
    echo "{\"decision\": \"continue\", \"reason\": \"Warning: ${issues[0]}\"}"
else
    echo '{"decision": "continue"}'
fi

exit 0
