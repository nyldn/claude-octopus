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
SUPPORTS_EFFORT_COMMAND=true
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

# The skill-facing helper must consume the same configured roster. Historically
# it did not recognize "develop" and silently rebuilt a generic research fleet.
helper_fleet="$(
  OCTO_ALLOWED_PROVIDERS="codex claude openrouter" \
    "$ROOT_DIR/scripts/helpers/build-fleet.sh" develop standard "review target" 2>/dev/null
)"
for expected in \
  "codex|" \
  "claude-opus|" \
  "openrouter-glm52|" \
  "openrouter-kimi-k3|"; do
  grep -Fq "$expected" <<<"$helper_fleet" || {
    echo "FAIL: skill-facing fleet omitted configured seat: $expected" >&2
    printf '%s\n' "$helper_fleet" >&2
    exit 1
  }
done
if grep -Eq '^(gemini|agy|claude-sonnet)\|' <<<"$helper_fleet"; then
  echo "FAIL: skill-facing fleet synthesized a provider outside configuration" >&2
  printf '%s\n' "$helper_fleet" >&2
  exit 1
fi

# Paid preflight probes must use those same exact aliases and require all four.
source "$ROOT_DIR/scripts/lib/smoke.sh"
SKIP_SMOKE_TEST=false
OCTOPUS_SKIP_PROVIDER_PROBES=false
OCTOPUS_REMOTE_SESSION=false
CLAUDE_CODE_REMOTE=false
VERBOSE=false
RED=""; YELLOW=""; DIM=""; NC=""
smoke_test_cache_valid() { return 1; }
smoke_test_cache_write() { :; }
secure_tempfile() { mktemp "$TEST_HOME/smoke.XXXXXX"; }
SMOKE_CAPTURE="$TEST_HOME/smoke-agents.txt"
_smoke_test_provider() {
  printf '%s\n' "$1" >> "$SMOKE_CAPTURE"
  printf 'PASS\n' > "$3"
}
provider_smoke_test true >/dev/null
for expected in codex claude-opus openrouter-glm52 openrouter-kimi-k3; do
  grep -Fqx "$expected" "$SMOKE_CAPTURE" || {
    echo "FAIL: smoke test omitted configured alias: $expected" >&2
    cat "$SMOKE_CAPTURE" >&2
    exit 1
  }
done
if grep -Eq '^(gemini|agy|claude-sonnet)$' "$SMOKE_CAPTURE"; then
  echo "FAIL: smoke test probed a provider outside configuration" >&2
  cat "$SMOKE_CAPTURE" >&2
  exit 1
fi
[[ "$(wc -l < "$SMOKE_CAPTURE" | tr -d ' ')" == "4" ]] || {
  echo "FAIL: smoke test did not probe exactly four configured aliases" >&2
  cat "$SMOKE_CAPTURE" >&2
  exit 1
}

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
[[ "$(get_agent_command codex review reviewer)" == *'model_reasoning_effort="high"'* ]] || {
  echo "FAIL: Codex review dispatch is not using high reasoning effort" >&2
  exit 1
}
claude_command="$(get_agent_command claude-opus review arch-reviewer)"
[[ "$claude_command" == *"--model claude-fable-5"* ]] || {
  echo "FAIL: configured Claude route is not Fable 5 primary" >&2
  printf '%s\n' "$claude_command" >&2
  exit 1
}
[[ "$claude_command" == *"--effort high"* && "$claude_command" != *"--fast"* ]] || {
  echo "FAIL: configured Claude route is not standard high effort" >&2
  printf '%s\n' "$claude_command" >&2
  exit 1
}
[[ "$(get_agent_model claude-opus review arch-reviewer)" == "claude-fable-5" ]] || {
  echo "FAIL: Claude model resolver did not preserve Fable 5 primary" >&2
  exit 1
}

if grep -Eq 'review_run_agent_sync_progress "claude-sonnet"|synthesis-claude-sonnet|Round 2.*claude-sonnet' \
    "$ROOT_DIR/scripts/lib/review.sh"; then
  echo "FAIL: configured review rounds still contain a Claude Sonnet fallback" >&2
  exit 1
fi

if grep -Eiq 'Gemini|Antigravity|Claude Sonnet|model: "sonnet"' \
    "$ROOT_DIR/skills/flow-develop/SKILL.md"; then
  echo "FAIL: flow-develop still advertises a hardcoded legacy provider" >&2
  exit 1
fi
grep -Fq 'build-fleet.sh" develop' "$ROOT_DIR/skills/flow-develop/SKILL.md" || {
  echo "FAIL: flow-develop does not resolve its configured develop fleet" >&2
  exit 1
}

echo "PASS: four-provider review fleet and model dispatch"
