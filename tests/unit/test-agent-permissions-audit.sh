#!/usr/bin/env bash
# Tests for agent tool permission audit — verify Agent tool only in 3 agents,
# readonly in 6 agents, security-auditor lacks Bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agent tool permission audit — verify Agent tool only in 3 agents,"

AGENTS_DIR="$PROJECT_ROOT/.claude/agents"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Only debugger, frontend-developer, tdd-orchestrator should have Agent tool ─

AGENTS_WITH_AGENT=0
for agent_file in "$AGENTS_DIR"/*.md; do
    name=$(basename "$agent_file" .md)
    # Extract frontmatter tools list
    has_agent=$(awk '/^---$/{n++; next} n==1 && /- Agent/{print "yes"; exit}' "$agent_file")
    if [[ "$has_agent" == "yes" ]]; then
        AGENTS_WITH_AGENT=$((AGENTS_WITH_AGENT + 1))
        case "$name" in
            debugger|frontend-developer|tdd-orchestrator)
                pass "$name keeps Agent tool (expected)"
                ;;
            *)
                fail "$name should NOT have Agent tool" "Agent tool found in frontmatter"
                ;;
        esac
    fi
done

if [[ $AGENTS_WITH_AGENT -eq 3 ]]; then
    pass "Exactly 3 agents have Agent tool"
else
    fail "Exactly 3 agents have Agent tool" "found $AGENTS_WITH_AGENT"
fi

# ── These 6 agents should have readonly: true ───────────────────────────────

for agent in backend-architect code-reviewer security-auditor performance-engineer cloud-architect database-architect; do
    agent_file="$AGENTS_DIR/${agent}.md"
    if awk '/^---$/{n++; next} n==1 && /readonly: true/{print "yes"; exit}' "$agent_file" | grep -q yes; then
        pass "$agent has readonly: true"
    else
        fail "$agent has readonly: true" "missing readonly frontmatter"
    fi
done

# ── security-auditor should NOT have Bash tool ──────────────────────────────

has_bash=$(awk '/^---$/{n++; next} n==1 && /- Bash/{print "yes"; exit}' "$AGENTS_DIR/security-auditor.md")
if [[ "$has_bash" == "yes" ]]; then
    fail "security-auditor lacks Bash tool" "Bash tool found in frontmatter"
else
    pass "security-auditor lacks Bash tool"
fi

# ── docs-architect should NOT have readonly (writes docs) ───────────────────

has_readonly=$(awk '/^---$/{n++; next} n==1 && /readonly: true/{print "yes"; exit}' "$AGENTS_DIR/docs-architect.md")
if [[ "$has_readonly" == "yes" ]]; then
    fail "docs-architect is NOT readonly" "readonly: true found (should be absent)"
else
    pass "docs-architect is NOT readonly (writes docs)"
fi
test_summary
