#!/usr/bin/env bash
# Regression: jq already decodes the outer OpenRouter response; do not decode
# the model's JSON content a second time and corrupt its escaping.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export OPENROUTER_API_KEY="test-key"
export VERBOSE=false
log() { :; }
json_escape() { printf '%s' "$1"; }
curl() {
    printf '%s' '{"choices":[{"message":{"content":"{\"findings\":[{\"detail\":\"say \\\"hello\\\" and line\\nnext\"}]}"}}]}200'
}

source "$ROOT_DIR/scripts/lib/perplexity.sh"

result=$(openrouter_execute_model "z-ai/glm-5.2" "review")
printf '%s' "$result" | jq -e '.findings[0].detail == "say \"hello\" and line\nnext"' >/dev/null || {
    echo "FAIL: OpenRouter model JSON escaping was corrupted after jq decoding" >&2
    printf '%s\n' "$result" >&2
    exit 1
}

echo "PASS: OpenRouter preserves model-emitted JSON escaping"
