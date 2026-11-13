#!/usr/bin/env bash
# build-codex-skills.sh — Generate native skills/ and codex-skills/ from .claude/skills/
#
# Transforms Claude Code skill files (.claude/skills/*.md or
# .claude/skills/*/SKILL.md) into Codex CLI
# compatible directory structure (codex-skills/<name>/SKILL.md) with adapted
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
#   - Directory per skill: codex-skills/<name>/SKILL.md
#   - Frontmatter: name (max 64 chars), description (max 1024 chars)
#   - Name charset: a-zA-Z0-9_- (colons added by auto-namespacing)
#   - Invocation: $skill-name (not /skill-name)

set -euo pipefail

# Keep generated metadata byte-stable across CI and contributor locales.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/.claude/skills"
OUTPUT_DIR="$PLUGIN_ROOT/codex-skills"
NATIVE_OUTPUT_DIR="$PLUGIN_ROOT/skills"
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

ui_short_description() {
    local description="$1"
    local skill_display_name="$2"

    description="$(normalize_single_line "$description")"
    if [[ ${#description} -lt 25 ]]; then
        description="Help with ${skill_display_name} tasks and workflows"
    fi
    if [[ ${#description} -le 64 ]]; then
        printf '%s\n' "$description"
        return 0
    fi

    local limit=61
    local prefix="${description:0:$limit}"
    local next_character="${description:$limit:1}"
    prefix="$(printf '%s' "$prefix" | sed -E 's/[[:space:]]+$//')"

    # If the boundary lands inside a word, remove that partial word. A string
    # with no usable boundary gets a stable complete fallback phrase.
    if [[ -n "$next_character" && "$next_character" != [[:space:]] ]]; then
        if [[ "$prefix" == *" "* ]]; then
            prefix="${prefix% *}"
        else
            prefix="Help with this skill and related workflows"
        fi
    fi
    if [[ ${#prefix} -lt 22 ]]; then
        prefix="Help with this skill and related workflows"
    fi
    printf '%s...\n' "$prefix"
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
        BEGIN {
            frontmatter_count = 0
            in_body = 0
            in_fence = 0
            in_contract = 0
            contract_level = 0
            found = 0
        }
        /^---$/ {
            frontmatter_count++
            if (frontmatter_count >= 2) {
                in_body = 1
            }
            next
        }

        !in_body { next }

        /^[[:space:]]*(```|~~~)/ {
            in_fence = !in_fence
            next
        }
        in_fence { next }

        /^#+[[:space:]]/ &&
            (/Execution Contract/ || /EXECUTION CONTRACT/ || /MANDATORY COMPLIANCE/) {
            match($0, /^#+/)
            in_contract = 1
            contract_level = RLENGTH
            if ($0 ~ /MANDATORY COMPLIANCE|EXECUTION CONTRACT.*MANDATORY|CANNOT SKIP/) {
                found = 1
                exit
            }
            next
        }
        in_contract && /^#+[[:space:]]/ {
            match($0, /^#+/)
            if (RLENGTH <= contract_level) {
                in_contract = 0
            }
        }
        in_contract &&
            /(^|[^[:alnum:]_])(MUST|MANDATORY|PROHIBITED|CANNOT|CANNOT SKIP|DO NOT)([^[:alnum:]_]|$)/ {
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

generated_enforcement_block() {
    local host="${1:-Codex}"
    cat <<EOF

## Execution Contract (MANDATORY - CANNOT SKIP)

This generated ${host} skill preserves an enforced workflow contract from the source skill.

**PROHIBITED:**
- Do not summarize, simulate, or skip the referenced workflow command when this skill requires execution.
- Do not claim provider output or validation artifacts exist without checking the actual files or command output.
- Do not continue silently when a required provider, command, or host capability is unavailable; report the unavailable dependency and use a supported fallback.

EOF
}

adapt_shared_paths_for_codex() {
    # Keep .claude/skills source paths intact while routing loaded entries and
    # phase resources to this host's generated tree. Bare inline directory
    # names describe source roots rather than a file to load.
    sed -E \
        -e 's@(^|[^[:alnum:]_.:/-])skills/([^`]|$)@\1codex-skills/\2@g' \
        -e 's@(\$\{?OCTO_ROOT\}?)/skills/([^`]|$)@\1/codex-skills/\2@g'
}

# Translate only commands with an installed skill equivalent. Keep unknown
# commands, URLs, file paths, and executable examples literal. A chat skill
# invocation is not a shell command or a replacement for a program string.
adapt_skill_references_for_codex() {
    awk '
        BEGIN {
            skill["parallel"] = "flow-parallel"
            skill["discover"] = "flow-discover"
            skill["define"] = "flow-define"
            skill["develop"] = "flow-develop"
            skill["deliver"] = "flow-deliver"
            skill["spec"] = "flow-spec"
            skill["quick"] = "octopus-quick"
            skill["research"] = "octopus-research"
            skill["security"] = "octopus-security-audit"
            skill["design-ui-ux"] = "octopus-ui-ux-design"
            skill["setup"] = "sys-configure"
            skill["review"] = "skill-code-review"
            skill["debate"] = "skill-debate"
            skill["docs"] = "skill-doc-delivery"
            skill["deck"] = "skill-deck"
            skill["prd"] = "skill-prd"
            skill["brainstorm"] = "skill-thought-partner"
            skill["km"] = "skill-knowledge-work"
            skill["debug"] = "skill-debug"
            skill["tdd"] = "skill-tdd"
            skill["factory"] = "skill-factory"
            skill["refine"] = "skill-refine"
            skill["resume"] = "skill-resume"
            skill["staged-review"] = "skill-staged-review"
            skill["status"] = "skill-status"
            skill["issues"] = "skill-issues"
            skill["ship"] = "skill-ship"
            skill["rollback"] = "skill-rollback"
            skill["extract"] = "skill-extract"
            skill["council"] = "skill-council"
            skill["multi"] = "skill-parallel-agents"
            skill["skill-doctor"] = "skill-doctor"
        }
        {
            marker = $0
            sub(/^[ \t]*/, "", marker)
            if (marker ~ /^```/ || marker ~ /^~~~/) {
                char = substr(marker, 1, 1)
                run = 0
                while (substr(marker, run + 1, 1) == char) run++
                language = substr(marker, run + 1)
                sub(/[ \t]*$/, "", language)
                if (!fenced) {
                    fenced = 1
                    fence_char = char
                    fence_length = run
                    prose_fence = language == "" || language == "text" || language == "markdown"
                } else if (char == fence_char && run >= fence_length && language == "") {
                    fenced = 0
                }
                print
                next
            }
            if (fenced && !prose_fence) {
                print
                next
            }
            rest = $0
            out = ""
            while (match(rest, /\/octo:[a-z][a-z0-9-]*/)) {
                prefix = substr(rest, 1, RSTART - 1)
                command = substr(rest, RSTART, RLENGTH)
                tail = substr(rest, RSTART + RLENGTH)
                name = substr(command, 7)
                before = substr(prefix, length(prefix), 1)
                after = substr(tail, 1, 1)
                if (name in skill && before !~ /[[:alnum:]_.\/:~-]/ && after !~ /[[:alnum:]_.\/:~-]/) {
                    command = "$" skill[name]
                }
                out = out prefix command
                rest = tail
            }
            print out rest
        }
    '
}

# Adapt narrator/tool references while preserving explicitly labelled native
# call examples, whose argument names must remain valid for their own host.
adapt_host_context_for_codex() {
    adapt_shared_paths_for_codex | adapt_skill_references_for_codex | sed -E \
        -e 's/Bash tool/native shell command tool/g' \
        -e 's/Agent tool/host subagent tool/g' \
        -e 's/Task tool/host subagent tool/g' \
        -e 's/TodoWrite/task plan tool/g' \
        -e 's/You \(Claude\)/You (the host model)/g' \
        -e 's/Claude Synthesizes/Host Synthesizes/g' \
        -e 's/if \[\[ -n "\$\{PLAN_MODE_ACTIVE\}" \]\] \|\| claude-code plan status 2>\/dev\/null \| grep -q "active"; then/if [[ -n "${PLAN_MODE_ACTIVE:-}" ]]; then/g'
}

adapt_body_for_codex() {
    local file="$1"
    if source_has_enforced_execution "$file" && ! body_has_enforcement "$file"; then
        generated_enforcement_block
    fi

    extract_body "$file" | adapt_host_context_for_codex | sed -E \
        -e 's/codex exec --skip-git-repo-check --full-auto/codex exec --skip-git-repo-check/g' \
        -e 's/codex exec --full-auto/codex exec --skip-git-repo-check/g' \
        -e 's/, or deprecated `--full-auto`//g' \
        -e 's/ or deprecated `--full-auto`//g' \
        -e 's/`--full-auto`/`--skip-git-repo-check`/g' \
        -e 's/Do NOT pipe stdin to codex — pass prompt as positional argument after flags/Prefer stdin-based prompt delivery for long prompts; use scripts\/lib\/dispatch.sh when possible/g' \
        -e 's/Core four always participate:/Core participants must be selected from actual available providers:/g' \
        -e 's/🟠 Sonnet 5: Available ✓ \(via host subagent tool — no extra cost\)/🟠 Sonnet 5: available only when this Codex session exposes a compatible host subagent tool/g' \
        -e 's/🟠 Sonnet 5 - Pragmatic implementer perspective/🟠 Sonnet 5 - Pragmatic implementer perspective if host subagents are available/g' \
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
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

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
| `AskUserQuestion` | use the active host question tool, or ask in the conversation and wait for the answer |
| Claude-native call examples such as `Agent(run_in_background: true)` | translate the call to the available host tool and its documented arguments; never invent a Codex argument with the same spelling |
| `/octo:*` command examples | use the installed skill name or run `scripts/orchestrate.sh` directly |

Provider and model availability must be checked at runtime. If `OCTO_ALLOWED_PROVIDERS` is set, treat providers outside that list as unavailable even when installed. If a skill names a provider that is missing or disallowed in the current Codex session, mark it unavailable and continue only with available providers.
EOF
}

write_skill() {
    local file="$1"
    local skill_dir="$2"
    local codex_name="$3"
    local codex_desc="$4"
    local codex_display_name="${5:-}"
    local codex_short_desc="${6:-}"
    local disable_model
    disable_model="$(extract_field "$file" "disable-model-invocation")"

    if [[ -z "$codex_display_name" ]]; then
        codex_display_name="$(display_name "$codex_name")"
    fi
    if [[ -z "$codex_short_desc" ]]; then
        codex_short_desc="$(ui_short_description "$codex_desc" "$codex_display_name")"
    fi

    mkdir -p "$skill_dir"

    {
        echo "---"
        echo "name: $codex_name"
        echo "description: \"$codex_desc\""
        [[ -n "$disable_model" ]] && echo "disable-model-invocation: $disable_model"
        echo "---"
        host_preamble
        adapt_body_for_codex "$file"
    } > "$skill_dir/SKILL.md"

    mkdir -p "$skill_dir/agents"
    {
        echo "interface:"
        printf '  display_name: %s\n' "$(yaml_quote "$codex_display_name")"
        printf '  short_description: %s\n' "$(yaml_quote "$codex_short_desc")"
        if [[ "$disable_model" == true ]]; then
            printf 'policy:\n  allow_implicit_invocation: false\n'
        fi
    } > "$skill_dir/agents/openai.yaml"
}

# Directories under skills/ that are hand-maintained rather than generated.
# Everything else is wiped and rebuilt from .claude/skills/, so anything listed
# here MUST be excluded or a plain regeneration silently deletes it.
#
#   blocks               shared prose fragments, no per-skill source
#   octopus-starter-pack a bundle of four sub-skills with no .claude/skills
#                        counterpart, registered in plugin.json
#   skill-council        has never had a source (no delete recorded in git
#                        history); generating without this exclusion removes it
#   skill-refine and flow-discover are canonical root skills with phase resources
PRESERVED_SKILL_DIRS=(blocks octopus-starter-pack skill-council skill-refine flow-discover)

_preserve_find_args() {
    local d
    for d in "${PRESERVED_SKILL_DIRS[@]}"; do
        printf '%s\n' "!" "-name" "$d"
    done
}

prepare_target_dir() {
    local target_dir="$1" d host="${2:-codex}"
    if [[ "$target_dir" == "$NATIVE_OUTPUT_DIR" ]]; then
        mkdir -p "$target_dir"
        local -a keep=()
        while IFS= read -r d; do keep+=("$d"); done < <(_preserve_find_args)
        find "$target_dir" -mindepth 1 -maxdepth 1 -type d "${keep[@]}" -exec rm -rf {} +
        find "$target_dir" -mindepth 1 -maxdepth 1 -type f -delete
    else
        rm -rf "$target_dir"
        mkdir -p "$target_dir"
        for d in "${PRESERVED_SKILL_DIRS[@]}"; do
            if [[ -d "$NATIVE_OUTPUT_DIR/$d" ]]; then
                mkdir -p "$target_dir/$d"
                cp -R "$NATIVE_OUTPUT_DIR/$d/." "$target_dir/$d/"
            fi
        done
        # Copied shared blocks and resource files also belong to this host tree.
        if [[ "$host" == codex ]]; then
            local file
            while IFS= read -r file; do
                adapt_host_context_for_codex < "$file" > "$file.tmp"
                mv "$file.tmp" "$file"
            done < <(find "$target_dir" -type f -name '*.md')
        fi
    fi
}

write_native_skill() {
    local file="$1" target="$2" name="$3"
    mkdir -p "$target"
    # Preserve native frontmatter and tools. Only a compatibility alias changes name.
    awk -v name="$name" '!renamed && /^name:/ { print "name: " name; renamed=1; next } { print }' \
        "$file" > "$target/SKILL.md"
    # Canonical preserved entries carry their contract in their own resources.
    # Do not append generated text to a tree that is itself an authored input.
    if [[ "$name" != flow-discover && "$name" != skill-refine ]] &&
       source_has_enforced_execution "$file" && ! body_has_enforcement "$file"; then
        generated_enforcement_block "Claude Code" | sed '${/^$/d;}' >> "$target/SKILL.md"
    fi
}

# --- Main ---
main() {
    local count=0
    local skipped=0
    local errors=0

    # Validate canonical inputs before cleaning either generated output tree.
    local canonical
    for canonical in skill-refine flow-discover; do
        if [[ -e "$NATIVE_OUTPUT_DIR/$canonical" || -e "$SKILLS_DIR/$canonical" ]]; then
            [[ -f "$NATIVE_OUTPUT_DIR/$canonical/SKILL.md" ]] || {
                printf 'Missing canonical skill entry: %s\n' "$NATIVE_OUTPUT_DIR/$canonical/SKILL.md" >&2
                return 1
            }
        fi
    done

    if $CHECK_MODE; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "'"$tmp_dir"'"' EXIT
        local check_output="$tmp_dir/codex-skills"
        mkdir -p "$check_output"
    fi

    local target_dir="$OUTPUT_DIR" native_target="$NATIVE_OUTPUT_DIR"
    if $CHECK_MODE; then
        target_dir="$check_output"
        native_target="$tmp_dir/native-skills"
    fi

    prepare_target_dir "$target_dir"
    prepare_target_dir "$native_target" native
    write_codex_adapter_block "$target_dir"

    # Canonical root entries own their native bytes and phase resources.
    # Refresh the source entry before generating the separate Codex adaptation.
    for canonical in skill-refine flow-discover; do
        # A partial source fixture may contain neither canonical skill. If either
        # side exists, require the canonical root copy rather than losing it.
        if [[ ! -e "$NATIVE_OUTPUT_DIR/$canonical" && ! -e "$SKILLS_DIR/$canonical" ]]; then
            continue
        fi
        if $CHECK_MODE; then
            cmp -s "$NATIVE_OUTPUT_DIR/$canonical/SKILL.md" "$SKILLS_DIR/$canonical/SKILL.md" || {
                echo "CHECK: .claude/skills/$canonical is stale; run skill sync" >&2
                return 1
            }
        else
            mkdir -p "$SKILLS_DIR/$canonical"
            cp "$NATIVE_OUTPUT_DIR/$canonical/SKILL.md" "$SKILLS_DIR/$canonical/SKILL.md"
        fi
    done

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

        local codex_display_name
        codex_display_name=$(extract_field "$file" "codex_display_name")
        [[ -n "$codex_display_name" ]] || codex_display_name="$(display_name "$codex_name")"

        local codex_short_desc
        codex_short_desc="$(ui_short_description "$description" "$codex_display_name")"

        write_native_skill "$file" "$native_target/$codex_name" "$codex_name"
        write_skill "$file" "$target_dir/$codex_name" "$codex_name" "$codex_desc" "$codex_display_name" "$codex_short_desc"

        ((count++)) || true
        $VERBOSE && echo "  OK: $basename → skills/$codex_name/SKILL.md"

        local alias_name
        alias_name="$(compat_alias_for "$codex_name")"
        if [[ -n "$alias_name" ]]; then
            local alias_desc
            alias_desc=$(extract_field "$file" "codex_alias_description")
            [[ -n "$alias_desc" ]] || alias_desc="$codex_desc"
            alias_desc=$(truncate "$alias_desc" 1024)

            local alias_display_name
            alias_display_name=$(extract_field "$file" "codex_alias_display_name")
            [[ -n "$alias_display_name" ]] || alias_display_name="$(display_name "$alias_name")"

            local alias_short_desc
            alias_short_desc="$(ui_short_description "$alias_desc" "$alias_display_name")"

            write_native_skill "$file" "$native_target/$alias_name" "$alias_name"
            write_skill "$file" "$target_dir/$alias_name" "$alias_name" "$alias_desc" "$alias_display_name" "$alias_short_desc"
            ((count++)) || true
            $VERBOSE && echo "  OK: $basename → skills/$alias_name/SKILL.md (compat alias)"
        fi
    done < <(list_skill_sources "$SKILLS_DIR" | LC_ALL=C sort)

    echo "build-codex-skills: $count skills generated, $skipped skipped, $errors errors"

    if $CHECK_MODE; then
        local missing_tree=false
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            printf 'CHECK: Codex skill tree does not exist: %s\n' "$OUTPUT_DIR" >&2
            missing_tree=true
        fi
        if [[ ! -d "$NATIVE_OUTPUT_DIR" ]]; then
            printf 'CHECK: native skill tree does not exist: %s\n' "$NATIVE_OUTPUT_DIR" >&2
            missing_tree=true
        fi
        $missing_tree && return 1
        if diff -rq "$check_output" "$OUTPUT_DIR" >/dev/null 2>&1 &&
           diff -rq "$native_target" "$NATIVE_OUTPUT_DIR" >/dev/null 2>&1; then
            echo "CHECK: native and Codex skills/ is up to date"
            return 0
        else
            echo "CHECK: native and Codex skills/ is out of date — run scripts/build-codex-skills.sh" >&2
            return 1
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
