#!/bin/bash
# Claude Octopus Architecture Gate Hook (v8.6.0, enhanced v8.8.0)
# Domain-specific quality gate for backend-architect, database-architect, cloud-architect, deployment-engineer
# Selects checks via OCTOPUS_AGENT_PERSONA env var
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

persona="${OCTOPUS_AGENT_PERSONA:-backend-architect}"
issues=()

# Shared check: Architecture decision rationale
rationale_found=false
for pattern in "trade.?off" "decision" "chose" "because" "rationale" "alternative" \
               "pros" "cons" "consider" "approach" "pattern" "architecture"; do
    if echo "$output" | grep -qiE "$pattern"; then
        rationale_found=true
        break
    fi
done

if [[ "$rationale_found" != "true" ]]; then
    issues+=("Missing architectural decision rationale or trade-off analysis")
fi

# Persona-specific checks
case "$persona" in
    backend-architect)
        # API contracts and interface definitions
        api_found=false
        for pattern in "API" "endpoint" "contract" "interface" "schema" "request" \
                       "response" "REST" "GraphQL" "gRPC" "proto" "OpenAPI"; do
            if echo "$output" | grep -qiE "$pattern"; then
                api_found=true
                break
            fi
        done
        if [[ "$api_found" != "true" ]]; then
            issues+=("Missing API contracts or interface definitions")
        fi
        ;;

    database-architect)
        # Migration safety and schema design
        migration_found=false
        for pattern in "migration" "schema" "index" "normali" "foreign.key" "constraint" \
                       "table" "column" "relation" "partition" "shard" "replica" "backup"; do
            if echo "$output" | grep -qiE "$pattern"; then
                migration_found=true
                break
            fi
        done
        if [[ "$migration_found" != "true" ]]; then
            issues+=("Missing migration safety checks or schema design details")
        fi
        ;;

    cloud-architect)
        # IaC references and infrastructure patterns
        iac_found=false
        for pattern in "terraform" "CloudFormation" "CDK" "Pulumi" "IaC" "infrastructure" \
                       "module" "resource" "provider" "region" "availability.zone" "VPC" \
                       "subnet" "security.group" "IAM" "policy"; do
            if echo "$output" | grep -qiE "$pattern"; then
                iac_found=true
                break
            fi
        done
        if [[ "$iac_found" != "true" ]]; then
            issues+=("Missing IaC references or infrastructure pattern details")
        fi
        ;;

    deployment-engineer)
        # CI/CD and rollback strategy
        cicd_found=false
        for pattern in "CI/CD" "pipeline" "deploy" "rollback" "canary" "blue.green" \
                       "rolling" "stage" "environment" "artifact" "release" "helm" \
                       "ArgoCD" "Flux" "GitHub Actions" "GitOps"; do
            if echo "$output" | grep -qiE "$pattern"; then
                cicd_found=true
                break
            fi
        done
        if [[ "$cicd_found" != "true" ]]; then
            issues+=("Missing CI/CD pipeline or rollback strategy details")
        fi
        ;;
esac

# Decision
if [[ ${#issues[@]} -gt 1 ]]; then
    reason=$(printf '%s; ' "${issues[@]}")
    reason="${reason%; }"
    # v8.8: Write stderr so Claude Code v2.1.41+ displays blocking reason to user
    echo "🏗️ Architecture gate BLOCKED [${persona}]: ${reason}" >&2
    echo "   Fix: Include decision rationale/trade-offs and persona-specific details (API contracts, migrations, IaC, CI/CD)." >&2
    echo "{\"decision\": \"block\", \"reason\": \"Architecture review incomplete: ${reason}\"}"
elif [[ ${#issues[@]} -eq 1 ]]; then
    echo "🏗️ Architecture gate warning [${persona}]: ${issues[0]}" >&2
    echo "{\"decision\": \"continue\", \"reason\": \"Warning: ${issues[0]}\"}"
else
    echo '{"decision": "continue"}'
fi

exit 0
