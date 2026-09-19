#!/usr/bin/env bash
# Claude Octopus doctor command wrapper.
set -eo pipefail

# Preserve the caller's logical path for standalone diagnostics.  The
# orchestrator already resolves its own dispatch path physically; resolving
# it again here would make symlinked checkouts report a different install root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${PLUGIN_DIR:-$(dirname "$SCRIPT_DIR")}"

source "${SCRIPT_DIR}/lib/doctor.sh"

do_doctor "$@"
