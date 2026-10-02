#!/usr/bin/env bash
# Standalone doctor must use shared startup state without running a workflow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${DOCTOR_TEST_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Doctor early dispatch"

fixture_home="$TEST_TMP_DIR/home"
mkdir -p "$fixture_home/.claude-octopus/config" "$TEST_TMP_DIR/tmp"
cat > "$MOCK_BIN_DIR/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCTOR_CALLS"
case "$*" in
    --version) echo '2.1.280 (Claude Code)' ;;
    agents) echo '[]' ;;
    'plugin validate --help') echo '--strict' ;;
    'plugin validate '*) exit 0 ;;
    *) exit 99 ;;
esac
SH
for binary in codex agy agent cursor-agent curl wget; do
    cat > "$MOCK_BIN_DIR/$binary" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && exit 1
printf '%s %s\n' "${0##*/}" "$*" >> "$DOCTOR_UNEXPECTED_CALLS"
exit 99
SH
done
chmod +x "$MOCK_BIN_DIR/"*
# A legacy configuration would be migrated by the ordinary dispatch resolver.
printf '%s\n' '{"version":"1.0","providers":{"codex":{"default":"gpt-5.6-terra"}}}' \
    > "$fixture_home/.claude-octopus/config/providers.json"
cp -a "$fixture_home" "$TEST_TMP_DIR/initial-home"
cp -a "$TEST_TMP_DIR/tmp" "$TEST_TMP_DIR/initial-tmp"

run_doctor() {
    local category="$1"
    shift
    local rc=0
    env -i "HOME=$fixture_home" "PATH=$MOCK_BIN_DIR:/usr/bin:/bin" \
        "TMPDIR=$TEST_TMP_DIR/tmp" "PLUGIN_DIR=$PROJECT_ROOT" \
        "OCTOPUS_HOST=claude" "OCTOPUS_DISABLE_BARE=1" "OCTOPUS_GRAPHIFY=0" \
        "DOCTOR_CALLS=$TEST_TMP_DIR/claude-calls" \
        "DOCTOR_UNEXPECTED_CALLS=$TEST_TMP_DIR/unexpected-calls" \
        "$@" bash "$PROJECT_ROOT/scripts/doctor.sh" ${category:+"$category"} --json \
        > "$TEST_TMP_DIR/result.json" 2> "$TEST_TMP_DIR/stderr" || rc=$?
    [[ "$rc" -le 1 ]] && jq -e '.results | type == "array"' "$TEST_TMP_DIR/result.json" >/dev/null
}

row_is() {
    jq -e --arg name "$1" --arg status "$2" --arg message "$3" '
        any(.results[]; .name == $name and .status == $status and (.message | contains($message)))
    ' "$TEST_TMP_DIR/result.json" >/dev/null
}

test_case "standalone JSON detects Claude version and removes the false deadlock warning"
run_doctor ""
if [[ ! -e "$fixture_home/.claude-octopus/plugin" && ! -L "$fixture_home/.claude-octopus/plugin" ]] &&
   row_is agents-version pass 'Claude Code v2.1.280' &&
   ! grep -q 'CC < v2.1.73' "$TEST_TMP_DIR/result.json" &&
   diff -r --no-dereference "$TEST_TMP_DIR/initial-home" "$fixture_home" &&
   diff -r "$TEST_TMP_DIR/initial-tmp" "$TEST_TMP_DIR/tmp"; then
    test_pass
else
    test_fail "version-gated rows did not use the shared Claude version detector"
fi

test_case "doctor finds an expired smoke cache"
printf '0\nstale-key\n0\n' > "$fixture_home/.claude-octopus/.smoke-test-cache"
run_doctor smoke
if row_is smoke-cache warn 'Smoke test cache expired or stale'; then test_pass; else test_fail "existing cache was not found"; fi

test_case "doctor resolves configured Codex and default Antigravity models"
if row_is smoke-codex-model pass 'Codex model: gpt-5.6-terra' &&
   row_is smoke-agy-model pass 'Antigravity model: default'; then
    test_pass
else
    test_fail "shared model configuration was not loaded"
fi

test_case "doctor validates a fresh smoke cache with the shared cache key and TTL"
printf '%s\n%s\n0\n' "$(date +%s)" \
    'gpt-5.6-terra:auto:none:workspace-write:claude=claude/claude-sonnet-5' \
    > "$fixture_home/.claude-octopus/.smoke-test-cache"
run_doctor smoke
if row_is smoke-cache pass 'Smoke test cache valid'; then test_pass; else test_fail "fresh cache was not validated"; fi

for url in https://api.anthropic.com https://api.anthropic.com/; do
    test_case "first-party URL $url is not a gateway"
    run_doctor config "ANTHROPIC_BASE_URL=$url"
    if row_is gateway-model-discovery pass 'No gateway: ANTHROPIC_BASE_URL is the Anthropic API'; then
        test_pass
    else
        test_fail "first-party API incorrectly classified"
    fi
done

test_case "custom gateway still warns when discovery is not enabled"
run_doctor config 'ANTHROPIC_BASE_URL=https://gateway.example.test'
if row_is gateway-model-discovery warn 'Gateway model discovery is opt-in'; then test_pass; else test_fail "gateway warning missing"; fi

for key_state in unset empty key; do
    test_case "disabled bare authentication with API key $key_state"
    args=()
    expected=pass
    message='--bare disabled: subscription OAuth (--bare accepts only ANTHROPIC_API_KEY/apiKeyHelper)'
    case "$key_state" in
        empty) args=('ANTHROPIC_API_KEY=') ;;
        key) args=('ANTHROPIC_API_KEY=dummy'); expected=warn; message='--bare flag disabled via OCTOPUS_DISABLE_BARE=1' ;;
    esac
    run_doctor skills "${args[@]}"
    if row_is bare-flag "$expected" "$message"; then test_pass; else test_fail "wrong bare status for $key_state key"; fi
done

test_case "static doctor detects once, makes no live calls, and leaves HOME and temp state unchanged"
ln -s "$PROJECT_ROOT" "$fixture_home/.claude-octopus/plugin"
cp -a "$fixture_home" "$TEST_TMP_DIR/home-before"
cp -a "$TEST_TMP_DIR/tmp" "$TEST_TMP_DIR/tmp-before"
: > "$TEST_TMP_DIR/claude-calls"
: > "$TEST_TMP_DIR/unexpected-calls"
run_doctor "" 'OCTOPUS_DISABLE_BARE=0' 'OCTOPUS_AGY_MODEL=Gemini 3.5 Flash (Low)'
if row_is agents-version pass 'Claude Code v2.1.280' &&
   row_is smoke-agy-model pass 'Antigravity model: Gemini 3.5 Flash (Low)' &&
   [[ "$(grep -c '^--version$' "$TEST_TMP_DIR/claude-calls")" == 1 ]] &&
   ! grep -Eq -- '--print|--bare' "$TEST_TMP_DIR/claude-calls" &&
   [[ ! -s "$TEST_TMP_DIR/unexpected-calls" ]] &&
   diff -r --no-dereference "$TEST_TMP_DIR/home-before" "$fixture_home" &&
   diff -r "$TEST_TMP_DIR/tmp-before" "$TEST_TMP_DIR/tmp"; then
    test_pass
else
    test_fail "static doctor probed a provider, changed state, or omitted initialized rows"
fi

test_summary
