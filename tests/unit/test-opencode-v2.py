#!/usr/bin/env python3
"""Exercise both OpenCode generations without auth, installs, or model calls."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("OCTO_TEST_ROOT", Path(__file__).resolve().parents[2]))


class OpenCodeCompatibility(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.data = self.base / "data" / "opencode"
        self.data.mkdir(parents=True)
        self.marker = self.base / "called"
        self.cli = self.bin / "opencode"
        self.cli.write_text("""#!/bin/sh
printf called >> "$PROBE_MARKER"
if [ "$1" = --version ]; then printf '%s\\n' "${CLI_VERSION:-1.18.34}"; exit 0; fi
if [ "$1" = --pure ]; then exit 64; fi
if [ "$1" = run ]; then
    [ "$OPENCODE_PURE" = 1 ] || exit 65
    printf '%s\\n' "$*"
else
    [ "$1 $2" = 'auth list' ] || exit 66
    case "$*" in
        *--format*) printf '%s\\n' "$AUTH_JSON" ;;
        *) printf '%s\\n' "$AUTH_LIST" ;;
    esac
    exit "${AUTH_RC:-0}"
fi
""")
        self.cli.chmod(0o755)
        self.env = {
            "PATH": str(self.bin) + ":/usr/bin:/bin",
            "HOME": str(self.base / "home"),
            "XDG_DATA_HOME": str(self.base / "data"),
            "PLUGIN_DIR": str(ROOT),
            "PROBE_MARKER": str(self.marker),
            "AUTH_LIST": "└  2 credentials",
            "AUTH_JSON": json.dumps([{"id": "openai", "connections": [{"type": "credential", "label": "Default"}]}]),
            "OCTO_ALLOWED_PROVIDERS": "opencode",
            "OCTOPUS_SKIP_PROVIDER_PROBES": "false",
        }
        Path(self.env["HOME"]).mkdir()

    def shell(self, script, *, root=ROOT):
        return subprocess.run(["bash", "-c", script], env=self.env, cwd=root,
                              text=True, capture_output=True, timeout=8)

    def readiness(self, kind):
        result = self.shell(f'source scripts/lib/preflight.sh; octo_provider_readiness_result opencode {kind}')
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_dispatch_keeps_v1_pure_environment_without_v2_removed_flag(self):
        result = self.shell("source scripts/lib/dispatch.sh; source scripts/lib/utils.sh; get_agent_model() { echo vendor/model; }; cmd=$(get_agent_command opencode); validate_agent_command \"$cmd\" || exit; echo \"$cmd\"")
        self.assertEqual(result.returncode, 0, result.stderr)
        cmd = shlex.split(result.stdout)
        run = subprocess.run(cmd, env=self.env, capture_output=True, text=True, timeout=3)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "run -m vendor/model")

    def test_v2_dispatch_uses_a_private_server(self):
        self.env["CLI_VERSION"] = "2.0.23"
        result = self.shell('source scripts/lib/dispatch.sh; source scripts/lib/utils.sh; get_agent_model() { echo vendor/model; }; cmd=$(get_agent_command opencode); validate_agent_command "$cmd" || exit; echo "$cmd"')
        self.assertEqual(result.returncode, 0, result.stderr)
        run = subprocess.run(shlex.split(result.stdout), env=self.env, capture_output=True, text=True, timeout=3)
        self.assertEqual(run.stdout.strip(), "run --standalone -m vendor/model")

    def test_unknown_generation_refuses_dispatch(self):
        self.env["CLI_VERSION"] = "unknown"
        result = self.shell('source scripts/lib/dispatch.sh; get_agent_model() { echo vendor/model; }; get_agent_command opencode')
        self.assertNotEqual(result.returncode, 0)

    def test_channel_database_is_configuration_evidence(self):
        (self.data / "opencode-dev.db").touch()
        self.assertEqual(self.readiness("static")["reason_code"], "live-check-required")
        self.assertFalse(self.marker.exists())

    def test_legacy_environment_only_login_is_accepted(self):
        self.env.update(AUTH_LIST="└  0 credentials\n┌ Environment\n└  1 environment variable", OPENROUTER_API_KEY="fixture")
        self.assertEqual(self.readiness("live")["status"], "available")

    def test_legacy_expired_summary_is_rejected(self):
        (self.data / "auth.json").touch()
        self.env["AUTH_LIST"] = "3 credentials expired, run login again"
        self.assertEqual(self.readiness("live")["status"], "degraded")

    def test_registry_declares_the_implemented_health_contract(self):
        result = self.shell('source scripts/lib/provider-registry.sh; octo_provider_validate_contracts && octo_provider_has_capability opencode health && test "$(octo_provider_health_handler opencode)" = check_provider_health')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dispatch_validator_rejects_other_environment_and_injection(self):
        for command in (
            "env OPENCODE_PURE=0 opencode run",
            "env OPENCODE_PURE=1 OTHER=1 opencode run",
            "env OPENCODE_PURE=1 sh run",
            "env OPENCODE_PURE=1 opencode auth list",
            "env OPENCODE_PURE=1 opencode run -m vendor/model;touch /tmp/probe",
            "env OPENCODE_PURE=1 opencode run -m $(id)",
            "env OPENCODE_PURE=1 opencode run -m --help",
        ):
            with self.subTest(command=command):
                self.env["CANDIDATE_COMMAND"] = command
                result = self.shell('source scripts/lib/utils.sh; validate_agent_command "$CANDIDATE_COMMAND"')
                self.assertNotEqual(result.returncode, 0)
        result = self.shell('source scripts/lib/utils.sh; validate_agent_command "env OPENCODE_PURE=1 opencode run"')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_v2_long_account_labels_remain_valid(self):
        (self.data / "opencode.db").touch()
        self.env["CLI_VERSION"] = "2.0.23"
        for label in ("x" * 28, "x" * 45):
            self.env["AUTH_JSON"] = json.dumps([{"id":"openai","connections":[{"type":"credential","label":label}]}])
            self.assertEqual(self.readiness("live")["status"], "available")

    def test_static_sqlite_store_requires_live_confirmation_without_cli(self):
        (self.data / "opencode.db").touch()
        result = self.readiness("static")
        self.assertEqual(result["reason_code"], "live-check-required")
        self.assertEqual(result["status"], "degraded")
        self.assertFalse(self.marker.exists())

    def test_live_v2_stored_and_environment_rows_are_recognized(self):
        (self.data / "opencode.db").touch()
        self.env["CLI_VERSION"] = "2.0.23"
        for kind in ("credential", "environment"):
            with self.subTest(kind=kind):
                self.env["AUTH_JSON"] = json.dumps([{"id":"openai","connections":[{"type":kind}]}])
                self.assertEqual(self.readiness("live")["status"], "available")
        self.assertTrue(self.marker.exists())

    def test_empty_failed_and_unknown_listings_never_pass(self):
        (self.data / "opencode.db").touch()
        for listing, rc in [("No authenticated integrations", "0"), ("", "0"),
                            ("unknown output", "0"), (self.env["AUTH_LIST"], "1"),
                            ("0 credentials", "0")]:
            with self.subTest(listing=listing, rc=rc):
                self.env.update(AUTH_LIST=listing, AUTH_RC=rc)
                self.assertEqual(self.readiness("live")["status"], "degraded")

    def test_v2_environment_only_login_is_checked_without_a_store(self):
        self.env.update(CLI_VERSION="2.0.23", OPENAI_API_KEY="fixture")
        self.env["AUTH_JSON"] = '[{"id":"openai","connections":[{"type":"environment"}]}]'
        self.assertEqual(self.readiness("static")["reason_code"], "auth-missing")
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.readiness("live")["status"], "available")
        self.assertTrue(self.marker.exists())

    def test_v2_empty_malformed_or_unknown_connections_are_rejected(self):
        (self.data / "opencode.db").touch()
        self.env["CLI_VERSION"] = "2.0.23"
        for listing in ("[]", "{}", "not json", '[{"id":"openai","connections":[]}]', '[{"id":"openai","connections":[{"type":"unknown"}]}]'):
            with self.subTest(listing=listing):
                self.env["AUTH_JSON"] = listing
                self.assertEqual(self.readiness("live")["status"], "degraded")

    def test_legacy_ansi_credential_summary_passes(self):
        (self.data / "auth.json").write_text("{}")
        self.env["AUTH_LIST"] = "\x1b[32m└  2 credentials\x1b[0m"
        self.assertEqual(self.readiness("live")["status"], "available")

    def test_static_discovery_does_not_execute_cli(self):
        (self.data / "opencode.db").touch()
        result = self.shell('log() { :; }; source scripts/lib/providers.sh; detect_providers')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("opencode:configured", result.stdout)
        self.assertFalse(self.marker.exists())

    def test_database_override_paths_and_memory(self):
        for database in ("named.db", str(self.base / "absolute.db")):
            with self.subTest(database=database):
                self.env["OPENCODE_DB"] = database
                path = Path(database) if database.startswith("/") else self.data / database
                path.touch()
                self.assertEqual(self.readiness("static")["reason_code"], "live-check-required")
                path.unlink()
        self.env["OPENCODE_DB"] = ":memory:"
        self.assertEqual(self.readiness("static")["reason_code"], "auth-missing")

    def test_skip_probes_preserves_no_execution(self):
        (self.data / "opencode.db").touch()
        self.env["OCTOPUS_SKIP_PROVIDER_PROBES"] = "true"
        self.assertEqual(self.readiness("live")["status"], "degraded")
        self.assertFalse(self.marker.exists())

    def test_stalled_login_list_is_bounded(self):
        (self.data / "opencode.db").touch()
        self.cli.write_text("#!/bin/sh\nsleep 20\n")
        self.assertEqual(self.readiness("live")["status"], "degraded")

    def test_provider_allowlist_prevents_live_probe(self):
        (self.data / "opencode.db").touch()
        self.env["OCTO_ALLOWED_PROVIDERS"] = "claude"
        self.assertEqual(self.readiness("live")["reason_code"], "disabled")
        self.assertFalse(self.marker.exists())


if __name__ == "__main__":
    unittest.main()
