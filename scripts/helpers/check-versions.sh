#!/usr/bin/env bash
# Check provider CLI versions against minimum floors.
# Sources scripts/lib/provider-versions.sh for constants and octo_version_ok().
#
# Usage:
#   bash scripts/helpers/check-versions.sh            # human-readable output
#   bash scripts/helpers/check-versions.sh --exit-code # exit 1 if any below floor
#   bash scripts/helpers/check-versions.sh --json      # JSON array output

OCTO_ROOT="${OCTO_ROOT:-$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || echo "${HOME}/.claude-octopus/plugin")}"

# shellcheck source=scripts/lib/provider-versions.sh
source "${OCTO_ROOT}/scripts/lib/provider-versions.sh" 2>/dev/null || {
  echo "ERROR: provider-versions.sh not found at ${OCTO_ROOT}/scripts/lib/" >&2
  exit 1
}

# Portable timeout: prefer gtimeout (macOS via coreutils), fallback to timeout,
# finally run without a timeout if neither exists.
_octo_timeout_cmd=""
if command -v gtimeout >/dev/null 2>&1; then
  _octo_timeout_cmd="gtimeout 3"
elif command -v timeout >/dev/null 2>&1; then
  _octo_timeout_cmd="timeout 3"
fi

# get_version CMD FLAG
# Extracts semver string from --version output; returns "unknown" on timeout/error.
get_version() {
  local cmd="$1" flag="${2:---version}"
  ${_octo_timeout_cmd} "${cmd}" "${flag}" 2>/dev/null \
    | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
}

declare -a CHECK_LINES
declare -a CHECK_STATUSES
ANY_BELOW_FLOOR=0

check_version() {
  local name="$1" cmd="$2" min="$3" flag="${4:---version}"

  # Skip if CLI not installed — version check only applies to present providers.
  command -v "${cmd}" &>/dev/null || return 0

  local ver
  ver=$(get_version "${cmd}" "${flag}")

  if octo_version_ok "${ver}" "${min}"; then
    CHECK_LINES+=("  ✅ ${name} v${ver}")
    CHECK_STATUSES+=("ok")
  else
    CHECK_LINES+=("  ⚠️  ${name} v${ver} (min: v${min})")
    CHECK_STATUSES+=("below_floor")
    ANY_BELOW_FLOOR=1
  fi
}

check_version "codex"     "codex"     "${OCTO_CODEX_MIN_VERSION}"
check_version "gemini"    "gemini"    "${OCTO_GEMINI_MIN_VERSION}"
check_version "qwen"      "qwen"      "${OCTO_QWEN_MIN_VERSION}"
check_version "gh"        "gh"        "${OCTO_GH_MIN_VERSION}"    "--version"
check_version "opencode"  "opencode"  "${OCTO_OPENCODE_MIN_VERSION}"

if [[ "${1:-}" == "--exit-code" ]]; then
  exit "${ANY_BELOW_FLOOR}"
fi

print_json_versions() {
  local count="${#CHECK_LINES[@]}"
  echo "{"
  echo "  \"any_below_floor\": $( [[ $ANY_BELOW_FLOOR -eq 1 ]] && echo true || echo false ),"
  echo "  \"results\": ["
  for i in "${!CHECK_LINES[@]}"; do
    local _json_comma=","
    [[ $((i + 1)) -eq ${count} ]] && _json_comma=""
    _json_label=$(echo "${CHECK_LINES[$i]}" | sed "s/^[[:space:]]*[✅⚠️ ]*//" | xargs)
    _json_status="${CHECK_STATUSES[$i]}"
    echo "    {\"name\": \"${_json_label}\", \"status\": \"${_json_status}\"}${_json_comma}"
  done
  echo "  ]"
  echo "}"
}

if [[ "${1:-}" == "--json" ]]; then
  print_json_versions
  exit 0
fi

# Human-readable output
for line in "${CHECK_LINES[@]}"; do
  echo "$line"
done
if [[ ${#CHECK_LINES[@]} -eq 0 ]]; then
  echo "  (no provider CLIs detected)"
fi
exit "${ANY_BELOW_FLOOR}"