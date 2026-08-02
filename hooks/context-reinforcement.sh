#!/bin/bash
# Context Reinforcement Hook — SessionStart
# Re-injects Iron Laws after context compaction so enforcement rules survive
# conversation compression. Inspired by obra/superpowers v4.3.1 SessionStart pattern.
#
# Hook type: SessionStart
# Returns: {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<CONTEXT-REINFORCEMENT>...</CONTEXT-REINFORCEMENT>"}

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read JSON payload from stdin (required by hook protocol)
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && INPUT='{}'

# Build compact enforcement context (~150 tokens vs ~750 previously)
#
# The human-only list is written out by hand and MUST match the skills whose
# frontmatter carries `invocation: human_only`. It cannot be derived at runtime:
# scripts/build-codex-skills.sh strips `invocation` from the generated skills/
# tree, which is what actually ships, so the key is only present in the
# .claude/skills/ sources. tests/unit/test-human-only-skill-list.sh is what keeps
# the two in step — it failed on the previous list, which named "deep-research"
# (no skill has that name; it is octopus-research) and omitted
# octopus-ui-ux-design entirely.
#
# Note this is advisory, not a hard gate. `disable-model-invocation: true` would
# be the native mechanism, but four of these are named in command bodies
# (commands/parallel.md, factory.md, research.md, security.md) and the model
# reaches them on the user's behalf when running those commands; disabling model
# invocation would break those routes. "Human-only" here means "do not fire from
# prompt-keyword auto-routing".
read -r -d '' CONTEXT <<'RULES' || true
<CONTEXT-REINFORCEMENT source="🐙 Octopus">
Hard gates: no-stubs (verify before claiming done), test-first (failing test before code), debug-protocol (root cause before fix), orchestrate-only (use orchestrate.sh for research), factory-pipeline (no skipping steps).
Human-only skills (never auto-trigger from keywords; the user asks for them): skill-factory, octopus-research, octopus-security-audit, flow-parallel, skill-ship, octopus-ui-ux-design.
</CONTEXT-REINFORCEMENT>
RULES

# Escape the context for JSON output
ESCAPED_CONTEXT=$(echo "$CONTEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

# Return the hook response
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"${ESCAPED_CONTEXT}"}}
EOF
