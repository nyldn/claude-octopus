#!/usr/bin/env python3
"""Exercise both OpenCode generations without auth, installs, or model calls."""
import json
import os
from itertools import product
from pathlib import Path
import shlex
import subprocess
import sys
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
    case "${CLI_VERSION:-1.18.34}" in
        2.*) [ "$*" = 'auth list --standalone --format json' ] || exit 67 ;;
    esac
    sleep "${AUTH_DELAY:-0}"
    if [ -n "${AUTH_LIST_FILE:-}" ]; then cat "$AUTH_LIST_FILE"; exit 0; fi
    case "$*" in
        *--format*) [ "$*" = 'auth list --standalone --format json' ] || exit 67; printf '%s\\n' "$AUTH_JSON" ;;
        *) printf '%s\\n' "$AUTH_LIST" ;;
    esac
    exit "${AUTH_RC:-0}"
fi
""")
        self.cli.chmod(0o755)
        self.env = {
            "PATH": f"{self.bin}:{Path(sys.executable).parent}:/usr/bin:/bin",
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

    def shell(self, script, *, root=ROOT, timeout=8):
        return subprocess.run(["bash", "-c", script], env=self.env, cwd=root,
                              text=True, capture_output=True, timeout=timeout)

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
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "run --standalone -m vendor/model")

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
        self.env["CLI_VERSION"] = "2.0.23"
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
            'printf called >>', '[ "$PWD" = "$PROJECT_ROOT" ] || exit 67\nprintf called >>', 1))
        project_bin = project / "bin"
        project_bin.mkdir()
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
            self.env["PATH"] = (f"bin:{Path(sys.executable).parent}:/usr/bin:/bin" if relative_path
                                else f"{self.bin}:{Path(sys.executable).parent}:/usr/bin:/bin")
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

    def test_preflight_missing_project_root_uses_current_directory(self):
        """Admission and direct probes must agree about absent project roots."""
        self.env.update(CLI_VERSION="2.0.23", OPENROUTER_API_KEY="fixture",
                        PROJECT_ROOT=str(self.base / "missing-project"), EXPECTED_CWD=str(ROOT))
        self.cli.write_text(self.cli.read_text().replace('printf called >>',
            '[ "$PWD" = "$EXPECTED_CWD" ] || exit 69\nprintf called >>', 1))
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
                self.env["PATH"] = f"{self.bin}:{Path(sys.executable).parent}:/usr/bin:/bin"
                Path(self.env["COMMAND_FILE"]).unlink(missing_ok=True)
                self.cli.write_text('#!/bin/sh\nif [ "$PWD" = "$PROJECT_ROOT" ]; then echo "$TARGET_VERSION"; else echo "$CALLER_VERSION"; fi\n')
                if relative_path:
                    for directory, version in ((caller, caller_version), (project, target_version)):
                        bindir = directory / "bin"
                        bindir.mkdir(exist_ok=True)
                        cli = bindir / "opencode"
                        cli.write_text(f"#!/bin/sh\necho {version}\n")
                        cli.chmod(0o755)
                    self.env["PATH"] = f"bin:{Path(sys.executable).parent}:/usr/bin:/bin"
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

    def test_mcp_environment_only_mistral_login_reaches_the_private_server(self):
        """Adapter filtering must retain the key that OpenCode confirms live."""
        script = """import {loadProviderEnvAllowlist, providerEnvironment} from './shared/adapter-runtime.mjs';
console.log(JSON.stringify(providerEnvironment(loadProviderEnvAllowlist(process.cwd()),
    {MISTRAL_API_KEY:'fixture', UNRELATED_PRIVATE_VALUE:'excluded'})));"""
        filtered = subprocess.run(["node", "--input-type=module", "-e", script],
                                  cwd=ROOT, capture_output=True, text=True, check=False)
        self.assertEqual(filtered.returncode, 0, filtered.stderr)
        forwarded = json.loads(filtered.stdout)
        self.assertNotIn("UNRELATED_PRIVATE_VALUE", forwarded)
        self.env.update(forwarded, CLI_VERSION="2.2.6")
        self.env["AUTH_JSON"] = '[{"id":"mistral","connections":[{"type":"environment"}]}]'
        self.cli.write_text(self.cli.read_text().replace(
            'sleep "${AUTH_DELAY:-0}"',
            '[ "$MISTRAL_API_KEY" = fixture ] || { printf "[]\\n"; exit 0; }\n'
            '    sleep "${AUTH_DELAY:-0}"'))
        self.assertEqual(self.readiness("static")["reason_code"], "auth-missing")
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.readiness("live")["status"], "available")
        self.cli.write_text(self.cli.read_text().replace(
            'if [ "$1" = run ]; then\n',
            'if [ "$1" = run ]; then\n    [ "${MISTRAL_API_KEY:-}" = fixture ] || exit 68\n'))
        child = self.shell('''source scripts/lib/provider-routing.sh
source scripts/lib/dispatch.sh
source scripts/lib/utils.sh
get_agent_model() { echo vendor/model; }
cmd=$(get_agent_command opencode) || exit
octo_dispatch_command_to_argv "$cmd" || exit
build_provider_env opencode || exit
"${PROVIDER_ENV_ARRAY[@]}" "${OCTO_COMMAND_ARGV[@]}"
''')
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertEqual(child.stdout.strip(), "run --standalone -m vendor/model")
        isolated = self.shell('''source scripts/lib/provider-routing.sh; build_provider_env codex
"${PROVIDER_ENV_ARRAY[@]}" bash -c '[[ -z "${MISTRAL_API_KEY+x}" ]]'
''')
        self.assertEqual(isolated.returncode, 0, "Mistral key reached the isolated Codex child")
        self.env.update(ANTHROPIC_API_KEY="claude-fixture", CLAUDE_SDK_API_KEY="sdk-fixture")
        for provider in ("claude", "claude-opus", "claude-sonnet", "claude-sdk", "claude-agent"):
            with self.subTest(provider=provider):
                isolated = self.shell(f'''source scripts/lib/provider-routing.sh
build_provider_env {provider} || exit
"${{PROVIDER_ENV_ARRAY[@]}}" bash -c '
    [[ -z "${{MISTRAL_API_KEY+x}}" ]] &&
    [[ "$ANTHROPIC_API_KEY" == claude-fixture ]] &&
    [[ "$CLAUDE_SDK_API_KEY" == sdk-fixture ]]'
child_rc=$?
[[ "$MISTRAL_API_KEY" == fixture ]] || exit 69
exit "$child_rc"
''')
                self.assertEqual(isolated.returncode, 0,
                                 f"Mistral isolation or Claude authentication changed for {provider}")
        vibe = self.shell('''source scripts/lib/provider-routing.sh
build_provider_env vibe || exit
"${PROVIDER_ENV_ARRAY[@]}" bash -c '[[ "$MISTRAL_API_KEY" == fixture ]]'
''')
        self.assertEqual(vibe.returncode, 0, "Mistral key no longer reaches Vibe")

    def test_forwarded_mistral_key_is_absent_from_unrelated_children(self):
        """Default CLI and shell-function routes must enforce the same boundary."""
        self.env.update(MISTRAL_API_KEY="mistral-fixture", QWEN_API_KEY="qwen-fixture",
                        PERPLEXITY_API_KEY="perplexity-fixture",
                        OPENROUTER_API_KEY="openrouter-fixture",
                        ORCAROUTER_API_KEY="orcarouter-fixture",
                        KEENABLE_API_KEY="search-fixture")
        for provider in ("qwen", "qwen:vendor/model", "copilot", "ollama",
                         "perplexity", "openrouter", "orcarouter"):
            with self.subTest(provider=provider):
                result = self.shell(f'''source scripts/lib/provider-routing.sh
build_provider_env {provider} || exit
assert_child_env() {{
    [[ -z "${{MISTRAL_API_KEY+x}}" && -z "${{KEENABLE_API_KEY+x}}" ]] &&
    [[ "$QWEN_API_KEY" == qwen-fixture ]]
}}
case {provider} in
    perplexity|openrouter|orcarouter) "${{PROVIDER_ENV_ARRAY[@]}}" assert_child_env ;;
    *) "${{PROVIDER_ENV_ARRAY[@]}}" bash -c '
        [[ -z "${{MISTRAL_API_KEY+x}}" && -z "${{KEENABLE_API_KEY+x}}" ]] &&
        [[ "$QWEN_API_KEY" == qwen-fixture ]]' ;;
esac
child_rc=$?
[[ "$MISTRAL_API_KEY" == mistral-fixture && "$KEENABLE_API_KEY" == search-fixture ]] || exit 69
exit "$child_rc"
''')
                self.assertEqual(result.returncode, 0, f"Mistral key leaked into {provider}")

    def test_explicit_mistral_credential_selection_remains_usable(self):
        """Removing an ambient key must preserve an operator-selected key."""
        self.env.update(MISTRAL_API_KEY="selected-fixture",
                        OPENAI_COMPAT_API_KEY_ENV="MISTRAL_API_KEY")
        config = Path(self.env["HOME"]) / ".codex"
        config.mkdir()
        (config / "config.toml").write_text(
            'model_provider = "mistral"\n[model_providers.mistral]\n'
            'env_key = "MISTRAL_API_KEY"\n')
        for provider in ("codex", "openai-compatible-agent"):
            with self.subTest(provider=provider):
                result = self.shell(f'''source scripts/lib/provider-routing.sh
build_provider_env {provider} || exit
"${{PROVIDER_ENV_ARRAY[@]}}" bash -c '[[ "$MISTRAL_API_KEY" == selected-fixture ]]'
''')
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_mcp_preserves_sqlite_login_storage_selection(self):
        """The adapter and private server must discover the same login store."""
        database = self.data / "saved-login.db"
        database.write_bytes(b"inert-login-store")
        config = self.base / "custom-config"
        config.mkdir()
        config_file = config / "opencode.json"
        config_file.write_text('{"fixture":true}')
        self.cli.write_text(self.cli.read_text().replace(
            'printf called >>',
            '[ -f "${OPENCODE_CONFIG_DIR}/opencode.json" ] && [ -f "$OPENCODE_CONFIG" ] || exit 69\nprintf called >>', 1))
        for override in ("saved-login.db", str(database)):
            with self.subTest(database=override):
                self.marker.unlink(missing_ok=True)
                settings = {"XDG_DATA_HOME": self.env["XDG_DATA_HOME"],
                            "OPENCODE_DB": override,
                            "OPENCODE_CONFIG_DIR": str(config),
                            "OPENCODE_CONFIG": str(config_file),
                            "UNRELATED_PRIVATE_VALUE": "excluded"}
                script = """import {loadProviderEnvAllowlist, providerEnvironment} from './shared/adapter-runtime.mjs';
console.log(JSON.stringify(providerEnvironment(loadProviderEnvAllowlist(process.cwd()),
    JSON.parse(process.argv[1]))));"""
                adapter = subprocess.run(["node", "--input-type=module", "-e", script,
                                          json.dumps(settings)], cwd=ROOT, capture_output=True,
                                         text=True, check=False)
                self.assertEqual(adapter.returncode, 0, adapter.stderr)
                forwarded = json.loads(adapter.stdout)
                self.env.update(forwarded, CLI_VERSION="2.0.23")
                self.assertEqual(self.readiness("static")["reason_code"], "live-check-required")
                self.assertFalse(self.marker.exists(), "static storage discovery launched the CLI")
                self.assertEqual(self.readiness("live")["status"], "available")
                self.assertEqual(forwarded, {key: settings[key] for key in
                                            ("XDG_DATA_HOME", "OPENCODE_DB", "OPENCODE_CONFIG_DIR", "OPENCODE_CONFIG")})
                # Exercise the actual dispatch environment, not only the JS map.
                child = self.shell('''source scripts/lib/provider-routing.sh
build_provider_env opencode || exit
"${PROVIDER_ENV_ARRAY[@]}" sh -c \'case "$OPENCODE_DB" in
    /*) store=$OPENCODE_DB ;; *) store=$XDG_DATA_HOME/opencode/$OPENCODE_DB ;;
esac
test -f "$store" && test -f "$OPENCODE_CONFIG_DIR/opencode.json" && test -f "$OPENCODE_CONFIG" && opencode --version\'
''')
                self.assertEqual(child.returncode, 0, child.stderr)
                self.assertEqual(child.stdout.strip(), "2.0.23")
                isolated = self.shell('''source scripts/lib/provider-routing.sh
build_provider_env codex || exit
"${PROVIDER_ENV_ARRAY[@]}" sh -c \'test -z "${OPENCODE_DB+x}" && test -z "${XDG_DATA_HOME+x}" && test -z "${OPENCODE_CONFIG_DIR+x}" && test -z "${OPENCODE_CONFIG+x}"\'
''')
                self.assertEqual(isolated.returncode, 0, "OpenCode store selection reached Codex")
                self.assertEqual(database.read_bytes(), b"inert-login-store")
                self.assertEqual(config_file.read_text(), '{"fixture":true}')

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
