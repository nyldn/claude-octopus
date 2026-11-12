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

class OpenCodeCases1(OpenCodeFixture):
    def test_host_path_claude_cannot_satisfy_missing_provider(self):
            host_bin = self.base / "host-bin"
            host_bin.mkdir()
            host_marker = self.base / "host-provider-called"
            hostile = host_bin / "claude"
            hostile.write_text('#!/bin/sh\nprintf called > ' + shlex.quote(str(host_marker)) + '\n')
            hostile.chmod(0o755)
            host_python = host_bin / "python3"
            host_python.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' "$@"\n')
            host_python.chmod(0o755)
            nested = type(self)("test_host_path_claude_cannot_satisfy_missing_provider")
            self.addCleanup(nested.doCleanups)
            # Model an installed provider beside the interpreter, without writing
            # into the real host installation or invoking that provider.
            with mock.patch.object(sys, "executable", str(host_python)):
                nested.setUp()
            nested.env["OCTO_ALLOWED_PROVIDERS"] = "claude,opencode"
            utility = nested.shell("printf '%s\\n' fixture-utility | xargs echo")
            self.assertEqual(utility.returncode, 0, utility.stderr)
            self.assertEqual(utility.stdout.strip(), "fixture-utility")
            script = 'source scripts/lib/preflight.sh; octo_provider_readiness_result claude static'
            result = nested.shell(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["status"], "missing")
            fixture = nested.bin / "claude"
            fixture.write_text('#!/bin/sh\nexit 0\n')
            fixture.chmod(0o755)
            result = nested.shell(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["status"], "available")
            self.assertFalse(host_marker.exists())

    def test_dispatch_keeps_v1_pure_environment_without_v2_removed_flag(self):
            result = self.shell("source scripts/lib/dispatch.sh; source scripts/lib/utils.sh; get_agent_model() { echo vendor/model; }; cmd=$(get_agent_command opencode); validate_agent_command \"$cmd\" || exit; echo \"$cmd\"")
            self.assertEqual(result.returncode, 0, result.stderr)
            cmd = shlex.split(result.stdout)
            run = subprocess.run(cmd, env=self.env, capture_output=True, text=True, timeout=3)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout.strip(), "run -m vendor/model")

    def test_auth_initialization_does_not_run_project_dirname(self):
            self.env["MISTRAL_API_KEY"] = "fixture-login"
            dirname = self.bin / "dirname"
            dirname.write_text('#!/bin/sh\nprintf called > "$PROBE_MARKER"\nexec /usr/bin/dirname "$@"\n')
            dirname.chmod(0o755)
            result = self.shell('source scripts/lib/auth.sh; [[ "$_auth_lib_dir" == "$PLUGIN_DIR/scripts/lib" ]]')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(self.marker.exists(), "auth initialization executed a project-selected utility")

    def test_v2_dispatch_uses_a_private_server(self):
            self.env["CLI_VERSION"] = "2.0.23"
            result = self.shell('source scripts/lib/dispatch.sh; source scripts/lib/utils.sh; get_agent_model() { echo vendor/model; }; cmd=$(get_agent_command opencode); validate_agent_command "$cmd" || exit; echo "$cmd"')
            self.assertEqual(result.returncode, 0, result.stderr)
            run = subprocess.run(shlex.split(result.stdout), env=self.env, capture_output=True, text=True, timeout=3)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout.strip(), "run --standalone -m vendor/model")

    def test_remote_automatic_defaults_allow_real_opencode_admission(self):
            """Remote discovery defaults must not disable selected OpenCode work."""
            self.env.pop("OCTOPUS_SKIP_PROVIDER_PROBES", None)
            self.env.update(CLAUDE_CODE_REMOTE="true", CLI_VERSION="2.0.23")
            orchestrator = (ROOT / "scripts/orchestrate.sh").read_text()
            defaults = orchestrator.split('# Claude Code web/remote sessions', 1)[1].split('# Keep debug flag', 1)[0]
            script = ('# Claude Code web/remote sessions' + defaults +
                      '\nsource scripts/lib/auth.sh; source scripts/lib/dispatch.sh; '
                      'log() { :; }; get_agent_model() { echo vendor/model; }; '
                      '_octo_opencode_has_saved_login && get_agent_command opencode')
            result = self.shell(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('run --standalone', result.stdout)
            self.assertTrue(self.marker.exists())

    def test_automatic_research_keeps_the_cache_without_an_opencode_candidate(self):
            """An absent or disallowed candidate must not disable broad cache reuse."""
            self.cli.rename(self.bin / 'disabled-opencode')
            self.env['OCTO_ALLOWED_PROVIDERS'] = 'codex'
            cache = Path(self.env['HOME']) / 'preflight-cache'
            cache.write_text('9999999999\n0\n')
            result = self.shell(r'''
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo codex; }
octo_provider_readiness_result() { printf '%s\n' '{"provider":"codex","status":"available","reason_code":"ready","remediation":""}'; }
detect_enterprise_backend() { :; }
provider_smoke_test() { touch "$PROBE_MARKER"; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
preflight_check false "" auto-dispatch
''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(self.marker.exists(), 'automatic admission bypassed a valid broad cache')

    def test_automatic_research_seats_the_opencode_login_it_confirmed(self):
            """The actual research entrypoint must use its admitted OpenCode seat."""
            self.env.update(CLI_VERSION='2.0.23', DRY_RUN='false',
                            OCTOPUS_RESEARCH_EVIDENCE='false', OCTOPUS_RESEARCH_INTENSITY='quick')
            (self.data / 'opencode.db').touch()
            selected = self.base / 'selected-agent'
            self.env['SELECTED_AGENT_FILE'] = str(selected)
            result = self.shell(r'''
source scripts/lib/workflows.sh
source scripts/lib/embrace.sh
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
log() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
display_workflow_cost_estimate() { return 0; }
get_cache_key() { echo fixture; }
check_cache() { return 1; }
load_blind_spot_checklist() { :; }
WORKSPACE_DIR="$HOME"; PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
RESULTS_DIR="$HOME/results"; LOGS_DIR="$HOME/logs"; TMUX_MODE=false
for helper in octopus_phase_banner cleanup_cache init_progress_tracking fleet_dispatch_begin fleet_dispatch_end; do
    eval "$helper() { :; }"
done
# Stop at the first actual seat, after the real preflight and fleet selector.
spawn_agent_capture_pid() { printf '%s\n' "$1" > "$SELECTED_AGENT_FILE"; return 77; }
probe_discover fixture
''')
            self.assertTrue(selected.exists(), result.stdout + result.stderr)
            self.assertEqual(selected.read_text().strip(), 'opencode')

    def test_github_auth_probe_excludes_forwarded_mistral_key(self):
            """Discovery may confirm GitHub login without exposing another provider key."""
            gh = self.bin / "gh"
            gh.write_text("""#!/bin/sh
[ "$*" = 'auth status' ] || exit 70
[ -z "${MISTRAL_API_KEY+x}" ] || { touch "$PROBE_MARKER"; exit 71; }
[ "$UNRELATED_SETTING" = preserved ] || exit 72
touch "$GITHUB_PROBE_CALLED"
""")
            gh.chmod(0o755)
            copilot = self.bin / "copilot"
            copilot.write_text("#!/bin/sh\nexit 0\n")
            copilot.chmod(0o755)
            called = self.base / "github-probe-called"
            self.env.update(MISTRAL_API_KEY="fixture", UNRELATED_SETTING="preserved",
                            OCTO_ALLOWED_PROVIDERS="copilot", GITHUB_PROBE_CALLED=str(called))
            result = self.shell('source scripts/lib/providers.sh; detected=$(detect_providers); '
                                '[[ "$MISTRAL_API_KEY" == fixture && "$UNRELATED_SETTING" == preserved ]] '
                                '|| exit 74; [[ "$detected" == *copilot:gh-cli* ]]')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(called.exists(), "GitHub authentication fixture was not reached")
            self.assertFalse(self.marker.exists(), "OpenCode credential reached GitHub authentication")

    def test_copilot_availability_probes_exclude_forwarded_mistral_key(self):
            """Capability and auth fallback probes must not inherit OpenCode's key."""
            self.env.update(MISTRAL_API_KEY="fixture", UNRELATED_SETTING="preserved")
            for name, arguments, output in (
                    ("copilot", "--help", "--prompt --model --silent --no-ask-user --disable-builtin-mcps"),
                    ("gh", "auth status", "")):
                cli = self.bin / name
                cli.write_text('#!/bin/sh\n'
                               f'[ "$*" = {shlex.quote(arguments)} ] || exit 70\n'
                               '[ -z "${MISTRAL_API_KEY+x}" ] || exit 71\n'
                               '[ "$UNRELATED_SETTING" = preserved ] || exit 72\n'
                               f'printf "%s\\n" {shlex.quote(name)} >> "$PROBE_MARKER"\n'
                               f'printf "%s\\n" {shlex.quote(output)}\n')
                cli.chmod(0o755)
            for action, expected in (("copilot_is_available", "copilot\ngh\n"),
                                     ("copilot_auth_method", "gh\n")):
                with self.subTest(action=action):
                    self.marker.unlink(missing_ok=True)
                    result = self.shell('source scripts/lib/copilot.sh; ' + action + '; rc=$?; '
                                        '[[ "$MISTRAL_API_KEY" == fixture && "$UNRELATED_SETTING" == preserved ]] '
                                        '|| exit 73; exit "$rc"')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.marker.read_text(), expected)
                    if action == "copilot_auth_method":
                        self.assertEqual(result.stdout.strip(), "gh-cli")

    def test_opencode_login_storage_cannot_bypass_quota_exclusions(self):
            """SQLite and undiscovered environment logins obey the same stop marks."""
            self.env["CLI_VERSION"] = "2.0.23"
            script = r'''
source scripts/lib/preflight.sh
octo_quota_failed_this_run() { [[ "$QUOTA_KIND" == health-failed ]]; }
octo_quota_is_dead() { [[ "$QUOTA_KIND" == quota ]]; }
octo_provider_readiness_result opencode "$CHECK_KIND"
'''
            for storage, quota, kind in product(("sqlite", "legacy", "environment", "none"),
                                                ("quota", "health-failed"), ("static", "live")):
                with self.subTest(storage=storage, quota=quota, kind=kind):
                    for name in ("opencode.db", "auth.json"):
                        (self.data / name).unlink(missing_ok=True)
                    self.env.pop("OPENROUTER_API_KEY", None)
                    if storage in ("sqlite", "legacy"):
                        (self.data / ("opencode.db" if storage == "sqlite" else "auth.json")).touch()
                    elif storage == "environment":
                        self.env["OPENROUTER_API_KEY"] = "fixture"
                    self.env.update(QUOTA_KIND=quota, CHECK_KIND=kind)
                    self.marker.unlink(missing_ok=True)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    readiness = json.loads(result.stdout)
                    self.assertEqual(readiness["status"], "degraded")
                    self.assertEqual(readiness["reason_code"], quota)
                    self.assertFalse(self.marker.exists(), "excluded provider was probed")

    def test_mcp_preserves_opencode_xdg_roots_through_login_and_dispatch(self):
            """Run the real adapter filter and child environment with custom XDG roots."""
            settings = {name: str(self.base / name.lower()) for name in
                        ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME")}
            for directory in settings.values():
                Path(directory).mkdir()
            script = """import {loadProviderEnvAllowlist, providerEnvironment} from './shared/adapter-runtime.mjs';
console.log(JSON.stringify(providerEnvironment(loadProviderEnvAllowlist(process.cwd()),
    JSON.parse(process.argv[1]))));"""
            adapter = subprocess.run(["node", "--input-type=module", "-e", script,
                                      json.dumps(settings)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(adapter.returncode, 0, adapter.stderr)
            forwarded = json.loads(adapter.stdout)
            self.assertEqual(forwarded, settings, "MCP dropped OpenCode's custom XDG roots")
            self.env.update(forwarded, CLI_VERSION="2.0.23")
            for name, value in settings.items():
                self.env["EXPECTED_" + name] = value
            self.cli.write_text(self.cli.read_text().replace('printf called >>',
                '[ "$XDG_CONFIG_HOME" = "$EXPECTED_XDG_CONFIG_HOME" ] && '
                '[ "$XDG_CACHE_HOME" = "$EXPECTED_XDG_CACHE_HOME" ] && '
                '[ "$XDG_STATE_HOME" = "$EXPECTED_XDG_STATE_HOME" ] || exit 69\nprintf called >>', 1))
            self.assertEqual(self.readiness("live")["status"], "available")
            child = self.shell("""source scripts/lib/provider-routing.sh
source scripts/lib/dispatch.sh
source scripts/lib/utils.sh
get_agent_model() { echo vendor/model; }
cmd=$(get_agent_command opencode) || exit
octo_dispatch_command_to_argv "$cmd" || exit
build_provider_env opencode vendor/model || exit
"${PROVIDER_ENV_ARRAY[@]}" "${OCTO_COMMAND_ARGV[@]}"
""")
            self.assertEqual(child.returncode, 0, child.stderr)
            self.assertEqual(child.stdout.strip(), "run --standalone -m vendor/model")
            isolated = self.shell("""source scripts/lib/provider-routing.sh
build_provider_env codex || exit
"${PROVIDER_ENV_ARRAY[@]}" sh -c '
    test -z "${XDG_CONFIG_HOME+x}" && test -z "${XDG_CACHE_HOME+x}" && test -z "${XDG_STATE_HOME+x}"'
""")
            self.assertEqual(isolated.returncode, 0, "OpenCode roots reached isolated Codex")

    def test_opencode_workers_receive_mistral_only_when_the_selected_model_needs_it(self):
            """Explicit other-provider seats omit the ambient key; defaults retain it."""
            self.env.update(MISTRAL_API_KEY="fixture", UNRELATED_SETTING="preserved")
            for seat, model, retained in (
                    ("opencode", "openai/gpt-fixture", False),
                    ("opencode", "opencode/free-fixture", False),
                    ("opencode", "mistral/model-fixture", True),
                    ("opencode:mistral/model-fixture", "", True),
                    ("opencode:google/model-fixture", "", False),
                    ("opencode", "default", True), ("opencode", "configured-alias", True),
                    ("opencode", "custom-provider/model-fixture", True),
                    ("opencode:mistral/model-fixture", "openai/actual-command-model", False),
                    ("opencode:openai/model-fixture", "mistral/actual-command-model", True),
                    ("opencode", "", True)):
                with self.subTest(seat=seat, model=model):
                    self.env.update(TEST_SEAT=seat, TEST_MODEL=model,
                                    EXPECT_MISTRAL="yes" if retained else "no")
                    result = self.shell("""source scripts/lib/provider-routing.sh
build_provider_env "$TEST_SEAT" "$TEST_MODEL" || exit
"${PROVIDER_ENV_ARRAY[@]}" bash -c '
    [[ "$UNRELATED_SETTING" == preserved ]] || exit 70
    if [[ "$EXPECT_MISTRAL" == yes ]]; then [[ "$MISTRAL_API_KEY" == fixture ]]
    else [[ -z "${MISTRAL_API_KEY+x}" ]]; fi'
child_rc=$?
[[ "$MISTRAL_API_KEY" == fixture ]] || exit 71
exit "$child_rc"
""")
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_background_dispatch_uses_the_final_command_model_for_environment_filtering(self):
            """The environment boundary must follow command overrides, not a display model."""
            marker = self.base / "environment-model"
            self.env.update(ENV_MODEL_MARKER=str(marker))
            result = self.shell(r'''
source scripts/lib/spawn.sh
source scripts/lib/dispatch.sh
for helper in log match_routing_rule load_agent_checkpoint load_earned_skills build_provider_context octo_spawn_contract_plan octo_spawn_contract_resolve octo_spawn_contract_authenticated octo_spawn_contract_finish; do
    eval "$helper() { :; }"
done
check_provider_health() { :; }
octo_spawn_contract_seat_id() { echo spawn-fixture; }
classify_task() { echo standard; }
apply_persona() { printf %s "$2"; }
octo_with_engineering_methods() { printf %s "$2"; }
enforce_context_budget() { printf %s "$1"; }
octopus_effective_agent_timeout() { echo 0; }
get_agent_model() { echo mistral/display-model; }
get_agent_command() { echo 'opencode run --standalone -m google/actual-command-model'; }
validate_agent_command() { :; }
build_provider_env() { printf '%s\n' "$1" "${2:-}" > "$ENV_MODEL_MARKER"; return 1; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
spawn_agent opencode fixture fixture reviewer probe
''')
            self.assertEqual(result.returncode, 74, result.stdout + result.stderr)
            self.assertTrue(marker.exists(), result.stdout + result.stderr)
            self.assertEqual(marker.read_text().splitlines(),
                             ["opencode", "google/actual-command-model"])

    def test_cursor_probes_exclude_forwarded_mistral_key(self):
            """MCP discovery must keep OpenCode's credential out of Cursor startup."""
            agent = self.bin / "agent"
            agent.write_text("""#!/bin/sh
[ -z "${MISTRAL_API_KEY+x}" ] || touch "$PROBE_MARKER"
[ "$UNRELATED_SETTING" = preserved ] || exit 72
printf '%s\\n' "$*" >> "$CURSOR_CALLS"
case "$*" in
    --version) echo 2026.11.11-fixture ;;
    'status --format json') echo '{"isAuthenticated":true}' ;;
    *) exit 73 ;;
esac
""")
            agent.chmod(0o755)
            script = """import {loadProviderEnvAllowlist, providerEnvironment} from './shared/adapter-runtime.mjs';
console.log(JSON.stringify(providerEnvironment(loadProviderEnvAllowlist(process.cwd()),
    JSON.parse(process.argv[1]))));"""
            adapter = subprocess.run(["node", "--input-type=module", "-e", script,
                                      json.dumps({"MISTRAL_API_KEY":"fixture"})], cwd=ROOT,
                                     capture_output=True, text=True, check=False)
            self.assertEqual(adapter.returncode, 0, adapter.stderr)
            self.env.update(json.loads(adapter.stdout), UNRELATED_SETTING="preserved",
                            OCTO_ALLOWED_PROVIDERS="cursor-agent",
                            OCTOPUS_CURSOR_AGENT_AUTH_CACHE_TTL="0",
                            CURSOR_CALLS=str(self.base / "cursor-calls"))
            actions = (
                'source scripts/lib/cursor-agent.sh; _is_cursor_agent_binary',
                'source scripts/lib/cursor-agent.sh; cursor_agent_session_authenticated verified',
                'source scripts/lib/preflight.sh; octo_provider_readiness_result cursor-agent static | '
                'jq -e \' .status == "available" \'',
                'source scripts/lib/providers.sh; check_provider_health cursor-agent',
                'source scripts/lib/providers.sh; detect_providers | grep -F cursor-agent:cursor-session',
            )
            for action in actions:
                with self.subTest(action=action):
                    self.marker.unlink(missing_ok=True)
                    calls = Path(self.env["CURSOR_CALLS"])
                    calls.unlink(missing_ok=True)
                    result = self.shell(action + '; rc=$?; '
                                        '[[ "$MISTRAL_API_KEY" == fixture && "$UNRELATED_SETTING" == preserved ]] '
                                        '|| exit 74; exit "$rc"')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertTrue(calls.exists(), "Cursor startup fixture was not reached")
                    self.assertFalse(self.marker.exists(), "Mistral credential reached a Cursor probe")

    def test_commandcode_probe_excludes_forwarded_mistral_key(self):
            """OpenCode's forwarded credential must not reach an unrelated health CLI."""
            commandcode = self.bin / "command-code"
            commandcode.write_text('#!/bin/sh\n[ "$*" = \'status --json\' ] || exit 70\n[ -z "${MISTRAL_API_KEY+x}" ] || { touch "$PROBE_MARKER"; exit 71; }\n[ "$UNRELATED_SETTING" = preserved ] || exit 72\nexit 0\n')
            commandcode.chmod(0o755)
            self.env.update(MISTRAL_API_KEY="fixture", UNRELATED_SETTING="preserved",
                            OCTO_ALLOWED_PROVIDERS="commandcode")
            result = self.shell('source scripts/lib/providers.sh; check_provider_health commandcode; '
                                'rc=$?; [[ "$MISTRAL_API_KEY" == fixture ]] || exit 73; exit "$rc"')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(self.marker.exists(), "Mistral credential reached CommandCode")

    def test_claude_startup_probes_exclude_forwarded_mistral_key(self):
            """Host metadata probes must not inherit OpenCode's ambient credential."""
            claude = self.bin / "claude"
            claude.write_text("""#!/bin/sh
[ -z "${MISTRAL_API_KEY+x}" ] || { touch "$PROBE_MARKER"; exit 71; }
[ "$UNRELATED_SETTING" = preserved ] || exit 72
case "$1" in
    --version) [ "${VERSION_FALLBACK:-false}" != true ] || exit 1; echo 2.1.219 ;;
    version) echo 2.1.219 ;;
    --help) echo 'usage: claude --effort high' ;;
    --bare|auth) echo ok ;;
    *) exit 73 ;;
esac
""")
            claude.chmod(0o755)
            self.env.update(MISTRAL_API_KEY="fixture", UNRELATED_SETTING="preserved",
                            OCTOPUS_HOST="claude", OCTOPUS_CLAUDE_BIN="claude",
                            OCTO_ALLOWED_PROVIDERS="claude")
            # Source a real file: the previous process-substitution fixture left
            # check_claude_version undefined on the exact-head macOS CI run.
            version_function = (ROOT / "scripts/orchestrate.sh").read_text().split(
                "check_claude_version() {\n", 1)[1].split("\n}", 1)[0]
            version_fixture = self.base / "check-claude-version.sh"
            version_fixture.write_text("check_claude_version() {\n" + version_function + "\n}\n")
            self.env["CLAUDE_VERSION_FIXTURE"] = str(version_fixture)
            actions = (
                'source scripts/lib/providers.sh; _octo_host_version_output claude',
                'source scripts/lib/providers.sh; detect_claude_code_version; '
                '[[ "$SUPPORTS_EFFORT_CLI_FLAG" == true ]]',
                'source scripts/lib/providers.sh; '
                'source "$CLAUDE_VERSION_FIXTURE"; '
                'check_claude_version | grep -Fx "CLAUDE_CODE_VERSION=2.1.219"',
                'source scripts/lib/providers.sh; _octo_bare_auth_probe',
                'source scripts/lib/providers.sh; SUPPORTS_AUTH_CLI=true; detect_enterprise_backend',
                'source scripts/lib/providers.sh; SUPPORTS_AUTH_CLI=true; detect_providers',
            )
            for fallback, action in product(("false", "true"), actions):
                if fallback == "true" and action != actions[2]:
                    continue
                with self.subTest(fallback=fallback, action=action):
                    self.marker.unlink(missing_ok=True)
                    self.env["VERSION_FALLBACK"] = fallback
                    result = self.shell(action + '; rc=$?; [[ "$MISTRAL_API_KEY" == fixture ]] || exit 74; exit "$rc"')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertFalse(self.marker.exists(), "Mistral key reached Claude startup")

    def test_version_probe_excludes_all_forwarded_credentials(self):
            self.env.update(CLI_VERSION="2.0.23", OPENAI_API_KEY="inert-openai",
                            ANTHROPIC_API_KEY="inert-anthropic", GH_TOKEN="inert-github")
            self.cli.write_text(self.cli.read_text().replace(
                'printf called >>',
                '[ -z "${OPENAI_API_KEY+x}${ANTHROPIC_API_KEY+x}${GH_TOKEN+x}" ] || exit 78\nprintf called >>', 1))
            result = self.shell('source scripts/lib/auth.sh; _octo_opencode_cli_major')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "2")

    def test_login_probe_disables_project_plugins_and_uses_private_directory(self):
            project = self.base / "project"
            project.mkdir()
            (project / "opencode.json").write_text('{"plugin":["./project-plugin.js"]}')
            self.env.update(CLI_VERSION="2.0.23", PROJECT_ROOT=str(project), MISTRAL_API_KEY="fixture")
            self.cli.write_text(self.cli.read_text().replace(
                'printf called >>',
                'if [ "$1 $2" = "auth list" ]; then\n'
                '  [ "$PWD" != "$PROJECT_ROOT" ] || exit 79\n'
                '  [ "$OPENCODE_CONFIG_PROJECT_DISABLE" = 1 ] || exit 80\n'
                '  [ "$OPENCODE_DISABLE_PROJECT_CONFIG" = 1 ] || exit 81\n'
                '  [ "$MISTRAL_API_KEY" = fixture ] || exit 82\n'
                'fi\nprintf called >>', 1))
            result = self.shell('source "$PLUGIN_DIR/scripts/lib/auth.sh"; _octo_opencode_has_saved_login', root=project)
            self.assertEqual(result.returncode, 0, result.stderr)
