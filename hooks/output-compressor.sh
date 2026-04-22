#!/usr/bin/env bash
# Claude Octopus — Output Compressor Hook (v9.20.0)
# PostToolUse hook that detects large tool outputs and injects compressed
# summaries as additionalContext. Also logs compression analytics.
#
# How it works:
#   1. Reads tool output from stdin (hook protocol)
#   2. If output > threshold, detects content type (JSON, logs, HTML, text)
#   3. Generates a compressed summary
#   4. Outputs {"decision":"continue","additionalContext":"<summary>"}
#   5. Logs before/after sizes to analytics file
#
# Note: PostToolUse hooks CANNOT replace tool output — they add context.
# The summary helps Claude focus on key data without re-reading verbose output.
# For actual output truncation, use bin/octo-compress as a pipe in bash commands.
#
# Hook event: PostToolUse (Bash|Read|WebFetch|Grep)
# Feature flag: OCTOPUS_COMPRESS_ENABLED (default: true)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# --- Config ---
COMPRESS_ENABLED="${OCTOPUS_COMPRESS_ENABLED:-true}"
[[ "$COMPRESS_ENABLED" == "true" ]] || exit 0

MIN_CHARS="${OCTOPUS_COMPRESS_MIN_CHARS:-3000}"
MIN_ARRAY_ITEMS="${OCTOPUS_COMPRESS_MIN_ARRAY:-5}"
ANALYTICS_DIR="${HOME}/.claude-octopus/analytics"
ANALYTICS_FILE="${ANALYTICS_DIR}/compression.jsonl"
CONFIG_FILE="${HOME}/.claude-octopus/.compression-config.json"
SESSION="${CLAUDE_SESSION_ID:-unknown}"

# Debounce: only analyze every 3rd tool call to reduce hook overhead
DEBOUNCE_FILE="/tmp/octopus-compress-debounce-${SESSION}.count"
count=0
[[ -f "$DEBOUNCE_FILE" ]] && count=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$DEBOUNCE_FILE" 2>/dev/null || true
[[ $((count % 3)) -eq 0 ]] || exit 0

# --- Read stdin (tool output from CC hook protocol) ---
OUTPUT=""
if [[ ! -t 0 ]]; then
    if command -v timeout &>/dev/null; then
        OUTPUT=$(timeout 5 cat 2>/dev/null || true)
    else
        OUTPUT=$(cat 2>/dev/null || true)
    fi
fi

[[ -z "$OUTPUT" ]] && exit 0

# --- Size check ---
char_count=${#OUTPUT}
[[ $char_count -lt $MIN_CHARS ]] && exit 0

# --- Load user config if present ---
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    _cfg_enabled=$(jq -r '.enabled // true' "$CONFIG_FILE" 2>/dev/null)
    [[ "$_cfg_enabled" == "false" ]] && exit 0
    _cfg_min=$(jq -r '.min_chars // empty' "$CONFIG_FILE" 2>/dev/null)
    [[ -n "$_cfg_min" ]] && MIN_CHARS="$_cfg_min"
    [[ $char_count -lt $MIN_CHARS ]] && exit 0
fi

# --- Content type detection ---
content_type="text"
compressed=""
line_count=$(echo "$OUTPUT" | wc -l | tr -d ' ')

# JSON array detection
if command -v jq &>/dev/null; then
    jq_type=$(echo "$OUTPUT" | jq -r 'type' 2>/dev/null || echo "")
    if [[ "$jq_type" == "array" ]]; then
        arr_len=$(echo "$OUTPUT" | jq 'length' 2>/dev/null || echo 0)
        if [[ $arr_len -gt $MIN_ARRAY_ITEMS ]]; then
            content_type="json_array"
            # Compress: first 2 + last 2 items + metadata
            compressed=$(echo "$OUTPUT" | jq -c '{
                _octopus_compressed: true,
                total_items: length,
                sample_keys: (if length > 0 then (.[0] | keys? // []) else [] end),
                first_items: .[:2],
                last_items: .[-2:],
                summary: "\(length) items total, showing first 2 and last 2"
            }' 2>/dev/null || echo "")
        fi
    elif [[ "$jq_type" == "object" ]]; then
        key_count=$(echo "$OUTPUT" | jq 'keys | length' 2>/dev/null || echo 0)
        if [[ $key_count -gt 20 ]]; then
            content_type="json_object"
            compressed=$(echo "$OUTPUT" | jq -c '{
                _octopus_compressed: true,
                total_keys: (keys | length),
                keys: (keys[:15]),
                summary: "\(keys | length) keys, showing first 15"
            }' 2>/dev/null || echo "")
        fi
    fi
fi

# HTML detection
if [[ "$content_type" == "text" ]] && echo "$OUTPUT" | head -5 | grep -qi '<html\|<!doctype'; then
    content_type="html"
    # Strip tags, keep text content, truncate
    stripped=$(echo "$OUTPUT" | sed 's/<[^>]*>//g' | sed '/^[[:space:]]*$/d' | head -30)
    stripped_len=${#stripped}
    compressed="[HTML content, ${char_count} chars → ${stripped_len} chars text extracted]\n${stripped}"
fi

# Log/verbose output detection (many lines with repeated patterns)
if [[ "$content_type" == "text" && $line_count -gt 40 ]]; then
    # Check for timestamp patterns (common in logs)
    ts_lines=$(echo "$OUTPUT" | head -20 | grep -cE '^\[?[0-9]{4}[-/][0-9]{2}|^[0-9]{2}:[0-9]{2}|^\w{3}\s+\d{1,2}' || echo 0)
    if [[ $ts_lines -gt 5 ]]; then
        content_type="logs"
    else
        content_type="verbose"
    fi
    # Head + tail compression for both logs and verbose output
    head_lines=$(echo "$OUTPUT" | head -15)
    tail_lines=$(echo "$OUTPUT" | tail -15)
    omitted=$((line_count - 30))
    compressed="${head_lines}\n\n[... ${omitted} lines omitted (${content_type}, ${char_count} chars total) ...]\n\n${tail_lines}"
fi

# --- Skip if no compression produced ---
[[ -z "$compressed" ]] && exit 0

# Estimate token savings (rough: 1 token ≈ 4 chars)
before_tokens=$((char_count / 4))
after_tokens=$((${#compressed} / 4))
saved_tokens=$((before_tokens - after_tokens))
ratio=0
[[ $before_tokens -gt 0 ]] && ratio=$(( (saved_tokens * 100) / before_tokens ))

# --- Log analytics ---
mkdir -p "$ANALYTICS_DIR"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session\":\"${SESSION}\",\"type\":\"${content_type}\",\"before\":${before_tokens},\"after\":${after_tokens},\"saved\":${saved_tokens},\"ratio\":${ratio}}" \
    >> "$ANALYTICS_FILE" 2>/dev/null || true

# --- Output compressed summary as additionalContext ---
# Escape for JSON output
summary="[🐙] compressed ${content_type}: ~${before_tokens}→~${after_tokens} tokens (${ratio}% saved)"

cat <<EOFJSON
{"decision":"continue","additionalContext":"${summary}"}
EOFJSON

exit 0
