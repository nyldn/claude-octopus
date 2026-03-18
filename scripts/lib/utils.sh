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

# Extract a single JSON field value using bash regex (no jq dependency)
# Usage: json_extract "$json_string" "fieldname" -> sets REPLY variable
# Returns 0 if found, 1 if not found
json_extract() {
    local json="$1"
    local field="$2"
    REPLY=""

    # Use bash regex to extract field value (handles quoted strings)
    if [[ "$json" =~ \"$field\":\"([^\"]+)\" ]]; then
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
        "env NODE_NO_WARNINGS="*) # only allow env with NODE_NO_WARNINGS prefix
            return 0 ;;
        *)
            _utils_log ERROR "Invalid agent command: $cmd"
            return 1
            ;;
    esac
}

# v8.41.0: Anti-injection nonce wrapper for untrusted content
# Wraps external/file-sourced content in random boundary tokens to prevent
# prompt injection from memory files, earned skills, or provider history.
# The nonce is a random hex string that cannot be predicted or forged.
# This is purely internal — users never see the nonces.
# Args: $1=content, $2=label (e.g. "memory", "earned-skills")
# Returns: content wrapped in nonce boundaries
sanitize_external_content() {
    local content="$1"
    local label="${2:-external}"

    [[ -z "$content" ]] && return

    # Generate random 16-char hex nonce
    local nonce
    nonce=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null) || nonce="$(date +%s%N)"

    echo "<!-- BEGIN-UNTRUSTED:${label}:${nonce} -->
${content}
<!-- END-UNTRUSTED:${label}:${nonce} -->"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEMP FILE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Create secure temporary file
# Returns path to temp file in the secure temp directory
secure_tempfile() {
    local prefix="${1:-tmp}"
    mktemp "${OCTOPUS_TMP_DIR:-/tmp}/${prefix}.XXXXXX"
}

# Guard against oversized output that could flood Claude's context window
# If content exceeds 49KB, writes to a temp file and returns a pointer instead
# Usage: guard_output "$content" "label"
guard_output() {
    local content="$1" label="${2:-output}" max_bytes=49000
    if [[ ${#content} -gt $max_bytes ]]; then
        local f; f=$(secure_tempfile "guard-${label}")
        printf '%s\n' "$content" > "$f"
        echo "[Output exceeded ${max_bytes} bytes. Full content at:]"
        echo "@file:${f}"
    else
        printf '%s\n' "$content"
    fi
}
