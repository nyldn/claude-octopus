#!/usr/bin/env bash
# Validate the report produced after one workflow invocation.
set -euo pipefail
[[ $# == 3 ]] || { echo "Usage: workflow-result.sh PHASE START_MARKER EXIT_STATUS" >&2; exit 64; }
phase="$1" marker="$2" run_status="$3"
[[ "$run_status" == 0 ]] || { echo "Workflow failed with exit status $run_status" >&2; exit 1; }
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$plugin_root/scripts/state-manager.sh"
source "$plugin_root/scripts/lib/host-runtime.sh"
workspace="$(resolve_octopus_workspace)"
if [[ "$(octo_detect_host_runtime "$plugin_root")" == codex ]]; then
    session="${CODEX_SESSION_ID:-${CODEX_TASK_ID:-}}"
else
    session="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
fi
results_dir="$workspace/results"
[[ -z "$session" ]] || results_dir="$results_dir/$session"
python3 - "$phase" "$marker" "$results_dir" <<'PYTHON'
import pathlib
import re
import sys

phase, marker, directory = sys.argv[1:]
prefixes = {"define": "grasp-consensus", "develop": "tangle-validation", "deliver": "delivery", "ink": "delivery"}
try:
    prefix = prefixes[phase]
    started = pathlib.Path(marker).stat().st_mtime_ns
    root = pathlib.Path(directory).resolve()
    reports = [p for p in root.glob(prefix + "-*.md")
               if p.is_file() and not p.is_symlink() and p.resolve().parent == root and p.stat().st_mtime_ns > started]
    if not reports:
        raise ValueError("no report from this invocation in " + str(root))
    if len(reports) != 1:
        raise ValueError("ambiguous reports from overlapping invocations in " + str(root))
    report = reports[0]
    text = report.read_text()
    if phase == "define":
        # Grasp has no status heading. Its launcher footer identifies the
        # synthesizer, or explicitly records a failed auto-consensus as none.
        footer = text.rstrip().splitlines()[-1]
        match = re.fullmatch(r"\*Consensus built from multiple agent perspectives \(task group: [^;]+; synthesizer: ([^)]+)\)\*", footer)
        valid = bool(match and match[1] != "none")
    elif phase == "develop":
        status = re.findall(r"^### Quality Gate: (.+)$", text, re.MULTILINE)
        valid = len(status) == 1 and status[0] in {"PASSED", "WARNING", "CHALLENGED"}
    else:
        # Status is launcher-owned in the report header, before provider text.
        valid = text.splitlines()[3:4] == ["## Status: COMPLETE"]
    if not valid:
        raise ValueError("report has a failed, missing or unknown completion status: " + str(report))
    print(report)
except (KeyError, OSError, ValueError) as error:
    print("Workflow report validation failed: " + str(error), file=sys.stderr)
    sys.exit(1)
PYTHON
