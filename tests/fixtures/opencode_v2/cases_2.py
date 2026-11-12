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

class OpenCodeCases2(OpenCodeFixture):
    def test_login_probe_rejects_project_executable_before_running_it(self):
            project = self.base / "project"
            bindir = project / "bin"
            bindir.mkdir(parents=True)
            cli = bindir / "opencode"
            cli.write_text(self.cli.read_text())
            cli.chmod(0o755)
            self.env.update(PROJECT_ROOT=str(project), MISTRAL_API_KEY="fixture",
                            PATH=f"bin:{self.bin}")
            for action in ("_octo_opencode_cli_major", "_octo_opencode_has_saved_login"):
                with self.subTest(action=action):
                    self.marker.unlink(missing_ok=True)
                    result = self.shell('source "$PLUGIN_DIR/scripts/lib/auth.sh"; ' + action, root=project)
                    self.assertEqual(result.returncode, 125, result.stderr)
                    self.assertFalse(self.marker.exists(), "project executable ran during admission")

    def test_login_launcher_rejects_project_python_before_executing_it(self):
            project = self.base / "project"
            bindir = project / "bin"
            bindir.mkdir(parents=True)
            shim = bindir / "python3"
            shim_marker = self.base / "python-shim-ran"
            shim.write_text('#!/bin/sh\nprintf called > "$PYTHON_SHIM_MARKER"\nexec '
                            + shlex.quote(sys.executable) + ' "$@"\n')
            shim.chmod(0o755)
            self.env.update(PROJECT_ROOT=str(project), CLI_VERSION="2.0.23", MISTRAL_API_KEY="fixture",
                            PYTHON_SHIM_MARKER=str(shim_marker),
                            PATH=f"bin:{self.bin}")
            result = self.shell('source "$PLUGIN_DIR/scripts/lib/auth.sh"; _octo_opencode_has_saved_login', root=project)
            self.assertEqual(result.returncode, 125, result.stderr)
            self.assertFalse(shim_marker.exists(), "project Python ran before probe isolation")
            self.assertFalse(self.marker.exists())

    def test_login_launcher_preserves_an_external_python_pin(self):
            shim = self.bin / "selected-python"
            shim_marker = self.base / "external-python-ran"
            shim.write_text('#!/bin/sh\nprintf called > "$PYTHON_SHIM_MARKER"\nexec '
                            + shlex.quote(sys.executable) + ' "$@"\n')
            shim.chmod(0o755)
            self.env.update(OCTOPUS_PYTHON=str(shim), PYTHON_SHIM_MARKER=str(shim_marker), CLI_VERSION="2.0.23")
            result = self.shell('source scripts/lib/auth.sh; _octo_opencode_has_saved_login')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(shim_marker.exists())
            self.assertTrue(self.marker.exists())

    def test_login_parsers_ignore_project_executables_and_clear_credentials(self):
            project = self.base / "project"
            bindir = project / "bin"
            bindir.mkdir(parents=True)
            parser_marker = self.base / "parser-ran"
            for name in ("jq", "sed", "grep"):
                parser = bindir / name
                parser.write_text('#!/bin/sh\ntouch "$PARSER_MARKER"\nexit 0\n')
                parser.chmod(0o755)
            self.env.update(PROJECT_ROOT=str(project), PARSER_MARKER=str(parser_marker),
                            OPENROUTER_API_KEY="fixture", GITHUB_TOKEN="fixture",
                            Z_AI_API_KEY="fixture", MINIMAX_API_KEY="fixture",
                            MISTRAL_API_KEY="fixture",
                            PATH=f"{bindir}:{self.env['PATH']}")
            # Stub the transport only. Execute the real post-probe parsing path.
            script = r'''
source "$PLUGIN_DIR/scripts/lib/auth.sh"
source "$PLUGIN_DIR/scripts/lib/pid-ledger.sh"
_octo_opencode_cli_major() { echo "$PARSER_MAJOR"; }
_octo_opencode_run_probe() { printf '%s\n' "$PARSER_LISTING"; }
_octo_opencode_has_saved_login
rc=$?
[[ "$MISTRAL_API_KEY" == fixture && "$GITHUB_TOKEN" == fixture ]] || exit 74
exit "$rc"
'''
            for major, listing, expected in (("1", "└  2 credentials", 0),
                                              ("1", "└  0 credentials", 1),
                                              ("2", self.env["AUTH_JSON"], 0),
                                              ("2", "[]", 1)):
                with self.subTest(major=major, listing=listing):
                    self.env.update(PARSER_MAJOR=major, PARSER_LISTING=listing)
                    result = self.shell(script, root=project)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertFalse(parser_marker.exists(), "project parser ran")

    def test_login_parser_interpreter_receives_no_credentials(self):
            shim = self.bin / "parser-python"
            parser_marker = self.base / "parser-python-ran"
            shim.write_text('#!/bin/sh\n'
                            '[ -z "${MISTRAL_API_KEY+x}${OPENROUTER_API_KEY+x}${GITHUB_TOKEN+x}${Z_AI_API_KEY+x}${MINIMAX_API_KEY+x}" ] || exit 79\n'
                            'touch "$PARSER_MARKER"\n'
                            'exec ' + shlex.quote(sys.executable) + ' "$@"\n')
            shim.chmod(0o755)
            self.env.update(OCTOPUS_PYTHON=str(shim), MISTRAL_API_KEY="fixture",
                            OPENROUTER_API_KEY="fixture", GITHUB_TOKEN="fixture",
                            Z_AI_API_KEY="fixture", MINIMAX_API_KEY="fixture",
                            PARSER_MARKER=str(parser_marker))
            result = self.shell('source scripts/lib/auth.sh; source scripts/lib/pid-ledger.sh; '
                                '_octo_opencode_cli_major() { echo 2; }; '
                                '_octo_opencode_run_probe() { printf "%s\\n" "$AUTH_JSON"; }; '
                                '_octo_opencode_has_saved_login')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(parser_marker.exists())

    def test_bounded_probes_apply_boundary_before_selected_executable(self):
            self.env.update(CLI_VERSION="2.0.23", OCTOPUS_TANGLE_EXECUTION_BOUNDARY="true")
            for action in ("_octo_opencode_cli_major", "_octo_opencode_has_saved_login"):
                with self.subTest(action=action):
                    self.marker.unlink(missing_ok=True)
                    result = self.shell('source scripts/lib/auth.sh; '
                                        'octopus_tangle_apply_execution_boundary() { return 125; }; ' + action)
                    self.assertEqual(result.returncode, 125, result.stderr)
                    self.assertFalse(self.marker.exists(), "provider ran before its boundary")

    def test_health_preserves_admission_refusal(self):
            result = self.shell('source scripts/lib/providers.sh; '
                                '_octo_opencode_has_saved_login() { return 125; }; '
                                'check_provider_health opencode vendor/model')
            self.assertEqual(result.returncode, 125, result.stderr)
            self.assertNotIn("no confirmed login", result.stderr)

    def test_non_council_research_does_not_admit_an_unrelated_council_roster(self):
            self.env.update(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="opencode",
                            ENTRY_MARKER=str(self.base / "research-entry"),
                            READY_TRACE=str(self.base / "ready-trace"))
            script = r'''
set -e
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
source scripts/lib/research.sh
log() { :; }
_preflight_provider_candidates() { printf 'agy\nopencode\n'; }
octo_provider_readiness_result() {
    printf '%s:%s\n' "$1" "$2" >> "$READY_TRACE"
    if [[ "$1" == agy ]]; then
        printf '{"status":"available","reason_code":"ready","remediation":""}\n'
    else
        printf '{"status":"degraded","reason_code":"live-check-required","remediation":"fixture login missing"}\n'
    fi
}
provider_smoke_test() { :; }
detect_enterprise_backend() { :; }
mkdir() {
    if [[ "$*" == "-p $RESULTS_DIR" ]]; then
        touch "$ENTRY_MARKER"
        exit 77
    fi
    command mkdir "$@"
}
RESULTS_DIR="$HOME/results" WORKSPACE_DIR="$HOME" PREFLIGHT_CACHE_FILE="$HOME/preflight-cache" DRY_RUN=false
"$RESEARCH_ENTRY" fixture
'''
            for entry in ("empathize_research", "synthesize_research"):
                with self.subTest(entry=entry):
                    self.env["RESEARCH_ENTRY"] = entry
                    Path(self.env["ENTRY_MARKER"]).unlink(missing_ok=True)
                    Path(self.env["READY_TRACE"]).unlink(missing_ok=True)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
                    self.assertTrue(Path(self.env["ENTRY_MARKER"]).exists())
                    self.assertNotIn("opencode:live", Path(self.env["READY_TRACE"]).read_text())

    def test_non_council_context_still_confirms_an_explicit_opencode_panel(self):
            (self.data / "opencode.db").touch()
            self.env.update(CLI_VERSION="2.0.23", OCTOPUS_PREFLIGHT_PROVIDERS="opencode",
                            OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="codex")
            result = self.shell('source scripts/lib/preflight.sh; source scripts/lib/config-display.sh; '
                                'log() { :; }; WORKSPACE_DIR="$HOME"; '
                                'PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"; '
                                'preflight_check true "" non-roster-dispatch')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(self.marker.exists())

    def test_selected_opencode_is_checked_alongside_a_different_roster(self):
            self.env.update(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="codex",
                            READY_TRACE=str(self.base / "ready-trace"))
            result = self.shell(r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
octo_provider_readiness_result() {
    printf '%s:%s\n' "$1" "$2" >> "$READY_TRACE"
    if [[ "$1" == codex ]]; then
        echo '{"status":"available","reason_code":"ready","remediation":""}'
    else
        echo '{"status":"degraded","reason_code":"auth-missing","remediation":"fixture"}'
    fi
}
WORKSPACE_DIR="$HOME" PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true opencode dispatch
''')
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            trace = Path(self.env["READY_TRACE"]).read_text().splitlines()
            self.assertIn("codex:static", trace)
            self.assertIn("opencode:live", trace)

    def test_review_and_security_include_the_admitted_single_opencode(self):
            for workflow in ("review", "security"):
                with self.subTest(workflow=workflow):
                    self.env["WORKFLOW"] = workflow
                    result = self.shell('source scripts/lib/embrace.sh; '
                                        '_gds_provider_allowed() { [[ "$1" == opencode ]]; }; '
                                        '_octo_opencode_research_ready=true; '
                                        'get_dispatch_strategy fixture "$WORKFLOW"')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "2:opencode,claude-sonnet:medium")

    def test_fixed_seat_workflows_ignore_roster_until_opencode_is_selected(self):
            script = self.production_inventory() + r'''
source scripts/lib/preflight.sh
source scripts/lib/sentinel.sh
source scripts/lib/testing.sh
source scripts/lib/debate.sh
source scripts/lib/routing.sh
log() { :; }
preflight_check() { printf '%s\n' "$3" > "$CONTEXT_FILE"; return 78; }
DRY_RUN=false
"$ENTRY" fixture
'''
            self.env["CONTEXT_FILE"] = str(self.base / "context")
            config = Path(self.env["HOME"]) / ".claude-octopus/config/providers.json"
            config.parent.mkdir(parents=True)
            for entry, seats, expected in (
                    ("advise_strategy", [], "non-roster-dispatch"),
                    ("squeeze_test", [], "non-roster-dispatch"),
                    ("grapple_debate", [], "non-roster-dispatch"),
                    ("grapple_debate", ["opencode", "agy", "claude-sonnet"], "non-roster-dispatch")):
                with self.subTest(entry=entry, seats=seats):
                    config.write_text(json.dumps({"routing": {"features": {"debate": seats}}}))
                    self.env["ENTRY"] = entry
                    Path(self.env["CONTEXT_FILE"]).unlink(missing_ok=True)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertEqual(Path(self.env["CONTEXT_FILE"]).read_text().strip(), expected)

    def test_debate_admits_its_actual_opencode_seats_independent_of_roster(self):
            config = Path(self.env["HOME"]) / ".claude-octopus/config/providers.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"routing": {"features": {"debate":
                                  ["opencode", "opencode-fast", "opencode-research"]}}}))
            self.env.update(CLI_VERSION="2.0.23", OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="codex",
                            ENTRY_MARKER=str(self.base / "debate-entered"), OCTOPUS_CONSENSUS="quorum")
            (self.data / "opencode.db").touch()
            script = self.production_inventory() + r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
source scripts/lib/debate.sh
source scripts/lib/routing.sh
log() { :; }
mkdir() {
    if [[ "$*" == "-p $RESULTS_DIR $LOGS_DIR" ]]; then
        touch "$ENTRY_MARKER"
        exit 77
    fi
    command mkdir "$@"
}
WORKSPACE_DIR="$HOME" RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs" DRY_RUN=false
grapple_debate fixture
'''
            for variant in ("opencode", "opencode-fast", "opencode-research"):
                # Keep every seat on the allowed provider so unrelated missing
                # credentials cannot mask the OpenCode admission result.
                config.write_text(json.dumps({"routing": {"features": {"debate":
                                      [variant, variant, variant]}}}))
                for connected in (False, True):
                    with self.subTest(variant=variant, connected=connected):
                        marker = Path(self.env["ENTRY_MARKER"])
                        marker.unlink(missing_ok=True)
                        self.env["AUTH_JSON"] = json.dumps([{"id":"openai","connections":[
                            {"type":"credential"}]}] if connected else [])
                        result = self.shell(script)
                        self.assertEqual(result.returncode, 77 if connected else 1, result.stdout + result.stderr)
                        self.assertEqual(marker.exists(), connected)

    def test_shared_routing_resolves_and_labels_each_registered_opencode_variant(self):
            result = self.shell(self.production_inventory() + r"""
source scripts/lib/routing.sh
for variant in opencode opencode-fast opencode-research; do
    resolve_provider_to_agent "$variant" || exit
    agent_display_label "$variant" || exit
    agent_display_label_upper "$variant" || exit
done
resolve_provider_to_agent opencode-unknown && exit 91
agent_display_label opencode-unknown && exit 92
AVAILABLE_AGENTS="opencode"
resolve_provider_to_agent opencode-fast && exit 93
exit 0
""")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.splitlines(), [
                "opencode", "OpenCode", "OPENCODE", "opencode-fast", "OpenCode", "OPENCODE",
                "opencode-research", "OpenCode", "OPENCODE"])
            self.assertFalse(self.marker.exists())

    def test_external_python_capability_probe_has_a_deadline_and_reaps_its_group(self):
            override = self.base / "python-stalling"
            pids = self.base / "capability-pids"
            override.write_text('#!/bin/sh\ntrap "" TERM\nsleep 30 &\n'
                                'printf "%s %s\\n" "$$" "$!" > "$CAPABILITY_PIDS"\nwait\n')
            override.chmod(0o755)
            project = self.base / "project"
            project.mkdir()
            project_bin = project / "bin"
            project_bin.mkdir()
            sleep_marker = self.base / "project-sleep-called"
            fake_sleep = project_bin / "sleep"
            fake_sleep.write_text('#!/bin/sh\nif [ "$1" = 0.1 ]; then printf touched > "$SLEEP_MARKER"; fi\nexec /bin/sleep "$@"\n')
            fake_sleep.chmod(0o755)
            self.env.update(OCTOPUS_PYTHON=str(override), CAPABILITY_PIDS=str(pids),
                            OCTOPUS_PROJECT_ROOT=str(project), SLEEP_MARKER=str(sleep_marker),
                            MISTRAL_API_KEY="inert-fixture-key")
            self.env["PATH"] = str(project_bin) + ":" + self.env["PATH"]
            process = subprocess.Popen(["bash", "-c", 'source scripts/lib/auth.sh; _octo_opencode_probe_python'],
                                       cwd=ROOT, env=self.env, text=True, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, start_new_session=True)
            started = time.monotonic()
            try:
                stdout, stderr = process.communicate(timeout=7)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
            self.assertEqual(process.returncode, 125, stdout + stderr)
            self.assertLess(time.monotonic() - started, 7)
            self.assertFalse(self.marker.exists())
            self.assertFalse(sleep_marker.exists(), "cleanup executed a project-owned sleep")
            self.assertTrue(pids.exists())
            for pid in pids.read_text().split():
                state = subprocess.run(["ps", "-o", "stat=", "-p", pid], text=True,
                                       capture_output=True, timeout=2).stdout.strip()
                self.assertTrue(not state or state.startswith("Z"), (pid, state))

    def test_live_preflight_bootstrap_does_not_run_project_path_tools_or_startup(self):
            caller, project = self.base / "caller", self.base / "project"
            caller.mkdir()
            (caller / "bin").mkdir()
            (project / "bin").mkdir(parents=True)
            marker = self.base / "bootstrap-called"
            tools = {"env": "/usr/bin/env", "bash": "/bin/bash", "date": "/bin/date", "dirname": "/usr/bin/dirname"}
            for directory in (project, project / "bin"):
                for name, executable in tools.items():
                    shim = directory / name
                    shim.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$BOOTSTRAP_MARKER"\nexec ' + executable + ' "$@"\n')
                    shim.chmod(0o755)
            startup = project / "probe-startup.sh"
            startup.write_text('printf "startup\\n" >> "$BOOTSTRAP_MARKER"\n')
            (self.data / "opencode.db").touch()
            self.env.update(PROJECT_ROOT=str(project), BOOTSTRAP_MARKER=str(marker),
                            CLI_VERSION="2.0.23", MISTRAL_API_KEY="inert-fixture-key")
            original_path = self.env["PATH"]
            script = r'''
source "$PLUGIN_DIR/scripts/lib/preflight.sh"
log() { :; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
export BASH_ENV="$STARTUP_VALUE"
WORKSPACE_DIR="$HOME" PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
case "$READINESS_ENTRY" in
    live) octo_provider_readiness_result opencode live "$PROJECT_ROOT" ;;
    dispatch) preflight_check true opencode dispatch ;;
    panel)
        OCTOPUS_PREFLIGHT_PROVIDERS=opencode
        preflight_check true opencode dispatch ;;
esac
rc=$?
[[ "$BASH_ENV" == "$STARTUP_VALUE" && "$MISTRAL_API_KEY" == inert-fixture-key ]] || exit 94
exit "$rc"
'''
            for entry, relative_path, startup_value in product(
                    ("live", "dispatch", "panel"), (".", "", "bin"),
                    ("probe-startup.sh", str(startup))):
                with self.subTest(entry=entry, path=relative_path, startup=startup_value):
                    marker.unlink(missing_ok=True)
                    self.marker.unlink(missing_ok=True)
                    self.env.update(READINESS_ENTRY=entry, STARTUP_VALUE=startup_value,
                                    PATH=relative_path + ":" + original_path)
                    result = self.shell(script, root=caller, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    if entry == "live":
                        self.assertEqual(json.loads(result.stdout)["status"], "available")
                    self.assertTrue(self.marker.exists(), "the isolated OpenCode login was never checked")
                    self.assertFalse(marker.exists(), marker.read_text() if marker.exists() else "")

    def test_automatic_eligibility_resolves_relative_path_from_project_directory(self):
            project = self.base / "project"
            caller = self.base / "caller"
            project.mkdir()
            caller.mkdir()
            (project / "bin").symlink_to(self.bin, target_is_directory=True)
            self.env.update(PROJECT_ROOT=str(project), CLI_VERSION="2.0.23",
                            PATH=f"bin:{self.bin}")
            (self.data / "opencode.db").touch()
            result = self.shell(r'''
source "$PLUGIN_DIR/scripts/lib/preflight.sh"
source "$PLUGIN_DIR/scripts/lib/config-display.sh"
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME" PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true "" auto-dispatch || exit
source "$PLUGIN_DIR/scripts/lib/embrace.sh"
get_dispatch_strategy fixture research
''', root=caller)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("opencode,claude-sonnet", result.stdout)

    def test_static_mistral_only_login_is_recognized_without_a_probe(self):
            self.env["MISTRAL_API_KEY"] = "fixture"
            self.assertEqual(self.readiness("static")["status"], "available")
            self.assertFalse(self.marker.exists())

    def test_live_readiness_distinguishes_execution_refusal_from_login_failure(self):
            self.env["OPENROUTER_API_KEY"] = "fixture"
            result = self.shell('source scripts/lib/preflight.sh; '
                                '_octo_run_bare_probe_with_timeout() { return 125; }; '
                                'octo_provider_readiness_result opencode live')
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report["reason_code"], "execution-refused")
            self.assertNotIn("auth login", report["remediation"])

    def test_opencode_dry_run_labels_unchecked_server_mode(self):
            result = self.shell(r'''
source scripts/lib/spawn.sh
source scripts/lib/dispatch.sh
log() { printf '%s\n' "$2"; }
classify_task() { echo standard; }
match_routing_rule() { return 1; }
get_agent_model() { echo vendor/model; }
DRY_RUN=true
spawn_agent opencode fixture fixture implementer tangle
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("server mode and bounded Tangle availability are unchecked", result.stdout)
            self.assertFalse(self.marker.exists())

    def test_opus_display_matches_dispatch_despite_generic_claude_override(self):
            source = (ROOT / "scripts/lib/auto-route.sh").read_text()
            start = source.index("    local agent\n", source.index('auto_route()'))
            end = source.index('    case "$task_type" in', start)
            display = source[start:end]
            self.env.update(OCTOPUS_CLAUDE_MODEL="claude-sonnet-5-5", SUPPORTS_OPUS_5_5="true")
            for seat in ("claude-opus", "claude-opus-fast"):
                with self.subTest(seat=seat):
                    self.env["DISPLAY_SEAT"] = seat
                    result = self.shell('source scripts/lib/model-resolver.sh; '
                                        'source scripts/lib/dispatch.sh; source scripts/lib/utils.sh; '
                                        'log() { :; }; '
                                        'get_tiered_agent() { echo "$DISPLAY_SEAT"; }; '
                                        'display() { local task_type=coding agent_complexity=3; ' + display + ' }; '
                                        'display; cmd=$(DRY_RUN=true OCTOPUS_MODEL_READ_ONLY=true '
                                        'OCTOPUS_DISPATCH_PREVIEW=true get_agent_command "$DISPLAY_SEAT") || exit; '
                                        'printf "WIRE=%s\\n" "$(octo_dispatch_command_model "$cmd" "")"')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    shown = result.stdout.split("→", 1)[1].splitlines()[0].strip()
                    wire = result.stdout.rsplit("WIRE=", 1)[1].strip()
                    self.assertEqual(wire, "claude-opus-5-5", result.stdout)
                    self.assertEqual(shown, wire, result.stdout)
