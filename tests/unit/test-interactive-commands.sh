#!/usr/bin/env bash
# Tests that interactive commands (setup, model-config, doctor) have the required
# "never dismiss" patterns that prevent the agent from silently skipping them.
#
# Bug context: A user reported that invoking /octo:setup as a returning user
# caused the agent to say "you're already set up" instead of running the
# interactive flow. This test ensures all interactive commands have guardrails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "that interactive commands (setup, model-config, doctor) have the required"


pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Interactive commands MUST have AskUserQuestion ─────────────────────────────
# These commands are interactive by design and must ALWAYS present UI

# CC-facing files (.claude/commands/) are what the agent actually reads.
# These are the authoritative versions that must have interactive UX.
INTERACTIVE_CC_COMMANDS="setup model-config doctor"

echo "=== Interactive Command Requirements ==="

for cmd in $INTERACTIVE_CC_COMMANDS; do
    cc="$PROJECT_ROOT/.claude/commands/${cmd}.md"

    if [[ -f "$cc" ]]; then
        if grep -q 'AskUserQuestion' "$cc" 2>/dev/null; then
            pass "$cmd.md has AskUserQuestion"
        else
            fail "$cmd.md missing AskUserQuestion" "Interactive commands must use AskUserQuestion"
        fi
    else
        fail "$cmd.md file missing" "$cc not found"
    fi
done

# ── Interactive commands MUST have "never dismiss" guardrails ─────────────────
# These phrases prevent the agent from silently skipping the interactive flow

echo ""
echo "=== Never-Dismiss Guardrails ==="

GUARDRAIL_PATTERNS="MUST always run|Never silently dismiss|CRITICAL.*always.*flow|ALWAYS show"

# Only check setup and model-config — doctor is a diagnostic tool that
# shows results and offers fixes, its interactive UX is different
GUARDRAIL_COMMANDS="setup model-config"

for cmd in $GUARDRAIL_COMMANDS; do
    cc="$PROJECT_ROOT/.claude/commands/${cmd}.md"
    if [[ -f "$cc" ]]; then
        if grep -qEi "$GUARDRAIL_PATTERNS" "$cc" 2>/dev/null; then
            pass "$cmd.md has never-dismiss guardrail"
        else
            fail "$cmd.md missing never-dismiss guardrail" "Must contain one of: $GUARDRAIL_PATTERNS"
        fi
    fi
done

# ── Interactive commands MUST have "Your first output line MUST be" ────────────
# This ensures the command always produces visible output (can't be silently dismissed)

echo ""
echo "=== Mandatory First Output Line ==="

for cmd in $INTERACTIVE_CC_COMMANDS; do
    cc="$PROJECT_ROOT/.claude/commands/${cmd}.md"
    if [[ -f "$cc" ]]; then
        if grep -q 'Your first output line MUST be' "$cc" 2>/dev/null; then
            pass "$cmd.md has mandatory first output line"
        else
            fail "$cmd.md missing mandatory first output line" "Must contain 'Your first output line MUST be'"
        fi
    fi
done

# ── Setup command must NOT have "skip the detailed setup" or "returning user" bypass ──
# These phrases historically caused agents to dismiss returning users

echo ""
echo "=== Anti-Bypass Phrases ==="

# These phrases historically caused agents to dismiss returning users.
# We search for them as INSTRUCTIONS (not as part of "Never say X" guardrails).
# Pattern: lines that instruct to skip, not lines that forbid skipping.

for f in "$PROJECT_ROOT/.claude/commands/setup.md"; do
    if [[ -f "$f" ]]; then
        name="$(basename "$f")"
        # Look for lines that INSTRUCT skipping (not lines that say "Never skip")
        # grep -v filters out guardrail lines first, then checks for bypass
        bypass_found=$(grep -Ei "skip the detailed setup sections|this is a returning user.*Skip" "$f" 2>/dev/null \
            | grep -viE "Never|MUST NOT|CRITICAL|MUST always" || true)
        if [[ -n "$bypass_found" ]]; then
            fail "$name contains bypass phrase" "Remove phrases that allow agent to skip interactive flow: $bypass_found"
        else
            pass "$name free of bypass phrases"
        fi
    fi
done

# ── model-config must support both interactive (no args) and CLI (with args) ──

echo ""
echo "=== Dual-Mode Support ==="

for f in "$PROJECT_ROOT/.claude/commands/model-config.md"; do
    if [[ -f "$f" ]]; then
        name="$(basename "$f")"
        has_interactive=$(grep -c 'Interactive Menu\|Interactive.*AskUserQuestion\|no arguments.*interactive' "$f" 2>/dev/null || true)
        has_cli=$(grep -c 'CLI.*EXECUTION CONTRACT\|direct arguments\|WITH arguments.*skip' "$f" 2>/dev/null || true)

        if [[ "$has_interactive" -gt 0 && "$has_cli" -gt 0 ]]; then
            pass "$name has both interactive and CLI modes"
        elif [[ "$has_interactive" -eq 0 ]]; then
            fail "$name missing interactive mode" "Must support no-args interactive flow"
        else
            fail "$name missing CLI mode" "Must support direct argument execution"
        fi
    fi
done
test_summary
