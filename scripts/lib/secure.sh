#!/usr/bin/env bash
# lib/secure.sh — Security utilities extracted from orchestrate.sh
# Anti-injection wrappers, secure temp files, and output guards.
# Sourced by orchestrate.sh at startup.

[[ -n "${_OCTOPUS_SECURE_LOADED:-}" ]] && return 0
_OCTOPUS_SECURE_LOADED=true

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
    # Fallback uses $RANDOM^3 + epoch because BSD `date +%s%N` returns a literal N on macOS
    local nonce
    nonce=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null) || nonce="${RANDOM}${RANDOM}${RANDOM}$(date +%s)"

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
# If content exceeds 49KB, writes to a temp file and returns a pointer instead.
# When truncating, preserves anomalous lines (errors, failures, warnings) so
# critical diagnostic info is never lost in the middle of truncated output.
# Usage: guard_output "$content" "label"
guard_output() {
    local content="$1" label="${2:-output}" max_bytes=49000
    if [[ ${#content} -gt $max_bytes ]]; then
        local f; f=$(secure_tempfile "guard-${label}")
        printf '%s\n' "$content" > "$f"

        # Anomaly-preserving truncation: scan for error/failure lines
        local anomaly_pattern='ERROR|FATAL|FAIL|PANIC|Traceback|Exception|CRITICAL|error:|failed|Error:'
        local anomaly_lines
        anomaly_lines=$(printf '%s\n' "$content" | grep -n -E "$anomaly_pattern" 2>/dev/null) || true

        if [[ -n "$anomaly_lines" ]]; then
            # Count total lines
            local total_lines
            total_lines=$(printf '%s\n' "$content" | wc -l | tr -d ' ')
            local omitted=$((total_lines - 30))
            if [[ $omitted -lt 0 ]]; then
                omitted=0
            fi

            # Head: first 20 lines
            printf '%s\n' "$content" | head -20

            echo ""
            echo "--- [${omitted} lines omitted, showing anomalies below] ---"
            echo ""

            # Anomalous lines with their line numbers (already from grep -n)
            printf '%s\n' "$anomaly_lines"

            echo ""
            echo "--- [end of anomalies] ---"
            echo ""

            # Tail: last 10 lines
            printf '%s\n' "$content" | tail -10

            echo ""
            echo "Full output: @file:${f}"
        else
            # No anomalies found — fall back to head-truncation
            echo "[Output exceeded ${max_bytes} bytes. Full content at:]"
            echo "@file:${f}"
        fi
    else
        printf '%s\n' "$content"
    fi
}

# ── Extracted from orchestrate.sh ──
sanitize_secrets() {
    local text="${1-}"

    # Accept a text argument or stdin so callers can redact before truncating.
    {
        if (( $# )); then
            echo "$text"
        else
            cat
        fi
    } | sed -E \
        -e 's/sk-[A-Za-z0-9_-]{20,}/[REDACTED-API-KEY]/g' \
        -e 's/AKIA[A-Z0-9]{16}/[REDACTED-AWS-KEY]/g' \
        -e 's/ASIA[A-Z0-9]{16}/[REDACTED-AWS-KEY]/g' \
        -e 's/ghp_[A-Za-z0-9]{36,}/[REDACTED-GITHUB-PAT]/g' \
        -e 's/github_pat_[A-Za-z0-9_]{16,}/[REDACTED-GITHUB-PAT]/g' \
        -e 's/gh[usr]_[A-Za-z0-9]{16,}/[REDACTED-GITHUB-TOKEN]/g' \
        -e 's/gho_[A-Za-z0-9]{36,}/[REDACTED-GITHUB-OAUTH]/g' \
        -e 's/pplx-[A-Za-z0-9_-]{16,}/[REDACTED-API-KEY]/g' \
        -e 's/AIza[A-Za-z0-9_-]{16,}/[REDACTED-API-KEY]/g' \
        -e 's/hf_[A-Za-z0-9]{16,}/[REDACTED-API-KEY]/g' \
        -e 's/glpat-[A-Za-z0-9_-]{20,}/[REDACTED-GITLAB-PAT]/g' \
        -e 's/xoxb-[A-Za-z0-9-]{20,}/[REDACTED-SLACK-BOT]/g' \
        -e 's/xoxp-[A-Za-z0-9-]{20,}/[REDACTED-SLACK-USER]/g' \
        -e 's/xox[ars]-[A-Za-z0-9-]{16,}/[REDACTED-SLACK-TOKEN]/g' \
        -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]{1,})[A-Za-z0-9._~+\/=-]{12,}/\1[REDACTED-BEARER]/g' \
        -e 's/([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*[Bb][Aa][Ss][Ii][Cc][[:space:]]{1,})[A-Za-z0-9+\/=]{1,}/\1[REDACTED-BASIC]/g' \
        -e 's#([Bb][Aa][Ss][Ii][Cc][[:space:]]+)([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{4}|[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)([^A-Za-z0-9+/=]|$)#\1[REDACTED-BASIC]\4#g' \
        -e 's/eyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*/[REDACTED-JWT]/g' \
        -e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----[^-]*-----END[A-Z ]*PRIVATE KEY-----/[REDACTED-PRIVATE-KEY]/g' \
        -e 's|postgres://[^[:space:]]*|[REDACTED-CONNECTION-STRING]|g' \
        -e 's|mysql://[^[:space:]]*|[REDACTED-CONNECTION-STRING]|g' \
        -e 's|mongodb://[^[:space:]]*|[REDACTED-CONNECTION-STRING]|g' \
        -e 's|mongodb\+srv://[^[:space:]]*|[REDACTED-CONNECTION-STRING]|g' \
        -e 's|redis://[^[:space:]]*|[REDACTED-CONNECTION-STRING]|g' \
        -e 's/password=[^[:space:]&]*/password=[REDACTED-PASSWORD]/g'
}
