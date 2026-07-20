#!/usr/bin/env bash
# Regression: Fable 5 stays primary and only model-unavailability errors use Opus.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-fable5-routing.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

source "$ROOT_DIR/scripts/lib/fable5.sh"

[[ "$(fable5_maybe_reroute "claude-fable-5" "security" "claude-opus" "review")" == "claude-fable-5" ]] || {
    echo "FAIL: security routing eagerly rerouted away from Fable 5" >&2
    exit 1
}

printf '%s\n' 'model unavailable' > "$TMP_DIR/unavailable.err"
: > "$TMP_DIR/empty.out"
fable5_model_unavailable "$TMP_DIR/unavailable.err" "$TMP_DIR/empty.out" || {
    echo "FAIL: model-unavailability classifier missed an unavailable model" >&2
    exit 1
}

printf '%s\n' 'content refused' > "$TMP_DIR/refusal.err"
if fable5_model_unavailable "$TMP_DIR/refusal.err" "$TMP_DIR/empty.out"; then
    echo "FAIL: content refusal incorrectly triggered paid Opus fallback" >&2
    exit 1
fi

grep -Fq 'fable5_model_unavailable "$temp_errors" "$temp_output"' "$ROOT_DIR/scripts/lib/spawn.sh" || {
    echo "FAIL: spawn path does not use availability-only Fable fallback" >&2
    exit 1
}

echo "PASS: Fable 5 primary routing and availability-only Opus fallback"
