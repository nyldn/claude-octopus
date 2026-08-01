#!/bin/bash
set -euo pipefail

# tests/unit/test-cli-flag-after-subcommand.sh
# Regression coverage for issue #698: a global flag placed AFTER the
# subcommand (e.g. `orchestrate.sh define --timeout 540 "prompt"`) that
# isn't recognized by the late-args loop used to be silently read as the
# prompt itself, discarding the real prompt with no error. orchestrate.sh
# must now fail loud instead of running on the flag name as its task.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "CLI: global flags after the subcommand (issue #698)"

run_orchestrate() {
    (cd "$PROJECT_ROOT" && bash scripts/orchestrate.sh "$@" 2>&1)
}

test_case "define --timeout after subcommand fails loud instead of eating the prompt"
out="$(run_orchestrate define --timeout 540 "REAL PROMPT HERE" --dry-run)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"looks like a flag but was read as the prompt"* ]]; then
    test_pass
else
    test_fail "expected a loud error; got exit=$rc, output: $out"
fi

test_case "define --timeout after subcommand never reaches grasp_define with the flag as prompt"
out="$(run_orchestrate define --timeout 540 "REAL PROMPT HERE" --dry-run)" || true
if [[ "$out" != *"Would grasp: --timeout"* ]]; then
    test_pass
else
    test_fail "flag name was silently treated as the prompt: $out"
fi

test_case "--timeout before the subcommand still works (unaffected)"
out="$(run_orchestrate --timeout 540 define "REAL PROMPT HERE" --dry-run)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"Would grasp: REAL PROMPT HERE"* ]]; then
    test_pass
else
    test_fail "expected successful dry-run with the real prompt; got exit=$rc, output: $out"
fi

# Table-driven coverage: every command that consumes a free-text prompt and
# shares the vulnerable late-args loop should get the same guard. grapple and
# probe-single are deliberately excluded — they run their own local flag
# parsers instead of falling through to the shared late-args loop.
GUARDED_COMMANDS=(
    "discover:--parallel 3"
    "research:--parallel 3"
    "probe:--parallel 3"
    "grasp:--timeout 540"
    "verify:--branch foo"
    "verification-only:--branch foo"
    "develop:--branch foo"
    "tangle:--branch foo"
    "deliver:--branch foo"
    "ink:--branch foo"
    "embrace:--branch foo"
    "squeeze:--branch foo"
    "red-team:--branch foo"
)

for entry in "${GUARDED_COMMANDS[@]}"; do
    cmd="${entry%%:*}"
    flag="${entry#*:}"
    test_case "$cmd $flag after subcommand fails loud"
    # shellcheck disable=SC2086 # deliberate split of the "flag value" pair
    out="$(run_orchestrate "$cmd" $flag "some prompt" --dry-run)" && rc=0 || rc=$?
    if [[ "$rc" -ne 0 && "$out" == *"looks like a flag but was read as the prompt"* ]]; then
        test_pass
    else
        test_fail "expected a loud error; got exit=$rc, output: $out"
    fi
done

test_case "define -h prints usage and is not mistaken for the flag-guard error"
out="$(run_orchestrate define -h)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"Usage:"* && "$out" != *"looks like a flag but was read as the prompt"* ]]; then
    test_pass
else
    test_fail "expected usage output; got exit=$rc, output: $out"
fi

test_case "define --help prints usage and is not mistaken for the flag-guard error"
out="$(run_orchestrate define --help)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"Usage:"* && "$out" != *"looks like a flag but was read as the prompt"* ]]; then
    test_pass
else
    test_fail "expected usage output; got exit=$rc, output: $out"
fi

test_summary
