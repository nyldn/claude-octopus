#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"

test_suite "Retired Gemini provider boundary"

test_case "Gemini is not a first-class provider and legacy IDs resolve to agy"
provider_ids=" $(octo_provider_ids) "
if [[ "$provider_ids" != *" gemini "* ]] && \
   [[ "$(octo_provider_canonical gemini)" == "agy" ]] && \
   [[ "$(octo_provider_canonical gemini-fast)" == "agy" ]] && \
   [[ "$(octo_provider_command gemini)" == "agy" ]]; then
    test_pass
else
    test_fail "registry still exposes direct Gemini instead of the agy migration alias"
fi

test_case "Legacy Gemini model resolution ignores stale direct-provider config"
resolver_home="$(mktemp -d)"
mkdir -p "$resolver_home/.claude-octopus/config"
printf '%s\n' '{"providers":{"gemini":{"default":"dead-direct-model"},"agy":{"default":"default"}}}' \
    > "$resolver_home/.claude-octopus/config/providers.json"
resolved="$(
    HOME="$resolver_home" bash -c '
        source "$1/scripts/lib/validation.sh"
        source "$1/scripts/lib/model-resolver.sh"
        resolve_octopus_model gemini gemini
    ' _ "$PROJECT_ROOT"
)"
rm -rf "$resolver_home"
if [[ "$resolved" == "default" ]]; then
    test_pass
else
    test_fail "legacy Gemini resolution used stale direct-provider config: $resolved"
fi

test_case "Persisted Gemini provider settings migrate one-way to Antigravity"
migration_home="$(mktemp -d)"
mkdir -p "$migration_home/.claude-octopus/config"
printf '%s\n' '{"version":"3.0","providers":{"gemini":{"default":"dead-model"}},"routing":{"phases":{"research":"gemini:flash"},"roles":{"reviewer":{"provider":"gemini","model":"dead-model"}}},"tiers":{"budget":{"gemini":"flash"}},"overrides":{"gemini":"dead-model"}}' \
    > "$migration_home/.claude-octopus/config/providers.json"
HOME="$migration_home" bash -c '
    log() { :; }
    source "$1/scripts/lib/provider-routing.sh"
    migrate_provider_config
' _ "$PROJECT_ROOT"
migrated_config="$migration_home/.claude-octopus/config/providers.json"
if jq -e '
      (.providers.gemini? == null) and
      (.providers.agy.default == "Gemini 3.1 Pro (High)") and
      (.overrides.gemini? == null) and
      (.overrides.agy == "default") and
      (.tiers.budget.gemini? == null) and
      (.tiers.budget.agy == "flash") and
      (.routing.phases.research == "agy:flash") and
      (.routing.roles.reviewer.provider == "agy") and
      (.routing.roles.reviewer.model == "default")
    ' "$migrated_config" >/dev/null; then
    test_pass
else
    test_fail "persisted Gemini settings were not safely migrated to Antigravity"
fi
rm -rf "$migration_home"

test_case "Default council and smoke policy seat agy but never Gemini"
source "$PROJECT_ROOT/scripts/lib/provider-policy.sh"
council=" $(printf '%s' "$OCTOPUS_COUNCIL_DEFAULT_PROVIDERS_DEFAULT" | tr ',' ' ') "
smoke=" $OCTOPUS_SMOKE_ROUTING_PROVIDERS_DEFAULT "
if [[ "$council" == *" agy "* && "$council" != *" gemini "* && \
      "$smoke" == *" agy "* && "$smoke" != *" gemini "* ]]; then
    test_pass
else
    test_fail "default provider policy still seats Gemini"
fi

test_case "Public agent selection exposes AGY but not retired Gemini IDs"
available_agents=$(sed -n 's/^AVAILABLE_AGENTS="\(.*\)"/ \1 /p' "$PROJECT_ROOT/scripts/orchestrate.sh")
if [[ "$available_agents" == *" agy "* && \
      "$available_agents" != *" gemini "* && \
      "$available_agents" != *" gemini-fast "* && \
      "$available_agents" != *" gemini-image "* ]]; then
    test_pass
else
    test_fail "public agent selection still exposes a retired Gemini ID: $available_agents"
fi

test_case "Direct Gemini provider artifacts are removed"
failed=false
for path in \
    "$PROJECT_ROOT/scripts/helpers/gemini-exec.sh" \
    "$PROJECT_ROOT/config/providers/gemini" \
    "$PROJECT_ROOT/.gemini/commands/octo"; do
    if [[ -e "$path" ]]; then
        test_fail "retired provider artifact remains: ${path#$PROJECT_ROOT/}"
        failed=true
        break
    fi
done
[[ "$failed" == true ]] || test_pass

test_case "Production routing cannot invoke the Gemini executable"
if grep -Ern \
    'gemini-exec\.sh|command[[:space:]]+-v[[:space:]]+gemini|(run_agent(_sync)?|spawn_agent(_capture_pid)?)[[:space:]]+"gemini"|cmd=\(gemini|agent_type="gemini"|check_version[[:space:]]+"gemini"|cli:[[:space:]]+gemini(-fast)?([[:space:]]|$)' \
    "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/hooks" "$PROJECT_ROOT/agents" \
    "$PROJECT_ROOT/.claude/hooks" >/dev/null; then
    test_fail "a direct Gemini execution or dispatch path remains"
else
    test_pass
fi

test_case "Public setup no longer installs or advertises Gemini CLI as a provider"
if grep -Ern \
    '@google/gemini-cli|command[[:space:]]+-v[[:space:]]+gemini|\|[^|]*Gemini CLI[^|]*\|' \
    "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/PRODUCT.md" \
    "$PROJECT_ROOT/docs/PROVIDERS.md" "$PROJECT_ROOT/.claude-plugin/README.md" \
    "$PROJECT_ROOT/.github/ISSUE_TEMPLATE/bug_report.yml" >/dev/null; then
    test_fail "public setup or provider tables still advertise direct Gemini CLI"
else
    test_pass
fi

test_case "CI workflows do not install or credential the retired Gemini CLI"
if grep -Ern \
    '@google/gemini-cli|GEMINI_API_KEY' \
    "$PROJECT_ROOT/.github/workflows" >/dev/null; then
    test_fail "a CI workflow still installs or credentials direct Gemini"
else
    test_pass
fi

test_case "Package, version checks, and provider configuration expose agy without Gemini"
if jq -e '
      (.files | index(".gemini/") | not) and
      (.keywords | index("gemini") | not) and
      (.keywords | index("antigravity") != null)
    ' "$PROJECT_ROOT/package.json" >/dev/null && \
   grep -Eq 'OCTO_AGY_MIN_VERSION' "$PROJECT_ROOT/scripts/lib/provider-versions.sh" && \
   ! grep -En 'OCTO_GEMINI_MIN_VERSION|"gemini"[[:space:]]*:' \
      "$PROJECT_ROOT/scripts/lib/provider-versions.sh" \
      "$PROJECT_ROOT/config/templates/config.json.template" >/dev/null; then
    test_pass
else
    test_fail "package/config still exposes Gemini as a provider"
fi

test_case "Plugin manifests advertise AGY without retired Gemini CLI keywords"
if jq -e '
      (.keywords | index("gemini") | not) and
      (.keywords | index("antigravity") != null)
    ' "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null && \
   jq -e '
      (.keywords | index("gemini") | not) and
      (.description | test("Gemini"; "i") | not) and
      (.interface.longDescription | test("Gemini"; "i") | not)
    ' "$PROJECT_ROOT/.codex-plugin/plugin.json" >/dev/null && \
   jq -e '(.keywords | index("gemini") | not)' \
      "$PROJECT_ROOT/.factory-plugin/plugin.json" >/dev/null && \
   jq -e '
      .plugins[] | select(.name == "octo") |
      (.keywords | index("gemini") | not) and
      (.keywords | index("antigravity") != null)
    ' "$PROJECT_ROOT/.claude-plugin/marketplace.json" >/dev/null; then
    test_pass
else
    test_fail "a public plugin manifest still advertises retired Gemini CLI support"
fi

test_summary
