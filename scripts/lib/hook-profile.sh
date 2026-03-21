#!/usr/bin/env bash
# Hook profile gating — determines if a hook should run based on active profile
# Profiles: minimal (cost/session only), standard (+ format/typecheck/compact), strict (all hooks)

# Profile: OCTO_HOOK_PROFILE env var (default: standard)
# Override: OCTO_DISABLED_HOOKS comma-separated hook names to skip

[[ -n "${_OCTOPUS_HOOK_PROFILE_LOADED:-}" ]] && return 0
_OCTOPUS_HOOK_PROFILE_LOADED=true

is_hook_enabled() {
  local hook_name="$1"
  local profile="${OCTO_HOOK_PROFILE:-standard}"

  # Check individual override first
  if [[ -n "${OCTO_DISABLED_HOOKS:-}" ]]; then
    if echo ",$OCTO_DISABLED_HOOKS," | grep -q ",$hook_name,"; then
      return 1
    fi
  fi

  # Profile-based gating
  case "$profile" in
    minimal)
      # Only essential hooks: session lifecycle, cost tracking
      case "$hook_name" in
        session-start-memory|session-end|session-sync|octopus-statusline|octopus-hud|telemetry-webhook) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    standard)
      # Everything except expensive review/security gates
      case "$hook_name" in
        security-gate|code-quality-gate|architecture-gate|perf-gate|frontend-gate) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    strict)
      # All hooks enabled
      return 0
      ;;
    *)
      # Unknown profile, default to standard behavior
      return 0
      ;;
  esac
}

get_hook_profile() {
  echo "${OCTO_HOOK_PROFILE:-standard}"
}
