#!/usr/bin/env bash
# Show or persist the lightweight context profile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/lifecycle.sh
source "$SCRIPT_DIR/lib/lifecycle.sh"
# shellcheck source=lib/user-config.sh
source "$SCRIPT_DIR/lib/user-config.sh"

case "${1:-show}" in
    show|status)
        [[ $# -le 1 ]] || { printf 'Usage: %s [show|core|orchestration|full]\n' "$(basename "$0")" >&2; exit 2; }
        octo_lifecycle_profile
        ;;
    core|orchestration|full)
        [[ $# -eq 1 ]] || { printf 'Usage: %s [show|core|orchestration|full]\n' "$(basename "$0")" >&2; exit 2; }
        octo_config_write context_profile "\"$1\""
        persisted="$(octo_config_read context_profile "")"
        if [[ "$persisted" != "$1" ]]; then
            printf 'Unable to persist context profile: %s\n' "$1" >&2
            exit 1
        fi
        printf 'context profile: %s\n' "$1"
        ;;
    --help|-h)
        printf 'Usage: %s [show|core|orchestration|full]\n' "$(basename "$0")"
        ;;
    *)
        printf 'Unknown profile: %s\n' "$1" >&2
        exit 2
        ;;
esac
