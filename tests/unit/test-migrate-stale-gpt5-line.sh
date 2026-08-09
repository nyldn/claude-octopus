#!/usr/bin/env bash
# tests/unit/test-migrate-stale-gpt5-line.sh
# Regression coverage for #798: migrate_provider_config's stale-model rewrite
# map (scripts/lib/provider-routing.sh) had cases for gpt-4o/o1/chatgpt-era
# names but nothing for the gpt-5.x line, so an install pinned to an older
# gpt-5.x point release (gpt-5.4, gpt-5.1-codex-max, ...) was never
# recognised as stale and silently stayed on it forever, even though
# CLAUDE.md and model-resolver.sh both document GPT-5.6 Sol as current.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "migrate_provider_config gpt-5.x staleness (#798)"

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT
rm -rf "$TEST_TMP_DIR"
mkdir -p "$TEST_TMP_DIR/home/.claude-octopus/config"
CONFIG_FILE="$TEST_TMP_DIR/home/.claude-octopus/config/providers.json"

# Reproduces the issue's "Evidence from a live machine" providers.json:
# every codex slot pinned to gpt-5.4 (a real config from before the GPT-5.6
# refresh, 972d9597, 2026-07-27). version:3.0 skips the unrelated structural
# v3.0 migration block so only the stale-model rewrite loop is exercised.
cat > "$CONFIG_FILE" <<'JSON'
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "gpt-5.4",
      "fallback": "gpt-5.4",
      "spark": "gpt-5.4",
      "mini": "gpt-5.4",
      "reasoning": "o1-preview",
      "large_context": "gpt-5.4"
    },
    "gemini": { "default": "gemini-3.1-pro-preview" }
  },
  "phases": {}, "roles": {}, "tiers": {}, "overrides": {}
}
JSON

run_migration_in_subshell() {
    # migrate_provider_config memoizes via _PROVIDER_CONFIG_MIGRATED and is
    # meant to run once per process — a fresh subshell per invocation avoids
    # that guard masking a second call.
    (
        log() { :; }
        HOME="$TEST_TMP_DIR/home"
        source "$PROJECT_ROOT/scripts/lib/provider-routing.sh" >/dev/null 2>&1
        migrate_provider_config
    )
}

run_migration_in_subshell

test_case "stale codex.default (gpt-5.4) migrates to the current default"
val="$(jq -r '.providers.codex.default' "$CONFIG_FILE")"
[[ "$val" == "gpt-5.6-sol" ]] && test_pass || test_fail "expected gpt-5.6-sol, got: $val"

test_case "stale codex.fallback (gpt-5.4) migrates to the current default"
val="$(jq -r '.providers.codex.fallback' "$CONFIG_FILE")"
[[ "$val" == "gpt-5.6-sol" ]] && test_pass || test_fail "expected gpt-5.6-sol, got: $val"

assert_stale_model_migrates() {
    local stale_model="$1"
    local fixture_home="$TEST_TMP_DIR/home-$stale_model"
    local fixture_file="$fixture_home/.claude-octopus/config/providers.json"

    mkdir -p "$(dirname "$fixture_file")"
    jq -n --arg model "$stale_model" '{
      version: "3.0",
      providers: {codex: {default: $model}},
      phases: {}, roles: {}, tiers: {}, overrides: {}
    }' > "$fixture_file"

    (
        log() { :; }
        HOME="$fixture_home"
        source "$PROJECT_ROOT/scripts/lib/provider-routing.sh" >/dev/null 2>&1
        migrate_provider_config
    )

    test_case "stale codex.default ($stale_model) migrates to the current default"
    val="$(jq -r '.providers.codex.default' "$fixture_file")"
    [[ "$val" == "gpt-5.6-sol" ]] && test_pass || test_fail "expected gpt-5.6-sol, got: $val"
}

for stale_model in gpt-5.5 gpt-5.4-pro gpt-5.3-codex gpt-5.2-codex gpt-5.1-codex-max; do
    assert_stale_model_migrates "$stale_model"
done

test_case "already-current gemini default is left untouched"
val="$(jq -r '.providers.gemini.default' "$CONFIG_FILE")"
[[ "$val" == "gemini-3.1-pro-preview" ]] && test_pass || test_fail "expected gemini-3.1-pro-preview (unchanged), got: $val"

# Known, deliberately out-of-scope gap this fix does NOT close: stale_paths
# only lists .providers.codex.{default,fallback} and the gemini equivalents,
# so codex.spark/mini/reasoning/large_context are never inspected at all —
# stale or not, they pass through untouched. That's issue #798's second,
# separate limitation ("no other provider's pins are ever migrated"), left
# for a follow-up. Documented here so a future stale_paths widening updates
# this assertion instead of silently leaving it stale itself.
test_case "codex.spark is NOT migrated (stale_paths doesn't cover it — known gap, not this fix's scope)"
val="$(jq -r '.providers.codex.spark' "$CONFIG_FILE")"
[[ "$val" == "gpt-5.4" ]] && test_pass || test_fail "expected gpt-5.4 (still untouched — if this now migrates, stale_paths grew; update this test), got: $val"

# A second config, already on the current GPT-5.6 line, must not be rewritten
# (proves the new glob doesn't also swallow gpt-5.6-* values).
CONFIG_FILE2="$TEST_TMP_DIR/home2/.claude-octopus/config/providers.json"
mkdir -p "$(dirname "$CONFIG_FILE2")"
cat > "$CONFIG_FILE2" <<'JSON'
{
  "version": "3.0",
  "providers": { "codex": { "default": "gpt-5.6-sol", "fallback": "gpt-5.6-terra" } },
  "phases": {}, "roles": {}, "tiers": {}, "overrides": {}
}
JSON
(
    log() { :; }
    HOME="$TEST_TMP_DIR/home2"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh" >/dev/null 2>&1
    migrate_provider_config
)

test_case "already-current codex.default (gpt-5.6-sol) is left untouched"
val="$(jq -r '.providers.codex.default' "$CONFIG_FILE2")"
[[ "$val" == "gpt-5.6-sol" ]] && test_pass || test_fail "expected gpt-5.6-sol (unchanged), got: $val"

test_case "already-current codex.fallback (gpt-5.6-terra) is left untouched"
val="$(jq -r '.providers.codex.fallback' "$CONFIG_FILE2")"
[[ "$val" == "gpt-5.6-terra" ]] && test_pass || test_fail "expected gpt-5.6-terra (unchanged), got: $val"

test_summary
