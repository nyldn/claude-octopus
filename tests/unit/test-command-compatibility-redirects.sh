#!/usr/bin/env bash
# Test deterministic command compatibility redirects and their removal metadata.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "command compatibility redirects"

TABLE="$PROJECT_ROOT/config/command-compatibility.json"

test_case "Compatibility table exists and parses"
if [[ -f "$TABLE" ]] && jq -e '.schema_version == 1 and (.entries | type == "array")' "$TABLE" >/dev/null; then
  test_pass
else
  test_fail "config/command-compatibility.json must define schema version 1"
fi

assert_compatibility_entry() {
  local command_name="$1" destination="$2" cost_mode="${3:-}"
  test_case "/octo:$command_name has one deterministic compatibility entry"
  if [[ ! -f "$TABLE" ]]; then
    test_fail "compatibility table is missing"
    return
  fi

  local count
  count="$(jq --arg command "$command_name" '[.entries[] | select(.command == $command)] | length' "$TABLE")"
  if [[ "$count" -ne 1 ]]; then
    test_fail "expected one entry for $command_name, found $count"
  elif ! jq -e --arg command "$command_name" --arg destination "$destination" \
      '.entries[] | select(.command == $command) |
       .destination == $destination and
       .removal_version == "11.0.0"' "$TABLE" >/dev/null; then
    test_fail "$command_name must target $destination and defer removal to 11.0.0"
  elif [[ -n "$cost_mode" ]] && ! jq -e --arg command "$command_name" --arg cost_mode "$cost_mode" \
      '.entries[] | select(.command == $command) | .arguments.cost_mode == $cost_mode' "$TABLE" >/dev/null; then
    test_fail "$command_name must preserve cost mode $cost_mode"
  else
    test_pass
  fi
}

assert_compatibility_entry "budget-mode" "model-config" "budget"
assert_compatibility_entry "standard-mode" "model-config" "standard"
assert_compatibility_entry "premium-mode" "model-config" "premium"
assert_compatibility_entry "octo" "auto"

for mode in budget standard premium; do
  command_file="$PROJECT_ROOT/commands/${mode}-mode.md"
  test_case "/octo:${mode}-mode invokes the real model-config helper"
  if grep -Fq 'scripts/helpers/octo-model-config.sh' "$command_file" &&
     grep -Fq 'cost-mode' "$command_file" &&
     grep -Fq '/octo:model-config' "$command_file"; then
    test_pass
  else
    test_fail "${mode}-mode must preserve helper behavior and name /octo:model-config"
  fi
done

test_case "/octo:octo delegates to the registered auto command"
if grep -Fq 'commands/auto.md' "$PROJECT_ROOT/commands/octo.md" &&
   grep -Fq '/octo:auto' "$PROJECT_ROOT/commands/octo.md"; then
  test_pass
else
  test_fail "octo must remain a deterministic redirect to auto"
fi

test_case "Compatibility entries remain registered for v10"
unregistered=0
while IFS= read -r command_name; do
  if ! jq -e --arg path "./commands/${command_name}.md" '.commands | index($path)' \
      "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null; then
    printf 'unregistered compatibility command: %s\n' "$command_name"
    unregistered=$((unregistered + 1))
  fi
done < <(printf '%s\n' budget-mode standard-mode premium-mode octo)

if [[ "$unregistered" -eq 0 ]]; then
  test_pass
else
  test_fail "$unregistered compatibility command(s) are unregistered"
fi

test_summary
