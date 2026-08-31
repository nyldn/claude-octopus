#!/usr/bin/env bash
# build-factory-skills.sh — Generate shared portable skills plus
# Cursor-compatible .cursor-plugin/commands/<name>.md from commands/*.md.
#
# Shared format: skills/<skill-name>/SKILL.md with frontmatter: name, description
# Cursor command format: .cursor-plugin/commands/<name>.md with frontmatter: description
# Our source format: .claude/skills/*.md and commands/*.md
#
# Usage: bash scripts/build-factory-skills.sh [--check|--clean]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$PLUGIN_ROOT/.claude/skills"
SKILLS_OUT="$PLUGIN_ROOT/skills"
COMMANDS_SRC="$PLUGIN_ROOT/commands"
COMMANDS_OUT="$PLUGIN_ROOT/.cursor-plugin/commands"
CHECK_MODE=false
CHECK_ROOT=""

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*" >&2
}

if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=true
  CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/octo-factory-check.XXXXXX")"
  trap 'rm -rf "$CHECK_ROOT"' EXIT INT TERM
fi

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

# Frontmatter extraction reads scalar text rather than parsing YAML. Remove one
# matching quote layer before re-encoding it for Factory so a quoted source
# description does not become a string containing quote characters.
yaml_unquote_scalar() {
  local value="$1"
  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      case "$value" in
        *\\*) ;;
        *) printf '%s' "$value"; return ;;
      esac
      if ! command -v python3 >/dev/null 2>&1; then
        log ERROR "python3 is required to decode quoted YAML metadata"
        return 1
      fi
      YAML_QUOTED_SCALAR="$value" python3 - <<'PY'
import os
import sys

value = os.environ["YAML_QUOTED_SCALAR"]
simple = {
    "a": "\a", "b": "\b", "t": "\t", "n": "\n", "v": "\v",
    "f": "\f", "r": "\r", "e": "\x1b", " ": " ", '"': '"',
    "/": "/", "\\": "\\", "_": "\u00a0", "N": "\u0085",
    "L": "\u2028", "P": "\u2029",
}
widths = {"x": 2, "u": 4, "U": 8}
decoded = []
i = 0
try:
    while i < len(value):
        if value[i] != "\\":
            decoded.append(value[i])
            i += 1
            continue
        i += 1
        if i >= len(value):
            raise ValueError("trailing backslash")
        escape = value[i]
        if escape == "0":
            raise ValueError(r"\0 cannot be represented by the shell")
        if escape in simple:
            decoded.append(simple[escape])
            i += 1
            continue
        if escape in widths:
            width = widths[escape]
            digits = value[i + 1:i + 1 + width]
            if len(digits) != width or any(c not in "0123456789abcdefABCDEF" for c in digits):
                raise ValueError(f"invalid \\{escape} escape")
            codepoint = int(digits, 16)
            if codepoint > 0x10FFFF or 0xD800 <= codepoint <= 0xDFFF:
                raise ValueError(f"invalid Unicode scalar U+{codepoint:04X}")
            decoded.append(chr(codepoint))
            i += width + 1
            continue
        raise ValueError(f"unsupported YAML escape \\{escape}")
except ValueError as error:
    print(f"ERROR: invalid quoted YAML metadata: {error}", file=sys.stderr)
    raise SystemExit(1)

sys.stdout.write("".join(decoded))
PY
      return
      ;;
    \'*\')
      value="${value#\'}"
      value="${value%\'}"
      value="${value//\'\'/\'}"
      ;;
  esac
  printf '%s' "$value"
}

# Octopus-only frontmatter keys to strip (Factory doesn't understand these)
STRIP_KEYS="agent|aliases|category|context|cost_optimization|created|execution_mode|invocation|pattern|pre_execution_contract|providers|tags|task_dependencies|task_management|trigger|updated|use_native_tasks|validation_gates|version"

if [[ "${1:-}" == "--clean" ]]; then
  log INFO "Cleaning generated skills and cursor command directories..."
  rm -rf "$SKILLS_OUT" "$COMMANDS_OUT"
  log INFO "Done."
  exit 0
fi

# --- Shared skills generation ---

if $CHECK_MODE; then
  bash "$SCRIPT_DIR/build-codex-skills.sh" --check
else
  bash "$SCRIPT_DIR/build-codex-skills.sh"
fi

# --- Commands generation ---
# Factory only supports: description, argument-hint, allowed-tools, disable-model-invocation
# Strip Claude Code-specific keys: command, aliases, redirect, version, category, tags, created, updated

COMMANDS_DEST="$COMMANDS_OUT"
if $CHECK_MODE; then
  COMMANDS_DEST="$CHECK_ROOT/commands"
fi
rm -rf "$COMMANDS_DEST"
mkdir -p "$COMMANDS_DEST"

cmd_count=0
cmd_skipped=0

# Frontmatter keys to strip from commands (Claude Code / Octopus-specific)
CMD_STRIP_KEYS="command|aliases|redirect|version|category|tags|created|updated|agent|context|cost_optimization|execution_mode|invocation|pattern|pre_execution_contract|providers|task_dependencies|task_management|trigger|use_native_tasks|validation_gates"

generate_cursor_command() {
    local src="$1"
    local out_filename="$2"
    local allowed_tools_override="${3:-}"
    local filename
    filename="$(basename "$src")"

    # Extract frontmatter (only first block between --- delimiters)
    local frontmatter
    frontmatter="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2) exit; next} c==1{print}' "$src")"

    # Extract description
    local cmd_desc
    cmd_desc="$(echo "$frontmatter" | grep "^description:" | head -1 | sed 's/^description: *//')"
    cmd_desc="$(normalize_single_line "$cmd_desc")"
    if ! cmd_desc="$(yaml_unquote_scalar "$cmd_desc")"; then
      log ERROR "Invalid description metadata: $filename"
      return 2
    fi
    if [[ -z "$cmd_desc" ]]; then
      log WARN "SKIP (no description): $filename"
      return 1
    fi

    # Extract optional Factory-compatible fields (|| true to avoid exit on no-match)
    local arg_hint disable_model allowed_tools
    arg_hint="$(echo "$frontmatter" | grep "^argument-hint:" | head -1 | sed 's/^argument-hint: *//' || true)"
    arg_hint="$(normalize_single_line "$arg_hint")"
    if ! arg_hint="$(yaml_unquote_scalar "$arg_hint")"; then
      log ERROR "Invalid argument-hint metadata: $filename"
      return 2
    fi
    disable_model="$(echo "$frontmatter" | grep "^disable-model-invocation:" | head -1 | sed 's/^disable-model-invocation: *//' || true)"
    allowed_tools="$(echo "$frontmatter" | grep "^allowed-tools:" | head -1 | sed 's/^allowed-tools: *//' || true)"
    [[ -n "$allowed_tools_override" ]] && allowed_tools="$allowed_tools_override"

    # Extract body (everything after the closing --- of frontmatter)
    local cmd_body
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
    } > "$COMMANDS_DEST/$out_filename"

    log INFO "GEN: $out_filename"
}

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

    if generate_cursor_command "$src" "$out_filename"; then
      cmd_count=$((cmd_count + 1))
    else
      generate_status=$?
      if [[ "$generate_status" -eq 1 ]]; then
        cmd_skipped=$((cmd_skipped + 1))
      else
        exit "$generate_status"
      fi
    fi
  done
fi

# Doctor is a canonical skill rather than a Claude command, but Cursor users
# still need the established /octo-doctor adapter. Generate it from the skill
# source so a clean rebuild cannot silently delete the shipped command.
DOCTOR_SKILL_SRC="$SKILLS_SRC/skill-doctor/SKILL.md"
if [[ -f "$DOCTOR_SKILL_SRC" ]]; then
  if generate_cursor_command "$DOCTOR_SKILL_SRC" "octo-doctor.md" \
      "Bash, Read, Glob, Grep, AskUserQuestion"; then
    cmd_count=$((cmd_count + 1))
  else
    generate_status=$?
    if [[ "$generate_status" -eq 1 ]]; then
      cmd_skipped=$((cmd_skipped + 1))
    else
      exit "$generate_status"
    fi
  fi
fi

log INFO "Factory commands generated: $cmd_count"
[[ $cmd_skipped -gt 0 ]] && log WARN "Skipped: $cmd_skipped"
log INFO "Output: $COMMANDS_OUT/"

if $CHECK_MODE && ! diff -qr "$COMMANDS_DEST" "$COMMANDS_OUT" >/dev/null 2>&1; then
  log ERROR "CHECK: .cursor-plugin/commands is out of date — run scripts/build-factory-skills.sh"
  diff -ru "$COMMANDS_OUT" "$COMMANDS_DEST" >&2 || true
  exit 1
fi

# --- Agents/Droids generation (v8.41.0) ---
# Factory discovers droids from agents/ directory. The personas are already there
# via agents/config.yaml + agents/personas/*.md. This section generates
# Factory-compatible droid entries from .claude/agents/ definitions so
# both Claude Code and Factory can invoke them as native subagents.

AGENTS_SRC="$PLUGIN_ROOT/.claude/agents"
DROIDS_OUT="$PLUGIN_ROOT/agents/droids"
DROIDS_DEST="$DROIDS_OUT"
if $CHECK_MODE; then
  DROIDS_DEST="$CHECK_ROOT/droids"
fi

if [[ -d "$AGENTS_SRC" ]]; then
  rm -rf "$DROIDS_DEST"
  mkdir -p "$DROIDS_DEST"

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
    if ! desc="$(yaml_unquote_scalar "$desc")"; then
      log ERROR "Invalid description metadata: $filename"
      exit 2
    fi
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
    } > "$DROIDS_DEST/$out_filename"

    log INFO "GEN droid: $out_name"
    droid_count=$((droid_count + 1))
  done

  log INFO "Factory droids generated: $droid_count"
  log INFO "Output: $DROIDS_OUT/"

  if $CHECK_MODE && ! diff -qr "$DROIDS_DEST" "$DROIDS_OUT" >/dev/null 2>&1; then
    log ERROR "CHECK: agents/droids is out of date — run scripts/build-factory-skills.sh"
    diff -ru "$DROIDS_OUT" "$DROIDS_DEST" >&2 || true
    exit 1
  fi
fi
