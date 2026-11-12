#!/usr/bin/env python3
"""Exercise both OpenCode generations without auth, installs, or model calls."""
import json
import os
import signal
import time
from itertools import product
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(os.environ.get("OCTO_TEST_ROOT", Path(__file__).resolve().parents[3]))

from .fixture import OpenCodeFixture

class OpenCodeCases4(OpenCodeFixture):
    def test_fixed_panel_checks_selected_opencode_missing_from_panel(self):
            """A ready Codex panel cannot authorize an unchecked OpenCode login."""
            codex = self.bin / "codex"
            codex.write_text('#!/bin/sh\nexit 70\n')
            codex.chmod(0o755)
            self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(ROOT),
                            OCTOPUS_PREFLIGHT_PROVIDERS="codex",
                            OCTO_ALLOWED_PROVIDERS="codex,opencode", OPENAI_API_KEY="fixture")
            script = r'''
source scripts/lib/preflight.sh
log() { :; }
check_codex_auth_freshness() { :; }
WORKSPACE_DIR="$HOME"
preflight_check false "$SELECTED_SEAT" "$CHECK_CONTEXT"
'''
            for seat, connected, context in product(
                    ("opencode", "opencode-fast", "opencode-research", "opencode:vendor/model"),
                    (False, True), ("static", "dispatch")):
                with self.subTest(seat=seat, connected=connected, context=context):
                    self.marker.unlink(missing_ok=True)
                    self.env.update(SELECTED_SEAT=seat, CHECK_CONTEXT=context,
                                    AUTH_JSON=json.dumps([{"id": "openai", "connections": [
                                        {"type": "environment"}]}] if connected else []))
                    result = self.shell(script)
                    self.assertEqual(result.returncode == 0, connected, result.stdout + result.stderr)
                    self.assertTrue(self.marker.exists(), "selected login was never checked")
            self.marker.unlink(missing_ok=True)
            self.env.update(SELECTED_SEAT="codex", CHECK_CONTEXT="dispatch", AUTH_JSON="[]")
            result = self.shell(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(self.marker.exists(), "unselected OpenCode was probed")

    def test_static_discovery_recognizes_supported_environment_auth_without_probes(self):
            """Discovery and readiness share the established static key evidence."""
            for name, value in product(
                    ("GITHUB_TOKEN", "OPENROUTER_API_KEY", "Z_AI_API_KEY", "MINIMAX_API_KEY"),
                    ("fixture", " \t")):
                with self.subTest(name=name, configured=bool(value.strip())):
                    self.env[name] = value
                    self.marker.unlink(missing_ok=True)
                    result = self.shell('log() { :; }; source scripts/lib/providers.sh; detect_providers')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    expected = "configured" if value.strip() else "none"
                    self.assertIn("opencode:" + expected, result.stdout)
                    readiness = self.readiness("static")
                    self.assertEqual(readiness["status"] == "available", bool(value.strip()))
                    self.assertFalse(self.marker.exists(), "static auth launched OpenCode")
                    self.env.pop(name)

    def test_blank_tokens_do_not_mask_another_supported_environment_login(self):
            """One blank credential must not hide a later supported token."""
            names = ("GITHUB_TOKEN", "OPENROUTER_API_KEY", "Z_AI_API_KEY", "MINIMAX_API_KEY")
            for selected in names:
                with self.subTest(selected=selected):
                    self.env.update({name: " \t\n" for name in names})
                    self.env[selected] = "fixture"
                    self.marker.unlink(missing_ok=True)
                    result = self.shell('log() { :; }; source scripts/lib/providers.sh; detect_providers')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("opencode:configured", result.stdout)
                    self.assertEqual(self.readiness("static")["status"], "available")
                    self.assertFalse(self.marker.exists(), "static checks launched OpenCode")
            self.env.update({name: " \t\n" for name in names})
            self.assertEqual(self.readiness("static")["reason_code"], "auth-missing")

    def test_preflight_missing_project_root_still_permits_isolated_login(self):
            """A missing project path cannot prevent a valid isolated login check."""
            self.env.update(CLI_VERSION="2.0.23", OPENROUTER_API_KEY="fixture",
                            PROJECT_ROOT=str(self.base / "missing-project"), EXPECTED_CWD=str(ROOT))
            self.cli.write_text(self.cli.read_text().replace('printf called >>',
                '[ "$OPENCODE_CONFIG_PROJECT_DISABLE" = 1 ] || exit 69\nprintf called >>', 1))
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true "$SELECTED_SEAT" "$CHECK_CONTEXT"
'''
            for panel, selected, context in (("", "", "static"),
                                             ("", "opencode", "dispatch"),
                                             ("opencode", "opencode", "dispatch")):
                with self.subTest(panel=panel, selected=selected, context=context):
                    self.marker.unlink(missing_ok=True)
                    self.env.update(OCTOPUS_PREFLIGHT_PROVIDERS=panel,
                                    SELECTED_SEAT=selected, CHECK_CONTEXT=context)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), context == "dispatch")

    def test_fixed_panel_leaves_other_providers_static(self):
            """Confirming one login must not launch another panel seat's health probe."""
            other_marker = self.base / "copilot-called"
            copilot = self.bin / "copilot"
            copilot.write_text('#!/bin/sh\ntouch "$OTHER_MARKER"\nexit 0\n')
            copilot.chmod(0o755)
            (self.data / "opencode.db").touch()
            self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(ROOT),
                            OCTOPUS_PREFLIGHT_PROVIDERS="opencode,copilot",
                            OCTO_ALLOWED_PROVIDERS="opencode,copilot",
                            COPILOT_GITHUB_TOKEN="fixture", OTHER_MARKER=str(other_marker))
            result = self.shell(r'''
source scripts/lib/preflight.sh
log() { :; }
WORKSPACE_DIR="$HOME"
preflight_check true "" dispatch
''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(other_marker.exists(), "unselected provider received a live check")

    def test_single_probe_admits_a_pinned_opencode_roster(self):
            """A real single-agent dispatch confirms the pinned roster before work."""
            project = self.base / "single-probe-project"
            project.mkdir()
            admitted = self.base / "admitted"
            self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(project),
                            OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="opencode",
                            ADMITTED_MARKER=str(admitted))
            script = r'''
source scripts/lib/workflows.sh
source scripts/lib/providers.sh
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
research_probe_single_begin() { touch "$ADMITTED_MARKER"; return 77; }
WORKSPACE_DIR="$HOME" PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
probe_single_agent "$REQUESTED_PROVIDER" perspective probe-admission
'''
            for provider, storage, connected, skip in product(
                    ("codex", "claude-sonnet"), ("sqlite", "environment"),
                    (False, True), (False, True)):
                with self.subTest(provider=provider, storage=storage, connected=connected, skip=skip):
                    admitted.unlink(missing_ok=True)
                    self.marker.unlink(missing_ok=True)
                    database = self.data / "opencode.db"
                    database.unlink(missing_ok=True)
                    if storage == "sqlite":
                        database.touch()
                    self.env.update(REQUESTED_PROVIDER=provider,
                                    OCTOPUS_SKIP_PROVIDER_PROBES="true" if skip else "false",
                                    AUTH_JSON=json.dumps([{"id": "openai", "connections": [
                                        {"type": "credential" if storage == "sqlite" else "environment"}]
                                    }] if connected else []))
                    result = self.shell(script)
                    self.assertNotEqual(result.returncode, 0)  # Stop at the admission marker.
                    self.assertEqual(admitted.exists(), connected and not skip,
                                     result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), not skip,
                                     "single-probe admission did not honor its live/skip contract")

    def test_broad_preflight_does_not_probe_unselected_opencode(self):
            """Broad discovery and roster inspection must remain static."""
            self.env["CLI_VERSION"] = "2.0.23"
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true "$REQUESTED_PROVIDER" "$CHECK_CONTEXT"
'''
            for storage, roster, selected, context in product(
                    ("sqlite", "none", "environment"), ("", "opencode"), ("", "codex"), ("static", "dispatch")):
                if context == "dispatch" and roster:
                    continue  # Covered by the workflow admission matrix.
                with self.subTest(storage=storage, roster=roster, selected=selected, context=context):
                    database = self.data / "opencode.db"
                    database.unlink(missing_ok=True)
                    self.env.pop("OPENROUTER_API_KEY", None)
                    if storage == "sqlite":
                        database.touch()
                    elif storage == "environment":
                        self.env["OPENROUTER_API_KEY"] = "fixture"
                    self.env.update(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=roster,
                                    REQUESTED_PROVIDER=selected, CHECK_CONTEXT=context)
                    self.marker.unlink(missing_ok=True)
                    result = self.shell(script)
                    self.assertFalse(self.marker.exists(), result.stdout + result.stderr)
                    self.assertEqual(result.returncode == 0, storage == "environment",
                                     result.stdout + result.stderr)

    def test_selected_opencode_checks_login_despite_broad_cached_success(self):
            """A static cache cannot authorize a selected seat's login."""
            self.env.update(CLI_VERSION="2.0.23", OPENROUTER_API_KEY="fixture", AUTH_JSON="[]")
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true >/dev/null || exit 71
PREFLIGHT_CACHE_TTL=3600
preflight_cache_valid && [[ "$(preflight_cache_read)" == 0 ]] || exit 72
preflight_check false "$SELECTED_SEAT"
'''
            for seat in ("opencode", "opencode-fast", "opencode-research", "opencode:vendor/model", "roster"):
                with self.subTest(seat=seat):
                    self.env["SELECTED_SEAT"] = seat
                    self.env["OCTOPUS_COUNCIL_DEFAULT_PROVIDERS"] = "opencode" if seat == "roster" else ""
                    self.marker.unlink(missing_ok=True)
                    attempt = (script.replace('preflight_check false "$SELECTED_SEAT"',
                                              'preflight_check false "" dispatch') if seat == "roster" else script)
                    result = self.shell(attempt)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertTrue(self.marker.exists(), "cached broad success bypassed selected login")

    def test_background_version_detection_uses_the_worker_directory(self):
            caller = self.base / "caller" / "workspace"
            project = self.base / "project" / "workspace"
            caller.mkdir(parents=True)
            project.mkdir(parents=True)
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
                    self.env["PATH"] = str(self.bin)
                    Path(self.env["COMMAND_FILE"]).unlink(missing_ok=True)
                    self.cli.write_text('#!/bin/sh\nif [ "$PWD" = "$PROJECT_ROOT" ]; then echo "$TARGET_VERSION"; else echo "$CALLER_VERSION"; fi\n')
                    if relative_path:
                        for directory, version in ((caller, caller_version), (project, target_version)):
                            bindir = directory.parent / "bin"
                            bindir.mkdir(exist_ok=True)
                            cli = bindir / "opencode"
                            cli.write_text(f"#!/bin/sh\necho {version}\n")
                            cli.chmod(0o755)
                        self.env["PATH"] = f"../bin:{self.bin}"
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

    def test_live_deadline_includes_startup_and_both_probes(self):
            (self.data / 'auth.json').touch()
            startup = self.base / 'slow-bash'
            startup.write_text('#!/bin/sh\nprintf started >> "$LIVE_STARTUP_MARKER"\n'
                               'sleep 3\nexec ' + shlex.quote(shutil.which('bash')) + ' "$@"\n')
            startup.chmod(0o755)
            self.env.update(LIVE_STARTUP_BASH=str(startup),
                            LIVE_STARTUP_MARKER=str(self.base / 'startup-called'),
                            LIVE_DATE_TOOL=shutil.which('date'), LIVE_ENV_TOOL=shutil.which('env'),
                            VERSION_DELAY='1.25', AUTH_DELAY='1.25')
            # Delay the interpreter selected for the live child, inside its deadline.
            # CLI calls remain below their two-second soft / three-second hard bounds.
            script = r'''
source scripts/lib/preflight.sh
_octo_preflight_system_tool() {
    case "$1" in
        bash) printf '%s\n' "$LIVE_STARTUP_BASH" ;;
        date) printf '%s\n' "$LIVE_DATE_TOOL" ;;
        env) printf '%s\n' "$LIVE_ENV_TOOL" ;;
        *) return 1 ;;
    esac
}
octo_provider_readiness_result opencode live
'''
            for deadline, status in ((None, 'available'), ('5', 'degraded')):
                with self.subTest(deadline=deadline):
                    if deadline is None:
                        self.env.pop('OCTOPUS_PROVIDER_LIVE_TIMEOUT', None)
                    else:
                        self.env['OCTOPUS_PROVIDER_LIVE_TIMEOUT'] = deadline
                    result = self.shell(script, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout)['status'], status)
            self.assertEqual(Path(self.env['LIVE_STARTUP_MARKER']).read_text(), 'startedstarted')

    def test_failed_direct_probe_completes_its_durable_seat(self):
            """Every pre-dispatch rejection closes the durable seat without launching."""
            self.env.update(CLI_VERSION='2.0.23', AUTH_JSON='[]')
            script = r'''
source scripts/lib/workflows.sh
source scripts/lib/providers.sh
source scripts/lib/research-evidence.sh
source scripts/lib/error-tracking.sh
log() { :; }
preflight_check() { :; }
classify_task() { echo research; }
match_routing_rule() { return 1; }
apply_persona() { printf '%s' "$2"; }
enforce_context_budget() { printf '%s' "$1"; }
octo_routing_policy() { echo off; }
get_agent_model() { echo vendor/model; }
get_agent_command() { echo /bin/true; }
validate_agent_command() { :; }
record_agent_call() { :; }
update_metrics() { :; }
bridge_register_task() { :; }
update_agent_status() { printf '%s\n' "$2" >> "$HOME/status-updates"; }
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
octo_dispatch_command_to_argv() { OCTO_COMMAND_ARGV=(/bin/true); }
write_agent_result_prompt() { :; }
octopus_capture_provider_output() { touch "$HOME/launched"; return 1; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
SUPPORTS_AGENT_TYPE_ROUTING=false OCTOPUS_PERSONA_PACKS=off
probe_single_agent opencode perspective probe-123-0 'Check compatibility'
'''
            failures = (
                ("health", "", 1),
                ("command", "get_agent_command() { return 1; }", 1),
                ("command-refused", "get_agent_command() { printf 'OpenCode command refused\\n' >&2; return 125; }", 125),
                ("lookup", "octo_provider_health_handler() { return 77; }", 1),
                ("missing", "octo_provider_health_handler() { echo none; }", 1),
                ("budget", "enforce_context_budget() { return 7; }", 7),
                ("validation", "validate_agent_command() { return 1; }", 1),
                ("environment", "build_provider_env() { return 1; }", 1),
                ("argv", "octo_dispatch_command_to_argv() { return 1; }", 1),
                ("timeout", "octopus_effective_agent_timeout() { return 2; }", 2),
                ("prompt", "write_agent_result_prompt() { return 1; }", 74),
                ("nonce", "od() { return 1; }", 74),
                ("model", "get_agent_model() { return 2; }", 2),
                ("model-no-errexit", "get_agent_model() { return 2; }", 2),
                ("model-invalid", 'source "$PLUGIN_DIR/scripts/lib/dispatch.sh"', 1),
            )
            for task, (failure, override, expected_rc) in enumerate(failures, 123):
                with self.subTest(failure=failure):
                    status_updates = Path(self.env['HOME']) / 'status-updates'
                    status_updates.unlink(missing_ok=True)
                    self.env.update(WORKSPACE_DIR=self.env['HOME'], OCTOPUS_RUN_ID=f'failure-{task}')
                    self.env['AUTH_JSON'] = ('[{"id":"openai","connections":[{"type":"credential"}]}]'
                                             if failure != "health" else '[]')
                    attempt = script.replace('probe-123-0', f'probe-{task}-0')
                    attempt = attempt.replace('probe_single_agent opencode perspective',
                                              override + '\nset -e\nprobe_single_agent opencode perspective')
                    if failure == 'model-no-errexit':
                        attempt = attempt.replace('\nset -e\nprobe_single_agent', '\nset +e\nprobe_single_agent')
                    elif failure == 'model-invalid':
                        attempt = attempt.replace('probe_single_agent opencode perspective',
                                                  "probe_single_agent 'opencode:invalid;model' perspective")
                    result = self.shell(attempt)
                    self.assertEqual(result.returncode, expected_rc, result.stderr)
                    self.assertFalse((Path(self.env['HOME']) / 'launched').exists())
                    events = self.base / f'home/research-runs/flow-{task}/events.jsonl'
                    records = [json.loads(line) for line in events.read_text().splitlines()]
                    self.assertEqual([r['event'] for r in records if r['event'].startswith('provider.')],
                                     ['provider.started', 'provider.completed'])
                    self.assertIn('status=failed', records[-1]['detail'])
                    if failure == 'argv':
                        self.assertEqual(status_updates.read_text().splitlines(), ['running', 'failed'])
                        snapshot = Path(self.env['HOME']) / f'runs/failure-{task}/agents.json'
                        agents = json.loads(snapshot.read_text())['agents']
                        self.assertEqual(len(agents), 1)
                        self.assertEqual(agents[0]['status'], 'failed')
                        self.assertEqual(agents[0]['reason'], 'Provider command argument conversion failed')
                        self.assertTrue(agents[0]['output_file'].endswith(f'opencode-probe-{task}-0.md'))

    def test_legacy_environment_only_login_is_accepted(self):
            self.env.update(AUTH_LIST="└  0 credentials\n┌ Environment\n└  1 environment variable", OPENROUTER_API_KEY="fixture")
            self.assertEqual(self.readiness("live")["status"], "available")

    def test_legacy_expired_summary_is_rejected(self):
            (self.data / "auth.json").touch()
            self.env["AUTH_LIST"] = "3 credentials expired, run login again"
            self.assertEqual(self.readiness("live")["status"], "degraded")

    def test_registry_declares_the_implemented_health_contract(self):
            # This structural validator scans the registry; it makes no provider
            # call. It exceeds eight seconds on the unchanged published tree too.
            result = self.shell('source scripts/lib/provider-registry.sh; octo_provider_validate_contracts && octo_provider_has_capability opencode health && test "$(octo_provider_health_handler opencode)" = check_provider_health', timeout=60)
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
                "env OPENCODE_PURE=1 opencode run --standalone --standalone",
                "env OPENCODE_PURE=1 opencode run --standalone extra",
                "env OPENCODE_PURE=1 opencode run -m vendor/model --standalone",
                "env OPENCODE_PURE=1 opencode run --standalone -m --help",
                "env OPENCODE_PURE=1 opencode run --standalone -m /tmp/model",
            ):
                with self.subTest(command=command):
                    self.env["CANDIDATE_COMMAND"] = command
                    result = self.shell('source scripts/lib/utils.sh; validate_agent_command "$CANDIDATE_COMMAND"')
                    self.assertNotEqual(result.returncode, 0)
            for command in ("env OPENCODE_PURE=1 opencode run",
                            "env OPENCODE_PURE=1 opencode run --standalone",
                            "env OPENCODE_PURE=1 opencode run --standalone -m vendor/model"):
                with self.subTest(command=command):
                    self.env["CANDIDATE_COMMAND"] = command
                    result = self.shell('source scripts/lib/utils.sh; validate_agent_command "$CANDIDATE_COMMAND"')
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_v2_long_account_labels_remain_valid(self):
            (self.data / "opencode.db").touch()
            self.env["CLI_VERSION"] = "2.0.23"
            for label in ("x" * 28, "x" * 45):
                self.env["AUTH_JSON"] = json.dumps([{"id":"openai","connections":[{"type":"credential","label":label}]}])
                self.assertEqual(self.readiness("live")["status"], "available")
