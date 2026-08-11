#!/bin/bash
# Provider CLI guard — blocks unsafe direct non-interactive provider dispatch.
# PreToolUse hook on Bash. Returns block decision with correction message.
# WHY: `codex "prompt"` launches interactive TUI which fails in non-TTY (Claude Code Bash tool).
#      `codex exec "prompt"` is the correct non-interactive mode.
#      Direct Qwen dispatch can enter OAuth device authorization and open a browser.
#      Direct Gemini dispatch uses a retired individual client. Both bypass Octopus
#      provider admission and authentication checks.
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Note: this gate guards correctness, not user permission policy, so it runs
# regardless of bypassPermissions.

INPUT=$(cat 2>/dev/null || true)
[[ -z "$INPUT" ]] && exit 0

# Extract command
if command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
else
    COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | cut -d'"' -f4)
fi
[[ -z "$COMMAND" ]] && exit 0

# Emit unquoted shell command segments, one per line. This deliberately ignores
# provider names in prompt/data strings while recognizing subshell, pipeline,
# background, chained, and multiline command positions. Bash 3.2 compatible.
_octo_command_segments() {
    local source="$1" segment="" state="plain" escaped="false"
    local i char

    for ((i = 0; i < ${#source}; i++)); do
        char="${source:i:1}"

        if [[ "$escaped" == "true" ]]; then
            # An unquoted backslash preserves the next character as part of the
            # same shell word. Keep ordinary characters (`q\wen` -> `qwen`),
            # but use a non-separator placeholder when the escaped character
            # would otherwise create a false token boundary.
            case "$char" in
                $'\n') ;;
                ' '|$'\t'|';'|'&'|'|'|'('|')'|'{'|'}') segment="${segment}_" ;;
                *) segment="${segment}${char}" ;;
            esac
            escaped="false"
            continue
        fi

        case "$state" in
            single)
                [[ "$char" == "'" ]] && state="plain"
                segment="${segment} "
                ;;
            double)
                if [[ "$char" == '"' ]]; then
                    state="plain"
                elif [[ "$char" == "\\" ]]; then
                    escaped="true"
                fi
                segment="${segment} "
                ;;
            plain)
                case "$char" in
                    "'") state="single"; segment="${segment} " ;;
                    '"') state="double"; segment="${segment} " ;;
                    "\\") escaped="true" ;;
                    ';'|'&'|'|'|'('|')'|'{'|'}'|$'\n')
                        printf '%s\n' "$segment"
                        segment=""
                        ;;
                    *) segment="${segment}${char}" ;;
                esac
                ;;
        esac
    done

    printf '%s\n' "$segment"
}

_octo_segment_provider() {
    local segment="$1" token="" provider="" first_arg=""
    local saw_env="false" saw_command="false"

    # Shell word splitting is intentional here; glob expansion is not.
    set -f
    # shellcheck disable=SC2086
    set -- $segment
    set +f

    while [[ $# -gt 0 ]]; do
        token="$1"
        shift

        case "$token" in
            if|then|elif|else|while|until|do|!|time)
                continue
                ;;
            env)
                saw_env="true"
                continue
                ;;
            command)
                saw_command="true"
                continue
                ;;
            -v|-V)
                # `command -v/-V provider` is harmless introspection.
                [[ "$saw_command" == "true" ]] && return 1
                [[ "$saw_env" == "true" ]] && continue
                return 1
                ;;
            -p|--)
                # Both are valid `command` prefixes; env also accepts `--`.
                if [[ "$saw_command" == "true" || "$saw_env" == "true" ]]; then
                    continue
                fi
                return 1
                ;;
            -*)
                [[ "$saw_env" == "true" ]] && continue
                return 1
                ;;
            [A-Za-z_][A-Za-z0-9_]*=*)
                continue
                ;;
            nohup)
                continue
                ;;
            *)
                provider="${token##*/}"
                first_arg="${1:-}"
                break
                ;;
        esac
    done

    case "$provider" in
        qwen|gemini)
            case "$first_arg" in
                --version|--help|-h|-v|version|help)
                    return 1
                    ;;
            esac
            printf '%s\n' "$provider"
            return 0
            ;;
        codex)
            case "$first_arg" in
                exec|--version|--help|-h|login|auth|completion)
                    return 1
                    ;;
            esac
            printf '%s\n' "$provider"
            return 0
            ;;
    esac

    return 1
}

DIRECT_PROVIDER=""
while IFS= read -r segment; do
    if DIRECT_PROVIDER=$(_octo_segment_provider "$segment"); then
        break
    fi
done < <(_octo_command_segments "$COMMAND")

if [[ "$DIRECT_PROVIDER" == "codex" ]]; then
    cat <<'BLOCK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: bare `codex \"prompt\"` launches interactive TUI and fails without a TTY. Flags such as `--approval-mode`, `--full-auto`, `-q`, and `--quiet` are not valid for current non-interactive Codex dispatch.\n\nUse `codex exec` instead:\n```bash\ncodex exec --skip-git-repo-check \"YOUR PROMPT\"\n```\n\nWith model: `codex exec --skip-git-repo-check --model gpt-5.4 \"YOUR PROMPT\"`\n\nFor long prompts, pipe stdin to `codex exec --skip-git-repo-check -`."}}
BLOCK
    exit 0
fi

if [[ "$DIRECT_PROVIDER" == "qwen" ]]; then
    cat <<'BLOCK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: direct Qwen CLI prompt dispatch bypasses Octopus provider admission and authentication checks. If Qwen OAuth is absent or expired, the CLI opens chat.qwen.ai and waits for interactive authorization.\n\nRun the workflow through an Octopus command or skill so Qwen is invoked non-interactively only after authentication is validated. Use `qwen --version` or `qwen --help` only for harmless inspection."}}
BLOCK
    exit 0
fi

if [[ "$DIRECT_PROVIDER" == "gemini" ]]; then
    cat <<'BLOCK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: the direct Gemini CLI individual client is retired and must not be dispatched by Octopus workflows. It can trigger obsolete OAuth/keychain flows before failing.\n\nUse the Antigravity provider through an Octopus command or skill. `gemini --version` and `gemini --help` remain available for harmless inspection."}}
BLOCK
    exit 0
fi

: # pass-through — current hook schema treats silence as continue
