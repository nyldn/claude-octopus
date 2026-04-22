#!/bin/bash
# Context Reinforcement Hook — SessionStart
# Re-injects Iron Laws after context compaction so enforcement rules survive
# conversation compression. Inspired by obra/superpowers v4.3.1 SessionStart pattern.
#
# Hook type: SessionStart
# Returns: {"decision":"continue","additionalContext":"<CONTEXT-REINFORCEMENT>...</CONTEXT-REINFORCEMENT>"}

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
read -r -d '' CONTEXT <<'RULES' || true
<CONTEXT-REINFORCEMENT source="🐙 Octopus">
Hard gates: no-stubs (verify before claiming done), test-first (failing test before code), debug-protocol (root cause before fix), orchestrate-only (use orchestrate.sh for research), factory-pipeline (no skipping steps).
Human-only skills (never auto-trigger): factory, deep-research, security-audit, parallel, ship.
</CONTEXT-REINFORCEMENT>
RULES

# Escape the context for JSON output
ESCAPED_CONTEXT=$(echo "$CONTEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

# Return the hook response
cat <<EOF
{"decision":"continue","additionalContext":"${ESCAPED_CONTEXT}"}
EOF
