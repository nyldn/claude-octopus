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
if [ "$1" = --version ]; then sleep "${VERSION_DELAY:-0}"; printf '%s\\n' "${CLI_VERSION:-1.18.34}"; exit 0; fi
if [ "$1" = --pure ]; then exit 64; fi
if [ "$1" = run ]; then
    [ "$OPENCODE_PURE" = 1 ] || exit 65
    printf '%s\\n' "$*"
else
    [ "$1 $2" = 'auth list' ] || exit 66
    sleep "${AUTH_DELAY:-0}"
    if [ -n "${AUTH_LIST_FILE:-}" ]; then cat "$AUTH_LIST_FILE"; exit 0; fi
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

    def test_probe_single_checks_login_before_constructing_command(self):
        self.env.update(CLI_VERSION="2.0.23", DISPATCH_MARKER=str(self.base / "dispatch"))
        script = r'''
source scripts/lib/workflows.sh
source scripts/lib/providers.sh
log() { :; }
preflight_check() { :; }
classify_task() { echo research; }
match_routing_rule() { return 1; }
apply_persona() { printf '%s' "$2"; }
enforce_context_budget() { printf '%s' "$1"; }
octo_routing_policy() { echo off; }
get_agent_model() { echo vendor/model; }
get_agent_command() { echo command > "$DISPATCH_MARKER"; return 77; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
SUPPORTS_AGENT_TYPE_ROUTING=false OCTOPUS_PERSONA_PACKS=off
probe_single_agent opencode perspective login-test
'''
        for provider in ('opencode', 'opencode-fast', 'opencode-research'):
            for connected in (False, True):
                with self.subTest(provider=provider, connected=connected):
                    Path(self.env["DISPATCH_MARKER"]).unlink(missing_ok=True)
                    self.marker.unlink(missing_ok=True)
                    self.env["AUTH_JSON"] = ('[{"id":"openai","connections":[{"type":"credential"}]}]'
                                             if connected else "[]")
                    result = self.shell(script.replace('probe_single_agent opencode ',
                                                      f'probe_single_agent {provider} '))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(Path(self.env["DISPATCH_MARKER"]).exists(), connected)
                    self.assertTrue(self.marker.exists())

    def test_workflow_admission_confirms_sqlite_and_environment_logins(self):
        project = self.base / "admission-project"
        project.mkdir()
        self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(project))
        self.cli.write_text(self.cli.read_text().replace(
            'printf called >>', '[ "$PWD" = "$PROJECT_ROOT" ] || exit 67\nprintf called >>', 1))
        script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true
'''
        for storage in ("sqlite", "environment"):
            database = self.data / "opencode.db"
            if storage == "sqlite":
                database.touch()
            else:
                database.unlink()
                self.env["OPENAI_API_KEY"] = "fixture"
            for roster in ("", "opencode"):
                for connected in (False, True):
                    with self.subTest(storage=storage, roster=roster, connected=connected):
                        self.marker.unlink(missing_ok=True)
                        self.env["OCTOPUS_COUNCIL_DEFAULT_PROVIDERS"] = roster
                        self.env["AUTH_JSON"] = json.dumps([
                            {"id": "openai", "connections": [{"type": "credential" if storage == "sqlite" else "environment"}]}
                        ] if connected else [])
                        result = self.shell(script)
                        self.assertEqual(result.returncode == 0, connected, result.stdout + result.stderr)
                        self.assertTrue(self.marker.exists(), "admission never checked login")
            self.env["OCTOPUS_SKIP_PROVIDER_PROBES"] = "true"
            self.marker.unlink(missing_ok=True)
            self.assertNotEqual(self.shell(script).returncode, 0)
            self.assertFalse(self.marker.exists())
            self.env["OCTOPUS_SKIP_PROVIDER_PROBES"] = "false"

    def test_background_version_detection_uses_the_worker_directory(self):
        caller = self.base / "caller"
        project = self.base / "project"
        caller.mkdir()
        project.mkdir()
        self.env.update(PROJECT_ROOT=str(project), COMMAND_FILE=str(self.base / "command"),
                        HEALTH_DIRECTORY=str(self.base / "health-directory"))
        script = r'''
source "$PLUGIN_DIR/scripts/lib/spawn.sh"
source "$PLUGIN_DIR/scripts/lib/dispatch.sh"
for helper in log match_routing_rule load_agent_checkpoint load_earned_skills build_provider_context octo_spawn_contract_plan octo_spawn_contract_resolve octo_spawn_contract_authenticated octo_spawn_contract_finish; do
    eval "$helper() { :; }"
done
check_provider_health() { pwd > "$HEALTH_DIRECTORY"; }
octo_spawn_contract_seat_id() { echo spawn-fixture; }
classify_task() { echo standard; }
apply_persona() { printf %s "$2"; }
octo_with_engineering_methods() { printf %s "$2"; }
enforce_context_budget() { printf %s "$1"; }
octopus_effective_agent_timeout() { echo 0; }
get_agent_model() { echo vendor/model; }
validate_agent_command() { printf %s "$1" > "$COMMAND_FILE"; return 1; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
spawn_agent opencode fixture fixture reviewer probe
'''
        for relative_path, target_version in ((False, "2.0.23"), (False, "1.18.34"),
                                               (True, "2.0.23"), (True, "1.18.34")):
            with self.subTest(relative_path=relative_path, target_version=target_version):
                caller_version = "1.18.34" if target_version.startswith("2.") else "2.0.23"
                self.env.update(TARGET_VERSION=target_version, CALLER_VERSION=caller_version)
                self.env["PATH"] = str(self.bin) + ":/usr/bin:/bin"
                Path(self.env["COMMAND_FILE"]).unlink(missing_ok=True)
                self.cli.write_text('#!/bin/sh\nif [ "$PWD" = "$PROJECT_ROOT" ]; then echo "$TARGET_VERSION"; else echo "$CALLER_VERSION"; fi\n')
                if relative_path:
                    for directory, version in ((caller, caller_version), (project, target_version)):
                        bindir = directory / "bin"
                        bindir.mkdir(exist_ok=True)
                        cli = bindir / "opencode"
                        cli.write_text(f"#!/bin/sh\necho {version}\n")
                        cli.chmod(0o755)
                    self.env["PATH"] = "bin:/usr/bin:/bin"
                result = self.shell(script, root=caller)
                self.assertNotEqual(result.returncode, 0)
                command_file = Path(self.env["COMMAND_FILE"])
                self.assertTrue(command_file.exists(), result.stderr)
                self.assertEqual("--standalone" in shlex.split(command_file.read_text()),
                                 target_version.startswith("2."))
                self.assertEqual(Path(self.env["HEALTH_DIRECTORY"]).read_text().strip(), str(project))

    def test_channel_database_is_configuration_evidence(self):
        (self.data / "opencode-dev.db").touch()
        self.assertEqual(self.readiness("static")["reason_code"], "live-check-required")
        self.assertFalse(self.marker.exists())

    def test_direct_probe_dry_run_stops_before_preflight_and_dispatch(self):
        self.env.update(DRY_RUN='true', PREFLIGHT_MARKER=str(self.base / 'preflight'))
        script = r'''
source scripts/lib/workflows.sh
source scripts/lib/providers.sh
log() { printf '%s\n' "$*"; }
preflight_check() { echo called > "$PREFLIGHT_MARKER"; return 77; }
probe_single_agent "$PREVIEW_PROVIDER" perspective preview-task
'''
        for provider in ('opencode', 'codex'):
            with self.subTest(provider=provider):
                self.env['PREVIEW_PROVIDER'] = provider
                result = self.shell(script)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('[DRY-RUN]', result.stdout)
                self.assertFalse(Path(self.env['PREFLIGHT_MARKER']).exists())
                self.assertFalse(self.marker.exists())

    def test_large_legacy_listing_is_consumed_under_pipefail(self):
        listing = self.base / 'listing.txt'
        listing.write_text('└  2 credentials\n' + 'account metadata\n' * 20000)
        self.env['AUTH_LIST_FILE'] = str(listing)
        result = self.shell('set -o pipefail; source scripts/lib/auth.sh; _octo_opencode_has_saved_login')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_live_deadline_includes_shell_startup_and_both_probes(self):
        (self.data / 'auth.json').touch()
        startup = self.base / 'startup.sh'
        startup.write_text('case "${1:-}" in */providers.sh) sleep 4.5 ;; esac\n')
        self.env.update(BASH_ENV=str(startup), VERSION_DELAY='0.5', AUTH_DELAY='0.5')
        self.assertEqual(self.readiness('live')['status'], 'available')
        # An explicit short user deadline still takes precedence.
        self.env['OCTOPUS_PROVIDER_LIVE_TIMEOUT'] = '1'
        self.assertEqual(self.readiness('live')['status'], 'degraded')

    def test_failed_direct_probe_completes_its_durable_seat(self):
        self.env.update(CLI_VERSION='2.0.23', AUTH_JSON='[]')
        script = r'''
source scripts/lib/workflows.sh
source scripts/lib/providers.sh
source scripts/lib/research-evidence.sh
log() { :; }
preflight_check() { :; }
classify_task() { echo research; }
match_routing_rule() { return 1; }
apply_persona() { printf '%s' "$2"; }
enforce_context_budget() { printf '%s' "$1"; }
octo_routing_policy() { echo off; }
get_agent_model() { echo vendor/model; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
SUPPORTS_AGENT_TYPE_ROUTING=false OCTOPUS_PERSONA_PACKS=off
probe_single_agent opencode perspective probe-123-0 'Check compatibility'
'''
        result = self.shell(script)
        self.assertNotEqual(result.returncode, 0)
        events = self.base / 'home/results/research-runs/flow-123/events.jsonl'
        records = [json.loads(line) for line in events.read_text().splitlines()]
        self.assertEqual([r['event'] for r in records if r['event'].startswith('provider.')],
                         ['provider.started', 'provider.completed'])
        self.assertIn('status=failed', records[-1]['detail'])

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

    def test_v2_login_without_jq_still_validates_connection_structure(self):
        self.env["CLI_VERSION"] = "2.0.23"
        script = r'''
source scripts/lib/auth.sh
command() {
    if [[ "$1" == -v && "${2:-}" == jq ]]; then return 1; fi
    builtin command "$@"
}
jq() { return 127; }
_octo_opencode_has_saved_login
'''
        for listing, valid in (
            ('[{"id":"openai","connections":[{"type":"credential"}]}]', True),
            ('[{"id":"openai","connections":[{"type":"environment"}]}]', True),
            ('[]', False), ('{}', False), ('not json', False),
            ('[{"id":"openai","connections":[]}]', False),
            ('[{"id":"","connections":[{"type":"credential"}]}]', False),
            ('[{"id":"openai","connections":[{"type":"unknown"}]}]', False),
            ('[{"id":"openai","connections":[null]}]', False),
        ):
            with self.subTest(listing=listing):
                self.env["AUTH_JSON"] = listing
                result = self.shell(script)
                self.assertEqual(result.returncode == 0, valid, result.stderr)
                self.assertEqual(result.stdout + result.stderr, "")

    def test_json_fallback_ignores_project_modules_and_pythonpath(self):
        shadow = self.base / "project"
        shadow.mkdir()
        imported = self.base / "shadow-imported"
        (shadow / "json.py").write_text(
            f'from pathlib import Path\nPath({str(imported)!r}).touch()\n'
            'raise RuntimeError("project module must not load")\n')
        self.env["PYTHONPATH"] = str(shadow)
        result = self.shell(r'''
source "$PLUGIN_DIR/scripts/lib/auth.sh"
command() {
    if [[ "$1" == -v && "${2:-}" == jq ]]; then return 1; fi
    builtin command "$@"
}
jq() { return 127; }
_octo_opencode_cli_major() { echo 2; }
_octo_run_bare_probe_with_timeout() { shift 3; "$@"; }
_octo_opencode_has_saved_login
''', root=shadow)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(imported.exists(), "JSON validation loaded a project module")
        self.assertEqual(result.stdout + result.stderr, "")

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

    def test_skip_probes_blocks_version_login_and_dispatch_for_both_true_values(self):
        self.env["CLI_VERSION"] = "2.0.23"
        for value in ("true", "1"):
            for command in ("_octo_opencode_cli_major", "_octo_opencode_has_saved_login",
                            "get_agent_command opencode"):
                with self.subTest(value=value, command=command):
                    self.marker.unlink(missing_ok=True)
                    self.env["OCTOPUS_SKIP_PROVIDER_PROBES"] = value
                    result = self.shell('source scripts/lib/auth.sh; source scripts/lib/dispatch.sh; '
                                        'log() { :; }; get_agent_model() { echo vendor/model; }; ' + command)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(self.marker.exists(), "disabled probe executed OpenCode")

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
