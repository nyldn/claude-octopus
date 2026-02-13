#!/bin/bash
# Claude Octopus Security Gate Hook (v8.6.0, enhanced v8.8.0)
# Domain-specific quality gate for security-auditor persona
# Validates: OWASP category coverage (2+), severity classifications, remediation present
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

# Check 1: OWASP category coverage (expect 2+ distinct categories)
owasp_categories=0
for pattern in "broken access" "cryptographic" "injection" "insecure design" \
               "security misconfiguration" "vulnerable.*component" "authentication" \
               "integrity" "logging" "server.side request" "OWASP" "A0[1-9]" "A10"; do
    if echo "$output" | grep -qiE "$pattern"; then
        owasp_categories=$((owasp_categories + 1))
    fi
done

if [[ $owasp_categories -lt 2 ]]; then
    issues+=("Insufficient OWASP coverage: found $owasp_categories categories (need 2+)")
fi

# Check 2: Severity classifications present
severity_found=false
for pattern in "critical" "high" "medium" "low" "severity" "CVSS" "risk.level" "priority"; do
    if echo "$output" | grep -qiE "$pattern"; then
        severity_found=true
        break
    fi
done

if [[ "$severity_found" != "true" ]]; then
    issues+=("Missing severity classifications (critical/high/medium/low or CVSS scores)")
fi

# Check 3: Remediation steps present
remediation_found=false
for pattern in "remediat" "fix" "mitigat" "recommend" "resolution" "patch" "upgrade" "update to"; do
    if echo "$output" | grep -qiE "$pattern"; then
        remediation_found=true
        break
    fi
done

if [[ "$remediation_found" != "true" ]]; then
    issues+=("Missing remediation steps or recommendations")
fi

# Decision
if [[ ${#issues[@]} -gt 1 ]]; then
    reason=$(printf '%s; ' "${issues[@]}")
    reason="${reason%; }"
    # v8.8: Write stderr so Claude Code v2.1.41+ displays blocking reason to user
    echo "🔒 Security gate BLOCKED: ${reason}" >&2
    echo "   Fix: Ensure analysis covers 2+ OWASP categories, includes severity levels, and provides remediation steps." >&2
    echo "{\"decision\": \"block\", \"reason\": \"Security audit incomplete: ${reason}\"}"
elif [[ ${#issues[@]} -eq 1 ]]; then
    echo "🔒 Security gate warning: ${issues[0]}" >&2
    echo "{\"decision\": \"continue\", \"reason\": \"Warning: ${issues[0]}\"}"
else
    echo '{"decision": "continue"}'
fi

exit 0
