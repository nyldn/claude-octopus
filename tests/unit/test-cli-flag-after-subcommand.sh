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

test_case "probe --parallel after subcommand fails loud"
out="$(run_orchestrate probe --parallel 3 "topic" --dry-run)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"looks like a flag but was read as the prompt"* ]]; then
    test_pass
else
    test_fail "expected a loud error; got exit=$rc, output: $out"
fi

test_case "develop --branch after subcommand fails loud"
out="$(run_orchestrate develop --branch foo "build the thing" --dry-run)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"looks like a flag but was read as the prompt"* ]]; then
    test_pass
else
    test_fail "expected a loud error; got exit=$rc, output: $out"
fi

test_case "define --help after subcommand is not mistaken for the flag-guard error"
out="$(run_orchestrate define --help)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" != *"looks like a flag but was read as the prompt"* ]]; then
    test_pass
else
    test_fail "expected normal help output; got exit=$rc, output: $out"
fi

test_summary
