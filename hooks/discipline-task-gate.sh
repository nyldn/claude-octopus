#!/usr/bin/env bash
# discipline-task-gate.sh — Brainstorm gate reminder on TaskCreated
# Only fires when discipline mode is on

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


DISCIPLINE_CONF="${HOME}/.claude-octopus/config/discipline.conf"

if [[ ! -f "$DISCIPLINE_CONF" ]] || ! grep -q "OCTOPUS_DISCIPLINE=on" "$DISCIPLINE_CONF" 2>/dev/null; then
    echo '{}'
    exit 0
fi

# Discipline is on — remind about brainstorm gate
printf '{"hookSpecificOutput":{"hookEventName":"TaskCreated","additionalContext":"DISCIPLINE BRAINSTORM GATE: A task was just created. Before implementing, confirm the approach has been planned. If this is new work without a prior discussion, pause and use skill-thought-partner or skill-writing-plans first."}}\n'
