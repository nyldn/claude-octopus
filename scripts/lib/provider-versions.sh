#!/usr/bin/env bash
# Provider CLI version floors — minimum versions for stable orchestration.
# Source this file to access floor constants and octo_version_ok().

OCTO_CODEX_MIN_VERSION="${OCTO_CODEX_MIN_VERSION:-0.100.0}"
OCTO_AGY_MIN_VERSION="${OCTO_AGY_MIN_VERSION:-1.0.6}"
OCTO_QWEN_MIN_VERSION="${OCTO_QWEN_MIN_VERSION:-0.14.0}"
OCTO_GH_MIN_VERSION="${OCTO_GH_MIN_VERSION:-2.0.0}"
OCTO_OPENCODE_MIN_VERSION="${OCTO_OPENCODE_MIN_VERSION:-0.1.0}"

# Ollama model staleness threshold (days). Models older than this raise WARN.
OCTO_OLLAMA_STALE_DAYS="${OCTO_OLLAMA_STALE_DAYS:-30}"

# octo_version_ok INSTALLED MIN
# Returns 0 (ok) if INSTALLED >= MIN, 1 if below floor.
# Unknown version always returns 0 (fail open — don't block users on unknown).
octo_version_ok() {
  local installed="$1" min="$2"
  [[ "$installed" == "unknown" ]] && return 0

  # Use inline IFS assignment (not local IFS) for bash 3.x portability.
  local -a iv mv
  IFS='.' read -ra iv <<< "$installed"
  IFS='.' read -ra mv <<< "$min"

  local i
  for i in 0 1 2; do
    local a="${iv[$i]:-0}" b="${mv[$i]:-0}"
    # Force base-10 to prevent octal interpretation of 08/09.
    (( 10#$a > 10#$b )) && return 0
    (( 10#$a < 10#$b )) && return 1
  done
  return 0
}

# _octo_parse_iso8601 ISO8601_STRING
# Internal helper. Prints epoch seconds, or 0 if parse fails.
# Tries python3 (most portable), then GNU date, then BSD date.
_octo_parse_iso8601() {
  local ts="$1"
  local epoch=0

  if command -v python3 &>/dev/null; then
    # Use python3 stdin script mode (avoids Windows .cmd wrapper mangling of -c args).
    epoch=$(python3 - "$ts" <<'PYEOF' 2>/dev/null
import sys, datetime
try:
    t = sys.argv[1].replace('Z', '+00:00')
    print(int(datetime.datetime.fromisoformat(t).timestamp()))
except Exception:
    print(0)
PYEOF
) || epoch=0
  elif date --version 2>/dev/null | grep -q GNU; then
    epoch=$(date -d "$ts" +%s 2>/dev/null) || epoch=0
  else
    # BSD date (macOS) — strip fractional seconds, +HH:MM offset, and Z suffix
    # F1 pre-mortem fix: BSD date -jf cannot parse Z or +HH:MM, must strip
    local ts_clean="${ts%%.*}"      # strip fractional seconds (if present)
    ts_clean="${ts_clean%+*}"       # strip +HH:MM offset (if present)
    ts_clean="${ts_clean%Z}"        # strip trailing Z (if present)
    epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "$ts_clean" +%s 2>/dev/null) || epoch=0
  fi

  [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0
  printf '%s\n' "$epoch"
}

# octo_ollama_model_age_ok MODIFIED_AT_ISO8601
# Returns 0 (ok) if model age <= OCTO_OLLAMA_STALE_DAYS, 1 if stale.
# Returns 0 (fail open) if date cannot be parsed.
octo_ollama_model_age_ok() {
  local modified_at="$1"
  [[ -z "$modified_at" ]] && return 0

  local model_epoch now_epoch age_days
  model_epoch=$(_octo_parse_iso8601 "$modified_at")
  [[ "$model_epoch" -eq 0 ]] && return 0  # fail open — unparseable date

  now_epoch=$(date +%s)
  age_days=$(( (now_epoch - model_epoch) / 86400 ))
  (( age_days > OCTO_OLLAMA_STALE_DAYS )) && return 1
  return 0
}
