#!/usr/bin/env bash
# Regression: Octopus Codex subagents must not share a newer desktop model cache.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-codex-home.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export WORKSPACE_DIR="$HOME/.claude-octopus"
export OCTOPUS_CODEX_ISOLATE_HOME=true
export OPENAI_API_KEY="test-key"
unset CODEX_HOME

mkdir -p "$HOME/.codex"
printf '%s\n' '{"tokens":{"access_token":"test"}}' > "$HOME/.codex/auth.json"
printf '%s\n' 'model = "gpt-5.4"' > "$HOME/.codex/config.toml"
printf '%s\n' '{"client_version":"newer-desktop"}' > "$HOME/.codex/models_cache.json"

resolve_provider_env() { :; }
source "$ROOT_DIR/scripts/lib/provider-routing.sh"

octopus_prepare_codex_runtime_home

expected="$WORKSPACE_DIR/codex-home"
[[ "$CODEX_HOME" == "$expected" ]] || {
    echo "FAIL: isolated CODEX_HOME was not selected" >&2
    exit 1
}
cmp -s "$HOME/.codex/auth.json" "$CODEX_HOME/auth.json" || {
    echo "FAIL: Codex authentication was not synchronized" >&2
    exit 1
}
cmp -s "$HOME/.codex/config.toml" "$CODEX_HOME/config.toml" || {
    echo "FAIL: Codex configuration was not synchronized" >&2
    exit 1
}
[[ ! -e "$CODEX_HOME/models_cache.json" ]] || {
    echo "FAIL: incompatible shared model cache leaked into runtime home" >&2
    exit 1
}

printf '%s\n' '{"client_version":"runtime-owned"}' > "$CODEX_HOME/models_cache.json"
printf '%s\n' 'model = "gpt-5.5"' > "$HOME/.codex/config.toml"
octopus_prepare_codex_runtime_home
grep -Fq 'gpt-5.5' "$CODEX_HOME/config.toml" || {
    echo "FAIL: updated Codex configuration was not synchronized" >&2
    exit 1
}
grep -Fq 'runtime-owned' "$CODEX_HOME/models_cache.json" || {
    echo "FAIL: runtime-owned model cache was overwritten" >&2
    exit 1
}

build_provider_env codex
[[ " ${PROVIDER_ENV_ARRAY[*]} " == *" CODEX_HOME=$expected "* ]] || {
    echo "FAIL: isolated CODEX_HOME was not propagated to Codex" >&2
    exit 1
}

echo "PASS: Codex subagents use an isolated runtime home and model cache"
