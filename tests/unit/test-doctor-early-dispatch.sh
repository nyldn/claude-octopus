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
    --version)
        case "${DOCTOR_VERSION_MODE:-success}" in
            stall) sleep 3; touch "$DOCTOR_VERSION_LATE"; echo '2.1.280 (Claude Code)' ;;
            error) echo '2.1.280 (Claude Code)'; exit 23 ;;
            error127) echo '2.1.280 (Claude Code)'; exit 127 ;;
            malformed) echo 'version unavailable' ;;
            *) echo '2.1.280 (Claude Code)' ;;
        esac ;;
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
    local flags=(--json)
    [[ "${DOCTOR_FIXTURE_LIVE:-false}" != true ]] || flags+=(--live)
    env -i "HOME=$fixture_home" "PATH=$MOCK_BIN_DIR:/usr/bin:/bin" \
        "TMPDIR=$TEST_TMP_DIR/tmp" "PLUGIN_DIR=$PROJECT_ROOT" \
        "OCTOPUS_HOST=claude" "OCTOPUS_DISABLE_BARE=1" "OCTOPUS_GRAPHIFY=0" \
        "DOCTOR_CALLS=$TEST_TMP_DIR/claude-calls" \
        "DOCTOR_UNEXPECTED_CALLS=$TEST_TMP_DIR/unexpected-calls" \
        "$@" bash "$PROJECT_ROOT/scripts/doctor.sh" ${category:+"$category"} "${flags[@]}" \
        > "$TEST_TMP_DIR/result.json" 2> "$TEST_TMP_DIR/stderr" || rc=$?
    DOCTOR_FIXTURE_STATUS="$rc"
    [[ "$rc" -le 1 ]] && jq -e '.results | type == "array"' "$TEST_TMP_DIR/result.json" >/dev/null
}

row_is() {
    jq -e --arg name "$1" --arg status "$2" --arg message "$3" '
        any(.results[]; .name == $name and .status == $status and (.message | contains($message)))
    ' "$TEST_TMP_DIR/result.json" >/dev/null
}

version_category_matches() {
    local selected="$1"
    jq -e --arg selected "$selected" --arg category "${selected:-config}" '
        any(.results[]; .name == "host-version-detection" and .category == $category)
        and ($selected == "" or all(.results[]; .category == $selected))
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

for version_mode in error malformed; do
    test_case "version discovery $version_mode produces failed JSON"
    run_doctor smoke "DOCTOR_VERSION_MODE=$version_mode" 'OCTOPUS_VERSION_PROBE_TIMEOUT=1'
    if [[ "$DOCTOR_FIXTURE_STATUS" == 1 ]] && row_is host-version-detection fail 'Host version discovery failed' &&
       version_category_matches smoke &&
       diff -r --no-dereference "$TEST_TMP_DIR/initial-home" "$fixture_home" &&
       diff -r "$TEST_TMP_DIR/initial-tmp" "$TEST_TMP_DIR/tmp"; then
        test_pass
    else
        test_fail "version failure or requested category was not preserved"
    fi
done

for version_mode in error stall; do
    test_case "providers category skips an unrelated $version_mode version command"
    : > "$TEST_TMP_DIR/claude-calls"
    run_doctor providers "DOCTOR_VERSION_MODE=$version_mode" 'OCTOPUS_VERSION_PROBE_TIMEOUT=1' \
        "DOCTOR_VERSION_LATE=$TEST_TMP_DIR/providers-version-late"
    if [[ "$DOCTOR_FIXTURE_STATUS" == 0 && ! -s "$TEST_TMP_DIR/claude-calls" ]] &&
       jq -e 'all(.results[]; .category == "providers")' "$TEST_TMP_DIR/result.json" >/dev/null &&
       diff -r --no-dereference "$TEST_TMP_DIR/initial-home" "$fixture_home" &&
       diff -r "$TEST_TMP_DIR/initial-tmp" "$TEST_TMP_DIR/tmp"; then test_pass
    else test_fail "provider-only diagnostics ran host discovery or added another category"; fi
done

test_case "state category does not run host version discovery"
: > "$TEST_TMP_DIR/claude-calls"
run_doctor state 'DOCTOR_VERSION_MODE=error'
if [[ ! -s "$TEST_TMP_DIR/claude-calls" ]] &&
   jq -e 'all(.results[]; .name != "host-version-detection")' "$TEST_TMP_DIR/result.json" >/dev/null; then test_pass
else test_fail "state-only diagnostics ran unrelated version discovery"; fi

for version_category in config skills agents ""; do
    test_case "${version_category:-default} diagnostics retain performed version failures"
    : > "$TEST_TMP_DIR/claude-calls"
    run_doctor "$version_category" 'DOCTOR_VERSION_MODE=error'
    if [[ "$DOCTOR_FIXTURE_STATUS" == 1 ]] && row_is host-version-detection fail 'exit 23' &&
       version_category_matches "$version_category" &&
       grep -Fxq -- '--version' "$TEST_TMP_DIR/claude-calls"; then test_pass
    else test_fail "version-dependent diagnostics lost a failure or its requested category"; fi
done

test_case "an installed version command returning 127 remains a failure"
run_doctor smoke 'DOCTOR_VERSION_MODE=error127'
if [[ "$DOCTOR_FIXTURE_STATUS" == 1 ]] && row_is host-version-detection fail 'exit 127' && version_category_matches smoke; then test_pass
else test_fail "performed command failure or requested category was not preserved"; fi

for missing_category in smoke config skills agents ""; do
    test_case "${missing_category:-default} diagnostics warn when optional host CLI is absent"
    # A global fallback prevents an isolated missing-client fixture.
    if [[ -x /usr/local/bin/claude ]]; then
        test_skip "global Claude fallback is installed"
        continue
    fi
    mv "$MOCK_BIN_DIR/claude" "$TEST_TMP_DIR/claude-saved"
    run_doctor "$missing_category"
    missing_warning=false
    row_is host-version-detection warn 'version was not checked' && missing_warning=true
    missing_failure=false
    row_is host-version-detection fail '' && missing_failure=true
    mv "$TEST_TMP_DIR/claude-saved" "$MOCK_BIN_DIR/claude"
    if [[ "$missing_warning" == true && "$missing_failure" == false ]] &&
       version_category_matches "$missing_category"; then test_pass
    else test_fail "optional-client warning or requested category was not preserved"; fi
done

test_case "stalled version discovery reports timeout and cancels its late write"
version_late="$TEST_TMP_DIR/version-late"
run_doctor smoke 'DOCTOR_VERSION_MODE=stall' 'OCTOPUS_VERSION_PROBE_TIMEOUT=1' "DOCTOR_VERSION_LATE=$version_late"
if [[ "$DOCTOR_FIXTURE_STATUS" == 1 ]] && row_is host-version-detection fail 'exit 124'; then
    sleep 2.3
    if [[ ! -e "$version_late" ]] && version_category_matches smoke &&
       diff -r --no-dereference "$TEST_TMP_DIR/initial-home" "$fixture_home" &&
       diff -r "$TEST_TMP_DIR/initial-tmp" "$TEST_TMP_DIR/tmp"; then test_pass
    else test_fail "version timeout, category, or local-state assertion failed"; fi
else
    test_fail "stalled version discovery did not produce a timeout failure"
fi

test_case "help skips a stalled version command"
: > "$TEST_TMP_DIR/claude-calls"
help_status=0
env -i "HOME=$fixture_home" "PATH=$MOCK_BIN_DIR:/usr/bin:/bin" \
    "TMPDIR=$TEST_TMP_DIR/tmp" "PLUGIN_DIR=$PROJECT_ROOT" \
    "OCTOPUS_HOST=claude" "DOCTOR_CALLS=$TEST_TMP_DIR/claude-calls" \
    "DOCTOR_VERSION_MODE=stall" "DOCTOR_VERSION_LATE=$TEST_TMP_DIR/help-late" \
    bash "$PROJECT_ROOT/scripts/doctor.sh" --help > "$TEST_TMP_DIR/help.txt" 2>&1 || help_status=$?
if [[ "$help_status" == 0 && ! -s "$TEST_TMP_DIR/claude-calls" ]] && grep -q '^Usage: octopus doctor' "$TEST_TMP_DIR/help.txt"; then
    test_pass
else
    test_fail "help performed version discovery"
fi

test_case "Codex host skips Claude version discovery"
: > "$TEST_TMP_DIR/claude-calls"
run_doctor smoke 'OCTOPUS_HOST=codex' 'DOCTOR_VERSION_MODE=stall'
if [[ "$DOCTOR_FIXTURE_STATUS" == 0 && ! -s "$TEST_TMP_DIR/claude-calls" ]]; then test_pass
else test_fail "Codex host attempted Claude version discovery"; fi

test_case "version discovery retains the private HOME install fallback"
mkdir -p "$fixture_home/.local/bin"
mv "$MOCK_BIN_DIR/claude" "$fixture_home/.local/bin/claude"
run_doctor agents
fallback_status="$DOCTOR_FIXTURE_STATUS"
fallback_version=false
row_is agents-version pass 'Claude Code v2.1.280' && fallback_version=true
mv "$fixture_home/.local/bin/claude" "$MOCK_BIN_DIR/claude"
rmdir "$fixture_home/.local/bin" "$fixture_home/.local"
if [[ "$fallback_status" == 0 && "$fallback_version" == true ]]; then test_pass
else test_fail "bounded discovery lost the existing HOME install fallback"; fi

test_case "Factory keeps its feature fallback when a successful Droid version is unparseable"
cat > "$MOCK_BIN_DIR/droid" <<'SH'
#!/usr/bin/env bash
echo 'version unavailable'
SH
chmod +x "$MOCK_BIN_DIR/droid"
mv "$MOCK_BIN_DIR/claude" "$TEST_TMP_DIR/claude-saved"
run_doctor agents 'OCTOPUS_HOST=factory'
factory_status="$DOCTOR_FIXTURE_STATUS"
factory_version=false
row_is agents-version pass 'Claude Code v2.1.69' && factory_version=true
mv "$TEST_TMP_DIR/claude-saved" "$MOCK_BIN_DIR/claude"
rm "$MOCK_BIN_DIR/droid"
if [[ "$factory_status" == 0 && "$factory_version" == true ]]; then test_pass
else test_fail "Factory version fallback changed"; fi

test_case "Factory reports a stalled Droid version command"
cat > "$MOCK_BIN_DIR/droid" <<'SH'
#!/usr/bin/env bash
sleep 3
touch "$DOCTOR_VERSION_LATE"
echo '2.1.280'
SH
chmod +x "$MOCK_BIN_DIR/droid"
mv "$MOCK_BIN_DIR/claude" "$TEST_TMP_DIR/claude-saved"
run_doctor smoke 'OCTOPUS_HOST=factory' 'OCTOPUS_VERSION_PROBE_TIMEOUT=1' "DOCTOR_VERSION_LATE=$TEST_TMP_DIR/droid-late"
factory_status="$DOCTOR_FIXTURE_STATUS"
factory_timeout=false
row_is host-version-detection fail 'exit 124' && version_category_matches smoke && factory_timeout=true
mv "$TEST_TMP_DIR/claude-saved" "$MOCK_BIN_DIR/claude"
rm "$MOCK_BIN_DIR/droid"
sleep 2.3
if [[ "$factory_status" == 1 && "$factory_timeout" == true && ! -e "$TEST_TMP_DIR/droid-late" ]] &&
   diff -r --no-dereference "$TEST_TMP_DIR/initial-home" "$fixture_home" &&
   diff -r "$TEST_TMP_DIR/initial-tmp" "$TEST_TMP_DIR/tmp"; then test_pass
else
    factory_late=false
    [[ ! -e "$TEST_TMP_DIR/droid-late" ]] || factory_late=true
    printf 'Factory timeout details: status=%s timeout_row=%s late_marker=%s\n' \
        "$factory_status" "$factory_timeout" "$factory_late" >&2
    jq -c '.results[] | select(.name == "host-version-detection") | {status, category, message}' \
        "$TEST_TMP_DIR/result.json" >&2 || printf 'Factory diagnostic JSON could not be read\n' >&2
    test_fail "Factory version timeout, category, or local-state assertion failed"
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
    message='--bare disabled; no ANTHROPIC_API_KEY in the environment'
    case "$key_state" in
        empty) args=('ANTHROPIC_API_KEY=') ;;
        key) args=('ANTHROPIC_API_KEY=dummy'); expected=warn; message='--bare flag disabled via OCTOPUS_DISABLE_BARE=1' ;;
    esac
    run_doctor skills ${args[@]+"${args[@]}"}
    if row_is bare-flag "$expected" "$message"; then test_pass; else test_fail "wrong bare status for $key_state key"; fi
done

test_case "disabled bare does not infer OAuth from apiKeyHelper settings"
mkdir -p "$fixture_home/.claude"
jq -n --arg command "touch $TEST_TMP_DIR/api-key-helper-called" '{apiKeyHelper: $command}' > "$fixture_home/.claude/settings.json"
run_doctor skills
if [[ ! -e "$TEST_TMP_DIR/api-key-helper-called" ]] && row_is bare-flag pass '--bare disabled' &&
   ! jq -r '.results[] | select(.name == "bare-flag") | .message' "$TEST_TMP_DIR/result.json" | grep -qi 'subscription OAuth'; then
    test_pass
else
    test_fail "doctor inferred an authentication method from the absent environment key"
fi

test_case "sourced bare-filename doctor loads helpers after changing directories"
env -i "HOME=$fixture_home" "PATH=$MOCK_BIN_DIR:/usr/bin:/bin" \
    "TMPDIR=$TEST_TMP_DIR/tmp" "PLUGIN_DIR=$PROJECT_ROOT" \
    "DOCTOR_CALLS=$TEST_TMP_DIR/claude-calls" \
    "DOCTOR_UNEXPECTED_CALLS=$TEST_TMP_DIR/unexpected-calls" \
    bash > "$TEST_TMP_DIR/result.json" 2> "$TEST_TMP_DIR/stderr" <<'SH'
log() { :; }
cd "$PLUGIN_DIR/scripts/lib" || exit 1
source doctor.sh
cd "$HOME" || exit 1
export PYTHONDONTWRITEBYTECODE=caller-value
do_doctor smoke --json
[[ "$PYTHONDONTWRITEBYTECODE" == caller-value ]] || exit 98
unset PYTHONDONTWRITEBYTECODE
do_doctor smoke --json >/dev/null
[[ -z "${PYTHONDONTWRITEBYTECODE+x}" && -z "${OCTOPUS_MODEL_READ_ONLY+x}" ]]
SH
if row_is smoke-codex-model pass 'Codex model: gpt-5.6-terra' && [[ ! -s "$TEST_TMP_DIR/stderr" ]]; then
    test_pass
else
    test_fail "bare-filename source lost the library directory or failed to load helpers"
fi

test_case "explicit live doctor reaches the inert bare-auth probe"
: > "$TEST_TMP_DIR/claude-calls"
DOCTOR_FIXTURE_LIVE=true run_doctor skills 'OCTOPUS_DISABLE_BARE=0' 'ANTHROPIC_API_KEY=dummy'
if row_is bare-flag warn '--bare' && grep -q -- '--bare' "$TEST_TMP_DIR/claude-calls"; then
    test_pass
else
    test_fail "explicit live mode did not reach the bounded authentication probe"
fi

incomplete_doctor_fixture() (
    local missing="$1" defect="${2:-missing}"
    local incomplete_root="$TEST_TMP_DIR/incomplete-${1%.sh}-$defect"
    mkdir -p "$incomplete_root"
    cp -a "$PROJECT_ROOT/scripts" "$incomplete_root/scripts"
    cp -a "$PROJECT_ROOT/config" "$incomplete_root/config"
    cp -a "$PROJECT_ROOT/.claude-plugin" "$incomplete_root/.claude-plugin"
    if [[ "$defect" == syntax ]]; then
        printf '%s\n' 'if then' > "$incomplete_root/scripts/lib/$missing"
    else
        rm "$incomplete_root/scripts/lib/$missing"
    fi
    PROJECT_ROOT="$incomplete_root"
    run_doctor smoke
    [[ "$DOCTOR_FIXTURE_STATUS" == 1 ]] || return 1
    row_is smoke-helpers fail "Smoke diagnostics helper unavailable: $missing"
)
for missing in model-resolver.sh dispatch.sh smoke.sh; do
    test_case "missing $missing produces valid failed diagnostic JSON"
    if incomplete_doctor_fixture "$missing"; then
        test_pass
    else
        test_fail "missing helper aborted JSON output or claimed healthy smoke configuration"
    fi
done
for malformed in model-resolver.sh dispatch.sh smoke.sh; do
    test_case "syntax error in $malformed produces valid failed diagnostic JSON"
    if incomplete_doctor_fixture "$malformed" syntax; then
        test_pass
    else
        test_fail "helper syntax error aborted JSON output or claimed healthy smoke configuration"
    fi
done

test_case "static doctor detects once, makes no live calls, and leaves HOME and temp state unchanged"
ln -s "$PROJECT_ROOT" "$fixture_home/.claude-octopus/plugin"
# A stale persistent cache must survive static inspection byte for byte.
printf '%s\n' '{"stale":"fixture"}' > "$TEST_TMP_DIR/tmp/octo-model-cache-unknown-global.json"
touch -t 200001010000 "$TEST_TMP_DIR/tmp/octo-model-cache-unknown-global.json"
cp -a "$fixture_home" "$TEST_TMP_DIR/home-before"
cp -a "$TEST_TMP_DIR/tmp" "$TEST_TMP_DIR/tmp-before"
: > "$TEST_TMP_DIR/claude-calls"
: > "$TEST_TMP_DIR/unexpected-calls"
run_doctor "" 'OCTOPUS_DISABLE_BARE=0' 'OCTOPUS_AGY_MODEL=Gemini 3.5 Flash (Low)'
if row_is agents-version pass 'Claude Code v2.1.280' &&
   row_is smoke-codex-model pass 'Codex model: gpt-5.6-terra' &&
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
