#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Setup path to first success"

SETUP="$PROJECT_ROOT/commands/setup.md"
setup_text="$(cat "$SETUP")"
default_path="$(sed -n '/^## Default path/,/^## Advanced setup/p' "$SETUP")"
advanced_path="$(sed -n '/^## Advanced setup/,$p' "$SETUP")"
readiness_step="$(sed -n '/^### 2\. Show shared readiness/,/^### 3\./p' "$SETUP")"

test_case "initial setup renders the shared static readiness contract once"
if [[ "$(grep -c 'scripts/helpers/preflight.sh.*--json' <<<"$readiness_step" || true)" -eq 1 ]] &&
   ! grep -Eq 'command -v (codex|agy|copilot|qwen|opencode|vibe)|PERPLEXITY_API_KEY|curl .*api/tags' <<<"$default_path"; then
    test_pass
else
    test_fail "default setup must consume one shared readiness report without re-detection"
fi

test_case "default path offers Claude-only or one additional provider"
if grep -q 'Use Claude alone' <<<"$default_path" &&
   grep -q 'Configure one provider' <<<"$default_path"; then
    test_pass
else
    test_fail "default setup choices do not establish the first-success path"
fi

test_case "default verification is deterministic and no-billing"
if grep -q 'setup-verification' <<<"$default_path" &&
   grep -qi 'no provider request' <<<"$default_path"; then
    test_pass
else
    test_fail "default setup lacks an explicit no-billing verification"
fi

test_case "default completion shows exactly the three next commands"
next_commands="$(awk '
  /^Next commands:/ {in_next=1; next}
  in_next && /^```text$/ {in_fence=1; next}
  in_next && in_fence && /^```$/ {exit}
  in_next && in_fence {print}
' <<<"$default_path" | grep -oE '/octo:[a-z-]+' || true)"
expected=$'/octo:auto\n/octo:skill-doctor\n/octo:setup'
if [[ "$next_commands" == "$expected" ]]; then
    test_pass
else
    test_fail "expected three next commands, got: ${next_commands//$'\n'/, }"
fi

test_case "optional companions and tuning stay in Advanced setup"
if ! grep -Eqi 'RTK|Graphify|memory companion|cost mode|scheduler|model override|project tier' <<<"$default_path" &&
   grep -Eqi 'RTK' <<<"$advanced_path" &&
   grep -Eqi 'Graphify' <<<"$advanced_path" &&
   grep -Eqi 'memory companion' <<<"$advanced_path"; then
    test_pass
else
    test_fail "optional setup leaked into the default path or is absent from Advanced setup"
fi

test_case "setup removes stale migration and retired Doctor guidance"
if ! grep -q 'v9.29 Migration' <<<"$setup_text" &&
   ! grep -q '/octo:doctor' <<<"$setup_text" &&
   grep -q '/octo:skill-doctor' <<<"$setup_text" &&
   grep -q 'octopus doctor' <<<"$setup_text"; then
    test_pass
else
    test_fail "setup still exposes stale migration or retired Doctor guidance"
fi

test_case "default path writes only after explicit confirmation"
first_question_line="$(grep -n 'AskUserQuestion' <<<"$default_path" | head -1 | cut -d: -f1 || true)"
first_write_line="$(grep -nE 'octo_(config|pref)_write|npm install|brew install|uv tool install' <<<"$default_path" | head -1 | cut -d: -f1 || true)"
if [[ -n "$first_question_line" ]] && { [[ -z "$first_write_line" ]] || (( first_write_line > first_question_line )); }; then
    test_pass
else
    test_fail "default setup can mutate state before the user chooses an option"
fi

test_summary
