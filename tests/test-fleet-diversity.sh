#!/usr/bin/env bash
# test-fleet-diversity.sh — Tests for dynamic fleet building and provider diversity
# Tests build-fleet.sh output, model family diversity enforcement, and that
# skills reference build-fleet.sh instead of hardcoding provider lists.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "-fleet-diversity.sh — Tests for dynamic fleet building and provider diversity"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLEET_SCRIPT="$PLUGIN_DIR/scripts/helpers/build-fleet.sh"
CHECK_SCRIPT="$PLUGIN_DIR/scripts/helpers/check-providers.sh"

# Source test helpers
PASS=0
FAIL=0
pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

echo "═══════════════════════════════════════════════════════════════"
echo "Test: Fleet Diversity & Dynamic Dispatch"
echo "═══════════════════════════════════════════════════════════════"

# ═══════════════════════════════════════════════════════════════
# Test Group 1: build-fleet.sh exists and is executable
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 1: build-fleet.sh existence and structure\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1: build-fleet.sh exists
if [[ -f "$FLEET_SCRIPT" ]]; then
    pass "1.1 build-fleet.sh exists"
else
    fail "1.1 build-fleet.sh missing" "$FLEET_SCRIPT"
fi

# 1.2: build-fleet.sh is executable
if [[ -x "$FLEET_SCRIPT" ]]; then
    pass "1.2 build-fleet.sh is executable"
else
    fail "1.2 build-fleet.sh not executable"
fi

# 1.3: check-providers.sh exists
if [[ -f "$CHECK_SCRIPT" ]]; then
    pass "1.3 check-providers.sh exists"
else
    fail "1.3 check-providers.sh missing"
fi

# 1.4: build-fleet.sh output format is pipe-delimited with 3 fields
output=$(bash "$FLEET_SCRIPT" research quick "test prompt" 2>/dev/null)
if echo "$output" | head -1 | grep -q '^[a-z-]*|[^|]*|'; then
    pass "1.4 build-fleet.sh outputs pipe-delimited format"
else
    fail "1.4 build-fleet.sh output format wrong" "$(echo "$output" | head -1)"
fi

# 1.5: build-fleet.sh handles all workflow types without error
for wf in research review debate architecture; do
    if bash "$FLEET_SCRIPT" "$wf" standard "test" >/dev/null 2>&1; then
        pass "1.5.$wf build-fleet.sh handles $wf workflow"
    else
        fail "1.5.$wf build-fleet.sh fails for $wf workflow"
    fi
done

# 1.6: build-fleet.sh handles all intensity levels
for intensity in quick standard deep; do
    if bash "$FLEET_SCRIPT" research "$intensity" "test" >/dev/null 2>&1; then
        pass "1.6.$intensity build-fleet.sh handles $intensity intensity"
    else
        fail "1.6.$intensity build-fleet.sh fails for $intensity intensity"
    fi
done

# ═══════════════════════════════════════════════════════════════
# Test Group 2: Model family diversity
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 2: Model family diversity enforcement\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1: build-fleet.sh emits FLEET_SUMMARY on stderr
summary=$(bash "$FLEET_SCRIPT" research standard "test" 2>&1 >/dev/null)
if echo "$summary" | grep -q "FLEET_SUMMARY:"; then
    pass "2.1 build-fleet.sh emits FLEET_SUMMARY on stderr"
else
    fail "2.1 FLEET_SUMMARY not found on stderr"
fi

# 2.2: Deep research uses more than 2 providers
deep_output=$(bash "$FLEET_SCRIPT" research deep "test" 2>/dev/null)
provider_count=$(echo "$deep_output" | cut -d'|' -f1 | sort -u | wc -l | tr -d ' ')
if [[ $provider_count -gt 2 ]]; then
    pass "2.2 Deep research uses $provider_count distinct providers (>2)"
else
    fail "2.2 Deep research only uses $provider_count providers" "expected >2"
fi

# 2.3: Deep research doesn't use only Anthropic models
anthropic_only=true
while IFS= read -r line; do
    agent=$(echo "$line" | cut -d'|' -f1)
    case "$agent" in
        claude*) ;;  # Anthropic
        *) anthropic_only=false ;;
    esac
done <<< "$deep_output"
if [[ "$anthropic_only" == "false" ]]; then
    pass "2.3 Deep research includes non-Anthropic providers"
else
    fail "2.3 Deep research only uses Anthropic models"
fi

# 2.4: Debate fleet uses diverse families
debate_output=$(bash "$FLEET_SCRIPT" debate standard "Redis vs Memcached" 2>/dev/null)
debate_providers=$(echo "$debate_output" | grep '|Debater|' | cut -d'|' -f1 | sort -u)
debate_count=$(echo "$debate_providers" | wc -l | tr -d ' ')
if [[ $debate_count -ge 2 ]]; then
    pass "2.4 Debate uses $debate_count distinct debater providers"
else
    fail "2.4 Debate only uses $debate_count debater provider" "expected ≥2"
fi

# 2.5: Quick research uses exactly 2 perspectives
quick_output=$(bash "$FLEET_SCRIPT" research quick "test" 2>/dev/null)
quick_count=$(echo "$quick_output" | wc -l | tr -d ' ')
if [[ $quick_count -eq 2 ]]; then
    pass "2.5 Quick research uses exactly 2 perspectives"
else
    fail "2.5 Quick research uses $quick_count perspectives" "expected 2"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 3: Skills reference build-fleet.sh (not hardcoded)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 3: Skills reference dynamic fleet (no hardcoded providers)\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3.1: flow-discover references build-fleet.sh
if grep -q "build-fleet.sh" "$PLUGIN_DIR/skills/flow-discover/SKILL.md"; then
    pass "3.1 flow-discover/SKILL.md references build-fleet.sh"
else
    fail "3.1 flow-discover/SKILL.md missing build-fleet.sh reference"
fi

# 3.2: flow-discover .claude skill references build-fleet.sh
if grep -q "build-fleet.sh" "$PLUGIN_DIR/.claude/skills/flow-discover.md"; then
    pass "3.2 .claude/skills/flow-discover.md references build-fleet.sh"
else
    fail "3.2 .claude/skills/flow-discover.md missing build-fleet.sh reference"
fi

# 3.3: skill-debate references build-fleet.sh
if grep -q "build-fleet.sh" "$PLUGIN_DIR/skills/skill-debate/SKILL.md"; then
    pass "3.3 skill-debate/SKILL.md references build-fleet.sh"
else
    fail "3.3 skill-debate/SKILL.md missing build-fleet.sh reference"
fi

# 3.4: ADVISORS is dynamically set from build-fleet.sh (fallback to "gemini,codex" is OK)
if grep -rq 'build-fleet.sh.*debate' "$PLUGIN_DIR/skills/skill-debate/SKILL.md" 2>/dev/null; then
    pass "3.4 skill-debate uses build-fleet.sh for advisor selection"
else
    fail "3.4 skill-debate missing build-fleet.sh for advisor selection"
fi

# 3.5: No skills still hardcode the old 3-provider-only fleet table
if grep -rq 'agent_type.*codex, gemini, claude-sonnet, or perplexity' "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/.claude/skills/" 2>/dev/null; then
    fail "3.5 Found old 4-provider fleet table" "$(grep -rl 'agent_type.*codex, gemini, claude-sonnet, or perplexity' "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/.claude/skills/" 2>/dev/null | head -1)"
else
    pass "3.5 No old 4-provider fleet table found"
fi

# 3.6: Codex-format skills use check-providers.sh instead of inline checks
stale_codex_skills=0
for skill_dir in flow-define flow-develop flow-deliver flow-spec octopus-architecture; do
    skill_file="$PLUGIN_DIR/skills/$skill_dir/SKILL.md"
    [[ ! -f "$skill_file" ]] && continue
    if grep -q 'command -v codex.*codex_status=' "$skill_file" 2>/dev/null; then
        stale_codex_skills=$((stale_codex_skills + 1))
        fail "3.6 $skill_dir/SKILL.md still uses inline provider check"
    fi
done
if [[ $stale_codex_skills -eq 0 ]]; then
    pass "3.6 All Codex-format skills use check-providers.sh"
fi

# 3.7: No hardcoded state metrics (update_metrics "provider" "codex/gemini/claude")
stale_metrics=0
for skill_file in "$PLUGIN_DIR"/skills/*/SKILL.md "$PLUGIN_DIR"/.claude/skills/*.md; do
    [[ ! -f "$skill_file" ]] && continue
    if grep -q 'update_metrics "provider" "codex"' "$skill_file" 2>/dev/null; then
        stale_metrics=$((stale_metrics + 1))
    fi
done
if [[ $stale_metrics -eq 0 ]]; then
    pass "3.7 No hardcoded state metric provider tracking"
else
    fail "3.7 Found $stale_metrics files with hardcoded provider metrics"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 4: check-providers.sh detects all providers
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 4: check-providers.sh coverage\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_output=$(bash "$CHECK_SCRIPT" 2>/dev/null)

# 4.1: Checks all 8 providers
for provider in codex gemini perplexity opencode copilot qwen ollama openrouter; do
    if echo "$check_output" | grep -q "^${provider}:"; then
        pass "4.1.$provider check-providers.sh reports $provider"
    else
        fail "4.1.$provider check-providers.sh missing $provider"
    fi
done

# 4.2: Output has PROVIDER_CHECK_START/END delimiters
if echo "$check_output" | grep -q "PROVIDER_CHECK_START" && echo "$check_output" | grep -q "PROVIDER_CHECK_END"; then
    pass "4.2 check-providers.sh has START/END delimiters"
else
    fail "4.2 check-providers.sh missing delimiters"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 5: review.sh fleet includes new providers
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 5: review.sh fleet diversity\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REVIEW_SH="$PLUGIN_DIR/scripts/lib/review.sh"

# 5.1: review.sh includes copilot in fallback chain
if grep -q 'copilot' "$REVIEW_SH"; then
    pass "5.1 review.sh includes copilot in fleet"
else
    fail "5.1 review.sh missing copilot"
fi

# 5.2: review.sh includes qwen in fallback chain
if grep -q 'qwen' "$REVIEW_SH"; then
    pass "5.2 review.sh includes qwen in fleet"
else
    fail "5.2 review.sh missing qwen"
fi

# 5.3: review.sh includes opencode in fallback chain
if grep -q 'opencode' "$REVIEW_SH"; then
    pass "5.3 review.sh includes opencode in fleet"
else
    fail "5.3 review.sh missing opencode"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
test_summary
