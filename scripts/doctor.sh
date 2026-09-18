#!/usr/bin/env bash
# Claude Octopus doctor command wrapper.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_DIR="${PLUGIN_DIR:-$(dirname "$SCRIPT_DIR")}"

source "${SCRIPT_DIR}/lib/doctor.sh"

do_doctor "$@"
