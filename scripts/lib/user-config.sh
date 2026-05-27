#!/usr/bin/env bash
set -eo pipefail
# Persistent user config for Claude Octopus.
# Stores setup choices to ~/.claude-octopus/user-config.json.
#
# Usage (source this file, then call functions):
#   source scripts/lib/user-config.sh
#   octo_config_write "work_mode" '"dev"'
#   octo_config_read  "work_mode" "dev"
#   octo_config_reset

OCTO_CONFIG_DIR="${HOME}/.claude-octopus"
OCTO_CONFIG_FILE="${OCTO_CONFIG_DIR}/user-config.json"

octo_config_write() {
  local key="$1"
  local value="$2"

  if ! command -v jq &>/dev/null; then
    echo "⚠️  jq not found — settings not persisted. Install: brew install jq" >&2
    return 0
  fi

  mkdir -p "$OCTO_CONFIG_DIR"

  local current="{}"
  [[ -f "$OCTO_CONFIG_FILE" ]] && current=$(cat "$OCTO_CONFIG_FILE")

  local updated
  updated=$(echo "$current" | jq --arg k "$key" --argjson v "$value" '.[$k] = $v' 2>/dev/null) || {
    echo "⚠️  Failed to update config key '$key'" >&2
    return 0
  }

  echo "$updated" > "$OCTO_CONFIG_FILE"
}

octo_config_read() {
  local key="$1"
  local default="${2:-}"

  if ! command -v jq &>/dev/null; then echo "$default"; return 0; fi
  if [[ ! -f "$OCTO_CONFIG_FILE" ]]; then echo "$default"; return 0; fi

  local val
  val=$(jq -r --arg k "$key" --arg d "$default" '.[$k] // $d' "$OCTO_CONFIG_FILE" 2>/dev/null) || { echo "$default"; return 0; }
  [[ "$val" == "null" ]] && echo "$default" || echo "$val"
}

octo_config_reset() {
  rm -f "$OCTO_CONFIG_FILE"
  echo "✓ Octopus user config reset."
}

octo_config_summary() {
  if [[ ! -f "$OCTO_CONFIG_FILE" ]]; then
    echo "  (no saved config — run /octo:setup to configure)"
    return 0
  fi
  echo "  Config: $OCTO_CONFIG_FILE"
  command -v jq &>/dev/null && jq -r 'to_entries[] | "  \(.key): \(.value)"' "$OCTO_CONFIG_FILE" 2>/dev/null || cat "$OCTO_CONFIG_FILE"
}
