#!/usr/bin/env bash
# build-factory-skills.sh — Generate shared portable skills plus
# Cursor-compatible .cursor-plugin/commands/<name>.md from commands/*.md.
#
# Shared format: skills/<skill-name>/SKILL.md with frontmatter: name, description
# Cursor command format: .cursor-plugin/commands/<name>.md with frontmatter: description
# Our source format: .claude/skills/*.md and commands/*.md
#
# Usage: bash scripts/build-factory-skills.sh [--clean]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$PLUGIN_ROOT/.claude/skills"
SKILLS_OUT="$PLUGIN_ROOT/skills"
COMMANDS_SRC="$PLUGIN_ROOT/commands"
COMMANDS_OUT="$PLUGIN_ROOT/.cursor-plugin/commands"

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

# Octopus-only frontmatter keys to strip (Factory doesn't understand these)
STRIP_KEYS="agent|aliases|category|context|cost_optimization|created|execution_mode|invocation|pattern|pre_execution_contract|providers|tags|task_dependencies|task_management|trigger|updated|use_native_tasks|validation_gates|version"

if [[ "${1:-}" == "--clean" ]]; then
  echo "Cleaning generated skills and cursor command directories..."
  rm -rf "$SKILLS_OUT" "$COMMANDS_OUT"
  echo "Done."
  exit 0
fi

# --- Shared skills generation ---

bash "$SCRIPT_DIR/build-codex-skills.sh"

# --- Commands generation ---
# Factory only supports: description, argument-hint, allowed-tools, disable-model-invocation
# Strip Claude Code-specific keys: command, aliases, redirect, version, category, tags, created, updated

rm -rf "$COMMANDS_OUT"
mkdir -p "$COMMANDS_OUT"

cmd_count=0
cmd_skipped=0

# Frontmatter keys to strip from commands (Claude Code / Octopus-specific)
CMD_STRIP_KEYS="command|aliases|redirect|version|category|tags|created|updated|agent|context|cost_optimization|execution_mode|invocation|pattern|pre_execution_contract|providers|task_dependencies|task_management|trigger|use_native_tasks|validation_gates"

if [[ -d "$COMMANDS_SRC" ]]; then
  for src in "$COMMANDS_SRC"/*.md; do
    [[ -f "$src" ]] || continue
    filename="$(basename "$src")"
    basename_no_ext="$(basename "$src" .md)"

    # Cursor has no plugin namespacing — prefix with "octo-" so all commands
    # appear under /octo-* (mirrors Claude Code's /octo:* namespace).
    # Skip prefixing "octo.md" itself (already named correctly).
    if [[ "$basename_no_ext" == "octo" ]]; then
      out_filename="$filename"
    else
      out_filename="octo-${filename}"
    fi

    # Extract frontmatter (only first block between --- delimiters)
    frontmatter="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2) exit; next} c==1{print}' "$src")"

    # Extract description
    cmd_desc="$(echo "$frontmatter" | grep "^description:" | head -1 | sed 's/^description: *//')"
    cmd_desc="$(normalize_single_line "$cmd_desc")"
    if [[ -z "$cmd_desc" ]]; then
      echo "  SKIP (no description): $filename"
      cmd_skipped=$((cmd_skipped + 1))
      continue
    fi

    # Extract optional Factory-compatible fields (|| true to avoid exit on no-match)
    arg_hint="$(echo "$frontmatter" | grep "^argument-hint:" | head -1 | sed 's/^argument-hint: *//' || true)"
    arg_hint="$(normalize_single_line "$arg_hint")"
    disable_model="$(echo "$frontmatter" | grep "^disable-model-invocation:" | head -1 | sed 's/^disable-model-invocation: *//' || true)"
    allowed_tools="$(echo "$frontmatter" | grep "^allowed-tools:" | head -1 | sed 's/^allowed-tools: *//' || true)"

    # Extract body (everything after the closing --- of frontmatter)
    cmd_body="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2){found=1; next}} found{print}' "$src")"

    # Build Factory-compatible command file
    {
      echo "---"
      printf 'description: %s\n' "$(yaml_quote "$cmd_desc")"
      [[ -n "$arg_hint" ]] && printf 'argument-hint: %s\n' "$(yaml_quote "$arg_hint")"
      [[ -n "$disable_model" ]] && echo "disable-model-invocation: $disable_model"
      [[ -n "$allowed_tools" ]] && echo "allowed-tools: $allowed_tools"
      echo "---"
      echo "$cmd_body"
    } > "$COMMANDS_OUT/$out_filename"

    echo "  GEN: $out_filename"
    cmd_count=$((cmd_count + 1))
  done
fi

echo ""
echo "Factory commands generated: $cmd_count"
[[ $cmd_skipped -gt 0 ]] && echo "Skipped: $cmd_skipped"
echo "Output: $COMMANDS_OUT/"

# --- Agents/Droids generation (v8.41.0) ---
# Factory discovers droids from agents/ directory. The personas are already there
# via agents/config.yaml + agents/personas/*.md. This section generates
# Factory-compatible droid entries from .claude/agents/ definitions so
# both Claude Code and Factory can invoke them as native subagents.

AGENTS_SRC="$PLUGIN_ROOT/.claude/agents"
DROIDS_OUT="$PLUGIN_ROOT/agents/droids"

if [[ -d "$AGENTS_SRC" ]]; then
  rm -rf "$DROIDS_OUT"
  mkdir -p "$DROIDS_OUT"

  droid_count=0

  for src in "$AGENTS_SRC"/*.md; do
    [[ -f "$src" ]] || continue
    filename="$(basename "$src")"
    agent_name="$(basename "$src" .md)"

    # Factory has no plugin namespacing — prefix with "octo-" so all droids
    # appear under octo-* (mirrors commands/ prefix convention).
    out_filename="octo-${filename}"
    out_name="octo-${agent_name}"

    # Extract frontmatter
    frontmatter="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2) exit; next} c==1{print}' "$src")"

    # Extract key fields
    desc="$(echo "$frontmatter" | grep "^description:" | head -1 | sed 's/^description: *//')"
    desc="$(normalize_single_line "$desc")"
    model="$(echo "$frontmatter" | grep "^model:" | head -1 | sed 's/^model: *//')"

    # Extract body
    body="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2){found=1; next}} found{print}' "$src")"

    # Write Factory-compatible droid definition
    {
      echo "---"
      echo "name: $out_name"
      printf 'description: %s\n' "$(yaml_quote "$desc")"
      echo "model: ${model:-inherit}"
      echo "---"
      printf '%s\n' "$body"
    } > "$DROIDS_OUT/$out_filename"

    echo "  GEN droid: $out_name"
    droid_count=$((droid_count + 1))
  done

  echo ""
  echo "Factory droids generated: $droid_count"
  echo "Output: $DROIDS_OUT/"
fi
