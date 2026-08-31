#!/usr/bin/env bash
set -euo pipefail

# Claude Octopus — provider availability compatibility renderer.
# The shared readiness evaluator owns installation, auth/config, allowlist,
# quota, and live-health decisions. This script preserves the documented
# PROVIDER_CHECK_START / name:state / PROVIDER_CHECK_END protocol.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Marketplace installs may not have the plugin-root symlink until SessionStart.
bash "${SCRIPT_DIR}/ensure-plugin-root.sh" 2>/dev/null || true

if ! declare -f log >/dev/null 2>&1; then
    log() { :; }
fi

source "${SCRIPT_DIR}/../lib/preflight.sh"

# Warn about the retired direct Gemini route without changing machine output.
if type -P gemini >/dev/null 2>&1 && ! command -v agy >/dev/null 2>&1; then
    echo "WARNING: gemini CLI found but Antigravity (agy) is not installed — gemini* seats route through agy. Install Antigravity to restore Google seats." >&2
fi

check_kind="static"
[[ "${OCTOPUS_PREFLIGHT_PROBE:-0}" == "1" ]] && check_kind="live"
octo_provider_readiness_legacy "$check_kind"
