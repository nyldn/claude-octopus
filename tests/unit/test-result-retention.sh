#!/usr/bin/env bash
# Result retention owns stderr sidecars, including those newer than the result.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/semantic-cache.sh"
test_suite "Result transcript retention"

RESULTS_DIR="$TEST_TMP_DIR/results"
DRY_RUN=false
OCTOPUS_RESULT_RETENTION_HOURS=24
log() { :; }
mkdir -p "$RESULTS_DIR/nested space"

# Set explicit ages portably, without depending on GNU touch or BSD date flags.
python3 - "$RESULTS_DIR" <<'PY'
import os
import pathlib
import sys
import time

root = pathlib.Path(sys.argv[1])
for name, age in [
    ("expired.md", 90000), ("expired.stderr.log", 0),
    ("fresh.md", 0), ("fresh.stderr.log", 90000),
    ("probe-synthesis-kept.md", 90000), ("probe-synthesis-kept.stderr.log", 90000),
    ("nested space/expired [seat].md", 90000),
    ("nested space/expired [seat].stderr.log", 0),
    ("linked.md", 90000), ("victim", 0),
    ("expired.marker", 90000), ("dry-run.md", 90000),
    ("dry-run.stderr.log", 90000),
]:
    path = root / name
    path.write_text("fixture\n")
    os.utime(path, (time.time() - age, time.time() - age))
(root / "linked.stderr.log").symlink_to(root / "victim")
PY

test_case "dry runs preserve expired results and transcripts"
DRY_RUN=true cleanup_old_results
if [[ -f "$RESULTS_DIR/dry-run.md" && -f "$RESULTS_DIR/dry-run.stderr.log" ]]; then
    test_pass
else
    test_fail "dry run deleted result artifacts"
fi

cleanup_old_results
test_case "expiry removes matching transcripts regardless of transcript age"
if [[ ! -e "$RESULTS_DIR/expired.md" && ! -e "$RESULTS_DIR/expired.stderr.log" &&
      ! -e "$RESULTS_DIR/nested space/expired [seat].stderr.log" &&
      ! -e "$RESULTS_DIR/dry-run.stderr.log" && ! -e "$RESULTS_DIR/expired.marker" ]]; then
    test_pass
else
    test_fail "expired result artifacts survived cleanup"
fi

test_case "fresh results and retained synthesis keep their transcripts"
if [[ -f "$RESULTS_DIR/fresh.md" && -f "$RESULTS_DIR/fresh.stderr.log" &&
      -f "$RESULTS_DIR/probe-synthesis-kept.md" &&
      -f "$RESULTS_DIR/probe-synthesis-kept.stderr.log" ]]; then
    test_pass
else
    test_fail "cleanup removed a retained result or transcript"
fi

test_case "expiry unlinks a transcript symlink without touching its target"
if [[ ! -L "$RESULTS_DIR/linked.stderr.log" && -f "$RESULTS_DIR/victim" ]]; then
    test_pass
else
    test_fail "transcript symlink survived or its target was deleted"
fi

test_summary
