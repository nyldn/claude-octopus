#!/usr/bin/env bash
# Exercise the real hooks with inert tool payloads and isolated session state.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid

REPO = Path(sys.argv.pop())


class SafetyContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="octo-safety-contract-")
        self.addCleanup(self.temp.cleanup)
        self.cwd = Path(self.temp.name).resolve()
        self.inside = self.cwd / 'src "quoted"'
        self.inside.mkdir()
        self.outside = self.cwd / "outside"
        self.outside.mkdir()
        (self.inside / "link").symlink_to(self.outside, target_is_directory=True)
        (self.inside / "file-link").symlink_to(self.outside / "missing.txt")
        (self.inside / "loop").symlink_to("loop")
        self.sid = "codex-safety-" + uuid.uuid4().hex
        self.env = {"PATH": os.environ["PATH"], "LANG": "C.UTF-8"}
        self.hook_root = REPO / "hooks"
        self.states = {}
        for mode in ("careful", "freeze"):
            path = Path(f"/tmp/octopus-{mode}-{self.sid}.txt")
            with path.open("x") as state:
                state.write(str(self.inside) if mode == "freeze" else "on")
            self.addCleanup(path.unlink, missing_ok=True)
            self.states[mode] = path

    def invoke(self, mode, tool, tool_input, expected, env=None, compact=False,
               cwd=None, raw=None):
        payload = {"session_id": self.sid, "cwd": str(cwd or self.cwd),
                   "tool_name": tool, "tool_input": tool_input}
        body = raw if raw is not None else json.dumps(
            payload, separators=(",", ":") if compact else None)
        result = subprocess.run(
            ["bash", str(self.hook_root / f"{mode}-check.sh")],
            input=body, text=True, capture_output=True, cwd=REPO,
            env=dict(self.env, **(env or {})), timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        if expected is None:
            self.assertEqual(result.stdout, "")
            return
        self.assertTrue(result.stdout.strip(), f"expected {expected}, got silence")
        try:
            output = json.loads(result.stdout)["hookSpecificOutput"]
        except (ValueError, KeyError) as error:
            self.fail(f"invalid hook response: {result.stdout!r}: {error}")
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertEqual(output["permissionDecision"], expected)
        self.assertTrue(output["permissionDecisionReason"])
        return output["permissionDecisionReason"]

    def patch(self, content, expected=None, **kwargs):
        return self.invoke("freeze", "apply_patch", {"command": content}, expected,
                           **kwargs)

    def test_spaced_bash_claude_ask(self):
        self.invoke("careful", "Bash", {"command": "git reset --hard"}, "ask")

    def test_codex_host_indicators_deny(self):
        for env in ({"OCTOPUS_HOST": "codex"}, {"CODEX_SANDBOX": "seatbelt"},
                    {"CODEX_PLUGIN_ROOT": "/tmp/plugin"},
                    {"PLUGIN_ROOT": "/tmp/.codex/plugins/cache/vendor/pkg/1"},
                    {"CLAUDE_PLUGIN_ROOT": "/tmp/.codex/plugins/cache/vendor/pkg/1"},
                    {"CODEX_HOME": "/tmp/custom-codex", "PLUGIN_ROOT":
                     "/tmp/custom-codex/plugins/cache/vendor/pkg/1"}):
            with self.subTest(env=env):
                reason = self.invoke("careful", "Bash", {"command": "git reset --hard"},
                                     "deny", env=env, compact=True)
                self.assertIn("Codex", reason)
                self.assertIn("/octo:careful", reason)

    def test_codex_home_alone_keeps_claude_ask(self):
        self.invoke("careful", "Bash", {"command": "git reset --hard"}, "ask",
                    env={"CODEX_HOME": "/tmp/inherited", "CLAUDE_PLUGIN_ROOT":
                         "/tmp/.claude/plugins/cache/vendor/pkg/1"}, compact=True)

    def test_installed_codex_cache_location(self):
        self.hook_root = self.cwd / ".codex/plugins/cache/vendor/pkg/1/hooks"
        self.hook_root.mkdir(parents=True)
        for filename in ("careful-check.sh", "safety-contract.py"):
            shutil.copy2(REPO / "hooks" / filename, self.hook_root / filename)
        session_lib = self.hook_root.parent / "scripts/lib"
        session_lib.mkdir(parents=True)
        shutil.copy2(REPO / "scripts/lib/session-id.sh", session_lib / "session-id.sh")
        self.invoke("careful", "Bash", {"command": "git reset --hard"}, "deny",
                    env={"CLAUDE_CODE_SESSION_ID": self.sid})

    def test_missing_python_fails_closed(self):
        binary_dir = self.cwd / "bin"
        binary_dir.mkdir()
        for command in ("bash", "cat", "dirname", "basename"):
            (binary_dir / command).symlink_to(shutil.which(command))
        for mode, name, inputs in (("freeze", "apply_patch", {"command": "bad"}),
                                   ("careful", "Bash", {"command": "git reset --hard"})):
            with self.subTest(mode=mode):
                self.invoke(mode, name, inputs, "deny", env={"PATH": str(binary_dir)})

    def test_all_careful_decisions_and_json_escaping(self):
        for command in ("rm -rf /inert-example", 'psql -c \'DROP TABLE "users"\'',
                        "git push --force", "git reset --hard", "git restore .",
                        "kubectl delete pod example", "docker rm -f example",
                        "docker system prune"):
            for host, decision in (("claude", "ask"), ("codex", "deny")):
                with self.subTest(command=command, host=host):
                    self.invoke("careful", "Bash", {"command": command}, decision,
                                env={"OCTOPUS_HOST": host}, compact=True)

    def test_unrelated_payload_text_is_not_a_command(self):
        self.invoke("careful", "Bash", {"command": "printf safe"}, None,
                    cwd=self.cwd / "git reset --hard")

    def test_spaced_edit_write_and_escaped_paths(self):
        for tool in ("Edit", "Write"):
            for filename, expected in ((self.inside / 'new "file".txt', None),
                                       (self.outside / 'bad "file".txt', "deny")):
                with self.subTest(tool=tool, filename=filename):
                    self.invoke("freeze", tool, {"file_path": str(filename)}, expected)

    def test_patch_all_operations_inside(self):
        self.patch('*** Begin Patch\n*** Add File: new/nested.txt\n+new\n'
                   '*** Update File: old.txt\n*** Move to: moved.txt\n@@\n-old\n+new\n'
                   '*** Delete File: deleted.txt\n*** End Patch', cwd=self.inside)

    def test_every_patch_target_is_checked(self):
        for action in ("*** Add File: ../outside/new.txt\n+new",
                       "*** Update File: ../outside/old.txt\n@@\n-old\n+new",
                       "*** Delete File: ../outside/deleted.txt",
                       "*** Update File: old.txt\n*** Move to: ../outside/moved.txt\n@@\n-old\n+new",
                       "*** Update File: ../outside/old.txt\n*** Move to: moved.txt\n@@\n-old\n+new"):
            with self.subTest(action=action):
                self.patch('*** Begin Patch\n*** Add File: inside.txt\n+ok\n' +
                           action + '\n*** End Patch', "deny", cwd=self.inside)

    def test_path_escape_and_prefix_collision(self):
        for filename in (str(self.inside / "../outside/escape.txt"),
                         str(self.inside) + "-other/file.txt", "../outside/file.txt",
                         "link/new/nested.txt", "file-link", "loop/file.txt"):
            with self.subTest(filename=filename):
                self.patch(f'*** Begin Patch\n*** Add File: {filename}\n+x\n*** End Patch',
                           "deny", cwd=self.inside)
                self.invoke("freeze", "Write", {"file_path": filename}, "deny",
                            cwd=self.inside)

    def test_relative_cwd_and_boundary_canonicalization(self):
        self.states["freeze"].write_text('src "quoted"')
        self.patch('*** Begin Patch\n*** Add File: src "quoted"/new/deep.txt\n+x\n*** End Patch')
        self.states["freeze"].write_text(str(self.inside / "../outside"))
        self.patch('*** Begin Patch\n*** Add File: outside/new.txt\n+x\n*** End Patch')

    def test_patch_heredoc(self):
        self.patch("apply_patch <<'PATCH'\n*** Begin Patch\n*** Add File: new.txt\n+x\n*** End Patch\nPATCH",
                   cwd=self.inside)

    def test_malformed_patch_fails_closed(self):
        for content in ("", "garbage", "*** Begin Patch\n*** End Patch",
                        "*** Begin Patch\n*** Add File: inside.txt\n+x",
                        "*** Begin Patch\n*** Add File: \n+x\n*** End Patch",
                        "*** Begin Patch\n*** Unknown: inside.txt\n*** End Patch",
                        "*** Begin Patch\n*** Add File: inside.txt\nnot a patch line\n*** End Patch",
                        "*** Begin Patch\n*** Add File: inside.txt\n+x\n*** Move to: other.txt\n*** End Patch",
                        "*** Begin Patch\n*** Update File: old.txt\n*** End Patch",
                        "*** Begin Patch\n*** Add File: inside.txt\n+x\n*** End Patch\ntrailing command"):
            with self.subTest(content=content):
                self.patch(content, "deny", cwd=self.inside)
        for value in ({}, {"command": None}, {"command": []}):
            with self.subTest(value=value):
                self.invoke("freeze", "apply_patch", value, "deny")

    def test_malformed_json_and_missing_path_fail_closed(self):
        self.invoke("freeze", "Write", {}, "deny")
        self.invoke("freeze", "apply_patch", {}, "deny", raw='{"tool_name":',
                    env={"CLAUDE_CODE_SESSION_ID": self.sid})

    def test_inactive_modes_and_kill_switches(self):
        self.patch("bad", None, env={"OCTO_FREEZE_MODE": "off"})
        self.invoke("careful", "Bash", {"command": "git reset --hard"}, None,
                    env={"OCTO_CAREFUL_MODE": "off"})
        for state in self.states.values():
            state.unlink()
        self.patch("bad", None)
        self.invoke("careful", "Bash", {"command": "git reset --hard"}, None)

    def test_session_environment_precedence(self):
        for env in ({"OCTOPUS_HOST": "codex", "CODEX_SESSION_ID": self.sid,
                     "CLAUDE_CODE_SESSION_ID": "unrelated"},
                    {"OCTOPUS_HOST": "claude", "CLAUDE_CODE_SESSION_ID": self.sid,
                     "CLAUDE_SESSION_ID": "unrelated"}):
            with self.subTest(env=env):
                self.invoke("freeze", "Write", {"file_path": str(self.outside / "x")},
                            "deny", env=env, raw=json.dumps({"session_id": "other",
                            "tool_name": "Write", "tool_input": {"file_path":
                            str(self.outside / "x")}}))


def interrupted(signum, frame):
    raise KeyboardInterrupt


signal.signal(signal.SIGTERM, interrupted)
unittest.main(verbosity=2)
PY
