#!/usr/bin/env bash
# Validate the report produced after one workflow invocation.
set -euo pipefail
log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*" >&2
}
[[ $# == 3 ]] || { log ERROR "Usage: workflow-result.sh PHASE START_MARKER EXIT_STATUS"; exit 64; }
phase="$1" marker="$2" run_status="$3"
[[ "$run_status" == 0 ]] || { log ERROR "Workflow failed with exit status $run_status"; exit 1; }
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
python3 -I - "$phase" "$marker" "$results_dir" <<'PYTHON'
import os
import pathlib
import re
import stat
import sys

phase, marker, directory = sys.argv[1:]
prefixes = {"define": "grasp-consensus", "develop": "tangle-validation", "deliver": "delivery", "ink": "delivery"}
try:
    prefix = prefixes[phase]
    started = pathlib.Path(marker).stat().st_mtime_ns
    root = pathlib.Path(directory).resolve()
    reports = list(root.glob(prefix + "-*.md"))
    # The launcher owns the line immediately after the title, before any task
    # or provider text. Freshness alone cannot distinguish overlapping writers.
    invocation = ("<!-- octopus-workflow-invocation: " + pathlib.Path(marker).name + " -->\n").encode("utf-8")
    owned = []
    # Pin the directory and inspect the opened file, rather than trusting
    # pathname checks performed before a concurrent writer can replace it.
    root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for report in reports:
            try:
                descriptor = os.open(report.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                                     dir_fd=root_fd)
            except OSError:
                continue
            with os.fdopen(descriptor, "rb") as stream:
                metadata = os.fstat(stream.fileno())
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_mtime_ns <= started:
                    continue
                # Foreign invocations need only a bounded launcher-header read.
                title = stream.readline(256)
                if title.endswith(b"\n") and stream.read(len(invocation)) == invocation:
                    owned.append((report, title + stream.read()))
    finally:
        os.close(root_fd)
    if not owned:
        raise ValueError("report does not belong to this invocation in " + str(root))
    if len(owned) > 1:
        # Feature scheduling emits one development report per coding wave.
        # Validate every wave, then present the last logical wave. Never pick
        # a report by modification time or let later success hide a failure.
        waves = [re.fullmatch(r"tangle-validation-(.+)-wave-([1-9][0-9]*)\.md", p.name)
                 for p, _ in owned]
        if (phase != "develop" or not all(waves) or
                len({wave[1] for wave in waves}) != 1):
            raise ValueError("ambiguous reports from this invocation in " + str(root))
        owned.sort(key=lambda item: int(re.fullmatch(
            r"tangle-validation-(.+)-wave-([1-9][0-9]*)\.md", item[0].name)[2]))
    for report, data in owned:
        # Provider output may be truncated mid-character. Keep byte offsets intact
        # for task framing and replace invalid text only when interpreting content.
        text = data.decode("utf-8", errors="replace")
        if phase == "define":
            # Grasp has no status heading. Its launcher footer identifies the
            # synthesizer, or explicitly records a failed auto-consensus as none.
            footer = next(iter(text.rstrip().splitlines()[-1:]), "")
            match = re.fullmatch(r"\*Consensus built from multiple agent perspectives \(task group: [^;]+; synthesizer: ([^)]+)\)\*", footer)
            valid = bool(match and match[1] != "none")
        elif phase == "develop":
            # The engine length-prefixes the task. Its own status immediately follows
            # that byte frame; task and provider headings cannot become metadata.
            frame = re.match(rb"# TANGLE Phase Validation Report\n<!-- octopus-task-bytes: ([0-9]+) -->\n## Task: ", data)
            status = None
            if frame:
                metadata = data[frame.end() + int(frame[1]):].decode("utf-8", errors="replace")
                status = re.match(r"\n## Generated: [^\n]+\n\n### Quality Gate: ([A-Z]+)\n", metadata)
            valid = bool(status and status[1] in {"PASSED", "WARNING", "CHALLENGED"})
        else:
            # Read metadata after the exact task byte frame, as in development.
            # The final certification remains an independent completion check.
            frame = re.match(rb"# DELIVERY DOCUMENT\n<!-- octopus-task-bytes: ([0-9]+) -->\n## Task: ", data)
            header_complete = None
            if frame:
                metadata = data[frame.end() + int(frame[1]):].decode("utf-8", errors="replace")
                header_complete = re.match(r"\n## Generated: [^\n]+\n## Status: COMPLETE\n\n---\n", metadata)
            parts = text.rsplit("\n## Quality Certification\n", 1)
            footer = parts[-1].splitlines()
            valid = bool(header_complete and len(parts) == 2 and len(footer) == 5 and
                         footer[0] == "- Pre-delivery checks: PASSED" and
                         footer[1].startswith("- Results synthesized: ") and
                         footer[2].startswith("- Context policy: ") and
                         footer[3] == "- Generated by: Claude Octopus Double Diamond" and
                         footer[4].startswith("- Timestamp: "))
        if not valid:
            raise ValueError("report has a failed, missing or unknown completion status: " + str(report))
    print(report)
except (KeyError, OSError, ValueError) as error:
    print("Workflow report validation failed: " + str(error), file=sys.stderr)
    sys.exit(1)
PYTHON
