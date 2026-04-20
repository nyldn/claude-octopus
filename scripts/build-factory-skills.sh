#!/usr/bin/env bash
# build-factory-skills.sh — Generate Factory AI-compatible skills/<name>/SKILL.md
# and commands/<name>.md from .claude/skills/*.md and .claude/commands/*.md.
#
# Factory format: skills/<skill-name>/SKILL.md with frontmatter: name, version, description
# Factory format: commands/<name>.md with frontmatter: description
# Our format: .claude/skills/<skill-name>.md with extended frontmatter
#
# Usage: bash scripts/build-factory-skills.sh [--clean]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$PLUGIN_ROOT/.claude/skills"
SKILLS_OUT="$PLUGIN_ROOT/skills"
COMMANDS_SRC="$PLUGIN_ROOT/.claude/commands"
COMMANDS_OUT="$PLUGIN_ROOT/commands"

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
  echo "Cleaning generated skills and commands directories..."
  rm -rf "$SKILLS_OUT" "$COMMANDS_OUT"
  echo "Done."
  exit 0
fi

# --- Skills generation ---

rm -rf "$SKILLS_OUT"
mkdir -p "$SKILLS_OUT"

generated=0
skipped=0

for src in "$SKILLS_SRC"/*.md; do
  filename="$(basename "$src" .md)"

  # Extract frontmatter (between first and second ---)
  frontmatter="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d')"

  # Skip human_only skills
  if echo "$frontmatter" | grep -q "^invocation: human_only"; then
    echo "  SKIP (human_only): $filename"
    skipped=$((skipped + 1))
    continue
  fi

  # Extract name from frontmatter
  skill_name="$(echo "$frontmatter" | grep "^name:" | head -1 | sed 's/^name: *//')"
  if [[ -z "$skill_name" ]]; then
    echo "  SKIP (no name): $filename"
    skipped=$((skipped + 1))
    continue
  fi

  # Extract description (may be multiline — take first line only for Factory)
  description="$(echo "$frontmatter" | grep "^description:" | head -1 | sed 's/^description: *//' | sed 's/^"//' | sed 's/"$//')"
  description="$(normalize_single_line "$description")"

  # Extract trigger content to enrich description
  trigger=""
  if echo "$frontmatter" | grep -q "^trigger:"; then
    trigger="$(echo "$frontmatter" | awk '/^trigger:/{f=1;next} f && /^[a-z_]*:/{exit} f{print}' | sed 's/^  //' | head -5)"
  fi

  # Build Factory-compatible description
  # Factory uses description as the selection signal, so merge trigger hints
  factory_desc="$description"
  if [[ -n "$trigger" ]]; then
    # Take meaningful trigger lines (skip blanks, "DO NOT" lines, and YAML delimiters)
    trigger_hints="$(echo "$trigger" | grep -v "^$" | grep -vi "DO NOT" | grep -v "^---$" | head -3 | sed 's/^- //' | awk 'NR>1{printf ". "}{printf "%s",$0}')"
    if [[ -n "$trigger_hints" ]]; then
      factory_desc="$description. Use when: $trigger_hints"
    fi
  fi
  factory_desc="$(normalize_single_line "$factory_desc")"

  # Extract body (everything after second ---)
  body="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2){found=1; next}} found{print}' "$src")"

  # Create output directory
  out_dir="$SKILLS_OUT/$skill_name"
  mkdir -p "$out_dir"

  # Write Factory-compatible SKILL.md
  {
    echo "---"
    echo "name: $skill_name"
    echo "version: 1.0.0"
    printf 'description: %s\n' "$(yaml_quote "$factory_desc")"
    echo "---"
    printf '%s\n' "$body"
  } > "$out_dir/SKILL.md"

  echo "  GEN: $skill_name ($filename)"
  generated=$((generated + 1))
done

echo ""
echo "Factory skills generated: $generated"
echo "Skipped: $skipped"
echo "Output: $SKILLS_OUT/"

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

    # Factory has no plugin namespacing — prefix with "octo-" so all commands
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
