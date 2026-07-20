#!/usr/bin/env bash
# Regression: configured review must preserve Codex, Claude, GLM 5.2, and Kimi K3.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-review-four-provider.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.claude-octopus/config"
cp "$ROOT_DIR/tests/fixtures/review-four-provider-config.json" \
   "$TEST_HOME/.claude-octopus/config/providers.json"

export HOME="$TEST_HOME"
export PLUGIN_DIR="$ROOT_DIR"
export USER_AGENTS_DIR="$ROOT_DIR/agents/personas"
export RESULTS_DIR="$TEST_HOME/.claude-octopus/results"
export LOGS_DIR="$TEST_HOME/.claude-octopus/logs"

log() { :; }
source "$ROOT_DIR/scripts/lib/review.sh"
source "$ROOT_DIR/scripts/lib/models.sh"
source "$ROOT_DIR/scripts/lib/model-resolver.sh"
source "$ROOT_DIR/scripts/lib/dispatch.sh"
migrate_provider_config() { :; }
validate_model_allowed() { return 0; }

fleet="$(build_review_fleet)"

for expected in \
  "codex:logic-reviewer" \
  "claude-opus:arch-reviewer" \
  "openrouter-glm52:diversity-reviewer" \
  "openrouter-kimi-k3:diversity-reviewer"; do
  grep -Fq "$expected" <<<"$fleet" || {
    echo "FAIL: missing configured review seat: $expected" >&2
    printf '%s\n' "$fleet" >&2
    exit 1
  }
done

[[ "$(get_agent_command openrouter-glm52 review review)" == *"z-ai/glm-5.2"* ]] || {
  echo "FAIL: GLM 5.2 dispatch target missing" >&2
  exit 1
}
[[ "$(get_agent_command openrouter-kimi-k3 review review)" == *"moonshotai/kimi-k3"* ]] || {
  echo "FAIL: Kimi K3 dispatch target missing" >&2
  exit 1
}
[[ "$(get_agent_model openrouter-glm52 review review)" == "z-ai/glm-5.2" ]] || {
  echo "FAIL: GLM 5.2 model resolver target missing" >&2
  exit 1
}
[[ "$(get_agent_model openrouter-kimi-k3 review review)" == "moonshotai/kimi-k3" ]] || {
  echo "FAIL: Kimi K3 model resolver target missing" >&2
  exit 1
}
[[ "$(get_agent_model codex review reviewer)" == "gpt-5.6-sol" ]] || {
  echo "FAIL: Codex review seat is not GPT-5.6 Sol" >&2
  exit 1
}
[[ "$(get_agent_command codex review reviewer)" == *"--model gpt-5.6-sol"* ]] || {
  echo "FAIL: Codex review dispatch does not invoke GPT-5.6 Sol" >&2
  exit 1
}

echo "PASS: four-provider review fleet and model dispatch"
