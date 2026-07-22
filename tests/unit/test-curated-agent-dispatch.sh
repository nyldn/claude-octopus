#!/usr/bin/env bash
# Regression: explicit persona names must resolve to an available provider CLI.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export PLUGIN_DIR="$ROOT_DIR"
export AGENTS_DIR="$ROOT_DIR/agents"
export AGENTS_CONFIG="$ROOT_DIR/agents/config.yaml"
export WORKSPACE_DIR="${TMPDIR:-/tmp}/octo-curated-agent-dispatch"
export SUPPORTS_PERSISTENT_MEMORY=false
export SUPPORTS_NATIVE_AUTO_MEMORY=false
export AVAILABLE_AGENTS="agy codex"

source "$ROOT_DIR/scripts/lib/agents.sh"

[[ "$(get_agent_config backend-architect cli)" == "agy" ]] || {
    echo "FAIL: inline YAML comment leaked into the configured CLI" >&2
    exit 1
}

octo_provider_allowed() { return 0; }
is_agent_available_v2() { [[ "$1" == "codex" ]]; }

[[ "$(resolve_curated_agent_executor backend-architect)" == "codex" ]] || {
    echo "FAIL: unavailable persona primary did not resolve to fallback_cli" >&2
    exit 1
}

is_agent_available_v2() { [[ "$1" == "agy" || "$1" == "codex" ]]; }
[[ "$(resolve_curated_agent_executor backend-architect)" == "agy" ]] || {
    echo "FAIL: available persona primary was not preferred" >&2
    exit 1
}

if resolve_curated_agent_executor missing-persona >/dev/null 2>&1; then
    echo "FAIL: unknown persona unexpectedly resolved" >&2
    exit 1
fi

grep -Fq 'resolve_curated_agent_executor "$1"' "$ROOT_DIR/scripts/orchestrate.sh" || {
    echo "FAIL: spawn command does not resolve explicit curated personas" >&2
    exit 1
}

echo "PASS: explicit curated personas resolve through available provider CLIs"
