#!/usr/bin/env python3
"""Execute rollback recipes in disposable repositories, without provider calls."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve()
TREES = (".claude/skills", "skills", "codex-skills")


class RollbackRecipes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self.marker = self.base / "called"
        self.env = dict(os.environ, HOME=str(self.base / "home"),
                        GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid",
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull,
                        GIT_CONFIG_NOSYSTEM="1", CLAUDE_PLUGIN_ROOT=str(ROOT),
                        CHECKPOINT_TAG="target", TIMESTAMP="20261112-150000",
                        MARKER=str(self.marker))
        self.env.pop("CODEX_PLUGIN_ROOT", None)
        Path(self.env["HOME"]).mkdir()
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env,
                                       stderr=subprocess.DEVNULL)

    def commit(self, message):
        self.git("add", "--all")
        self.git("commit", "-qm", message)

    def text(self, tree):
        return (ROOT / tree / "skill-rollback/SKILL.md").read_text()

    def blocks(self, text, section, end=None):
        selected = text.split(section, 1)[1]
        if end:
            selected = selected.split(end, 1)[0]
        return re.findall(r"```bash\n(.*?)\n\s*```", selected, re.S)

    def step(self, text, number):
        return self.blocks(text, f"### Step {number}:", f"### Step {number + 1}:")

    def run_recipe(self, command, env=None):
        return subprocess.run(["/bin/bash", "-c", command], cwd=self.repo,
                              env=self.env if env is None else env,
                              capture_output=True, text=True, timeout=10)

    def test_host_roots_preserve_claude_precedence_and_support_codex(self):
        (self.repo / "work.txt").write_text("current\n")
        self.commit("initial")
        claude = self.base / "claude"
        codex = self.base / "codex"
        for name, install in (("claude", claude), ("codex", codex)):
            helper = install / "scripts/helpers/rollback-preflight.py"
            helper.parent.mkdir(parents=True)
            helper.write_text("import os\nfrom pathlib import Path\n"
                              f"Path(os.environ['MARKER']).write_text({name!r})\n"
                              "raise SystemExit(77)\n")
        for tree in TREES:
            for step in (4, 6):
                for hosts, expected in (({"CLAUDE_PLUGIN_ROOT": str(claude)}, "claude"),
                                        ({"CODEX_PLUGIN_ROOT": str(codex)}, "codex"),
                                        ({"CLAUDE_PLUGIN_ROOT": str(claude),
                                          "CODEX_PLUGIN_ROOT": str(codex)}, "claude")):
                    with self.subTest(tree=tree, step=step, hosts=tuple(hosts)):
                        env = {k: v for k, v in self.env.items()
                               if k not in ("CLAUDE_PLUGIN_ROOT", "CODEX_PLUGIN_ROOT")}
                        env.update(hosts)
                        self.marker.unlink(missing_ok=True)
                        result = self.run_recipe(self.step(self.text(tree), step)[0], env)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertTrue(self.marker.exists(), result.stderr)
                        self.assertEqual(self.marker.read_text(), expected)
                        self.assertEqual(self.git("tag", "--list"), b"")

    def test_missing_recovery_timestamp_stops_before_helper_or_restore(self):
        (self.repo / "work.txt").write_text("old\n")
        self.commit("checkpoint")
        self.git("tag", "octo-checkpoint-pre-rollback-")
        (self.repo / "work.txt").write_text("current\n")
        self.commit("current")
        helper = self.repo / os.fsdecode(self.git("rev-parse", "--git-path",
                                                  "octo-rollback-preflight-.py")).strip()
        helper.write_text("import os\nfrom pathlib import Path\n"
                          "Path(os.environ['MARKER']).write_text('unexpected')\n")
        env = dict(self.env)
        env.pop("TIMESTAMP")
        for tree in TREES:
            with self.subTest(tree=tree):
                self.marker.unlink(missing_ok=True)
                before = (self.repo / "work.txt").read_bytes()
                recipe = self.blocks(self.text(tree), "### Recover from the safety checkpoint")[0]
                result = self.run_recipe(recipe, env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("TIMESTAMP", result.stderr)
                self.assertFalse(self.marker.exists())
                self.assertEqual((self.repo / "work.txt").read_bytes(), before)
                self.assertEqual(self.git("diff", "--cached"), b"")

    def test_reviewed_history_is_committed_with_the_restored_snapshot(self):
        for tree in TREES:
            for state_exists in (True, False):
                with self.subTest(tree=tree, state_exists=state_exists), tempfile.TemporaryDirectory() as tmp:
                    original_repo = self.repo
                    self.repo = Path(tmp)
                    try:
                        self.git("init", "-q")
                        (self.repo / "work.txt").write_text("checkpoint\n")
                        state = self.repo / ".octo/STATE.md"
                        if state_exists:
                            state.parent.mkdir()
                            state.write_text("checkpoint history\n")
                        self.commit("checkpoint")
                        self.git("tag", "target")
                        (self.repo / "work.txt").write_text("current\n")
                        self.commit("current")
                        text = self.text(tree)
                        result = self.run_recipe(self.step(text, 6)[0])
                        self.assertEqual(result.returncode, 0, result.stderr)
                        history = self.step(text, 7)
                        result = self.run_recipe(history[0])
                        self.assertEqual(result.returncode, 0, result.stderr)
                        # Read the actual history diff before executing its staging recipe.
                        reviewed = self.git("diff", "--", ".octo/STATE.md")
                        if state_exists:
                            self.assertIn(b"Rollback", reviewed)
                        for command in history[1:]:
                            result = self.run_recipe(command)
                            self.assertEqual(result.returncode, 0, result.stderr)
                        commit = self.blocks(text, "### Step 8:", "### Recover from the safety checkpoint")[0]
                        result = self.run_recipe(commit)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(self.git("show", "HEAD:work.txt"), b"checkpoint\n")
                        self.assertEqual(self.git("status", "--porcelain"), b"")
                        if state_exists:
                            committed = self.git("show", "HEAD:.octo/STATE.md")
                            self.assertIn(b"**Target:** target", committed)
                            self.assertIn(b"octo-checkpoint-pre-rollback-20261112-150000", committed)
                        else:
                            self.assertFalse(state.exists())
                    finally:
                        self.repo = original_repo

    def test_ignored_lessons_leaf_is_preserved_but_real_collisions_still_stop(self):
        for tree in TREES:
            for shape in ("protected-leaf", "ancestor", "descendant", "neighbor"):
                for step in (4, 6):
                    with self.subTest(tree=tree, shape=shape, step=step), tempfile.TemporaryDirectory() as tmp:
                        original_repo = self.repo
                        self.repo = Path(tmp)
                        try:
                            self.git("init", "-q")
                            target = self.repo / (".octo" if shape == "ancestor" else
                                                 ".octo/LESSONS.md/archive.md" if shape == "descendant" else
                                                 ".octo/LESSONS.md")
                            target.parent.mkdir(parents=True, exist_ok=True)
                            target.write_text("old lessons\n")
                            (self.repo / "work.txt").write_text("checkpoint\n")
                            if shape == "neighbor":
                                (self.repo / ".octo/other.md").write_text("old neighbor\n")
                            self.commit("checkpoint")
                            self.git("tag", "target")
                            self.git("rm", "-qr", ".octo")
                            (self.repo / ".gitignore").write_text(".octo/\n")
                            (self.repo / "work.txt").write_text("current\n")
                            self.commit("current")
                            lessons = self.repo / ".octo/LESSONS.md"
                            lessons.parent.mkdir()
                            lessons.write_text("private current lessons\n")
                            neighbor = self.repo / ".octo/other.md"
                            if shape == "neighbor":
                                neighbor.write_text("private neighbor\n")
                            before = self.git("diff", "--cached", "--binary")
                            result = self.run_recipe(self.step(self.text(tree), step)[0])
                            allowed = shape == "protected-leaf"
                            self.assertEqual(result.returncode == 0, allowed, result.stderr)
                            self.assertEqual(lessons.read_text(), "private current lessons\n")
                            self.assertEqual(self.git("ls-files", "--", ".octo/LESSONS.md"), b"")
                            if not allowed:
                                self.assertEqual(self.git("diff", "--cached", "--binary"), before)
                                self.assertEqual((self.repo / "work.txt").read_text(), "current\n")
                                self.assertEqual(self.git("tag", "--list", "octo-checkpoint-pre-rollback-*"), b"")
                            if shape == "neighbor":
                                self.assertEqual(neighbor.read_text(), "private neighbor\n")
                        finally:
                            self.repo = original_repo


if __name__ == "__main__":
    unittest.main()
