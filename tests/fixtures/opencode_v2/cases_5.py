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

class OpenCodeCases5(OpenCodeFixture):
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
            self.assertEqual(self.readiness("static")["reason_code"], "ready")
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
            self.env["AUTH_DELAY"] = "20"
            trace = self.base / "login-probe-trace"
            self.cli.write_text(self.cli.read_text().replace(
                'printf called >> "$PROBE_MARKER"',
                'printf \'%s\\n\' "$*" >> ' + shlex.quote(str(trace))))
            self.assertEqual(self.readiness("live")["status"], "degraded")
            self.assertIn("--version", trace.read_text().splitlines())
            self.assertIn("auth list", trace.read_text().splitlines())

    def test_provider_allowlist_prevents_live_probe(self):
            (self.data / "opencode.db").touch()
            self.env["OCTO_ALLOWED_PROVIDERS"] = "claude"
            self.assertEqual(self.readiness("live")["reason_code"], "disabled")
            self.assertFalse(self.marker.exists())

    def test_commandcode_availability_isolates_key_and_preserves_key_fast_path(self):
            cli = self.bin / "command-code"
            cli.write_text('#!/bin/sh\n[ "$*" = \'status --json\' ] || exit 70\n'
                           '[ -z "${MISTRAL_API_KEY+x}" ] || exit 71\n'
                           '[ "$UNRELATED_SETTING" = preserved ] || exit 72\n'
                           'printf called >> "$PROBE_MARKER"\n')
            cli.chmod(0o755)
            self.env.update(MISTRAL_API_KEY="fixture", UNRELATED_SETTING="preserved")
            for agent, api_key in product(("commandcode", "commandcode-fast", "commandcode-research"), (False, True)):
                with self.subTest(agent=agent, api_key=api_key):
                    self.marker.unlink(missing_ok=True)
                    self.env["COMMAND_CODE_API_KEY"] = "fixture" if api_key else ""
                    result = self.shell('source scripts/lib/model-resolver.sh; '
                                        'PROVIDERS_CONFIG_LOADED=true; is_claude_agent_type() { return 1; }; '
                                        f'is_agent_available_v2 {agent}; rc=$?; '
                                        '[[ "$MISTRAL_API_KEY" == fixture ]] || exit 73; exit "$rc"')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), not api_key)

    def test_debate_moderator_is_admitted_before_proposals_except_for_quorum(self):
            config = Path(self.env["HOME"]) / ".claude-octopus/config/providers.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"routing": {"features": {"debate": ["opencode"] * 3}}}))
            self.env.update(CLI_VERSION="2.0.23", OCTO_ALLOWED_PROVIDERS="opencode,claude")
            (self.data / "opencode.db").touch()
            script = self.production_inventory() + r"""
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
source scripts/lib/debate.sh
source scripts/lib/routing.sh
log() { :; }
mkdir() {
    if [[ "$*" == "-p $RESULTS_DIR $LOGS_DIR" ]]; then exit 77; fi
    command mkdir "$@"
}
WORKSPACE_DIR="$HOME" RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs" DRY_RUN=false
grapple_debate fixture
"""
            claude = self.bin / "claude"
            for mode, installed in product(("moderator", "quorum"), (False, True)):
                with self.subTest(mode=mode, installed=installed):
                    self.env["OCTOPUS_CONSENSUS"] = mode
                    claude.unlink(missing_ok=True)
                    if installed:
                        claude.write_text('#!/bin/sh\nexit 0\n')
                        claude.chmod(0o755)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 77 if installed or mode == "quorum" else 1,
                                     result.stdout + result.stderr)

    def test_squeeze_requires_every_provider_before_any_phase(self):
            self.env.update(OCTO_ALLOWED_PROVIDERS="opencode,codex,agy,claude", OPENAI_API_KEY="fixture",
                            OPENROUTER_API_KEY="fixture", DRY_RUN="false")
            script = r"""
source scripts/lib/preflight.sh
source scripts/lib/testing.sh
log() { :; }
check_codex_auth_freshness() { :; }
_preflight_provider_candidates() { echo opencode; }
detect_enterprise_backend() { :; }
provider_smoke_test() { :; }
run_agent_sync() { printf called > "$PROBE_MARKER"; exit 77; }
WORKSPACE_DIR="$HOME" RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
PREFLIGHT_CACHE_FILE="$HOME/preflight-cache"
squeeze_test fixture
"""
            for missing in ("codex", "agy", "claude", ""):
                with self.subTest(missing=missing):
                    self.marker.unlink(missing_ok=True)
                    for name in ("codex", "agy", "claude"):
                        cli = self.bin / name
                        cli.unlink(missing_ok=True)
                        if name != missing:
                            cli.write_text('#!/bin/sh\nexit 0\n')
                            cli.chmod(0o755)
                    result = self.shell(script, timeout=15)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), not missing, result.stdout + result.stderr)
                    self.assertNotIn("exercise complete", result.stdout)
                    self.assertFalse(list(Path(self.env["HOME"]).glob("results/squeeze-*.md")))

    def test_squeeze_empty_or_failed_fallback_never_publishes_completion(self):
            script = r"""
source scripts/lib/testing.sh
log() { :; }
preflight_check() { return 0; }
run_agent_sync() {
    local calls=0
    [[ ! -f "$PROBE_MARKER" ]] || read -r calls < "$PROBE_MARKER"
    calls=$((calls + 1)); printf '%s\n' "$calls" > "$PROBE_MARKER"
    if [[ "$5" == squeeze && "$4" == "$FAILED_ROLE" ]]; then
        if [[ "$FAILURE_MODE" == error ]]; then echo diagnostic; return 1; fi
        printf ' \t\n'; return 0
    fi
    printf 'fixture response\n'
}
DRY_RUN=false RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
squeeze_test fixture
"""
            for role, failure in product(("backend-architect", "security-auditor", "implementer", "code-reviewer"),
                                         ("empty", "error")):
                with self.subTest(role=role, failure=failure):
                    self.env.update(FAILED_ROLE=role, FAILURE_MODE=failure)
                    self.marker.unlink(missing_ok=True)
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn("exercise complete", result.stdout)
                    self.assertFalse(list(Path(self.env["HOME"]).glob("results/squeeze-*.md")))

    def test_completed_research_resume_returns_without_live_admission(self):
            run = self.base / "research" / "saved"
            run.mkdir(parents=True)
            results = self.base / "results"
            results.mkdir()
            synthesis = results / "probe-synthesis-saved.md"
            self.env.update(OCTOPUS_RESEARCH_ROOT=str(run.parent), OCTOPUS_RESEARCH_RUN_ID="saved",
                            DRY_RUN="false", SAVED_RESULTS=str(results))
            script = r"""
source scripts/lib/research-evidence.sh
source scripts/lib/workflows.sh
log() { :; }
octopus_phase_banner() { :; }
preflight_check() { printf admission >> "$PROBE_MARKER"; return 1; }
RESULTS_DIR="$SAVED_RESULTS"
probe_discover fixture
"""
            for resume, completed, saved in ((True, True, True), (True, False, True),
                                             (True, True, False), (False, True, True)):
                with self.subTest(resume=resume, completed=completed, saved=saved):
                    self.marker.unlink(missing_ok=True)
                    synthesis.unlink(missing_ok=True)
                    if saved:
                        synthesis.write_text("# Saved verified synthesis\n")
                    (run / "manifest.json").write_text(json.dumps({
                        "task_group": "saved", "prompt": "saved question", "intensity": "standard",
                        "provider_results_dir": str(results), "project_root": str(ROOT),
                        "status": "completed" if completed else "running", "stage": "complete"
                    }, indent=2))
                    self.env["OCTOPUS_RESEARCH_RESUME"] = "true" if resume else "false"
                    result = self.shell(script)
                    returns_saved = resume and completed and saved
                    self.assertEqual(result.returncode, 0 if returns_saved else 1, result.stdout + result.stderr)
                    self.assertEqual(self.marker.exists(), not returns_saved)
                    self.assertEqual(synthesis.exists(), saved)
                    if returns_saved:
                        self.assertIn(str(synthesis), result.stdout)
            # A fresh, rejected run must not create durable evidence.
            self.env.update(OCTOPUS_RESEARCH_RUN_ID="fresh", OCTOPUS_RESEARCH_RESUME="false")
            result = self.shell(script)
            self.assertEqual(result.returncode, 1)
            self.assertFalse((run.parent / "fresh").exists())

    def test_quorum_only_admits_moderator_when_consensus_needs_fallback(self):
            config = Path(self.env["HOME"]) / ".claude-octopus/config/providers.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"routing": {"features": {"debate": ["opencode"] * 3}}}))
            self.env.update(OCTOPUS_CONSENSUS="quorum", DRY_RUN="false",
                            ADMISSION_LOG=str(self.base / "admission"))
            script = self.production_inventory() + r"""
source scripts/lib/preflight.sh
source scripts/lib/config-display.sh
source scripts/lib/debate.sh
source scripts/lib/routing.sh
log() { :; }
preflight_check() {
    printf '%s\n' "$OCTOPUS_PREFLIGHT_PROVIDERS" >> "$ADMISSION_LOG"
    [[ "$OCTOPUS_PREFLIGHT_PROVIDERS" != claude || "$MODERATOR_READY" == true ]]
}
run_agent_sync() { printf '%s\n' "$1" >> "$PROBE_MARKER"; echo 'fixture answer'; }
apply_consensus() { printf '%s\n' "$QUORUM_RESULT"; }
octopus_complete() { :; }
record_agent_call() { :; }
RESULTS_DIR="$HOME/results" LOGS_DIR="$HOME/logs"
grapple_debate fixture general 3 blinded
"""
            for consensus, ready in product((True, False), (True, False)):
                with self.subTest(consensus=consensus, ready=ready):
                    self.marker.unlink(missing_ok=True)
                    admission = Path(self.env["ADMISSION_LOG"])
                    admission.unlink(missing_ok=True)
                    self.env.update(QUORUM_RESULT="majority" if consensus else "MODERATOR_MODE",
                                    MODERATOR_READY="true" if ready else "false")
                    result = self.shell(script)
                    self.assertEqual(result.returncode, 0 if consensus or ready else 1,
                                     result.stdout + result.stderr)
                    self.assertEqual(admission.read_text().splitlines(),
                                     ["opencode"] if consensus else ["opencode", "claude"])
                    self.assertEqual("claude" in self.marker.read_text().splitlines(), not consensus and ready)
