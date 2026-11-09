#!/usr/bin/env python3
"""Inert behavior regressions for workflow sampling, lookup, and waiting."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "scripts/lib"


def shell(script, cwd=ROOT, timeout=12):
    """Run an inert shell fixture with a bounded timeout."""
    return subprocess.check_output(["bash", "-c", script], cwd=cwd,
                                   stderr=subprocess.PIPE, timeout=timeout).decode()


class EfficiencyTests(unittest.TestCase):
    def test_correction_completion_and_failure(self):
        """Notice fast worker completion without waiting for the progress cadence."""
        for rc in (0, 9):
            with tempfile.TemporaryDirectory() as tmp:
                script = f'''source "{LIB}/workflows.sh"
RESULTS_DIR="{tmp}"
log() {{ :; }}
tangle_normal_findings_summary() {{ echo finding; }}
tangle_correction_strategy_prompt() {{ :; }}
tangle_worktree_fingerprint() {{ echo same; }}
tangle_scope_contamination_summary() {{ :; }}
tangle_correction_identity_message() {{ :; }}
get_agent_model() {{ echo inert; }}
run_agent_sync() {{ sleep 0.15; echo partial; return {rc}; }}
OCTOPUS_TANGLE_CORRECTION_POLL_SECS=30
OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW=1
start=$SECONDS
tangle_apply_review_corrections task context findings 1 inert || :
printf '%s\n' "$((SECONDS-start))" "$TANGLE_CORRECTION_STATUS"
cat "$TANGLE_CORRECTION_FILE"
'''
                out = shell(script)
                self.assertLess(int(out.splitlines()[0]), 4)
                self.assertIn("completed" if rc == 0 else "failed-no-progress", out)
                self.assertIn("partial", out)

    def test_retry_policy_and_inert_probe_loop(self):
        # Exercise the actual probe retry loop with file-backed inert captures.
        """Retry recoverable failures while preserving terminal-error behavior."""
        src = (LIB / "workflows.sh").read_text()
        start = src.index('    local auth_deadline=0')
        loop = src[start:src.index('    # Process output', start)]
        cases = [("ERROR: invalid API key", 1),
                 ("ERROR: API key revoked\nERROR: ECONNRESET", 1),
                 ("See auth/credentials.md, issue 401", 1),
                 ("ERROR: not logged in", 1),
                 ("ERROR: sandbox permission denied\nERROR: ECONNRESET", 1),
                 ("ERROR: HTTP 503 Service unavailable", 3),
                 ("ERROR: token refresh failed: connection timeout", 3),
                 ("ERROR: QUOTA_EXHAUSTED\nERROR: ECONNRESET", 1)]
        for diagnostic, expected in cases:
            with tempfile.TemporaryDirectory() as tmp:
                Path(tmp, "diagnostic").write_text(diagnostic)
                script = f'''source "{LIB}/provider-failure.sh"
run() {{
local agent_type=codex seat_timeout=100 max_auth_retries=2 auth_attempt=0 exit_code=0
local temp_input="{tmp}/in" raw_output="{tmp}/out" temp_output="{tmp}/copy" temp_errors="{tmp}/err"
local enhanced_prompt=x
local cmd_array=(inert)
local calls=0
log() {{ :; }}
sleep() {{ :; }}
octopus_capture_provider_output() {{ calls=$((calls+1)); cp "{tmp}/diagnostic" "$temp_errors"; : > "$raw_output"; return 1; }}
{loop}
echo "$calls"
}}
run
'''
                self.assertEqual(int(shell(script).strip()), expected, diagnostic)

    def test_workflows_can_be_sourced_by_basename(self):
        """Resolve workflow imports independently of the source path spelling."""
        output = shell('source workflows.sh; declare -F octopus_provider_failure_classify', cwd=LIB)
        self.assertEqual(output.strip(), 'octopus_provider_failure_classify')

    def test_large_diagnostics_preserve_pipefail_classification(self):
        """Consume large diagnostics without losing their classification to SIGPIPE."""
        for first, expected in [('ERROR: invalid API key', 'terminal'),
                                ('ERROR: ECONNRESET', 'retryable'),
                                ('ERROR: sandbox permission denied', 'other'),
                                ('RATE_LIMIT', 'terminal')]:
            script = f'''set -o pipefail
source "{LIB}/provider-failure.sh"
OCTOPUS_QUOTA_PATTERN=RATE_LIMIT
diagnostic="{first}"
for ((i=0; i<20000; i++)); do diagnostic+=$'\\ncontext line'; done
octopus_provider_failure_classify codex "$diagnostic"
'''
            self.assertEqual(shell(script).strip(), expected)

    def test_stat_fallback_remains_size_sensitive(self):
        """Retain size sensitivity when both stat variants fail."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, 'artifact'); path.write_text('first')
            script = f'''source "{LIB}/heartbeat.sh"
stat() {{ return 1; }}
_octo_capture_file_signature "{path}"
printf 'longer content' > "{path}"
_octo_capture_file_signature "{path}"
'''
            self.assertEqual([line.strip() for line in shell(script).splitlines()], ['5:unknown', '14:unknown'])

    def test_metadata_framing_and_freshness(self):
        """Preserve path framing and observe renames without reading file contents."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            names = ["space name", "line\nname", "unicode-雪", "deleted", "link", "broken", ".octo/runtime"]
            for name in names[:3]:
                (root / name).write_text("data")
            (root / "link").symlink_to("space name")
            (root / "broken").symlink_to("absent")
            paths = names + [names[0]]  # staged/unstaged duplicates stay framed
            def sample():
                """Collect the real metadata sampler output for the current fixture paths."""
                return subprocess.check_output(["python3", str(LIB / "worktree-metadata.py"), tmp],
                    input=b"\0".join(os.fsencode(n) for n in paths) + b"\0")
            expected = b""
            for n in paths:
                if n.startswith(".octo/"):
                    continue
                sig = "missing"
                if (root / n).exists():
                    st = (root / n).lstat()
                    sig = f"{st.st_size}:{st.st_mtime_ns // 1_000_000_000}"
                expected += b"path=" + os.fsencode(n) + b";" + sig.encode() + b"\n"
            self.assertEqual(sample(), expected)
            (root / names[0]).write_text("longer data")
            self.assertNotEqual(sample(), expected)
            (root / names[0]).rename(root / "renamed")
            self.assertIn(b"path=space name;missing", sample())
            stop = threading.Event()
            def rename_repeatedly():
                """Move the fixture path while the sampler observes concurrent changes."""
                while not stop.is_set():
                    (root / "renamed").rename(root / names[0])
                    (root / names[0]).rename(root / "renamed")
            worker = threading.Thread(target=rename_repeatedly)
            worker.start()
            try:
                for _ in range(4):
                    self.assertIn(b"path=space name;", sample())
            finally:
                stop.set()
                worker.join()
            # Sampling failures produce metadata sentinels, never file reads.
            code = f'''import io, runpy, sys, unittest.mock as m
sys.argv = ["sampler", {tmp!r}]
sys.stdin = m.Mock(buffer=io.BytesIO(b"space name\\0"))
with m.patch("os.path.exists", return_value=True), m.patch("os.lstat", side_effect=PermissionError):
 runpy.run_path({str(LIB / "worktree-metadata.py")!r}, run_name="__main__")
'''
            self.assertIn(b"0:unknown", subprocess.check_output(["python3", "-c", code]))

    def test_worktree_digest_matches_original_framing(self):
        """Match the original digest for staged, changed and unusual paths."""
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp, "repo")
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            shell(f'''set -o pipefail
source "{LIB}/heartbeat.sh"
python3() {{ echo unexpected-python >&2; return 97; }}
_octo_capture_worktree_fingerprint "{repo}"
''')
            for name in ("changed", "deleted", "renamed", "space 雪", "line\nname"):
                (repo / name).write_text("before")
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
            (repo / "changed").write_text("after and longer")
            os.utime(repo / "changed", ns=(-500_000_000, -500_000_000))
            (repo / "deleted").unlink()
            (repo / "renamed").rename(repo / "destination")
            (repo / "untracked").write_text("new")
            (repo / ".octo").mkdir()
            (repo / ".octo/runtime").write_text("runtime")
            (repo / "broken").symlink_to("missing")
            baseline = Path(tmp, "old.sh")
            baseline.write_bytes((ROOT / "tests/fixtures/command-workflow-efficiency/metadata-reference.sh").read_bytes())
            before = shell(f'source "{baseline}"; _octo_capture_worktree_fingerprint "{repo}"')
            after = shell(f'source "{LIB}/heartbeat.sh"; _octo_capture_worktree_fingerprint "{repo}"')
            self.assertEqual(before, after)
            # Runtime-only writes must not change the digest.
            (repo / ".octo/runtime").write_text("runtime changed")
            self.assertEqual(after, shell(f'source "{LIB}/heartbeat.sh"; _octo_capture_worktree_fingerprint "{repo}"'))

    def test_fractional_pre_epoch_metadata_matches_stat_and_shell_fallback(self):
        """Keep batch, original and no-Python digests equal across the epoch."""
        reference = ROOT / "tests/fixtures/command-workflow-efficiency/metadata-reference.sh"
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init", "-q", tmp], check=True)
            artifact = repo / "space 雪\nchanged"
            artifact.write_text("before")
            subprocess.run(["git", "-C", tmp, "add", "."], check=True)
            artifact.write_text("after and longer")
            (repo / "link").symlink_to(artifact.name)
            (repo / "broken").symlink_to("missing")
            (repo / ".octo").mkdir()
            (repo / ".octo/runtime").write_text("ignored")
            for ns in (-1_500_000_001, -1_000_000_000, -500_000_000, -1,
                       0, 500_000_000, 1_500_000_001):
                with self.subTest(mtime_ns=ns):
                    os.utime(artifact, ns=(ns, ns))
                    script = f'''source "{reference}"
_octo_capture_worktree_fingerprint "{repo}"
source "{LIB}/heartbeat.sh"
_octo_capture_worktree_fingerprint "{repo}"
command() {{
    [[ "$*" != "-v python3" ]] || return 1
    builtin command "$@"
}}
_octo_capture_worktree_fingerprint "{repo}"
'''
                    original, batch, fallback = shell(script).splitlines()
                    self.assertEqual(batch, original)
                    self.assertEqual(fallback, original)

    def test_ordinary_metadata_does_not_launch_stat(self):
        """Keep whole seconds and post-epoch fractions on the batch fast path."""
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp, "artifact")
            artifact.write_text("data")
            for ns in (-1_000_000_000, 0, 500_000_000):
                with self.subTest(mtime_ns=ns):
                    os.utime(artifact, ns=(ns, ns))
                    code = f'''import io, runpy, sys, unittest.mock as m
sys.argv = ["sampler", {tmp!r}]
sys.stdin = m.Mock(buffer=io.BytesIO(b"artifact\\0"))
with m.patch("subprocess.run", side_effect=AssertionError("unexpected stat subprocess")):
 runpy.run_path({str(LIB / "worktree-metadata.py")!r}, run_name="__main__")
'''
                    expected = f"path=artifact;4:{artifact.lstat().st_mtime_ns // 1_000_000_000}\n"
                    self.assertEqual(subprocess.check_output(["python3", "-c", code]).decode(), expected)

    def test_context_snapshot_is_per_call(self):
        """Reuse one tracked-file snapshot without hiding later index changes."""
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["git", "init", "-q", tmp], check=True)
            for i in range(6):
                p = Path(tmp, str(i), "target.sh")
                p.parent.mkdir()
                p.write_text("fixture")
            subprocess.run(["git", "-C", tmp, "add", "."], check=True)
            out = shell(f'''source "{LIB}/workflows.sh"
PROJECT_ROOT="{tmp}"
git() {{ echo "$*" >> "{tmp}/git-calls"; command git "$@"; }}
tangle_build_repo_context_block "wrong/target.sh wrong/another.py"
''')
            self.assertIn("0/target.sh\n1/target.sh\n2/target.sh\n3/target.sh", out)
            calls = Path(tmp, "git-calls").read_text().splitlines()
            self.assertEqual(sum(line.endswith(" ls-files") for line in calls), 1)
            p = Path(tmp, "another.py")
            p.write_text("fixture")
            subprocess.run(["git", "-C", tmp, "add", "another.py"], check=True)
            out = shell(f'''source "{LIB}/workflows.sh"; PROJECT_ROOT="{tmp}"
tangle_resolve_repo_context_files "wrong/another.py"
''')
            self.assertEqual(out.strip(), "another.py")

    def test_usage_stream_matches_baseline(self):
        # Frozen v11.19.0 output fixtures also work without repository history.
        """Keep report bytes stable while streaming the synthetic usage log."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usage").mkdir()
            (root / "results/run").mkdir(parents=True)
            records = [{"provider": "codex", "model": "gpt-6-astra", "tokens_in": 300000,
                        "tokens_out": 100, "skill": "test", "mcp_server": "fixture"},
                       {"provider": "agy", "tokens_in": 1}]
            (root / "usage/a.jsonl").write_text("\ninvalid\n" + "\n".join(json.dumps(r) for r in records * 1000))
            (root / "results/run/summary.json").write_text('{"workflow":"test","seats":[{"provider":"claude"}]}')
            env = dict(os.environ, OCTOPUS_MODEL_PRICING_FILE=str(ROOT / "config/model-pricing.tsv"))
            for fmt in ("json", "csv", "table"):
                for view in ("usage", "costs"):
                    args = ["--format", fmt, "--view", view, "--usage-dir", str(root / "usage"), "--results-dir", str(root / "results")]
                    old = (ROOT / "tests/fixtures/command-workflow-efficiency" / f"{view}.{fmt}").read_bytes()
                    new = subprocess.check_output(["bash", str(ROOT / "scripts/helpers/usage-report.sh"), *args], env=env)
                    self.assertEqual(old, new)

    def test_usage_append_and_rotation_keep_open_file_semantics(self):
        """Read appended rows from the open file after its pathname rotates."""
        script = (ROOT / "scripts/helpers/usage-report.sh").read_text()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            usage = root / "usage"
            usage.mkdir()
            path = usage / "a.jsonl"
            path.write_text('{"provider":"codex","tokens_in":1}\n')
            body = script.split("python3 - <<'PYEOF'\n", 1)[1].rsplit("\nPYEOF", 1)[0]
            hook = f'''import builtins, os
original_open = builtins.open
target = {str(path)!r}
class RotateOnRead:
 def __init__(self, f): self.f = f; self.changed = False
 def __enter__(self): return self
 def __exit__(self, *args): self.f.close()
 def __iter__(self): return self
 def __next__(self):
  line = next(self.f)
  if not self.changed:
   self.changed = True
   with original_open(target, 'a') as out: out.write('{{"provider":"codex","tokens_in":2}}\\n')
   os.rename(target, target + '.rotated')
   with original_open(target, 'w') as out: out.write('{{"provider":"codex","tokens_in":999}}\\n')
  return line
def hooked_open(path, *args, **kwargs):
 f = original_open(path, *args, **kwargs)
 return RotateOnRead(f) if str(path) == target else f
builtins.open = hooked_open
'''
            env = dict(os.environ, _OCTOPUS_USAGE_DIR=str(usage),
                _OCTOPUS_RESULTS_DIR=str(root / "results"), _OCTOPUS_FORMAT="json",
                _OCTOPUS_VIEW="usage", _OCTOPUS_MODEL_PRICING_FILE=str(ROOT / "config/model-pricing.tsv"))
            output = subprocess.check_output(["python3", "-c", hook + body], env=env)
        totals = json.loads(output)["totals"]
        self.assertEqual(totals["queries"], 2)
        self.assertEqual(totals["tokens_in"], 3)

    def test_yaml_wait_has_one_budget_and_keeps_required_workers(self):
        """Wait for required workers within one shared phase budget."""
        src = (LIB / "yaml-workflow.sh").read_text()
        start = src.index('    # Wait for remaining parallel agents')
        block = src[start:src.index('    # Result files land', start)]
        for completes_at, remaining in [(100, 0), (4, 2)]:
            out = shell(f'''run() {{
local pids=(12 13) phase_name=fixture task_group=fixture
RESULTS_DIR=/nonexistent TIMEOUT=6 OCTOPUS_CONVERGENCE_ENABLED=true
SECONDS=0
log() {{ :; }}
kill() {{ [[ "$1" == -0 ]] || exit 90; (( SECONDS < {completes_at} )); }}
sleep() {{ SECONDS=$((SECONDS + $1)); }}
check_convergence() {{ echo observed; return 0; }}
_yaml_wait_for_pids() {{ echo "remaining=$1"; }}
{block}
}}
run
''')
            self.assertEqual(out.count("observed"), 1)
            self.assertIn(f"remaining={remaining}", out)

    def test_explicit_convergence_files_and_cache(self):
        """Invalidate cached convergence only when the explicit inputs change."""
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp, "a space.md"), Path(tmp, "b\n雪.md")
            a.write_text("# Same\n")
            b.write_text("# Same\n")
            out = shell(f'''source "{LIB}/similarity.sh"
OCTOPUS_CONVERGENCE_ENABLED=true
check_convergence "{a}" "{b}" || exit 1
jaccard_similarity() {{ echo recomputed >&2; return 99; }}
check_convergence "{a}" "{b}" || exit 2
printf '# Different\n' > "{b}"
check_convergence "{a}" "{b}" && exit 3
printf ok
''')
            self.assertEqual(out, "ok")


if __name__ == "__main__":
    unittest.main()
