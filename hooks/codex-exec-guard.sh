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

# Find the closing parenthesis for a $(...) command substitution. Parentheses
# inside quotes/backticks do not close the substitution; nested substitutions
# and grouping parentheses increase its depth. Bash 3.2 compatible.
_octo_command_sub_end() {
    local source="$1" start="$2" state="plain" escaped="false" depth=1
    local i char next

    for ((i = start; i < ${#source}; i++)); do
        char="${source:i:1}"
        next="${source:i+1:1}"

        if [[ "$escaped" == "true" ]]; then
            escaped="false"
            continue
        fi

        case "$state" in
            single)
                [[ "$char" == "'" ]] && state="plain"
                ;;
            double)
                case "$char" in
                    '"') state="plain" ;;
                    "\\") escaped="true" ;;
                    '$')
                        if [[ "$next" == '(' ]]; then
                            depth=$((depth + 1))
                            i=$((i + 1))
                        fi
                        ;;
                esac
                ;;
            backtick)
                case "$char" in
                    '`') state="plain" ;;
                    "\\") escaped="true" ;;
                esac
                ;;
            plain)
                case "$char" in
                    "'") state="single" ;;
                    '"') state="double" ;;
                    '`') state="backtick" ;;
                    "\\") escaped="true" ;;
                    '(') depth=$((depth + 1)) ;;
                    ')')
                        depth=$((depth - 1))
                        if [[ $depth -eq 0 ]]; then
                            printf '%s\n' "$i"
                            return 0
                        fi
                        ;;
                esac
                ;;
        esac
    done

    return 1
}

_octo_backtick_end() {
    local source="$1" start="$2" escaped="false" i char

    for ((i = start; i < ${#source}; i++)); do
        char="${source:i:1}"
        if [[ "$escaped" == "true" ]]; then
            escaped="false"
        elif [[ "$char" == "\\" ]]; then
            escaped="true"
        elif [[ "$char" == '`' ]]; then
            printf '%s\n' "$i"
            return 0
        fi
    done

    return 1
}

# Print the delimiter, tab-stripping flag, and quoting flag for the first
# heredoc operator that appears in executable shell syntax on a line. Operators
# inside quotes and comments are data, not syntax.
_octo_heredoc_spec() {
    local line="$1" state="plain" escaped="false"
    local i char next previous j strip_tabs="false" quote delimiter="" quoted="false"

    for ((i = 0; i < ${#line}; i++)); do
        char="${line:i:1}"
        next="${line:i+1:1}"
        previous="${line:i-1:1}"

        if [[ "$escaped" == "true" ]]; then
            escaped="false"
            continue
        fi

        case "$state" in
            single)
                [[ "$char" == "'" ]] && state="plain"
                ;;
            double)
                case "$char" in
                    '"') state="plain" ;;
                    "\\") escaped="true" ;;
                esac
                ;;
            plain)
                case "$char" in
                    "'") state="single" ;;
                    '"') state="double" ;;
                    "\\") escaped="true" ;;
                    '#')
                        if [[ $i -eq 0 || "$previous" == ' ' || "$previous" == $'\t' ]]; then
                            return 1
                        fi
                        ;;
                    '<')
                        [[ "$next" == '<' ]] || continue
                        j=$((i + 2))
                        if [[ "${line:j:1}" == '-' ]]; then
                            strip_tabs="true"
                            j=$((j + 1))
                        fi
                        while [[ "${line:j:1}" == ' ' || "${line:j:1}" == $'\t' ]]; do
                            j=$((j + 1))
                        done
                        quote="${line:j:1}"
                        if [[ "$quote" == "'" || "$quote" == '"' ]]; then
                            quoted="true"
                            j=$((j + 1))
                            while [[ $j -lt ${#line} && "${line:j:1}" != "$quote" ]]; do
                                delimiter="${delimiter}${line:j:1}"
                                j=$((j + 1))
                            done
                            [[ $j -lt ${#line} ]] || return 1
                        else
                            while [[ $j -lt ${#line} ]]; do
                                char="${line:j:1}"
                                case "$char" in
                                    ' '|$'\t'|';'|'&'|'|'|'<'|'>'|'('|')') break ;;
                                    *) delimiter="${delimiter}${char}" ;;
                                esac
                                j=$((j + 1))
                            done
                        fi
                        [[ -n "$delimiter" ]] || return 1
                        printf '%s|%s|%s\n' "$delimiter" "$strip_tabs" "$quoted"
                        return 0
                        ;;
                esac
                ;;
        esac
    done

    return 1
}

# Quoted heredoc bodies do not perform shell expansion. Remove only those
# bodies before command segmentation so documentation and source code cannot be
# mistaken for provider execution. Keep the command line and terminator as
# separators, and leave unquoted heredocs untouched because they may execute
# command substitutions.
_octo_strip_quoted_heredoc_bodies() {
    local source="$1" line spec delimiter="" strip_tabs="false" quoted="false" candidate

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$delimiter" ]]; then
            candidate="$line"
            [[ "$strip_tabs" == "true" ]] && candidate="${candidate#"${candidate%%[!$'\t']*}"}"
            if [[ "$candidate" == "$delimiter" ]]; then
                delimiter=""
                strip_tabs="false"
                quoted="false"
            fi
            if [[ "$quoted" == "true" ]]; then
                printf '\n'
            else
                printf '%s\n' "$line"
            fi
            continue
        fi

        printf '%s\n' "$line"
        if spec=$(_octo_heredoc_spec "$line"); then
            delimiter="${spec%%|*}"
            spec="${spec#*|}"
            strip_tabs="${spec%%|*}"
            quoted="${spec##*|}"
        fi
    done <<< "$source"
}

# Emit shell command segments, one per line. Quoted text remains a single
# sanitized word, so a quoted executable is visible without treating provider
# names in prompt/data strings as command positions. Command substitutions are
# scanned recursively because they execute even inside double quotes.
_octo_command_segments() {
    local source segment="" state="plain" escaped="false"
    local i char next end inner

    source=$(_octo_strip_quoted_heredoc_bodies "$1")

    for ((i = 0; i < ${#source}; i++)); do
        char="${source:i:1}"
        next="${source:i+1:1}"

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

        if [[ "$state" != "single" && "$char" == '$' && "$next" == '(' ]]; then
            if end=$(_octo_command_sub_end "$source" "$((i + 2))"); then
                printf '%s\n' "$segment"
                inner="${source:i+2:end-i-2}"
                _octo_command_segments "$inner"
                segment="${segment}_"
                i="$end"
                continue
            fi
        fi

        if [[ "$state" != "single" && "$char" == '`' ]]; then
            if end=$(_octo_backtick_end "$source" "$((i + 1))"); then
                printf '%s\n' "$segment"
                inner="${source:i+1:end-i-1}"
                _octo_command_segments "$inner"
                segment="${segment}_"
                i="$end"
                continue
            fi
        fi

        case "$state" in
            single)
                if [[ "$char" == "'" ]]; then
                    state="plain"
                else
                    case "$char" in
                        ' '|$'\t'|';'|'&'|'|'|'('|')'|'{'|'}'|$'\n') segment="${segment}_" ;;
                        *) segment="${segment}${char}" ;;
                    esac
                fi
                ;;
            double)
                if [[ "$char" == '"' ]]; then
                    state="plain"
                elif [[ "$char" == "\\" ]]; then
                    escaped="true"
                else
                    case "$char" in
                        ' '|$'\t'|';'|'&'|'|'|'('|')'|'{'|'}'|$'\n') segment="${segment}_" ;;
                        *) segment="${segment}${char}" ;;
                    esac
                fi
                ;;
            plain)
                case "$char" in
                    "'") state="single" ;;
                    '"') state="double" ;;
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
    local saw_env="false" saw_command="false" saw_exec="false"

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
            exec)
                saw_exec="true"
                continue
                ;;
            -v|-V)
                # `command -v/-V provider` is harmless introspection.
                [[ "$saw_command" == "true" ]] && return 1
                [[ "$saw_env" == "true" ]] && continue
                return 1
                ;;
            -p|--)
                # Both are valid `command` prefixes; env/exec accept `--`.
                if [[ "$saw_command" == "true" || "$saw_env" == "true" || "$saw_exec" == "true" ]]; then
                    continue
                fi
                return 1
                ;;
            -a)
                # `exec -a name command` supplies an alternate argv[0].
                if [[ "$saw_exec" == "true" && $# -gt 0 ]]; then
                    shift
                    continue
                fi
                return 1
                ;;
            -c|-l)
                [[ "$saw_exec" == "true" ]] && continue
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
