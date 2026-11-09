#!/usr/bin/env bash
# Leading help must work without the workflow runtime libraries.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "early help dispatch"
TMP="$TEST_TMP_DIR/help-early"
mkdir -p "$TMP"
mkdir -p "$TMP/plugin/scripts/lib" "$TMP/home/.claude/agents"
printf 'custom agent fixture\n' > "$TMP/home/.claude/agents/example.md"
cp "$ROOT/scripts/orchestrate.sh" "$TMP/plugin/scripts/"
for lib in usage-help provider-registry provider-policy agent-spec models plugin-root host-runtime; do
    cp "$ROOT/scripts/lib/$lib.sh" "$TMP/plugin/scripts/lib/"
done
for host in claude codex factory; do
    for args in '--help' '-h' 'help' '--help --full' 'help --full' 'help council' 'help discover' 'help unknown'; do
        test_case "$host $args matches the shared renderer without runtime libraries"
        read -r -a argv <<< "$args"
        rc=0; expected_rc=0
        env -i PATH="$PATH" HOME="$TMP/home" OCTOPUS_HOST="$host" CLAUDE_OCTOPUS_QUALITY_THRESHOLD=83 \
            bash "$TMP/plugin/scripts/orchestrate.sh" "${argv[@]}" > "$TMP/actual" 2> "$TMP/err" || rc=$?
        env -i PATH="$PATH" HOME="$TMP/home" CLAUDE_OCTOPUS_QUALITY_THRESHOLD=83 \
            bash -c 'source "$1"; shift; octopus_help_colors; octopus_help_defaults; [[ "$1" != help ]] || shift; usage "$@"' \
            "$TMP/plugin/scripts/orchestrate.sh" "$ROOT/scripts/lib/usage-help.sh" "${argv[@]}" > "$TMP/expected" 2> "$TMP/expected-err" || expected_rc=$?
        if [[ "$rc" == "$expected_rc" ]] && cmp -s "$TMP/actual" "$TMP/expected" && cmp -s "$TMP/err" "$TMP/expected-err"; then test_pass
        else test_fail "rc=$rc expected=$expected_rc stderr=$(cat "$TMP/err")"; fi
    done
done
test_case "full help retains all three configurable/default values"
env -i PATH="$PATH" HOME="$TMP/home" bash "$TMP/plugin/scripts/orchestrate.sh" --help --full > "$TMP/full"
if grep -q 'Quality threshold (default: 75)' "$TMP/full" && grep -q 'Max parallel agents (default: 3)' "$TMP/full" && grep -q 'Timeout per task (default: 600)' "$TMP/full"; then test_pass; else test_fail "missing defaults"; fi
test_case "help creates no workspace state"
if [[ ! -e "$TMP/home/.claude-octopus" ]]; then test_pass; else test_fail "help initialized workspace"; fi
test_summary
