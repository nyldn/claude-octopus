#!/usr/bin/env bash
# Regression: flow-develop's ceremony must consume the configured review fleet.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-design-fleet.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.claude-octopus/config"
cp "$ROOT_DIR/tests/fixtures/review-four-provider-config.json" \
   "$TEST_HOME/.claude-octopus/config/providers.json"

export HOME="$TEST_HOME"
export WORKSPACE_DIR="$TEST_HOME/.claude-octopus"
export DRY_RUN=false
export OCTOPUS_CEREMONIES=true
export OCTOPUS_DESIGN_REVIEW_TIMEOUT=1
export OCTOPUS_DESIGN_REVIEW_SYNTH_TIMEOUT=1
CAPTURE_FILE="$TEST_HOME/dispatches.txt"

CYAN=""; GREEN=""; NC=""; _BOX_TOP=""; _BOX_BOT=""
log() { :; }
write_structured_decision() { :; }
run_agent_sync() {
  local agent="$1" role="${4:-}" phase="${5:-}"
  printf '%s|%s|%s\n' "$agent" "$role" "$phase" >> "$CAPTURE_FILE"
  if [[ "$agent" == "openrouter-kimi-k3" && ! -f "$TEST_HOME/kimi-failed-once" ]]; then
    : > "$TEST_HOME/kimi-failed-once"
    return 1
  fi
  printf 'Approach from %s\n' "$agent"
}

source "$ROOT_DIR/scripts/lib/review.sh"
source "$ROOT_DIR/scripts/lib/quality.sh"

design_review_ceremony "verify configured fleet" >/dev/null

for expected in \
  "codex|logic-reviewer|ceremony" \
  "claude-opus|arch-reviewer|ceremony" \
  "openrouter-glm52|diversity-reviewer|ceremony" \
  "openrouter-kimi-k3|diversity-reviewer|ceremony" \
  "claude-opus|synthesizer|ceremony"; do
  grep -Fqx "$expected" "$CAPTURE_FILE" || {
    echo "FAIL: missing design-review dispatch: $expected" >&2
    cat "$CAPTURE_FILE" >&2
    exit 1
  }
done

[[ "$(grep -c '^openrouter-kimi-k3|' "$CAPTURE_FILE")" == "2" ]] || {
  echo "FAIL: transient design-review failure was not retried once" >&2
  cat "$CAPTURE_FILE" >&2
  exit 1
}

if grep -Eq '^(agy|claude-sonnet)\|' "$CAPTURE_FILE"; then
  echo "FAIL: hardcoded legacy design-review seat was dispatched" >&2
  cat "$CAPTURE_FILE" >&2
  exit 1
fi

echo "PASS: design review consumes configured provider fleet"
