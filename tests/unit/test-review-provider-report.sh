#!/usr/bin/env bash
# Regression: the terminal report must show the configured four-provider fleet.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-review-report.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
STATUS_FILE="$TMP_DIR/status"

log() { :; }
source "$ROOT_DIR/scripts/lib/review.sh"

cat > "$STATUS_FILE" <<'EOF'
codex|ok|Round 1 completed
claude-opus|ok|Round 1 completed
openrouter-glm52|ok|Round 1 completed
openrouter-kimi-k3|ok|Round 1 completed
codex|ok|Round 2 verification
EOF

report=$(print_provider_report "$STATUS_FILE")
for label in 'Codex' 'Claude / Fable' 'OpenRouter / GLM 5.2' 'OpenRouter / Kimi K3'; do
    grep -Fq "$label" <<< "$report" || {
        echo "FAIL: report omitted $label" >&2
        printf '%s\n' "$report" >&2
        exit 1
    }
done
if grep -Fq 'Gemini' <<< "$report"; then
    echo "FAIL: report listed an unused legacy provider" >&2
    exit 1
fi

grep -Fq 'echo "${atype}|ok|Round 1 completed"' "$ROOT_DIR/scripts/lib/review.sh" || {
    echo "FAIL: Round 1 status still collapses configured aliases" >&2
    exit 1
}

echo "PASS: provider report shows the exact configured review fleet"
