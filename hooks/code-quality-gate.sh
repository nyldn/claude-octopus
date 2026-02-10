#!/bin/bash
# Claude Octopus Code Quality Gate Hook (v8.6.0)
# Domain-specific quality gate for code-reviewer, tdd-orchestrator, incident-responder
# Validates: Actionable findings (2+), severity/priority levels, root cause (incident)
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
set -euo pipefail

# Read tool output from stdin
output=$(cat 2>/dev/null || true)

# If no output or very short, continue (likely non-analysis command)
if [[ ${#output} -lt 100 ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

persona="${OCTOPUS_AGENT_PERSONA:-code-reviewer}"
issues=()

# Check 1: Actionable findings (2+ distinct items)
finding_count=0
for pattern in "issue" "finding" "bug" "smell" "violation" "warning" "error" "defect" \
               "vulnerability" "concern" "problem" "improvement" "suggestion" "TODO" "FIXME"; do
    if echo "$output" | grep -qiE "$pattern"; then
        finding_count=$((finding_count + 1))
    fi
done

if [[ $finding_count -lt 2 ]]; then
    issues+=("Insufficient actionable findings: found $finding_count categories (need 2+)")
fi

# Check 2: Severity or priority levels
severity_found=false
for pattern in "critical" "high" "medium" "low" "severity" "priority" "P[0-3]" \
               "blocker" "major" "minor" "trivial" "must.fix" "should.fix" "nice.to.have"; do
    if echo "$output" | grep -qiE "$pattern"; then
        severity_found=true
        break
    fi
done

if [[ "$severity_found" != "true" ]]; then
    issues+=("Missing severity/priority levels for findings")
fi

# Check 3: Persona-specific checks
case "$persona" in
    incident-responder)
        # Root cause analysis required
        root_cause_found=false
        for pattern in "root cause" "underlying" "caused by" "triggered by" "origin" \
                       "timeline" "sequence of events" "contributing factor"; do
            if echo "$output" | grep -qiE "$pattern"; then
                root_cause_found=true
                break
            fi
        done
        if [[ "$root_cause_found" != "true" ]]; then
            issues+=("Missing root cause analysis (required for incident response)")
        fi
        ;;
    tdd-orchestrator)
        # Test references required
        test_ref_found=false
        for pattern in "test" "spec" "assert" "expect" "describe" "it(" "should" \
                       "red.green" "refactor" "coverage"; do
            if echo "$output" | grep -qiE "$pattern"; then
                test_ref_found=true
                break
            fi
        done
        if [[ "$test_ref_found" != "true" ]]; then
            issues+=("Missing test references (required for TDD workflow)")
        fi
        ;;
esac

# Decision
if [[ ${#issues[@]} -gt 1 ]]; then
    reason=$(printf '%s; ' "${issues[@]}")
    reason="${reason%; }"
    echo "{\"decision\": \"block\", \"reason\": \"Code quality review incomplete: ${reason}\"}"
elif [[ ${#issues[@]} -eq 1 ]]; then
    echo "{\"decision\": \"continue\", \"reason\": \"Warning: ${issues[0]}\"}"
else
    echo '{"decision": "continue"}'
fi

exit 0
