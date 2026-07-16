#!/usr/bin/env bash
# Tests for the periodic GitHub work queue reminder hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"

test_suite "GitHub work queue hook"

HOOK="$PROJECT_ROOT/hooks/github-work-queue-watch.sh"
HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"

test_case "hook exists and is executable"
if [[ -x "$HOOK" ]]; then
    test_pass
else
    test_fail "github-work-queue-watch.sh missing or not executable"
fi

test_case "hook is registered on UserPromptSubmit"
if jq -e '(.hooks // .) | .UserPromptSubmit[]?.hooks[]? | select(.command | contains("github-work-queue-watch.sh"))' "$HOOKS_JSON" >/dev/null; then
    test_pass
else
    test_fail "github-work-queue-watch.sh not registered in UserPromptSubmit hooks"
fi

mock_bin="$TEST_TMP_DIR/github-work-queue-bin"
mock_home="$TEST_TMP_DIR/github-work-queue-home"
mkdir -p "$mock_bin" "$mock_home"
cat > "$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "auth" ]]; then
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "#370 Native provider allowlist - https://github.com/nyldn/claude-octopus/issues/370"
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  echo "#370 Native provider allowlist - https://github.com/nyldn/claude-octopus/issues/370"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo "#372 symlink self-loop - https://github.com/nyldn/claude-octopus/pull/372"
  exit 0
fi
exit 1
SH
chmod +x "$mock_bin/gh"

test_case "hook emits open issues and PRs as additional context"
output=$(cd "$PROJECT_ROOT" && HOME="$mock_home" PATH="$mock_bin:$PATH" OCTOPUS_GITHUB_WORK_QUEUE_FORCE=1 OCTOPUS_GITHUB_WORK_QUEUE_ISSUE=370 "$HOOK" <<'JSON'
{"prompt":"what should we work on"}
JSON
)
if assert_contains "$output" "additionalContext" "hook returns context" &&
   assert_contains "$output" "#370 Native provider allowlist" "hook includes focus issue" &&
   assert_contains "$output" "Open PRs" "hook includes open PR section" &&
   assert_contains "$output" "only push/comment/merge after the user asks" "hook stays non-destructive"; then
    test_pass
fi

test_case "hook debounces repeated checks"
debounce_home="$TEST_TMP_DIR/github-work-queue-debounce-home"
mkdir -p "$debounce_home"
first=$(cd "$PROJECT_ROOT" && HOME="$debounce_home" PATH="$mock_bin:$PATH" "$HOOK" <<'JSON'
{"prompt":"first"}
JSON
)
second=$(cd "$PROJECT_ROOT" && HOME="$debounce_home" PATH="$mock_bin:$PATH" "$HOOK" <<'JSON'
{"prompt":"second"}
JSON
)
if assert_contains "$first" "Open upstream work exists" "first run surfaces queue" &&
   assert_not_contains "$second" "Open upstream work exists" "second run is debounced"; then
    test_pass
fi

test_summary
