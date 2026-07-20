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

# A user pin must outrank a model value cached before the pin was exported.
# Otherwise dispatch can execute Fable while telemetry still reports Opus 4.8.
export HOME="$TMP_DIR/home"
export TMPDIR="$TMP_DIR/cache"
mkdir -p "$HOME" "$TMPDIR"
log() { :; }
migrate_provider_config() { :; }
source "$ROOT_DIR/scripts/lib/models.sh"
source "$ROOT_DIR/scripts/lib/model-resolver.sh"
source "$ROOT_DIR/scripts/lib/dispatch.sh"

unset OCTOPUS_OPUS_MODEL
export SUPPORTS_OPUS_4_8=true
[[ "$(get_agent_model claude-opus review code-reviewer)" == "claude-opus-4.8" ]] || {
    echo "FAIL: could not prime Opus 4.8 model cache" >&2
    exit 1
}

export OCTOPUS_OPUS_MODEL="claude-fable-5"
[[ "$(get_agent_model claude-opus review code-reviewer)" == "claude-fable-5" ]] || {
    echo "FAIL: OCTOPUS_OPUS_MODEL did not bypass the stale model cache" >&2
    exit 1
}

grep -Fq '[[ "${OCTOPUS_OPUS_MODEL:-}" != "claude-fable-5" ]]' "$ROOT_DIR/scripts/lib/spawn.sh" || {
    echo "FAIL: Fable 5 can be eagerly replaced by the Opus --fast alias" >&2
    exit 1
}

grep -Fq '[[ "${OCTOPUS_OPUS_MODE:-auto}" == "fast" ]]' "$ROOT_DIR/scripts/lib/spawn.sh" || {
    echo "FAIL: claude-opus can still auto-route to the more expensive Fast tier" >&2
    exit 1
}

echo "PASS: Fable 5 primary routing and availability-only Opus fallback"
