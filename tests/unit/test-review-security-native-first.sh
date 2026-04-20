#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REVIEW_CMD="$PROJECT_ROOT/.claude/commands/review.md"
SECURITY_CMD="$PROJECT_ROOT/.claude/commands/security.md"
CONTEXT_SKILL="$PROJECT_ROOT/.claude/skills/skill-context-detection.md"

grep -q 'enhanced multi-LLM review' "$REVIEW_CMD"
grep -q 'Claude-native `/review`' "$REVIEW_CMD"
grep -q 'enhanced multi-LLM or adversarial security audit' "$SECURITY_CMD"
grep -q 'Claude-native `/security-review`' "$SECURITY_CMD"
grep -q 'Claude-native `/review` for ordinary review' "$CONTEXT_SKILL"
grep -q 'Claude-native `/security-review` for ordinary security review' "$CONTEXT_SKILL"

echo "PASS: review and security surfaces reflect native-first escalation semantics"
