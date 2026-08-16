#!/usr/bin/env bash
# Sourced library: sets no shell options, because `set -e`/`set -o pipefail`
# here would leak into the caller's shell and persist after this file returns.
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

# Runtime preferences read by the prompt hooks live in a separate file from the
# setup choices above. Hooks read preferences.json on the UserPromptSubmit path,
# so nothing here may add a second file read to that hot path (#898).
octo_prefs_file() {
  printf '%s/.claude-octopus/preferences.json' "$HOME"
}

# Portable best-effort exclusive lock, matching scripts/lib/events.sh: flock is
# Linux-only, while mkdir is atomic on every POSIX filesystem. Bounded spin so a
# dead holder degrades to "skip the write" rather than hanging setup.
_octo_pref_lock() {
  local lockdir="$1.lock"
  local tries=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    tries=$((tries + 1))
    [[ "$tries" -ge 50 ]] && return 1
    sleep 0.02 2>/dev/null || return 1
  done
  return 0
}

_octo_pref_unlock() {
  rmdir "$1.lock" 2>/dev/null || true
}

# Set a preference key ONLY when it is absent. An explicit user choice, including
# an opt-out, is never overwritten. Value must be valid JSON (e.g. '"suggest"').
#
# The read-check-write sequence holds a lock for its whole duration. Without it,
# a concurrent writer could set auto_router_mode=off between the has() check and
# the rename, and this function would silently clobber that opt-out — the exact
# thing it promises never to do. When the lock cannot be taken, skip the write:
# leaving the preference unset keeps routing dormant, which is the safe side.
# Body of the locked write. Never call this directly: octo_pref_write_default
# owns the lock around it. Multiple early returns live here so the caller can
# keep exactly one unlock path.
_octo_pref_write_locked() {
  local key="$1" value="$2" prefs_file="$3" prefs_dir="$4"
  local current updated tmp

  current="{}"
  if [[ -f "$prefs_file" ]]; then
    # An unreadable existing file must not be treated as empty. Falling back to
    # "{}" here would let the write below replace the file and discard every key
    # the user has, which is the opposite of preserving their settings.
    if ! current=$(cat "$prefs_file" 2>/dev/null); then
      echo "⚠️  Failed to read $prefs_file — preference '$key' not persisted." >&2
      return 0
    fi
    # A corrupt preferences file must not be silently replaced: leaving it alone
    # keeps the user's other keys recoverable and keeps routing dormant.
    if ! printf '%s' "$current" | jq empty 2>/dev/null; then
      echo "⚠️  $prefs_file is not valid JSON — preference '$key' not persisted." >&2
      return 0
    fi
    # Already set (including an explicit opt-out): respect it and stop.
    if printf '%s' "$current" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
      return 0
    fi
  fi

  updated=$(printf '%s' "$current" | jq --arg k "$key" --argjson v "$value" '.[$k] = $v' 2>/dev/null) || {
    echo "⚠️  Failed to set preference '$key'" >&2
    return 0
  }

  # Atomic write at 0600 without leaking the caller's umask.
  tmp=$(mktemp "${prefs_dir}/.preferences.XXXXXX") || return 0
  chmod 600 "$tmp" 2>/dev/null || true
  if printf '%s\n' "$updated" > "$tmp" && mv -f "$tmp" "$prefs_file"; then
    chmod 600 "$prefs_file" 2>/dev/null || true
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  # Warn but succeed, like every other failure path here and like
  # octo_config_write. Persisting a preference is best-effort: a caller running
  # under `set -e` must not have its setup run aborted because one optional
  # write failed. The original file is untouched either way.
  echo "⚠️  Failed to write $prefs_file — preference '$key' not persisted." >&2
  return 0
}

octo_pref_write_default() {
  local key="$1"
  local value="$2"
  local prefs_file prefs_dir rc

  if ! command -v jq &>/dev/null; then
    echo "⚠️  jq not found — preference '$key' not persisted. Install: brew install jq" >&2
    return 0
  fi

  prefs_file="$(octo_prefs_file)"
  prefs_dir="$(dirname "$prefs_file")"
  mkdir -p "$prefs_dir" || return 0

  if ! _octo_pref_lock "$prefs_file"; then
    echo "⚠️  $prefs_file is busy — preference '$key' not persisted." >&2
    return 0
  fi

  # No trap here, deliberately. A sourced library must not install EXIT/INT/TERM
  # traps: they replace the caller's. A RETURN trap is worse — under `set -T`
  # plus `set -u` it stays armed for later returns and then expands an
  # out-of-scope path, aborting the caller. Instead the locked body is a
  # separate function so there is exactly one unlock path here. An interrupt
  # between lock and unlock leaves a stale lock directory; the bounded spin in
  # _octo_pref_lock degrades that to "skip the write", matching
  # scripts/lib/events.sh.
  # The call sits in an `if` condition so a nonzero return cannot trip the
  # caller's `set -e` before the unlock below. A bare call followed by `rc=$?`
  # would exit the shell on a failed write and strand the lock directory.
  if _octo_pref_write_locked "$key" "$value" "$prefs_file" "$prefs_dir"; then
    rc=0
  else
    rc=$?
  fi
  _octo_pref_unlock "$prefs_file"
  return "$rc"
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
