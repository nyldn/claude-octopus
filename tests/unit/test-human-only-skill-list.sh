#!/usr/bin/env bash
# Compatibility filename: verifies the native explicit-invocation gate that
# replaced the old advisory human-only list.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Native manual-only skill gate"

frontmatter_value() {
    local file="$1" key="$2"
    awk -v key="$key" '
        BEGIN { fm = 0 }
        /^---$/ { if (fm) exit; fm = 1; next }
        fm && index($0, key ":") == 1 {
            sub("^" key ":[[:space:]]*", "")
            print
            exit
        }
    ' "$file"
}

test_case "all source skills disable model invocation"
bad=""
while IFS= read -r file; do
    [[ "$(frontmatter_value "$file" disable-model-invocation)" == "true" ]] || bad="$bad ${file#$PROJECT_ROOT/}"
done < <(find "$PROJECT_ROOT/.claude/skills" -name SKILL.md -type f | sort)
if [[ -z "$bad" ]]; then test_pass; else test_fail "missing native gate:$bad"; fi

test_case "all generated skills preserve the native gate"
bad=""
while IFS= read -r file; do
    [[ "$(frontmatter_value "$file" disable-model-invocation)" == "true" ]] || bad="$bad ${file#$PROJECT_ROOT/}"
done < <(find "$PROJECT_ROOT/skills" -name SKILL.md -type f | sort)
if [[ -z "$bad" ]]; then test_pass; else test_fail "generated gate drift:$bad"; fi

test_case "all portable skills declare the Codex explicit-invocation policy"
bad=""
while IFS= read -r file; do
    metadata="${file%SKILL.md}agents/openai.yaml"
    [[ -f "$metadata" ]] && grep -q '^  allow_implicit_invocation: false$' "$metadata" || bad="$bad ${file#$PROJECT_ROOT/}"
done < <(find "$PROJECT_ROOT/skills" -name SKILL.md -type f | sort)
if [[ -z "$bad" ]]; then test_pass; else test_fail "Codex invocation policy missing:$bad"; fi

test_case "workflow reinforcement is session-affine"
if grep -q 'octo_hook_workflow_active' "$PROJECT_ROOT/hooks/context-reinforcement.sh"; then
    test_pass
else
    test_fail "context reinforcement lacks an active-session gate"
fi

test_summary
