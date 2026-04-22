#!/usr/bin/env bash
# build-codex-skills.sh — Generate .codex/skills/ from .claude/skills/
#
# Transforms Claude Code skill files (.claude/skills/*.md) into Codex CLI
# compatible directory structure (.codex/skills/<name>/SKILL.md) with
# adapted frontmatter and host preamble.
#
# Usage:
#   ./scripts/build-codex-skills.sh [--check] [--verbose]
#
# Options:
#   --check     Dry-run mode — exits non-zero if generated files would change
#   --verbose   Show per-skill processing details
#
# Codex skill format requirements:
#   - Directory per skill: .codex/skills/<name>/SKILL.md
#   - Frontmatter: name (max 64 chars), description (max 1024 chars)
#   - Name charset: a-zA-Z0-9_- (colons added by auto-namespacing)
#   - Invocation: $skill-name (not /skill-name)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/.claude/skills"
OUTPUT_DIR="$PLUGIN_ROOT/.codex/skills"
CHECK_MODE=false
VERBOSE=false

for arg in "$@"; do
    [[ "$arg" == "--check" ]] && CHECK_MODE=true
    [[ "$arg" == "--verbose" ]] && VERBOSE=true
done

# Skills to skip (templates, not directly invocable)
SKIP_PATTERNS="*.tmpl"

# --- Truncate string to max length ---
truncate() {
    local str="$1"
    local max="$2"
    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$((max - 3))}..."
    else
        echo "$str"
    fi
}

# --- Sanitize name for Codex (a-zA-Z0-9_- only) ---
sanitize_name() {
    local name="$1"
    # Remove characters not in allowed set
    echo "$name" | tr -cd 'a-zA-Z0-9_-'
}

# --- Extract frontmatter field value ---
extract_field() {
    local file="$1"
    local field="$2"
    local in_frontmatter=false
    local in_multiline=false

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if $in_frontmatter; then
                break
            else
                in_frontmatter=true
                continue
            fi
        fi
        if $in_frontmatter; then
            # Match "field: value" or "field: \"value\""
            if [[ "$line" =~ ^${field}:\ *(.*) ]]; then
                local val="${BASH_REMATCH[1]}"
                # Strip surrounding quotes
                val="${val#\"}"
                val="${val%\"}"
                val="${val#\'}"
                val="${val%\'}"
                # Check for multiline (pipe or >)
                if [[ "$val" == "|" || "$val" == ">" ]]; then
                    in_multiline=true
                    continue
                fi
                echo "$val"
                return
            fi
            if $in_multiline; then
                if [[ "$line" =~ ^[a-zA-Z] ]]; then
                    # New field started, multiline is over
                    return
                fi
                # Return first non-empty line of multiline
                local trimmed
                trimmed="$(echo "$line" | sed 's/^[[:space:]]*//')"
                if [[ -n "$trimmed" ]]; then
                    echo "$trimmed"
                    return
                fi
            fi
        fi
    done < "$file"
}

# --- Extract body (everything after frontmatter) ---
extract_body() {
    local file="$1"
    local past_frontmatter=false
    local frontmatter_count=0

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            ((frontmatter_count++)) || true
            if [[ $frontmatter_count -ge 2 ]]; then
                past_frontmatter=true
                continue
            fi
            continue
        fi
        if $past_frontmatter; then
            echo "$line"
        fi
    done < "$file"
}

# --- Host adaptation preamble ---
host_preamble() {
    cat <<'PREAMBLE'

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use `$` sigil in Codex (e.g., `$octo-auto` not `/octo:auto`).
> `orchestrate.sh` commands work identically via Bash tool on both hosts.

PREAMBLE
}

# --- Main ---
main() {
    local count=0
    local skipped=0
    local errors=0

    if $CHECK_MODE; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "'"$tmp_dir"'"' EXIT
        local check_output="$tmp_dir/codex-skills"
        mkdir -p "$check_output"
    fi

    local target_dir="$OUTPUT_DIR"
    $CHECK_MODE && target_dir="$check_output"

    # Clean target
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
    fi
    mkdir -p "$target_dir"

    for file in "$SKILLS_DIR"/*.md; do
        [[ -f "$file" ]] || continue

        local basename
        basename=$(basename "$file")

        # Skip templates
        for pattern in $SKIP_PATTERNS; do
            if [[ "$basename" == $pattern ]]; then
                $VERBOSE && echo "  SKIP: $basename (template)"
                ((skipped++)) || true
                continue 2
            fi
        done

        # Extract metadata
        local name
        name=$(extract_field "$file" "name")
        if [[ -z "$name" ]]; then
            name="${basename%.md}"
        fi

        local description
        description=$(extract_field "$file" "description")
        if [[ -z "$description" ]]; then
            description="Claude Octopus skill: $name"
        fi

        # Sanitize and truncate for Codex limits
        local codex_name
        codex_name=$(sanitize_name "$name")
        codex_name=$(truncate "$codex_name" 64)

        local codex_desc
        codex_desc=$(truncate "$description" 1024)

        # Create skill directory
        local skill_dir="$target_dir/$codex_name"
        mkdir -p "$skill_dir"

        # Write SKILL.md
        {
            echo "---"
            echo "name: $codex_name"
            echo "description: \"$codex_desc\""
            echo "---"
            host_preamble
            extract_body "$file"
        } > "$skill_dir/SKILL.md"

        ((count++)) || true
        $VERBOSE && echo "  OK: $basename → .codex/skills/$codex_name/SKILL.md"
    done

    echo "build-codex-skills: $count skills generated, $skipped skipped, $errors errors"

    if $CHECK_MODE; then
        if [[ -d "$OUTPUT_DIR" ]]; then
            if diff -rq "$check_output" "$OUTPUT_DIR" >/dev/null 2>&1; then
                echo "CHECK: .codex/skills/ is up to date"
                return 0
            else
                echo "CHECK: .codex/skills/ is out of date — run scripts/build-codex-skills.sh" >&2
                return 1
            fi
        else
            echo "CHECK: .codex/skills/ does not exist — run scripts/build-codex-skills.sh" >&2
            return 1
        fi
    fi
}

main
