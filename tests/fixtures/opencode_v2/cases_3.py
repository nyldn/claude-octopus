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

class OpenCodeCases3(OpenCodeFixture):
    def test_login_rejects_project_config_and_symlinked_executable(self):
            project = self.base / "project"
            project.mkdir()
            config = project / "opencode.json"
            config.write_text('{"plugin":["./project-plugin.js"]}')
            self.env.update(PROJECT_ROOT=str(project), OPENCODE_CONFIG=str(config))
            result = self.shell('source scripts/lib/auth.sh; _octo_opencode_has_saved_login')
            self.assertEqual(result.returncode, 125, result.stderr)
            self.assertFalse(self.marker.exists())
            self.env.pop("OPENCODE_CONFIG")
            project_cli = project / "opencode"
            project_cli.write_text(self.cli.read_text())
            project_cli.chmod(0o755)
            self.cli.unlink()
            self.cli.symlink_to(project_cli)
            result = self.shell('source scripts/lib/auth.sh; _octo_opencode_has_saved_login')
            self.assertEqual(result.returncode, 125, result.stderr)
            self.assertFalse(self.marker.exists())

    def test_bounded_legacy_login_and_command_use_the_probe_boundary(self):
            self.env.update(CLI_VERSION="1.18.34", OCTOPUS_TANGLE_EXECUTION_BOUNDARY="true")
            self.cli.write_text(self.cli.read_text().replace(
                'printf called >>', '[ "$BOUNDARY_ACTIVE" = 1 ] || exit 83\nprintf called >>', 1))
            result = self.shell(r'''
source scripts/lib/dispatch.sh
source scripts/lib/auth.sh
log() { :; }
octopus_tangle_apply_execution_boundary() { cmd_array=(env BOUNDARY_ACTIVE=1 "${cmd_array[@]}"); }
get_agent_model() { echo vendor/model; }
_octo_opencode_has_saved_login && get_agent_command opencode tangle
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("opencode run", result.stdout)
            self.assertNotIn("--standalone", result.stdout)

    def test_background_command_refusal_keeps_status_and_contract_reason(self):
            self.env["CONTRACT_CAPTURE"] = str(self.base / "contract")
            result = self.shell(r'''
source scripts/lib/spawn.sh
for helper in log match_routing_rule load_agent_checkpoint load_earned_skills build_provider_context octo_spawn_contract_plan octo_spawn_contract_resolve octo_spawn_contract_authenticated; do
    eval "$helper() { :; }"
done
check_provider_health() { :; }
octo_spawn_contract_finish() { printf '%s\n' "$@" > "$CONTRACT_CAPTURE"; }
octo_spawn_contract_seat_id() { echo spawn-fixture; }
classify_task() { echo standard; }
apply_persona() { printf %s "$2"; }
octo_with_engineering_methods() { printf %s "$2"; }
enforce_context_budget() { printf %s "$1"; }
octopus_effective_agent_timeout() { echo 0; }
get_agent_model() { echo vendor/model; }
get_agent_command() { printf 'OpenCode requires saved-login-preserving session storage\n' >&2; return 125; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
spawn_agent opencode fixture fixture implementer tangle
''')
            self.assertEqual(result.returncode, 125, result.stderr)
            fields = Path(self.env["CONTRACT_CAPTURE"]).read_text().splitlines()
            self.assertEqual(fields[4:6], ["OpenCode requires saved-login-preserving session storage", "125"])

    def test_opencode_probes_preserve_only_their_required_credentials(self):
            """Metadata needs no Mistral key; login needs it but never the search key."""
            self.env.update(CLI_VERSION="2.0.23", MISTRAL_API_KEY="fixture", KEENABLE_API_KEY="search-fixture")
            self.cli.write_text(self.cli.read_text().replace(
                'printf called >>',
                '[ -z "${KEENABLE_API_KEY+x}" ] || exit 70\n'
                'if [ "$1" = --version ]; then [ -z "${MISTRAL_API_KEY+x}" ] || exit 71; '
                'else [ "$MISTRAL_API_KEY" = fixture ] || exit 72; fi\nprintf called >>', 1))
            for action in ("_octo_opencode_cli_major", "_octo_opencode_has_saved_login"):
                with self.subTest(action=action):
                    result = self.shell('source scripts/lib/auth.sh; ' + action + '; rc=$?; '
                                        '[[ "$KEENABLE_API_KEY" == search-fixture && "$MISTRAL_API_KEY" == fixture ]] || exit 73; exit "$rc"')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_selected_admission_failure_preserves_broad_cache(self):
            """Neither login nor smoke failure can replace unrelated discovery evidence."""
            self.env.update(CLI_VERSION="2.0.23", OPENROUTER_API_KEY="fixture")
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { [[ "${SMOKE_FAILURE:-false}" != true ]]; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true >/dev/null || exit 71
cp "$PREFLIGHT_CACHE_FILE" "$HOME/cache-before" || exit 72
if [[ "$FAILURE_KIND" == login ]]; then
    AUTH_JSON='[]'; export AUTH_JSON
else
    SMOKE_FAILURE=true
fi
rc=0
preflight_check true "$SELECTED_SEAT" dispatch >/dev/null || rc=$?
[[ "$rc" == 1 ]] || exit 73
cmp -s "$PREFLIGHT_CACHE_FILE" "$HOME/cache-before"
'''
            for failure, seat in product(("login", "smoke"),
                                         ("opencode", "opencode-fast", "opencode-research",
                                          "opencode:vendor/model", "")):
                with self.subTest(failure=failure, seat=seat):
                    self.env.update(FAILURE_KIND=failure, SELECTED_SEAT=seat,
                                    OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="opencode" if not seat else "")
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unknown_generation_refuses_dispatch(self):
            self.env["CLI_VERSION"] = "unknown"
            result = self.shell('source scripts/lib/dispatch.sh; get_agent_model() { echo vendor/model; }; get_agent_command opencode')
            self.assertNotEqual(result.returncode, 0)

    def test_auto_route_display_does_not_probe_before_actual_dispatch(self):
            """The display must reach dispatch even when CLI probes are disabled."""
            self.env.update(CLI_VERSION="2.0.23", OCTOPUS_SKIP_PROVIDER_PROBES="true")
            script = r'''
set -eo pipefail
source scripts/lib/dispatch.sh
source scripts/lib/auto-route.sh
log() { :; }
classify_task() { echo coding; }
estimate_complexity() { echo 2; }
get_tier_name() { echo standard; }
evaluate_branch_condition() { echo standard; }
get_branch_display() { echo standard; }
detect_context() { echo dev:fixture; }
get_context_display() { echo fixture; }
classify_cynefin() { echo clear; }
detect_response_mode() { echo standard; }
get_tiered_agent() { echo "$DISPLAY_SEAT"; }
get_agent_model() { echo vendor/model; }
spawn_agent() {
    [[ "$1" == "$DISPLAY_SEAT" && "$2" == 'implement fixture' ]] || return 78
    [[ "${OCTOPUS_SKIP_PROVIDER_PROBES:-}" == true && "${OCTOPUS_MODEL_READ_ONLY:-false}" == false ]] || return 79
    touch "$HOME/reached-dispatch"
    return 77
}
auto_route 'implement fixture'
'''
            for seat in ("opencode", "opencode-fast", "opencode-research", "opencode:vendor/model"):
                with self.subTest(seat=seat):
                    marker = Path(self.env["HOME"]) / "reached-dispatch"
                    marker.unlink(missing_ok=True)
                    self.marker.unlink(missing_ok=True)
                    self.env["DISPLAY_SEAT"] = seat
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
                    self.assertTrue(marker.exists())
                    self.assertIn("vendor/model", result.stdout)
                    self.assertFalse(self.marker.exists(), "model display launched the CLI")

    def test_bare_filename_sources_resolve_helpers_after_directory_changes(self):
            """Lazy helper loads use the source directory, not the later cwd."""
            self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(ROOT))
            for library, action in (("auth.sh", "_octo_opencode_has_saved_login"),
                                    ("dispatch.sh", "get_agent_command opencode")):
                with self.subTest(library=library):
                    self.marker.unlink(missing_ok=True)
                    script = ('set -e; cd scripts/lib; source ' + library + '; '
                              'cd "$HOME"; unset -f _octo_run_bare_probe_with_timeout; '
                              'get_agent_model() { echo vendor/model; }; ' + action)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(self.marker.exists(), "the real bounded probe did not run")

    def test_bounded_v2_refuses_before_launch_without_changing_saved_login(self):
            """A private server must not start with unwritable session storage."""
            self.env["CLI_VERSION"] = "2.0.23"
            database = self.data / "opencode.db"
            database.write_bytes(b"saved-login-fixture")
            script = ('source scripts/lib/dispatch.sh; log() { printf "%s\\n" "$2" >&2; }; '
                      # Storage refusal is independent of the host's sandbox support.
                      'octopus_tangle_apply_execution_boundary() { :; }; '
                      'get_agent_model() { echo vendor/model; }; get_agent_command opencode tangle')
            for boundary, scope, refused in (("true", "strict", True), ("false", "adaptive", True),
                                              ("false", "strict", False)):
                with self.subTest(boundary=boundary, scope=scope):
                    self.env.update(OCTOPUS_TANGLE_EXECUTION_BOUNDARY=boundary,
                                    OCTOPUS_TANGLE_WRITE_SCOPE_MODE=scope)
                    result = self.shell(script)
                    if refused:
                        self.assertEqual(result.returncode, 125, result.stderr)
                        self.assertEqual(result.stdout, "")
                        self.assertIn("saved-login-preserving session storage", result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn("run --standalone", result.stdout)
                    self.assertEqual(database.read_bytes(), b"saved-login-fixture")

    def test_health_failure_uses_the_callers_logger(self):
            self.env.update(CLI_VERSION="2.0.23", AUTH_JSON="[]")
            result = self.shell('source scripts/lib/providers.sh; '
                                'log() { printf "logged:%s:%s\\n" "$1" "$2" >&2; }; '
                                'check_provider_health opencode')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("logged:ERROR:opencode: no confirmed login", result.stderr)

    def test_standalone_health_failure_keeps_its_diagnostic(self):
            """Use stderr with or without a platform log executable on PATH."""
            self.env.update(CLI_VERSION="2.0.23", AUTH_JSON="[]")
            external_log = self.bin / "log"
            for installed in (False, True):
                with self.subTest(external_logger=installed):
                    if installed:
                        external_log.write_text('#!/bin/sh\necho external-system-logger >&2\nexit 64\n')
                        external_log.chmod(0o755)
                    result = self.shell('source scripts/lib/providers.sh; check_provider_health opencode')
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("[ERROR] opencode: no confirmed login", result.stderr)
                    self.assertNotIn("command not found", result.stderr)
                    self.assertNotIn("external-system-logger", result.stderr)

    def test_failed_live_login_keeps_the_login_command(self):
            """Live rejection must retain an actionable command in readiness JSON."""
            self.env.update(CLI_VERSION="2.0.23", AUTH_JSON="[]")
            readiness = self.readiness("live")
            self.assertEqual(readiness["reason_code"], "health-failed")
            self.assertIn("opencode auth login", readiness["remediation"])

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
                'printf called >>',
                '[ "$OPENCODE_CONFIG_PROJECT_DISABLE" = 1 ] || exit 67\nprintf called >>', 1))
            project_bin = self.base / "trusted" / "bin"
            project_bin.mkdir(parents=True)
            project_cli = project_bin / "opencode"
            project_cli.write_text(self.cli.read_text())
            project_cli.chmod(0o755)
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check true opencode
'''
            for relative_path, storage, roster, connected in product(
                    (False, True), ("sqlite", "environment", "known-environment"), ("", "opencode"), (False, True)):
                self.env["PATH"] = (f"../trusted/bin:{self.bin}" if relative_path else str(self.bin))
                self.env.pop("OPENAI_API_KEY", None)
                self.env.pop("OPENROUTER_API_KEY", None)
                database = self.data / "opencode.db"
                if storage == "sqlite":
                    database.touch()
                else:
                    database.unlink(missing_ok=True)
                    self.env["OPENROUTER_API_KEY" if storage == "known-environment" else "OPENAI_API_KEY"] = "fixture"
                with self.subTest(relative_path=relative_path, storage=storage, roster=roster, connected=connected):
                    self.marker.unlink(missing_ok=True)
                    cache = Path(self.env["HOME"]) / "preflight-cache"
                    cache.unlink(missing_ok=True)
                    self.env["OCTOPUS_COUNCIL_DEFAULT_PROVIDERS"] = roster
                    self.env["AUTH_JSON"] = json.dumps([
                        {"id": "openai", "connections": [{"type": "credential" if storage == "sqlite" else "environment"}]}
                    ] if connected else [])
                    admission = (script.replace('preflight_check true opencode',
                                                'preflight_check true "" dispatch') if roster else script)
                    result = self.shell(admission)
                    self.assertEqual(result.returncode == 0, connected, result.stdout + result.stderr)
                    if connected:
                        self.assertFalse(cache.exists(), "selected admission populated the broad cache")
                    if not connected and roster:
                        self.assertIn("health-failed", result.stdout)
                        self.assertIn("opencode auth login", result.stdout)
                        self.assertNotIn("run an explicit live readiness check", result.stdout)
                    self.assertTrue(self.marker.exists(), "admission never checked login")
                    self.env["OCTOPUS_SKIP_PROVIDER_PROBES"] = "true"
                    self.marker.unlink(missing_ok=True)
                    self.assertNotEqual(self.shell(admission).returncode, 0)
                    self.assertFalse(self.marker.exists())
                self.env["OCTOPUS_SKIP_PROVIDER_PROBES"] = "false"

    def test_automatic_research_admission_confirms_unpinned_opencode(self):
            """Only an actual automatic research dispatch can confirm an unpinned seat."""
            self.env.update(CLI_VERSION="2.0.23", CHECK_CONTEXT="auto-dispatch")
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check false "" "$CHECK_CONTEXT"
'''
            for storage, connected, skip in product(("sqlite", "environment"), (False, True), (False, True)):
                with self.subTest(storage=storage, connected=connected, skip=skip):
                    database = self.data / "opencode.db"
                    database.unlink(missing_ok=True)
                    self.env.pop("OPENROUTER_API_KEY", None)
                    if storage == "sqlite":
                        database.touch()
                    else:
                        self.env["OPENROUTER_API_KEY"] = "fixture"
                    cache = Path(self.env["HOME"]) / "preflight-cache"
                    cache.write_text("9999999999\n0\n")
                    cache_before = cache.read_bytes()
                    self.env.update(OCTOPUS_SKIP_PROVIDER_PROBES="true" if skip else "false",
                                    AUTH_JSON=json.dumps([{"id": "openai", "connections": [
                                        {"type": "credential" if storage == "sqlite" else "environment"}]}]
                                        if connected else []))
                    self.marker.unlink(missing_ok=True)
                    result = self.shell(script)
                    self.assertEqual(result.returncode == 0, connected and not skip,
                                     result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), not skip)
                    self.assertEqual(cache.read_bytes(), cache_before,
                                     "dispatch replaced broad discovery evidence")

    def test_automatic_research_admission_honors_exclusions_without_probes(self):
            """A selected automatic workflow must still obey admission ceilings."""
            self.env.update(CLI_VERSION="2.0.23")
            (self.data / "opencode.db").touch()
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
octo_quota_is_dead() { [[ "$EXCLUSION" == quota ]]; }
octo_quota_failed_this_run() { [[ "$EXCLUSION" == health ]]; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check false "" auto-dispatch
'''
            for exclusion in ("quota", "health", "allowlist"):
                with self.subTest(exclusion=exclusion):
                    self.marker.unlink(missing_ok=True)
                    self.env.update(EXCLUSION=exclusion,
                                    OCTO_ALLOWED_PROVIDERS="codex" if exclusion == "allowlist" else "opencode")
                    result = self.shell(script)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertFalse(self.marker.exists(), "excluded OpenCode was probed")

    def test_research_entrypoint_selects_automatic_dispatch_context(self):
            """The real research entrypoint distinguishes dispatch from inspection."""
            result = self.shell(r'''
source scripts/lib/workflows.sh
log() { :; }
preflight_check() { printf 'preflight:%s|%s|%s\n' "$1" "$2" "$3"; return 77; }
probe_discover fixture
''')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("preflight:false||auto-dispatch", result.stdout)

    def test_embrace_confirms_unpinned_sqlite_login_before_research(self):
            """Embrace must reach the same bounded admission as automatic research."""
            self.env.update(CLI_VERSION="2.0.23", SUPPORTS_DISABLE_CRON_ENV="false",
                            AUTONOMY_MODE="autonomous", LOOP_UNTIL_APPROVED="false",
                            DRY_RUN="false", RESUME_SESSION="false")
            (self.data / "opencode.db").touch()
            script = r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
source scripts/lib/workflows.sh
log() { :; }
cleanup_old_results() { :; }
show_cost_estimate() { :; }
cleanup_expired_checkpoints() { :; }
reset_provider_lockouts() { :; }
search_observations() { :; }
embrace_normalize_debate_gates() { echo none; }
init_session() { :; }
check_resume_session() { return 0; }
get_resume_phase() { printf '%s\n' "$RESUME_PHASE"; }
display_workflow_cost_estimate() { return 0; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
definition="$(declare -f preflight_check)"
eval "${definition/preflight_check/_original_preflight_check}"
preflight_check() {
    _original_preflight_check "$@"
    printf 'embrace-admission:%s\n' "$?"
    return 77 # Stop before any model dispatch, after real login admission.
}
embrace_full_workflow fixture
'''
            for phase, connected, skip in product(("", "probe", "tangle"), (False, True), (False, True)):
                with self.subTest(phase=phase, connected=connected, skip=skip):
                    self.env.update(RESUME_SESSION="true" if phase else "false", RESUME_PHASE=phase,
                                    OCTOPUS_SKIP_PROVIDER_PROBES="true" if skip else "false",
                                    AUTH_JSON=json.dumps([{"id": "openai", "connections": [
                                        {"type": "credential"}]}] if connected else []))
                    self.marker.unlink(missing_ok=True)
                    result = self.shell(script)
                    expected = 0 if connected and not skip and not phase else 1
                    self.assertIn(f"embrace-admission:{expected}", result.stdout,
                                  result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), not skip and not phase)

    def test_fixed_panel_confirms_only_dispatch_selected_opencode(self):
            """Static panel receipts never authorize a selected SQLite login."""
            auth_marker = self.base / "auth-called"
            self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(ROOT),
                            OCTOPUS_PREFLIGHT_PROVIDERS="opencode", AUTH_MARKER=str(auth_marker))
            self.cli.write_text(self.cli.read_text().replace(
                '    sleep "${AUTH_DELAY:-0}"', '    touch "$AUTH_MARKER"\n    sleep "${AUTH_DELAY:-0}"'))
            script = r'''
source scripts/lib/preflight.sh
log() { :; }
WORKSPACE_DIR="$HOME"
preflight_check true "" "$CHECK_CONTEXT"
'''
            for storage, connected, context in product(
                    ("sqlite", "environment"), (False, True), ("static", "dispatch")):
                with self.subTest(storage=storage, connected=connected, context=context):
                    database = self.data / "opencode.db"
                    database.unlink(missing_ok=True)
                    self.env.pop("OPENROUTER_API_KEY", None)
                    if storage == "sqlite":
                        database.touch()
                    else:
                        self.env["OPENROUTER_API_KEY"] = "fixture"
                    auth_marker.unlink(missing_ok=True)
                    self.env.update(CHECK_CONTEXT=context, AUTH_JSON=json.dumps([
                        {"id": "openai", "connections": [{"type": "credential"}]}]
                        if connected else []))
                    self.marker.unlink(missing_ok=True)
                    result = self.shell(script)
                    expected = connected if context == "dispatch" else storage == "environment"
                    self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)
                    self.assertEqual(auth_marker.exists(), context == "dispatch",
                                     "fixed panel violated static/dispatch login confirmation")
