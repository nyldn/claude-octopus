#!/usr/bin/env bash
# Tests for direct provider CLI guard hook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider CLI guard"

HOOK="$PROJECT_ROOT/hooks/codex-exec-guard.sh"

run_hook() {
    local command="$1"
    printf '{"tool_input":{"command":%s}}\n' "$(printf '%s' "$command" | jq -Rs .)" | bash "$HOOK"
}

test_case "blocks obsolete approval-mode quiet dispatch"
output="$(run_hook 'codex --approval-mode full-auto -q "hello"')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]] \
   && [[ "$output" == *'codex exec --skip-git-repo-check'* ]] \
   && [[ "$output" != *'codex exec --full-auto'* ]]; then
    test_pass
else
    test_fail "expected block with current codex exec guidance, got: ${output:-<empty>}"
fi

test_case "allows current codex exec dispatch"
output="$(run_hook 'codex exec --skip-git-repo-check "hello"')"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected allow for codex exec, got: ${output:-<empty>}"
fi

test_case "blocks direct Qwen prompt dispatch before OAuth can open a browser"
output="$(run_hook '( qwen -p "$PROMPT" > raw-qwen.md ) &')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]] \
   && [[ "$output" == *'Qwen CLI'* ]] \
   && [[ "$output" == *'Octopus'* ]]; then
    test_pass
else
    test_fail "expected direct Qwen dispatch to be denied, got: ${output:-<empty>}"
fi

test_case "blocks environment-prefixed Qwen prompt dispatch"
output="$(run_hook 'NO_BROWSER=1 qwen --prompt "hello"')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    test_pass
else
    test_fail "expected prefixed Qwen dispatch to be denied, got: ${output:-<empty>}"
fi

test_case "blocks escaped and command-wrapped provider dispatch"
for command in \
    'q\wen -p hello' \
    'command -- qwen -p hello' \
    'command -p qwen -p hello' \
    'command -p codex "hello"' \
    'exec qwen -p hello' \
    'exec -- gemini -p hello' \
    'exec -a provider codex "hello"'; do
    output="$(run_hook "$command")"
    if [[ "$output" != *'"permissionDecision":"deny"'* ]]; then
        test_fail "expected wrapped provider dispatch to be denied for $command, got: ${output:-<empty>}"
        break
    fi
done
[[ "$output" == *'"permissionDecision":"deny"'* ]] && test_pass

test_case "allows safe command-wrapped Codex exec"
for command in \
    'command -p codex exec --skip-git-repo-check "hello"' \
    'exec codex exec --skip-git-repo-check "hello"'; do
    output="$(run_hook "$command")"
    if [[ -n "$output" ]]; then
        test_fail "expected command-wrapped codex exec to be allowed for $command, got: $output"
        break
    fi
done
[[ -z "${output:-}" ]] && test_pass

test_case "blocks direct Gemini dispatch and points to Antigravity"
output="$(run_hook 'cd /tmp && (gemini -p "hello")')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]] \
   && [[ "$output" == *'retired'* ]] \
   && [[ "$output" == *'Antigravity'* ]]; then
    test_pass
else
    test_fail "expected direct Gemini dispatch to be denied, got: ${output:-<empty>}"
fi

test_case "blocks direct provider dispatch in a multiline generated workflow"
output="$(run_hook $'PROMPT="hello"\n( codex exec "$PROMPT" ) &\n( qwen -p "$PROMPT" ) &\nwait')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    test_pass
else
    test_fail "expected multiline direct Qwen dispatch to be denied, got: ${output:-<empty>}"
fi

test_case "blocks provider dispatch in shell substitutions"
for command in \
    'printf "%s" "`gemini -p hello`"' \
    'printf "%s" "$(qwen -p hello)"' \
    'echo $(gemini -p hello)'; do
    output="$(run_hook "$command")"
    if [[ "$output" != *'"permissionDecision":"deny"'* ]]; then
        test_fail "expected substitution dispatch to be denied for $command, got: ${output:-<empty>}"
        break
    fi
done
[[ "$output" == *'"permissionDecision":"deny"'* ]] && test_pass

test_case "blocks quoted and absolute provider executables"
for command in '"qwen" -p hello' '/opt/homebrew/bin/qwen -p hello'; do
    output="$(run_hook "$command")"
    if [[ "$output" != *'"permissionDecision":"deny"'* ]]; then
        test_fail "expected executable to be denied for $command, got: ${output:-<empty>}"
        break
    fi
done
[[ "$output" == *'"permissionDecision":"deny"'* ]] && test_pass

test_case "allows harmless provider introspection"
for command in 'qwen --version' '/opt/homebrew/bin/qwen --help' 'gemini --version' 'command -v qwen'; do
    output="$(run_hook "$command")"
    if [[ -n "$output" ]]; then
        test_fail "expected introspection to be allowed for $command, got: $output"
        break
    fi
done
[[ -z "${output:-}" ]] && test_pass

test_case "does not block provider names inside data"
output="$(run_hook 'printf "%s\\n" "safe; qwen -p is unsafe text"')"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected quoted provider text to be allowed, got: ${output:-<empty>}"
fi

test_case "does not parse quoted heredoc bodies as commands"
for command in \
    $'python3 <<\'PY\'\nfrom pathlib import Path\nPath(\'/etc/codex\')\nPY' \
    $'cat <<"DOC"\nqwen -p this is documentation\nDOC' \
    $'cat <<-\'DOC\'\n\tgemini -p this is indented documentation\n\tDOC'; do
    output="$(run_hook "$command")"
    if [[ -n "$output" ]]; then
        test_fail "expected quoted heredoc data to be allowed, got: ${output:-<empty>}"
        break
    fi
done
[[ -z "${output:-}" ]] && test_pass

test_case "quoted heredoc parsing preserves following provider commands"
output="$(run_hook $'cat <<\'DOC\'\nqwen -p documentation only\nDOC\nqwen -p real-dispatch')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    test_pass
else
    test_fail "provider command after quoted heredoc bypassed guard"
fi

test_case "unquoted heredoc command substitutions remain guarded"
output="$(run_hook $'cat <<DOC\n$(qwen -p real-dispatch)\nDOC')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    test_pass
else
    test_fail "provider substitution in an unquoted heredoc bypassed guard"
fi

test_case "does not treat heredoc-looking quoted text as shell syntax"
output="$(run_hook $'printf "%s" "<<\'DOC\'"\nqwen -p real-dispatch')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    test_pass
else
    test_fail "quoted heredoc text hid a following provider command"
fi

test_summary
