#!/usr/bin/env bash
# Regression: every Codex capability routes to GPT-5.6 Sol through Codex CLI.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-codex-sol.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.claude-octopus/config"
cat > "$TEST_HOME/.claude-octopus/config/providers.json" <<'EOF'
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "gpt-5.6-sol",
      "fallback": "gpt-5.6-sol",
      "spark": "gpt-5.6-sol",
      "mini": "gpt-5.6-sol",
      "reasoning": "gpt-5.6-sol",
      "large_context": "gpt-5.6-sol"
    }
  },
  "routing": {"phases": {}, "roles": {}},
  "tiers": {},
  "overrides": {}
}
EOF

export HOME="$TEST_HOME"
export PLUGIN_DIR="$ROOT_DIR"
export CLAUDE_CODE_SESSION="codex-sol-test-$$"
log() { :; }
source "$ROOT_DIR/scripts/lib/models.sh"
source "$ROOT_DIR/scripts/lib/model-resolver.sh"
source "$ROOT_DIR/scripts/lib/dispatch.sh"
migrate_provider_config() { :; }
validate_model_allowed() { return 0; }
octopus_resolve_reasoning_level() { echo high; }
octopus_resolve_reasoning_policy() { echo best_effort; }
octopus_reasoning_cli_fragment() { :; }

for alias in codex codex-spark codex-mini codex-reasoning codex-large-context; do
    [[ "$(get_agent_model "$alias" review reviewer)" == "gpt-5.6-sol" ]] || {
        echo "FAIL: $alias did not resolve to GPT-5.6 Sol" >&2
        exit 1
    }
done

command_line=$(get_agent_command codex review reviewer)
[[ "$command_line" == "codex exec --skip-git-repo-check --model gpt-5.6-sol --sandbox workspace-write -" ]] || {
    echo "FAIL: Codex dispatch does not use the subscription CLI with Sol: $command_line" >&2
    exit 1
}

[[ "$(get_model_capability gpt-5.6-sol provider)" == "codex" ]] || {
    echo "FAIL: GPT-5.6 Sol is absent from the Codex model catalog" >&2
    exit 1
}

[[ "$(find_capable_fallback gpt-5.4 codex)" == "gpt-5.6-sol" ]] || {
    echo "FAIL: legacy Codex models do not converge on GPT-5.6 Sol" >&2
    exit 1
}
if find_capable_fallback gpt-5.6-sol codex >/dev/null 2>&1; then
    echo "FAIL: unavailable GPT-5.6 Sol silently falls back to another Codex model" >&2
    exit 1
fi

rm -f "$TEST_HOME/.claude-octopus/config/providers.json"
[[ "$(resolve_octopus_model codex codex fallback-test fallback-test)" == "gpt-5.6-sol" ]] || {
    echo "FAIL: hardcoded Codex fallback is not GPT-5.6 Sol" >&2
    exit 1
}

default_count=$(grep -c '"gpt-5.6-sol"' "$ROOT_DIR/scripts/helpers/octo-model-config.sh" || true)
[[ "$default_count" -ge 6 ]] || {
    echo "FAIL: setup/model-config defaults do not fully pin GPT-5.6 Sol" >&2
    exit 1
}

echo "PASS: Codex aliases and defaults route to GPT-5.6 Sol via Codex CLI"
