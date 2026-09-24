#!/usr/bin/env bash
# tests/unit/test-migrate-provider-config-preserves-user-keys.sh
# Regression coverage: migrate_provider_config treated any providers.json
# without "version": "3.0" as a legacy file and replaced it with a template,
# keeping only .overrides and .routing.frontier. A hand-written config that
# already used v3.0 keys lost .routing.features.review (so /octo:review fell
# back to the command -v cascade on the next run) and provider sub-keys such
# as .providers.agy.installed=false.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "migrate_provider_config preserves keys it does not own"

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT
rm -rf "$TEST_TMP_DIR"
mkdir -p "$TEST_TMP_DIR"

fixture_file() {
    local name="$1"
    printf '%s\n' "$TEST_TMP_DIR/$name/.claude-octopus/config/providers.json"
}

write_fixture() {
    local name="$1" file
    file="$(fixture_file "$name")"
    mkdir -p "$(dirname "$file")"
    cat > "$file"
}

run_migration() {
    local name="$1"
    (
        log() { :; }
        HOME="$TEST_TMP_DIR/$name"
        source "$PROJECT_ROOT/scripts/lib/provider-routing.sh" >/dev/null 2>&1
        migrate_provider_config
    )
}

write_fixture versionless-v3 <<'JSON'
{"routing":{"features":{"review":["codex-standard","claude"]}},"providers":{"agy":{"installed":false}}}
JSON
run_migration versionless-v3
file="$(fixture_file versionless-v3)"

test_case "versionless v3-shaped config is stamped 3.0"
val="$(jq -r '.version' "$file")"
[[ "$val" == "3.0" ]] && test_pass || test_fail "expected version 3.0, got: $val"

test_case "routing.features.review participants survive the migration"
val="$(jq -c '.routing.features.review' "$file")"
[[ "$val" == '["codex-standard","claude"]' ]] && test_pass || test_fail "review participants lost: $val"

test_case "providers.agy.installed=false survives next to the template defaults"
if jq -e '.providers.agy.installed == false and .providers.agy.default == "Gemini 3.1 Pro (High)"' "$file" >/dev/null; then
    test_pass
else
    test_fail "agy sub-keys not merged: $(jq -c '.providers.agy' "$file")"
fi

test_case "template defaults fill the keys the user did not set"
if jq -e '.providers.codex.default == "gpt-6-sol" and .providers.codex.fallback == "gpt-5.6-sol" and .providers.codex.mini == "gpt-6-luna" and .tiers.standard.claude == "default" and .overrides == {}' "$file" >/dev/null; then
    test_pass
else
    test_fail "template defaults missing: $(jq -c . "$file")"
fi

test_case "a second migration pass leaves the migrated file byte-identical"
before="$(cat "$file")"
run_migration versionless-v3
after="$(cat "$file")"
[[ "$before" == "$after" ]] && test_pass || test_fail "second pass rewrote the file"

write_fixture legacy-v2 <<'JSON'
{
  "version": "2.0",
  "providers": {"codex": {"model": "gpt-5.6-terra"}, "claude": {"default": "claude-opus-5"}},
  "routing": {
    "phases": {"review": "claude:opus"},
    "features": {"debate": ["claude", "codex"], "summarizer": ["codex"]},
    "frontier": {"codex": {"model": "gpt-6-astra"}}
  },
  "tiers": {"budget": {"codex": "spark"}},
  "overrides": {"codex": "gpt-5.6-luna"}
}
JSON
run_migration legacy-v2
file="$(fixture_file legacy-v2)"

test_case "legacy codex.model still seeds codex.default"
val="$(jq -r '.providers.codex.default' "$file")"
[[ "$val" == "gpt-5.6-terra" ]] && test_pass || test_fail "expected gpt-5.6-terra, got: $val"

test_case "user values win over template values at every depth"
if jq -e '
    .version == "3.0" and
    .providers.claude.default == "claude-opus-5" and
    .providers.claude.budget == "claude-haiku-4.5" and
    .routing.phases.review == "claude:opus" and
    .routing.phases.deliver == "codex:default" and
    .tiers.budget.codex == "spark" and
    .tiers.budget.claude == "budget"
' "$file" >/dev/null; then
    test_pass
else
    test_fail "template overwrote user values: $(jq -c . "$file")"
fi

test_case "overrides, frontier policy and feature participant lists are preserved"
if jq -e '
    .overrides == {"codex": "gpt-5.6-luna"} and
    .routing.frontier.codex.model == "gpt-6-astra" and
    .routing.features.debate == ["claude", "codex"] and
    .routing.features.summarizer == ["codex"]
' "$file" >/dev/null; then
    test_pass
else
    test_fail "user routing state lost: $(jq -c . "$file")"
fi

write_fixture malformed <<'JSON'
{"routing": {"features": {"review": ["codex"]}
JSON
run_migration malformed
file="$(fixture_file malformed)"

test_case "a malformed config is left untouched instead of being replaced by the template"
if [[ "$(cat "$file")" == '{"routing": {"features": {"review": ["codex"]}' ]] &&
   [[ -z "$(find "$(dirname "$file")" -name 'providers.json.tmp.*' -print)" ]]; then
    test_pass
else
    test_fail "malformed config was rewritten or temp files leaked: $(cat "$file")"
fi

write_fixture non-object <<'JSON'
["codex", "claude"]
JSON
run_migration non-object
file="$(fixture_file non-object)"

test_case "a non-object config is left untouched"
val="$(jq -c . "$file")"
[[ "$val" == '["codex","claude"]' ]] && test_pass || test_fail "non-object config was rewritten: $val"

write_fixture invalid-known-sections <<'JSON'
{"providers":[],"routing":"broken","tiers":false,"overrides":42}
JSON
file="$(fixture_file invalid-known-sections)"
before="$(cat "$file")"
run_migration invalid-known-sections

test_case "invalid known section types are left untouched"
after="$(cat "$file")"
if [[ "$after" == "$before" ]] &&
   [[ -z "$(find "$(dirname "$file")" -name 'providers.json.tmp.*' -print)" ]]; then
    test_pass
else
    test_fail "invalid known sections were stamped or rewritten: $after"
fi

write_fixture explicit-null-section <<'JSON'
{"providers":null,"custom":{"keep":true}}
JSON
file="$(fixture_file explicit-null-section)"
before="$(cat "$file")"
run_migration explicit-null-section

test_case "an explicitly null known section is left untouched"
after="$(cat "$file")"
if [[ "$after" == "$before" ]] &&
   [[ -z "$(find "$(dirname "$file")" -name 'providers.json.tmp.*' -print)" ]]; then
    test_pass
else
    test_fail "explicitly null section was stamped or rewritten: $after"
fi

test_summary
