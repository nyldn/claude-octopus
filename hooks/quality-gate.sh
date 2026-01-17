#!/bin/bash
# Claude Octopus Quality Gate Hook
# Validates tangle output before continuing workflow
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}

VALIDATION_FILE=$(ls -t ~/.claude-octopus/results/tangle-validation-*.md 2>/dev/null | head -1)

if [[ -f "$VALIDATION_FILE" ]]; then
    # Check if quality gate passed
    STATUS=$(grep -E "^## (Quality Gate|Status):" "$VALIDATION_FILE" | head -1)

    if echo "$STATUS" | grep -qi "failed"; then
        echo '{"decision": "block", "reason": "Quality gate validation failed. Review tangle output before proceeding."}'
        exit 0
    fi

    if echo "$STATUS" | grep -qi "warning"; then
        echo '{"decision": "block", "reason": "Quality gate has warnings. Review tangle output before proceeding."}'
        exit 0
    fi
fi

# No validation file or quality gate passed
echo '{"decision": "continue"}'
exit 0
