#!/usr/bin/env bash
# Whole-block filtering must preserve an applicable patch for retained files.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "REVIEW.md skip globs"
source "$ROOT/scripts/lib/review.sh"
log() { :; }
mkdir -p "$TEST_TMP_DIR/settings"
printf '## Skip\n- src/gen/\n- `*.lock`\n' > "$TEST_TMP_DIR/settings/REVIEW.md"
parse_review_md "$TEST_TMP_DIR/settings"
test_case "REVIEW.md exposes the documented directory and glob entries"
if [[ "$REVIEW_SKIP_PATTERNS" == $'src/gen/\n`*.lock`\n' ]]; then test_pass
else test_fail "skip patterns were not read from REVIEW.md"; fi
export SKIP_TEST_ROOT="$TEST_TMP_DIR" SKIP_FILTER="$ROOT/scripts/helpers/review-diff-filter.py"
test_case "real Git patches retain hunks and filter paths across change types"
if python3 - <<'PY'
import os
from pathlib import Path
import subprocess

root = Path(os.environ["SKIP_TEST_ROOT"]) / "skip-repo"
root.mkdir()
def git(*args, **kwargs):
    return subprocess.run(["git", *args], cwd=root, check=True, stdout=subprocess.PIPE, **kwargs).stdout
git("init", "-q")
git("config", "user.email", "test@example.com")
git("config", "user.name", "Octopus Test")
files = ["app.ts", "src/gen/client.ts", "src/gen/deleted.ts", "src/gen/binary file.bin",
         "src/gen/café\tfile.ts", "old.ts", "src/gen/leaving.ts", "nested/package.lock",
         "src/gen/mode.sh", "retained binary.bin", 'src/gen/" b/file.bin',
         'src/gen/" b/mode.sh']
for name in files:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\0old\n" if name.endswith(".bin") else (name + "\n").encode())
git("add", ".")
git("commit", "-qm", "fixture")
for name in files:
    if name in ("old.ts", "src/gen/leaving.ts", "src/gen/mode.sh", 'src/gen/" b/mode.sh'):
        continue
    (root / name).write_bytes(b"\0new\n" if name.endswith(".bin") else b"new\n")
(root / "app.ts").write_text('import "src/gen/client";\nconst lock = "package.lock";\n')
(root / "src/gen/deleted.ts").unlink()
(root / "old.ts").rename(root / "src/gen/arrived.ts")
(root / "src/gen/leaving.ts").rename(root / "retained.ts")
(root / "src/gen/mode.sh").chmod(0o755)
(root / 'src/gen/" b/mode.sh').chmod(0o755)
git("add", "-A")
for quote_path in ("true", "false"):
    git("config", "core.quotePath", quote_path)
    patch = git("diff", "--cached", "--binary", "--find-renames")
    filtered = subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "src/gen/\n`*.lock`\n"], input=patch)
    expected = b"".join(b"diff --git " + block for block in patch.split(b"diff --git ")[1:]
                       if block.startswith((b"a/app.ts b/app.ts\n", b"a/src/gen/leaving.ts b/retained.ts\n",
                                            b"a/retained binary.bin b/retained binary.bin\n")))
    assert b"rename to retained.ts" in expected, "fixture did not produce a rename"
    assert filtered == expected, (filtered, expected)
    git("apply", "--reverse", "--check", input=filtered)
    assert b'import "src/gen/client";' in filtered
    assert b'const lock = "package.lock";' in filtered
    assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "*"], input=patch) == b""
    assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "absent/*"], input=patch) == patch
plain = b"--- other\n+++ other\n@@ -1 +1 @@\n-old\n+new\n"
assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "*"], input=plain) == plain
# No-prefix paths can themselves begin with a/ or b/. Additions, deletions,
# binary/mode-only records and C-quoted names must keep their actual paths.
added = ["added.ts", "a/actual.ts", "b/actual.ts"]
for name in added:
    (root / name).parent.mkdir(parents=True, exist_ok=True)
    (root / name).write_text("new file\n")
git("add", "-A")
for quote_path in ("true", "false"):
    git("config", "core.quotePath", quote_path)
    for name in files + added + ["src/gen/arrived.ts", "retained.ts"]:
        unprefixed = git("diff", "--cached", "--binary", "--no-prefix", "--", name)
        assert unprefixed, ("missing no-prefix fixture", name)
        assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], name], input=unprefixed) == b"", name
        assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "absent/*"], input=unprefixed) == unprefixed
directory_cases = ["packages/client/gen/client.ts", "packages/server/gen/deep/client.ts",
                   "packages/client/gen/quoted\tfile.bin", "packages/client/app.ts",
                   "packages/client/genesis/keep.ts"]
for name in directory_cases:
    (root / name).parent.mkdir(parents=True, exist_ok=True)
    (root / name).write_bytes(b"\0generated\n" if name.endswith(".bin") else b"new file\n")
git("add", "-A")
for quote_path in ("true", "false"):
    git("config", "core.quotePath", quote_path)
    for no_prefix in ([], ["--no-prefix"]):
        for name in directory_cases:
            patch = git("diff", "--cached", "--binary", *no_prefix, "--", name)
            for pattern in ("packages/*/gen/", "packages/[cs]*/g?n/"):
                actual = subprocess.check_output(["python3", os.environ["SKIP_FILTER"], pattern], input=patch)
                assert actual == (b"" if "/gen/" in name else patch), (pattern, name)
custom = git("diff", "--cached", "--src-prefix=before/", "--dst-prefix=after/", "--", "app.ts")
assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "*"], input=custom) == custom
# Standard rename/copy headers can accidentally have identical byte halves.
# Destination metadata must win over the no-prefix shortcut.
for change in ("rename", "copy"):
    root = Path(os.environ["SKIP_TEST_ROOT"]) / (change + "-repo")
    root.mkdir()
    git("init", "-q")
    git("config", "user.email", "test@example.com")
    git("config", "user.name", "Octopus Test")
    (root / "foo").write_text("source content\n")
    git("add", ".")
    git("commit", "-qm", "fixture")
    destination = root / "bar a/foo b/bar"
    destination.parent.mkdir(parents=True)
    if change == "rename":
        (root / "foo").rename(destination)
    else:
        destination.write_bytes((root / "foo").read_bytes())
    git("add", "-A")
    for no_prefix in ([], ["--no-prefix"]):
        patch = git("diff", "--cached", "--find-renames", "--find-copies-harder", *no_prefix)
        assert (change + " to bar a/foo b/bar").encode() in patch, patch
        for pattern in ("a/", "foo"):
            assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], pattern], input=patch) == patch
        assert subprocess.check_output(["python3", os.environ["SKIP_FILTER"], "bar a/"], input=patch) == b""
usage = subprocess.run(["python3", os.environ["SKIP_FILTER"]], capture_output=True)
assert usage.returncode != 0 and b"Usage:" in usage.stderr and b"Traceback" not in usage.stderr
PY
then test_pass; else test_fail "filtered patch lost retained bytes or kept skipped blocks"; fi
test_summary
