#!/usr/bin/env bash
# lib/utils.sh — Pure utility functions extracted from orchestrate.sh (Wave 1)
# All functions are parameter-in, echo-out with zero or minimal global dependencies.
# Sourced by orchestrate.sh at startup.

[[ -n "${_OCTOPUS_UTILS_LOADED:-}" ]] && return 0
_OCTOPUS_UTILS_LOADED=true

# Internal log helper — uses orchestrate.sh's log() if available, falls back to stderr
_utils_log() {
    if type log &>/dev/null 2>&1; then
        log "$@"
    else
        echo "[$1] ${*:2}" >&2
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# JSON UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Extract a single JSON field value from a JSON string.
# Tries jq first (most reliable), then python3, then an improved bash regex.
# Usage: json_extract "$json_string" "fieldname" -> sets REPLY variable
# Returns 0 if found, 1 if not found
json_extract() {
    local json="$1"
    local field="$2"
    REPLY=""

    # Strategy 1: jq (most reliable — handles all edge cases)
    if command -v jq &>/dev/null; then
        local jq_out
        jq_out=$(printf '%s' "$json" | jq -re --arg f "$field" '.[$f] // empty' 2>/dev/null) && {
            REPLY="$jq_out"
            return 0
        }
        # jq available but field not found — authoritative miss, no fallback
        return 1
    fi

    # Strategy 2: python3 one-liner (available on macOS and most Linux)
    if command -v python3 &>/dev/null; then
        local py_out
        py_out=$(python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    v=d[sys.argv[1]]
    print(v if isinstance(v,str) else json.dumps(v))
except Exception:
    sys.exit(1)
" "$field" <<< "$json" 2>/dev/null) && {
            REPLY="$py_out"
            return 0
        }
        return 1
    fi

    # Strategy 3: Improved bash regex fallback (handles whitespace around colon
    # and escaped quotes inside values). BASH_REMATCH used for static-analysis compat.
    # Try quoted string value first (handles escaped quotes via negative lookbehind approx)
    local pattern="\"${field}\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
    if [[ "$json" =~ $pattern ]]; then
        REPLY="${BASH_REMATCH[1]}"
        return 0
    fi
    # Try numeric / boolean / null value
    local num_pattern="\"${field}\"[[:space:]]*:[[:space:]]*([0-9eE.+-]+|true|false|null)"
    if [[ "$json" =~ $num_pattern ]]; then
        REPLY="${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Extract multiple JSON fields at once (single pass, no subprocesses)
# Usage: json_extract_multi "$json_string" field1 field2 field3
# Sets variables: _field1, _field2, _field3
# Uses bash nameref (4.3+) to avoid command injection via eval
json_extract_multi() {
    local json="$1"
    shift

    for field in "$@"; do
        local -n ref="_$field"
        if [[ "$json" =~ \"$field\":\"([^\"]+)\" ]]; then
            ref="${BASH_REMATCH[1]}"
        else
            ref=""
        fi
    done
}

# Properly escape string for JSON
# Handles all special characters per JSON spec
json_escape() {
    local str="$1"

    # Escape in order: backslash first, then other special chars
    str="${str//\\/\\\\}"     # backslash
    str="${str//\"/\\\"}"     # double quote
    str="${str//$'\t'/\\t}"   # tab
    str="${str//$'\n'/\\n}"   # newline
    str="${str//$'\r'/\\r}"   # carriage return
    str="${str//$'\b'/\\b}"   # backspace
    str="${str//$'\f'/\\f}"   # form feed

    echo "$str"
}

# ═══════════════════════════════════════════════════════════════════════════════
# VALIDATION & SANITIZATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate output file path to prevent path traversal attacks
# Returns resolved path on success, exits with error on failure
validate_output_file() {
    local file="$1"
    local resolved

    # RESULTS_DIR must be set for path validation to be meaningful
    if [[ -z "${RESULTS_DIR:-}" ]]; then
        _utils_log ERROR "RESULTS_DIR is not set — cannot validate output file"
        return 1
    fi

    # Resolve to absolute path
    resolved=$(realpath "$file" 2>/dev/null) || {
        _utils_log ERROR "Invalid file path: $file"
        return 1
    }

    # Must be under RESULTS_DIR
    if [[ "$resolved" != "${RESULTS_DIR}"/* ]]; then
        _utils_log ERROR "File path outside results directory: $file"
        return 1
    fi

    # File must exist
    if [[ ! -f "$resolved" ]]; then
        _utils_log ERROR "File not found: $file"
        return 1
    fi

    echo "$resolved"
    return 0
}

# Sanitize review ID to prevent sed injection
# Only allows alphanumeric, hyphen, and underscore characters
sanitize_review_id() {
    local id="$1"

    # Only allow alphanumeric, hyphen, underscore
    if [[ ! "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        _utils_log ERROR "Invalid review ID format: $id"
        return 1
    fi

    echo "$id"
    return 0
}

# Validate agent command to prevent command injection
# Only allows whitelisted command prefixes
validate_agent_command() {
    local cmd="$1"

    # Whitelist of allowed command prefixes (v7.19.0: tightened to exact patterns)
    case "$cmd" in
        "codex "*|"codex")
            return 0 ;;
        "gemini "*|"gemini")
            return 0 ;;
        "claude "*|"claude")
            return 0 ;;
        "openrouter_execute"*) # openrouter_execute and openrouter_execute_model
            return 0 ;;
        "perplexity_execute"*) # v8.24.0: Perplexity Sonar API (Issue #22)
            return 0 ;;
        "copilot "*|"copilot")   # GitHub Copilot CLI
            return 0 ;;
        "opencode "*|"opencode")  # v9.11.0: OpenCode CLI multi-provider router
            return 0 ;;
        "ollama "*|"ollama")      # Ollama local LLM
            return 0 ;;
        "agent "*|"agent")        # Cursor Agent CLI (v9.23.0)
            return 0 ;;
        "env NODE_NO_WARNINGS="*) # only allow env with NODE_NO_WARNINGS prefix
            return 0 ;;
        *)
            _utils_log ERROR "Invalid agent command: $cmd"
            return 1
            ;;
    esac
}


# [EXTRACTED to lib/secure.sh] sanitize_external_content, secure_tempfile, guard_output

# ── Extracted from orchestrate.sh (optimization sweep) ──

rotate_logs() {
    local max_size_mb=50
    local max_age_days="${1:-30}"  # Default 30 days, configurable

    [[ ! -d "$LOGS_DIR" ]] && return 0

    local rotated=0
    local deleted=0
    local total_freed=0

    # Rotate large log files
    for log in "$LOGS_DIR"/*.log; do
        [[ ! -f "$log" ]] && continue

        # Check file size
        local size_kb=$(du -k "$log" 2>/dev/null | cut -f1)
        if [[ ${size_kb:-0} -gt $((max_size_mb * 1024)) ]]; then
            # Rotate large log files
            mv "$log" "${log}.1"
            gzip "${log}.1" 2>/dev/null || true
            ((rotated++)) || true
            log DEBUG "Rotated large log: $(basename "$log") (${size_kb}KB)"
        fi
    done

    # v7.19.0 P2.1: Remove old logs (both .log and .log.*.gz)
    # Find uncompressed logs older than max_age_days
    while IFS= read -r -d '' old_log; do
        local size_kb=$(du -k "$old_log" 2>/dev/null | cut -f1)
        total_freed=$((total_freed + size_kb))
        rm -f "$old_log"
        ((deleted++)) || true
        log DEBUG "Deleted old log: $(basename "$old_log") (${size_kb}KB)"
    done < <(find "$LOGS_DIR" -name "*.log" -mtime "+$max_age_days" -print0 2>/dev/null)

    # Find compressed logs older than max_age_days
    while IFS= read -r -d '' old_log; do
        local size_kb=$(du -k "$old_log" 2>/dev/null | cut -f1)
        total_freed=$((total_freed + size_kb))
        rm -f "$old_log"
        ((deleted++)) || true
        log DEBUG "Deleted old compressed log: $(basename "$old_log") (${size_kb}KB)"
    done < <(find "$LOGS_DIR" -name "*.log.*.gz" -mtime "+$max_age_days" -print0 2>/dev/null)

    # Also clean up old .raw files (v7.19.0 debugging artifacts)
    while IFS= read -r -d '' raw_file; do
        local size_kb=$(du -k "$raw_file" 2>/dev/null | cut -f1)
        total_freed=$((total_freed + size_kb))
        rm -f "$raw_file"
        log DEBUG "Deleted old raw output: $(basename "$raw_file") (${size_kb}KB)"
    done < <(find "$RESULTS_DIR" -name ".raw-*.out" -mtime "+7" -print0 2>/dev/null)

    # Report if anything was cleaned up
    if [[ $rotated -gt 0 ]] || [[ $deleted -gt 0 ]]; then
        local freed_mb=$((total_freed / 1024))
        log INFO "Log cleanup: rotated $rotated, deleted $deleted files, freed ${freed_mb}MB"
    fi
}

open_browser() {
    local url="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$url"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "$url" 2>/dev/null || sensible-browser "$url" 2>/dev/null || echo "Please open: $url"
    elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
        start "$url"
    else
        echo "Please open: $url"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# ESSENTIAL DEVELOPER TOOLS - Detection and Installation (v4.8.2)
# Tools that AI coding assistants rely on for auditing, testing, and browser work
# Compatible with bash 3.2+ (macOS default)
# ═══════════════════════════════════════════════════════════════════════════════

# Essential tools list (space-separated for bash 3.2 compat)
ESSENTIAL_TOOLS_LIST="jq shellcheck gh imagemagick playwright"

# Get tool description
get_tool_description() {
    case "$1" in
        jq)          echo "JSON processor (critical for AI workflows)" ;;
        shellcheck)  echo "Shell script static analysis" ;;
        gh)          echo "GitHub CLI for PR/issue automation" ;;
        imagemagick) echo "Screenshot compression (5MB API limits)" ;;
        playwright)  echo "Modern browser automation & screenshots" ;;
        *)           echo "Developer tool" ;;
    esac
}

# Check if a tool is installed
is_tool_installed() {
    local tool="$1"
    case "$tool" in
        imagemagick)
            command -v convert &>/dev/null || command -v magick &>/dev/null
            ;;
        playwright)
            # Check for playwright in node_modules or global
            command -v playwright &>/dev/null || [[ -f "node_modules/.bin/playwright" ]] || npx playwright --version &>/dev/null 2>&1
            ;;
        *)
            command -v "$tool" &>/dev/null && return 0
            # Windows: check common install paths not in PATH
            if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "mingw"* ]] || [[ "$OSTYPE" == "cygwin" ]]; then
                case "$tool" in
                    gh)
                        [[ -f "/c/Program Files/GitHub CLI/gh.exe" ]] || \
                        [[ -f "/c/ProgramData/chocolatey/bin/gh.exe" ]] || \
                        [[ -f "$LOCALAPPDATA/Microsoft/WinGet/Links/gh.exe" ]] 2>/dev/null
                        ;;
                    jq)
                        [[ -f "/c/ProgramData/chocolatey/bin/jq.exe" ]] || \
                        [[ -f "$LOCALAPPDATA/Microsoft/WinGet/Links/jq.exe" ]] 2>/dev/null
                        ;;
                    shellcheck)
                        [[ -f "/c/ProgramData/chocolatey/bin/shellcheck.exe" ]] || \
                        [[ -f "$LOCALAPPDATA/Microsoft/WinGet/Links/shellcheck.exe" ]] 2>/dev/null
                        ;;
                    *) return 1 ;;
                esac
            else
                return 1
            fi
            ;;
    esac
}

# Get install command for current platform
get_install_command() {
    local tool="$1"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - prefer brew
        case "$tool" in
            jq)          echo "brew install jq" ;;
            shellcheck)  echo "brew install shellcheck" ;;
            gh)          echo "brew install gh" ;;
            imagemagick) echo "brew install imagemagick" ;;
            playwright)  echo "npx playwright install" ;;
        esac
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "mingw"* ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        # Windows (Git Bash / MSYS2 / Cygwin) - prefer winget, fall back to choco
        local pm=""
        if command -v winget &>/dev/null; then
            pm="winget"
        elif command -v choco &>/dev/null; then
            pm="choco"
        fi
        case "$pm" in
            winget)
                case "$tool" in
                    jq)          echo "winget install --id jqlang.jq --accept-source-agreements --accept-package-agreements" ;;
                    shellcheck)  echo "winget install --id koalaman.shellcheck --accept-source-agreements --accept-package-agreements" ;;
                    gh)          echo "winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements" ;;
                    imagemagick) echo "winget install --id ImageMagick.ImageMagick --accept-source-agreements --accept-package-agreements" ;;
                    playwright)  echo "npx playwright install" ;;
                esac
                ;;
            choco)
                case "$tool" in
                    jq)          echo "choco install jq -y" ;;
                    shellcheck)  echo "choco install shellcheck -y" ;;
                    gh)          echo "choco install gh -y" ;;
                    imagemagick) echo "choco install imagemagick -y" ;;
                    playwright)  echo "npx playwright install" ;;
                esac
                ;;
            *)
                # No package manager found — give manual instructions
                echo "echo 'No package manager found. Install $tool manually via winget or choco, then restart your shell.'"
                ;;
        esac
    else
        # Linux - apt-get
        case "$tool" in
            jq)          echo "sudo apt-get install -y jq" ;;
            shellcheck)  echo "sudo apt-get install -y shellcheck" ;;
            gh)          echo "sudo apt-get install -y gh" ;;
            imagemagick) echo "sudo apt-get install -y imagemagick" ;;
            playwright)  echo "npx playwright install" ;;
        esac
    fi
}

# Install a single tool
install_tool() {
    local tool="$1"
    local install_cmd
    install_cmd=$(get_install_command "$tool")

    if [[ -z "$install_cmd" ]]; then
        echo -e "    ${RED}✗${NC} No install command for $tool"
        return 1
    fi

    # Security: validate tool against allowlist before executing
    case "$tool" in
        jq|shellcheck|gh|imagemagick|playwright) ;;
        *)
            echo -e "    ${RED}✗${NC} Unknown tool: $tool"
            return 1
            ;;
    esac

    echo -e "    ${CYAN}→${NC} $install_cmd"
    if bash -c "$install_cmd" 2>&1 | sed 's/^/      /'; then
        echo -e "    ${GREEN}✓${NC} $tool installed"
        return 0
    else
        echo -e "    ${RED}✗${NC} Failed to install $tool"
        return 1
    fi
}
