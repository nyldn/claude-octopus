#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Factory Session Metadata"

log() { :; }
OCTOPUS_FACTORY_HOLDOUT_RATIO=0.20
OCTOPUS_FACTORY_MAX_RETRIES=1
OCTOPUS_FACTORY_SATISFACTION_TARGET=""

# shellcheck source=scripts/lib/factory-spec.sh
source "$PROJECT_ROOT/scripts/lib/factory-spec.sh"

SPEC="$TEST_TMP_DIR/factory-spec.md"
cat > "$SPEC" <<'SPEC'
# Factory specification

Complexity: complicated
Satisfaction Target: 0.90

## Behaviors
### Produce the requested artifact
SPEC

test_case "session metadata persists effective positional factory parameters"
RUN_DIR="$TEST_TMP_DIR/effective"
mkdir -p "$RUN_DIR"
if target=$(parse_factory_spec "$SPEC" "$RUN_DIR" '{"level":"Mature"}' 0.35 3) &&
   [[ "$target" == "0.90" ]] &&
   jq -e '.holdout_ratio == 0.35 and .max_retries == 3 and .maturity.level == "Mature"' \
       "$RUN_DIR/session.json" >/dev/null; then
    test_pass
else
    test_fail "session.json did not preserve the effective run parameters"
fi

test_case "invalid maturity JSON is rejected before session metadata is written"
RUN_DIR="$TEST_TMP_DIR/invalid-maturity"
mkdir -p "$RUN_DIR"
if parse_factory_spec "$SPEC" "$RUN_DIR" '{bad json' 0.20 1 >/dev/null 2>&1 ||
   [[ -e "$RUN_DIR/session.json" ]]; then
    test_fail "malformed maturity metadata should fail without writing session.json"
else
    test_pass
fi

test_case "multiple top-level maturity JSON values are rejected"
RUN_DIR="$TEST_TMP_DIR/multiple-maturity-values"
mkdir -p "$RUN_DIR"
if parse_factory_spec "$SPEC" "$RUN_DIR" '{} {}' 0.20 1 >/dev/null 2>&1 ||
   [[ -e "$RUN_DIR/session.json" ]]; then
    test_fail "multiple JSON documents should fail without writing session.json"
else
    test_pass
fi

test_case "invalid ratios and retries are rejected before session metadata is written"
invalid_values_rejected=true
for values in '1.5 1' 'word 1' '0.20 -1' '0.20 1.5'; do
    read -r ratio retries <<<"$values"
    RUN_DIR="$TEST_TMP_DIR/invalid-${ratio//[^A-Za-z0-9]/_}-${retries//[^A-Za-z0-9]/_}"
    mkdir -p "$RUN_DIR"
    if parse_factory_spec "$SPEC" "$RUN_DIR" '{}' "$ratio" "$retries" >/dev/null 2>&1 ||
       [[ -e "$RUN_DIR/session.json" ]]; then
        invalid_values_rejected=false
    fi
done
if [[ "$invalid_values_rejected" == "true" ]]; then
    test_pass
else
    test_fail "invalid holdout ratio or retry count reached session.json"
fi

test_case "omitted maturity data no longer reads a dynamically scoped caller variable"
RUN_DIR="$TEST_TMP_DIR/no-dynamic-scope"
mkdir -p "$RUN_DIR"
call_without_maturity_argument() {
    local maturity_json='{bad json'
    parse_factory_spec "$SPEC" "$RUN_DIR"
}
if call_without_maturity_argument >/dev/null &&
   jq -e '.maturity == {}' "$RUN_DIR/session.json" >/dev/null; then
    test_pass
else
    test_fail "parse_factory_spec still inherited maturity_json from its caller"
fi

test_summary
