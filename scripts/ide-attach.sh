#!/usr/bin/env bash
# ide-attach.sh — Auto-detect IDE and configure MCP server connection
#
# Usage:
#   ./scripts/ide-attach.sh [--ide vscode|cursor|zed|windsurf] [--project-dir /path/to/project]
#   ./scripts/ide-attach.sh --list        # List detected IDEs
#   ./scripts/ide-attach.sh --remove      # Remove MCP config from detected IDE
#
# If no --ide flag is given, auto-detects installed IDEs and configures the first found.

set -euo pipefail

# Resolve plugin root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_SERVER_DIR="$PLUGIN_ROOT/mcp-server"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# --- Helpers ---

log_info()  { echo -e "${BLUE}[octopus]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[octopus]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[octopus]${NC} $*"; }
log_error() { echo -e "${RED}[octopus]${NC} $*" >&2; }

# --- IDE Detection ---

detect_vscode() {
  command -v code &>/dev/null && return 0
  [[ -d "$HOME/.vscode" ]] && return 0
  [[ -d "/Applications/Visual Studio Code.app" ]] && return 0
  return 1
}

detect_cursor() {
  command -v cursor &>/dev/null && return 0
  [[ -d "$HOME/.cursor" ]] && return 0
  [[ -d "/Applications/Cursor.app" ]] && return 0
  return 1
}

detect_zed() {
  command -v zed &>/dev/null && return 0
  [[ -d "/Applications/Zed.app" ]] && return 0
  return 1
}

detect_windsurf() {
  command -v windsurf &>/dev/null && return 0
  [[ -d "/Applications/Windsurf.app" ]] && return 0
  return 1
}

list_detected_ides() {
  echo -e "${PURPLE}🐙 Claude Octopus — IDE Detection${NC}"
  echo ""
  local found=0
  if detect_vscode; then
    echo -e "  ${GREEN}✓${NC} VS Code"
    found=$((found + 1))
  else
    echo -e "  ${RED}✗${NC} VS Code — not found"
  fi
  if detect_cursor; then
    echo -e "  ${GREEN}✓${NC} Cursor"
    found=$((found + 1))
  else
    echo -e "  ${RED}✗${NC} Cursor — not found"
  fi
  if detect_zed; then
    echo -e "  ${GREEN}✓${NC} Zed"
    found=$((found + 1))
  else
    echo -e "  ${RED}✗${NC} Zed — not found"
  fi
  if detect_windsurf; then
    echo -e "  ${GREEN}✓${NC} Windsurf"
    found=$((found + 1))
  else
    echo -e "  ${RED}✗${NC} Windsurf — not found"
  fi
  echo ""
  if [[ $found -eq 0 ]]; then
    echo -e "  ${YELLOW}No supported IDEs detected.${NC}"
    echo "  Supported: VS Code, Cursor, Zed, Windsurf"
  else
    echo -e "  ${found} IDE(s) detected. Run ${BLUE}./scripts/ide-attach.sh${NC} to configure."
  fi
}

# --- MCP Config Generation ---

# Build the MCP server config JSON for a given IDE
generate_mcp_config() {
  local ide="$1"
  local mcp_server_path="$MCP_SERVER_DIR/src/index.ts"

  # Validate path doesn't contain JSON-breaking characters
  if [[ "$mcp_server_path" =~ [\"\\] ]]; then
    log_error "Plugin path contains characters unsafe for JSON: $mcp_server_path"
    return 1
  fi

  # Cursor uses "mcpServers" key; VS Code/Windsurf use "servers"
  local top_key="servers"
  [[ "$ide" == "cursor" ]] && top_key="mcpServers"

  # Use tsx to run TypeScript directly (no build step needed)
  cat <<EOF
{
  "$top_key": {
    "claude-octopus": {
      "command": "npx",
      "args": ["tsx", "$mcp_server_path"],
      "env": {
        "OPENAI_API_KEY": "\${env:OPENAI_API_KEY}",
        "GEMINI_API_KEY": "\${env:GEMINI_API_KEY}",
        "GOOGLE_API_KEY": "\${env:GOOGLE_API_KEY}",
        "OPENROUTER_API_KEY": "\${env:OPENROUTER_API_KEY}",
        "PERPLEXITY_API_KEY": "\${env:PERPLEXITY_API_KEY}"
      }
    }
  }
}
EOF
}

# Zed uses a different config format (settings.json under context_servers)
generate_zed_config() {
  local mcp_server_path="$MCP_SERVER_DIR/src/index.ts"
  cat <<EOF
{
  "context_servers": {
    "claude-octopus": {
      "command": {
        "path": "npx",
        "args": ["tsx", "$mcp_server_path"],
        "env": {
          "OPENAI_API_KEY": "\${env:OPENAI_API_KEY}",
          "GEMINI_API_KEY": "\${env:GEMINI_API_KEY}",
          "GOOGLE_API_KEY": "\${env:GOOGLE_API_KEY}",
          "OPENROUTER_API_KEY": "\${env:OPENROUTER_API_KEY}",
          "PERPLEXITY_API_KEY": "\${env:PERPLEXITY_API_KEY}"
        }
      }
    }
  }
}
EOF
}

# --- Config Writers ---

get_config_path() {
  local ide="$1"
  local project_dir="$2"

  case "$ide" in
    vscode)
      echo "$project_dir/.vscode/mcp.json"
      ;;
    cursor)
      echo "$project_dir/.cursor/mcp.json"
      ;;
    zed)
      # Zed uses project-level .zed/settings.json or global settings
      echo "$project_dir/.zed/settings.json"
      ;;
    windsurf)
      echo "$project_dir/.windsurf/mcp.json"
      ;;
    *)
      log_error "Unknown IDE: $ide"
      return 1
      ;;
  esac
}

write_config() {
  local ide="$1"
  local project_dir="$2"
  local config_path
  config_path="$(get_config_path "$ide" "$project_dir")"
  local config_dir
  config_dir="$(dirname "$config_path")"

  # Create directory if needed
  if [[ ! -d "$config_dir" ]]; then
    mkdir -p "$config_dir"
    log_info "Created $config_dir"
  fi

  # Check for existing config
  if [[ -f "$config_path" ]]; then
    # Check if octopus is already configured
    if grep -q "claude-octopus" "$config_path" 2>/dev/null; then
      log_warn "Claude Octopus already configured in $config_path"
      log_info "To reconfigure, remove the existing config first: ./scripts/ide-attach.sh --remove"
      return 0
    fi
    log_warn "Existing config found at $config_path — merging claude-octopus entry"
    # For simplicity, warn and don't overwrite existing configs with other servers
    log_info "Please manually add the claude-octopus server entry. Template:"
    echo ""
    if [[ "$ide" == "zed" ]]; then
      generate_zed_config
    else
      generate_mcp_config "$ide"
    fi
    return 0
  fi

  # Write fresh config
  if [[ "$ide" == "zed" ]]; then
    generate_zed_config > "$config_path"
  else
    generate_mcp_config "$ide" > "$config_path"
  fi

  log_ok "Wrote MCP config to $config_path"
}

remove_config() {
  local ide="$1"
  local project_dir="$2"
  local config_path
  config_path="$(get_config_path "$ide" "$project_dir")"

  if [[ ! -f "$config_path" ]]; then
    log_warn "No config found at $config_path"
    return 0
  fi

  if ! grep -q "claude-octopus" "$config_path" 2>/dev/null; then
    log_warn "Config at $config_path doesn't contain claude-octopus"
    return 0
  fi

  # If octopus is the only server, remove the file
  local server_count
  server_count=$(grep -c '"command"' "$config_path" 2>/dev/null || echo "0")
  if [[ "$server_count" -le 1 ]]; then
    rm "$config_path"
    log_ok "Removed $config_path"
  else
    log_warn "Multiple servers in $config_path — please remove claude-octopus entry manually"
  fi
}

# --- Main ---

main() {
  local ide=""
  local project_dir="${PWD}"
  local action="attach"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ide)
        ide="$2"
        shift 2
        ;;
      --project-dir)
        project_dir="$2"
        shift 2
        ;;
      --list)
        list_detected_ides
        return 0
        ;;
      --remove)
        action="remove"
        shift
        ;;
      --help|-h)
        echo "Usage: ide-attach.sh [--ide vscode|cursor|zed|windsurf] [--project-dir DIR]"
        echo ""
        echo "Options:"
        echo "  --ide IDE          Target IDE (auto-detect if omitted)"
        echo "  --project-dir DIR  Project directory for config (default: PWD)"
        echo "  --list             List detected IDEs"
        echo "  --remove           Remove MCP config"
        echo "  --help             Show this help"
        return 0
        ;;
      *)
        log_error "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  # Canonicalize and validate project directory
  project_dir="$(cd "$project_dir" 2>/dev/null && pwd)" || {
    log_error "Project directory does not exist: $project_dir"
    return 1
  }

  # Verify MCP server exists
  if [[ ! -f "$MCP_SERVER_DIR/src/index.ts" ]]; then
    log_error "MCP server not found at $MCP_SERVER_DIR/src/index.ts"
    log_error "Ensure you're running from the claude-octopus plugin directory"
    return 1
  fi

  # Check node_modules
  if [[ ! -d "$MCP_SERVER_DIR/node_modules" ]]; then
    if ! command -v npm &>/dev/null; then
      log_error "npm not found. Install Node.js (>=18) to use the MCP server."
      return 1
    fi
    log_info "Installing MCP server dependencies..."
    (cd "$MCP_SERVER_DIR" && npm install --silent)
  fi

  # Auto-detect IDE if not specified
  if [[ -z "$ide" ]]; then
    if detect_cursor; then
      ide="cursor"
    elif detect_vscode; then
      ide="vscode"
    elif detect_zed; then
      ide="zed"
    elif detect_windsurf; then
      ide="windsurf"
    else
      log_error "No supported IDE detected. Use --ide to specify manually."
      log_info "Supported: vscode, cursor, zed, windsurf"
      return 1
    fi
    log_info "Auto-detected IDE: $ide"
  fi

  echo -e "${PURPLE}🐙 Claude Octopus — IDE Integration${NC}"
  echo ""

  if [[ "$action" == "remove" ]]; then
    remove_config "$ide" "$project_dir"
  else
    write_config "$ide" "$project_dir"
    echo ""
    echo -e "${GREEN}Setup complete!${NC} Available MCP tools in your IDE:"
    echo ""
    echo "  octopus_discover  — Multi-provider research (Codex + Gemini)"
    echo "  octopus_define    — Consensus building on requirements"
    echo "  octopus_develop   — Implementation with quality gates"
    echo "  octopus_deliver   — Final validation and review"
    echo "  octopus_embrace   — Full 4-phase workflow"
    echo "  octopus_debate    — Three-way AI debate"
    echo "  octopus_review    — Code review"
    echo "  octopus_security  — Security audit"
    echo "  octopus_status    — Provider availability check"
    echo ""
    echo -e "Restart your IDE or reload the window for changes to take effect."
    echo -e "Run ${BLUE}./scripts/ide-attach.sh --list${NC} to see all detected IDEs."
  fi
}

main "$@"
