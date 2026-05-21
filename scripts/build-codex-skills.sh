#!/usr/bin/env bash
# build-codex-skills.sh — Generate portable root skills/ from .claude/skills/
#
# Transforms Claude Code skill files (.claude/skills/*.md or
# .claude/skills/*/SKILL.md) into Codex CLI
# compatible directory structure (skills/<name>/SKILL.md) with adapted
# frontmatter, host preamble, and Codex interface metadata.
#
# Usage:
#   ./scripts/build-codex-skills.sh [--check] [--verbose]
#
# Options:
#   --check     Dry-run mode — exits non-zero if generated files would change
#   --verbose   Show per-skill processing details
#
# Codex skill format requirements:
#   - Directory per skill: skills/<name>/SKILL.md
#   - Frontmatter: name (max 64 chars), description (max 1024 chars)
#   - Name charset: a-zA-Z0-9_- (colons added by auto-namespacing)
#   - Invocation: $skill-name (not /skill-name)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/.claude/skills"
OUTPUT_DIR="$PLUGIN_ROOT/skills"
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

normalize_single_line() {
    printf '%s' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

yaml_quote() {
    local value
    value="$(normalize_single_line "$1")"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"' "$value"
}

display_name() {
    local name="$1"
    name="${name#skill-}"
    name="${name#flow-}"
    name="${name#sys-}"
    name="${name#octopus-}"
    printf '%s\n' "$name" | tr '_-' '  ' | awk '{
        for (i = 1; i <= NF; i++) {
            $i = toupper(substr($i, 1, 1)) substr($i, 2)
        }
        print
    }'
}

compat_alias_for() {
    local name="$1"
    case "$name" in
        skill-verification-gate)
            echo "skill-verify"
            ;;
    esac
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

list_skill_sources() {
    local dir="$1"

    find "$dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null
    find "$dir" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print 2>/dev/null
}

source_skill_basename() {
    local file="$1"

    if [[ "$(basename "$file")" == "SKILL.md" ]]; then
        basename "$(dirname "$file")"
    else
        basename "$file"
    fi
}

source_has_enforced_execution() {
    local file="$1"
    awk '
        BEGIN { in_frontmatter = 0 }
        /^---$/ {
            if (in_frontmatter) {
                exit
            }
            in_frontmatter = 1
            next
        }
        in_frontmatter && /^execution_mode:[[:space:]]*enforced[[:space:]]*$/ { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$file"
}

body_has_enforcement() {
    local file="$1"
    awk '
        BEGIN { frontmatter_count = 0; in_body = 0; found = 0 }
        /^---$/ {
            frontmatter_count++
            if (frontmatter_count >= 2) {
                in_body = 1
            }
            next
        }
        in_body && /MANDATORY COMPLIANCE|EXECUTION CONTRACT.*MANDATORY|CANNOT SKIP/ {
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

generated_enforcement_block() {
    cat <<'EOF'

## Execution Contract (MANDATORY - CANNOT SKIP)

This generated Codex skill preserves an enforced workflow contract from the source skill.

**PROHIBITED:**
- Do not summarize, simulate, or skip the referenced workflow command when this skill requires execution.
- Do not claim provider output or validation artifacts exist without checking the actual files or command output.
- Do not continue silently when a required provider, command, or host capability is unavailable; report the unavailable dependency and use a supported fallback.

EOF
}

adapt_body_for_codex() {
    local file="$1"
    if source_has_enforced_execution "$file" && ! body_has_enforcement "$file"; then
        generated_enforcement_block
    fi

    extract_body "$file" | sed -E \
        -e 's/Bash tool/native shell command tool/g' \
        -e 's/Agent tool/host subagent tool/g' \
        -e 's/Task tool/host subagent tool/g' \
        -e 's/TodoWrite/task plan tool/g' \
        -e 's/run_in_background/background execution/g' \
        -e 's/codex exec --skip-git-repo-check --full-auto/codex exec --skip-git-repo-check/g' \
        -e 's/codex exec --full-auto/codex exec --skip-git-repo-check/g' \
        -e 's/, or deprecated `--full-auto`//g' \
        -e 's/ or deprecated `--full-auto`//g' \
        -e 's/`--full-auto`/`--skip-git-repo-check`/g' \
        -e 's/Do NOT pipe stdin to codex — pass prompt as positional argument after flags/Prefer stdin-based prompt delivery for long prompts; use scripts\/lib\/dispatch.sh when possible/g' \
        -e 's/Core four always participate:/Core participants must be selected from actual available providers:/g' \
        -e 's/🟠 Sonnet 4\.6: Available ✓ \(via host subagent tool — no extra cost\)/🟠 Sonnet 4.6: available only when this Codex session exposes a compatible host subagent tool/g' \
        -e 's/🟠 Sonnet 4\.6 - Pragmatic implementer perspective/🟠 Sonnet 4.6 - Pragmatic implementer perspective if host subagents are available/g' \
        -e 's/Claude \(Opus\)/current host model/g' \
        -e 's/Claude\/Opus/current host model/g' \
        -e 's/You are Claude \(Opus\)/You are the current host model/g' \
        -e 's/launch Sonnet as an independent analyst via host subagent tool/use a Sonnet-style implementer perspective only when a compatible host subagent tool is available/g' \
        -e 's/Launch Sonnet/Launch optional host subagent/g'
}

# --- Host adaptation preamble ---
host_preamble() {
    cat <<'PREAMBLE'

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.

PREAMBLE
}

write_codex_adapter_block() {
    local target_dir="$1"
    mkdir -p "$target_dir/blocks"
    cat > "$target_dir/blocks/codex-host-adapter.md" <<'EOF'
# Codex Host Adapter

Claude Octopus skills are authored from the Claude Code source surface and then adapted for Codex.

When a generated skill references a host tool, use the active Codex equivalent:

| Skill wording | Codex equivalent |
| --- | --- |
| native shell command tool | use the available Codex shell execution tool |
| host subagent tool | use `spawn_agent`, `wait_agent`, and `close_agent` only when those tools are available and the user has authorized delegation |
| task plan tool | use Codex task planning/status tools when present |
| `/octo:*` command examples | use the installed skill name or run `scripts/orchestrate.sh` directly |

Provider and model availability must be checked at runtime. If `OCTO_ALLOWED_PROVIDERS` is set, treat providers outside that list as unavailable even when installed. If a skill names a provider that is missing or disallowed in the current Codex session, mark it unavailable and continue only with available providers.
EOF
}

write_skill() {
    local file="$1"
    local skill_dir="$2"
    local codex_name="$3"
    local codex_desc="$4"

    mkdir -p "$skill_dir"

    {
        echo "---"
        echo "name: $codex_name"
        echo "description: \"$codex_desc\""
        echo "---"
        host_preamble
        adapt_body_for_codex "$file"
    } > "$skill_dir/SKILL.md"

    mkdir -p "$skill_dir/agents"
    {
        echo "interface:"
        printf '  display_name: %s\n' "$(yaml_quote "$(display_name "$codex_name")")"
        printf '  short_description: %s\n' "$(yaml_quote "$codex_desc")"
    } > "$skill_dir/agents/openai.yaml"
}

prepare_target_dir() {
    local target_dir="$1"

    if [[ "$target_dir" == "$OUTPUT_DIR" ]]; then
        mkdir -p "$target_dir"
        find "$target_dir" -mindepth 1 -maxdepth 1 -type d ! -name blocks -exec rm -rf {} +
        find "$target_dir" -mindepth 1 -maxdepth 1 -type f -delete
    else
        rm -rf "$target_dir"
        mkdir -p "$target_dir"
        if [[ -d "$OUTPUT_DIR/blocks" ]]; then
            mkdir -p "$target_dir/blocks"
            cp -R "$OUTPUT_DIR/blocks/." "$target_dir/blocks/"
        fi
    fi

    write_codex_adapter_block "$target_dir"
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

    prepare_target_dir "$target_dir"

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        local basename
        basename=$(source_skill_basename "$file")

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

        write_skill "$file" "$target_dir/$codex_name" "$codex_name" "$codex_desc"

        ((count++)) || true
        $VERBOSE && echo "  OK: $basename → skills/$codex_name/SKILL.md"

        local alias_name
        alias_name="$(compat_alias_for "$codex_name")"
        if [[ -n "$alias_name" ]]; then
            write_skill "$file" "$target_dir/$alias_name" "$alias_name" "$codex_desc"
            ((count++)) || true
            $VERBOSE && echo "  OK: $basename → skills/$alias_name/SKILL.md (compat alias)"
        fi
    done < <(list_skill_sources "$SKILLS_DIR" | LC_ALL=C sort)

    echo "build-codex-skills: $count skills generated, $skipped skipped, $errors errors"

    if $CHECK_MODE; then
        if [[ -d "$OUTPUT_DIR" ]]; then
            if diff -rq "$check_output" "$OUTPUT_DIR" >/dev/null 2>&1; then
                echo "CHECK: skills/ is up to date"
                return 0
            else
                echo "CHECK: skills/ is out of date — run scripts/build-codex-skills.sh" >&2
                return 1
            fi
        else
            echo "CHECK: skills/ does not exist — run scripts/build-codex-skills.sh" >&2
            return 1
        fi
    fi
}

main
