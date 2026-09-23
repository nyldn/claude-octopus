#!/bin/bash
# Claude Octopus Quality Gate Hook (v8.43.0)
# Validates tangle output before continuing workflow
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
# v8.43: Added reference integrity check for cross-file dependencies
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

# Parse one shell word without evaluating it. The result is written to the
# global OCTO_SHELL_WORD so callers do not need a command-substitution process.
_octo_parse_shell_word() {
    local input="$1" char="" word="" state="plain" escaped=0 i
    OCTO_SHELL_WORD=""

    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        case "$state" in
            single)
                if [[ "$char" == "'" ]]; then state="plain"; else word+="$char"; fi
                ;;
            double)
                if ((escaped)); then
                    word+="$char"; escaped=0
                elif [[ "$char" == '\\' ]]; then
                    escaped=1
                elif [[ "$char" == '"' ]]; then
                    state="plain"
                else
                    word+="$char"
                fi
                ;;
            *)
                if ((escaped)); then
                    word+="$char"; escaped=0
                elif [[ "$char" == '\\' ]]; then
                    escaped=1
                elif [[ "$char" == "'" ]]; then
                    state="single"
                elif [[ "$char" == '"' ]]; then
                    state="double"
                elif [[ "$char" =~ [[:space:]] ]] || [[ "$char" == ';' || "$char" == '|' || "$char" == '&' || "$char" == '<' || "$char" == '>' || "$char" == '(' || "$char" == ')' ]]; then
                    break
                else
                    word+="$char"
                fi
                ;;
        esac
    done

    [[ "$state" == "plain" && $escaped -eq 0 ]] || return 1
    OCTO_SHELL_WORD="$word"
}

# Track multiline shell quote state so jq/awk programs embedded in a shell
# string are not mistaken for executable shell source statements.
_octo_advance_shell_quote_state() {
    local input="$1" single="$2" double="$3" char="" escaped=0 comment_ok=1 i

    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        if ((single)); then
            [[ "$char" != "'" ]] || single=0
            continue
        fi
        if ((double)); then
            if ((escaped)); then
                escaped=0
            elif [[ "$char" == '\\' ]]; then
                escaped=1
            elif [[ "$char" == '"' ]]; then
                double=0
            fi
            continue
        fi
        if ((escaped)); then
            escaped=0; comment_ok=0; continue
        fi
        case "$char" in
            \\) escaped=1; comment_ok=0 ;;
            "'") single=1; comment_ok=0 ;;
            '"') double=1; comment_ok=0 ;;
            '#') ((comment_ok)) && break; comment_ok=0 ;;
            ' '|$'\t') comment_ok=1 ;;
            ';'|'|'|'&'|'('|')') comment_ok=1 ;;
            *) comment_ok=0 ;;
        esac
    done

    OCTO_IN_SINGLE_QUOTE="$single"
    OCTO_IN_DOUBLE_QUOTE="$double"
}

# Claude Code before v2.1.85 ignores hook-handler `if` filters. Keep the same
# guard in-process so stale clients do not scan the workspace after every Bash
# command. Current clients avoid spawning this hook altogether.
HOOK_INPUT=""
if [[ ! -t 0 ]]; then
    if command -v timeout >/dev/null 2>&1; then
        HOOK_INPUT=$(timeout 3 cat 2>/dev/null || true)
    else
        HOOK_INPUT=$(cat 2>/dev/null || true)
    fi
fi
case "$HOOK_INPUT" in
    *orchestrate.sh*) ;;
    *) exit 0 ;;
esac

VALIDATION_FILE=$(ls -t ~/.claude-octopus/results/tangle-validation-*.md 2>/dev/null | head -1 || true)

if [[ -f "$VALIDATION_FILE" ]]; then
    # Check if quality gate passed. `|| true` — grep-no-match must not cascade
    # under `set -o pipefail` and trigger the silent-fail path (issue #313).
    STATUS=$(grep -E "^## (Quality Gate|Status):" "$VALIDATION_FILE" 2>/dev/null | head -1 || true)

    if echo "$STATUS" | grep -qi "failed"; then
        echo '{"decision": "block", "reason": "Quality gate validation failed. Review tangle output before proceeding."}'
        exit 0
    fi

    if echo "$STATUS" | grep -qi "warning"; then
        echo '{"decision": "block", "reason": "Quality gate has warnings. Review tangle output before proceeding."}'
        exit 0
    fi
fi

# Reference integrity check: scan recently created/modified files for broken references.
# Only defined here — called below when VALIDATION_FILE exists (i.e. tangle was recently run).
# Catches: HTML linking missing JS/CSS, scripts sourcing missing files, configs referencing missing paths
check_reference_integrity() {
    # Scope-local: disable -u because bash 3.2 (macOS CI) aborts (exit 134)
    # on `local arr=()` + `${#arr[@]}` when the array stays empty. We re-enable
    # -u on exit. See issue #313 PR #314 CI failure trail.
    set +u
    trap 'set -u' RETURN
    local issues=()

    # Find files modified in the last 10 minutes (likely tangle output)
    local recent_files
    recent_files=$(find . -maxdepth 5 -type f \( -name "*.html" -o -name "*.htm" \) -mmin -10 2>/dev/null || true)

    for file in $recent_files; do
        local dir
        dir=$(dirname "$file")

        # Check <script src="..."> references (skip http/https/CDN URLs)
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing script: $ref")
            fi
        done < <(grep -oE '<script[^>]+src=["'"'"'][^"'"'"']+' "$file" 2>/dev/null | sed 's/.*src=["'"'"']//' | grep -vE '^(https?://|/)' || true)

        # Check <link href="..."> stylesheet references (skip http/https/CDN URLs)
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing stylesheet: $ref")
            fi
        done < <(grep -oE '<link[^>]+href=["'"'"'][^"'"'"']+' "$file" 2>/dev/null | sed 's/.*href=["'"'"']//' | grep -vE '^(https?://|/)' | grep -v '^#' || true)
    done

    # Check shell scripts sourcing missing files
    while IFS= read -r -d '' file; do
        local dir
        dir=$(dirname "$file")
        local in_single_quote=0 in_double_quote=0

        while IFS= read -r stmt; do
            local starts_in_quote=0 ref="" remainder=""
            ((in_single_quote || in_double_quote)) && starts_in_quote=1

            if (( ! starts_in_quote )) && [[ "$stmt" =~ ^[[:space:]]*(\.|source)[[:space:]]+(.+)$ ]]; then
                remainder="${BASH_REMATCH[2]}"
                if _octo_parse_shell_word "$remainder"; then
                    ref="$OCTO_SHELL_WORD"
                    # Skip variable references and command substitutions.
                    if [[ -n "$ref" && "$ref" != *'$'* && "$ref" != *'`'* && ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                        issues+=("$file sources missing file: $ref")
                    fi
                fi
            fi

            _octo_advance_shell_quote_state "$stmt" "$in_single_quote" "$in_double_quote"
            in_single_quote="$OCTO_IN_SINGLE_QUOTE"
            in_double_quote="$OCTO_IN_DOUBLE_QUOTE"
        done < "$file"
    done < <(find . -maxdepth 5 -type f -name "*.sh" -mmin -10 -print0 2>/dev/null || true)

    # Check docker-compose referencing missing Dockerfiles/configs
    local recent_compose
    recent_compose=$(find . -maxdepth 3 -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -mmin -10 2>/dev/null || true)

    for file in $recent_compose; do
        local dir
        dir=$(dirname "$file")

        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing file: $ref")
            fi
        done < <(grep -oE '^\s*(dockerfile|env_file|config):\s*\S+' "$file" 2>/dev/null | sed -E 's/^[[:space:]]*(dockerfile|env_file|config):[[:space:]]*//' || true)
    done

    if [[ ${#issues[@]} -gt 0 ]]; then
        local msg="Reference integrity check failed: ${issues[0]}"
        if [[ ${#issues[@]} -gt 1 ]]; then
            msg="$msg (and $((${#issues[@]}-1)) more)"
        fi
        echo "{\"decision\": \"block\", \"reason\": \"$msg\"}"
        # Human-readable stderr for Claude Code v2.1.41+
        printf '\n⚠️  Broken references detected:\n' >&2
        for issue in "${issues[@]}"; do
            printf '  • %s\n' "$issue" >&2
        done
        printf 'Fix: create the missing files or inline the code.\n' >&2
        exit 0
    fi
}

# Only scan for broken references when a tangle run actually happened recently.
# Skipping when VALIDATION_FILE is absent avoids scanning the plugin source tree
# in CI (where all .sh files are "recently modified" by the checkout), which
# triggered Abort trap: 6 on bash 3.2 macOS. See issue #313.
[[ -f "$VALIDATION_FILE" ]] && check_reference_integrity

# No validation file or quality gate passed
: # pass-through — current hook schema treats silence as continue
exit 0
