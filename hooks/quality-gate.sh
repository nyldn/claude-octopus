#!/bin/bash
# Claude Octopus Quality Gate Hook (v8.43.0)
# Validates tangle output before continuing workflow
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
# v8.43: Added reference integrity check for cross-file dependencies
set -euo pipefail

VALIDATION_FILE=$(ls -t ~/.claude-octopus/results/tangle-validation-*.md 2>/dev/null | head -1)

if [[ -f "$VALIDATION_FILE" ]]; then
    # Check if quality gate passed
    STATUS=$(grep -E "^## (Quality Gate|Status):" "$VALIDATION_FILE" | head -1)

    if echo "$STATUS" | grep -qi "failed"; then
        echo '{"decision": "block", "reason": "Quality gate validation failed. Review tangle output before proceeding."}'
        exit 0
    fi

    if echo "$STATUS" | grep -qi "warning"; then
        echo '{"decision": "block", "reason": "Quality gate has warnings. Review tangle output before proceeding."}'
        exit 0
    fi
fi

# Reference integrity check: scan recently created/modified files for broken references
# Catches: HTML linking missing JS/CSS, scripts sourcing missing files, configs referencing missing paths
check_reference_integrity() {
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
        done < <(grep -oP '<script[^>]+src=["'\'']\K[^"'\'']+' "$file" 2>/dev/null | grep -v '^https\?://' || true)

        # Check <link href="..."> stylesheet references (skip http/https/CDN URLs)
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing stylesheet: $ref")
            fi
        done < <(grep -oP '<link[^>]+href=["'\'']\K[^"'\'']+' "$file" 2>/dev/null | grep -v '^https\?://' | grep -v '^#' || true)
    done

    # Check shell scripts sourcing missing files
    local recent_scripts
    recent_scripts=$(find . -maxdepth 5 -type f -name "*.sh" -mmin -10 2>/dev/null || true)

    for file in $recent_scripts; do
        local dir
        dir=$(dirname "$file")

        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            # Skip variable references and command substitutions
            [[ "$ref" == *'$'* ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file sources missing file: $ref")
            fi
        done < <(grep -oP '^\s*(\.|source)\s+["'\''"]?\K[^"'\''"\s]+' "$file" 2>/dev/null || true)
    done

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
        done < <(grep -oP '^\s*(dockerfile|env_file|config):\s*\K\S+' "$file" 2>/dev/null || true)
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

check_reference_integrity

# No validation file or quality gate passed
echo '{"decision": "continue"}'
exit 0
