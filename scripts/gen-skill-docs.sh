#!/usr/bin/env bash
# Generate SKILL.md files from .tmpl templates
# Usage: scripts/gen-skill-docs.sh [--dry-run]
#
# Templates use {{PLACEHOLDER}} syntax. Shared blocks from skills/blocks/
# are resolved first, then metadata placeholders (COMMAND_COUNT, etc.).
# --dry-run exits non-zero if any generated file differs from committed file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$PLUGIN_ROOT/.claude/skills"
BLOCKS_DIR="$PLUGIN_ROOT/skills/blocks"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Collect metadata from source ─────────────────────────────────────────────

COMMAND_COUNT=$(find "$PLUGIN_ROOT/.claude/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
SKILL_COUNT=$(find "$SKILLS_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
PERSONA_COUNT=$(find "$PLUGIN_ROOT/agents/personas" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

hook_count=0
if [[ -d "$PLUGIN_ROOT/hooks" ]]; then
    hook_count=$(find "$PLUGIN_ROOT/hooks" -maxdepth 1 \( -name '*.sh' -o -name '*.mjs' \) 2>/dev/null | wc -l | tr -d ' ')
fi
HOOK_COUNT="$hook_count"

VERSION=$(grep '"version"' "$PLUGIN_ROOT/package.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')

# ── Generate command list ────────────────────────────────────────────────────

COMMAND_LIST=""
for cmd in "$PLUGIN_ROOT/.claude/commands/"*.md; do
    [[ -f "$cmd" ]] || continue
    name="${cmd##*/}"
    name="${name%.md}"
    COMMAND_LIST="${COMMAND_LIST}- \`/octo:${name}\`
"
done

# ── replace_block: replace a {{PLACEHOLDER}} with file contents using sed ────
# Uses a temp file approach to handle multi-line block content safely.

replace_placeholder_with_file() {
    local input_file="$1"
    local placeholder="$2"
    local block_file="$3"
    local output_file="$4"

    if ! grep -qF "$placeholder" "$input_file" 2>/dev/null; then
        cp "$input_file" "$output_file"
        return
    fi

    # Use awk to do the replacement — read block content from file
    awk -v placeholder="$placeholder" -v blockfile="$block_file" '
    {
        idx = index($0, placeholder)
        if (idx > 0) {
            before = substr($0, 1, idx - 1)
            after = substr($0, idx + length(placeholder))
            printf "%s", before
            while ((getline line < blockfile) > 0) {
                print line
            }
            close(blockfile)
            print after
        } else {
            print
        }
    }' "$input_file" > "$output_file"
}

# ── Process each .tmpl file ──────────────────────────────────────────────────

changed=0
processed=0
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

for tmpl in "$SKILLS_DIR/"*.tmpl; do
    [[ -f "$tmpl" ]] || continue
    target="${tmpl%.tmpl}.md"

    # Start with the template
    cp "$tmpl" "$WORK_DIR/current.md"

    # Replace shared blocks from skills/blocks/
    if [[ -d "$BLOCKS_DIR" ]]; then
        for block in "$BLOCKS_DIR/"*.md; do
            [[ -f "$block" ]] || continue
            block_name="${block##*/}"
            block_name="${block_name%.md}"
            # Convert to uppercase and replace hyphens with underscores
            block_key=$(printf '%s' "$block_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            placeholder="{{${block_key}}}"

            replace_placeholder_with_file "$WORK_DIR/current.md" "$placeholder" "$block" "$WORK_DIR/next.md"
            mv "$WORK_DIR/next.md" "$WORK_DIR/current.md"
        done
    fi

    # Replace metadata placeholders (single-line values) using sed
    sed \
        -e "s|{{COMMAND_COUNT}}|${COMMAND_COUNT}|g" \
        -e "s|{{SKILL_COUNT}}|${SKILL_COUNT}|g" \
        -e "s|{{PERSONA_COUNT}}|${PERSONA_COUNT}|g" \
        -e "s|{{HOOK_COUNT}}|${HOOK_COUNT}|g" \
        -e "s|{{VERSION}}|${VERSION}|g" \
        "$WORK_DIR/current.md" > "$WORK_DIR/replaced.md"
    mv "$WORK_DIR/replaced.md" "$WORK_DIR/current.md"

    # Replace COMMAND_LIST (multi-line) — write list to temp file, use awk
    printf '%s' "$COMMAND_LIST" > "$WORK_DIR/cmdlist.md"
    if grep -qF '{{COMMAND_LIST}}' "$WORK_DIR/current.md" 2>/dev/null; then
        replace_placeholder_with_file "$WORK_DIR/current.md" '{{COMMAND_LIST}}' "$WORK_DIR/cmdlist.md" "$WORK_DIR/next.md"
        mv "$WORK_DIR/next.md" "$WORK_DIR/current.md"
    fi

    processed=$((processed + 1))

    if $DRY_RUN; then
        if [[ -f "$target" ]] && diff "$WORK_DIR/current.md" "$target" > /dev/null 2>&1; then
            echo "  OK: $(basename "$target")"
        else
            echo "  STALE: $(basename "$target")"
            changed=$((changed + 1))
        fi
    else
        cp "$WORK_DIR/current.md" "$target"
        echo "  Generated: $(basename "$target")"
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

if [[ $processed -eq 0 ]]; then
    echo "No .tmpl files found in $SKILLS_DIR"
    exit 0
fi

if $DRY_RUN && [[ $changed -gt 0 ]]; then
    echo "ERROR: $changed generated file(s) are stale. Run scripts/gen-skill-docs.sh to update."
    exit 1
fi

echo "Done. Processed $processed template(s)."