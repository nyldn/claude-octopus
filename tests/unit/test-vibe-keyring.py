#!/usr/bin/env python3
"""Exercise Vibe readiness against an isolated, inert Python installation."""
import os
import json
import re
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class VibeKeyringTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.home = self.base / 'home'
        self.bin = self.base / 'bin'
        self.home.mkdir()
        self.bin.mkdir()
        environment = self.base / 'venv'
        (environment / 'bin').mkdir(parents=True)
        (environment / 'pyvenv.cfg').write_text(
            f'home = {Path(sys.executable).resolve().parent}\ninclude-system-site-packages = false\n')
        self.python = environment / 'bin/python3'
        self.python.symlink_to(sys.executable)
        packages = environment / f'lib/python{sys.version_info.major}.{sys.version_info.minor}/site-packages'
        self.module = packages / 'vibe/utils/keyring.py'
        self.module.parent.mkdir(parents=True)
        (packages / 'vibe/__init__.py').touch()
        (packages / 'vibe/utils/__init__.py').touch()
        self.vibe = self.bin / 'vibe'
        self.vibe.write_text(f'#!{self.python}\nraise RuntimeError("CLI must not execute")\n')
        self.vibe.chmod(0o755)
        self.marker = self.base / 'probed'
        self.import_marker = self.base / 'imported'
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        OCTOPUS_SKIP_PROVIDER_PROBES='false', OCTO_ALLOWED_PROVIDERS='vibe',
                        MISTRAL_API_KEY='', VIBE_PROBE_MARKER=str(self.marker))
        self.env.pop('OCTOPUS_COUNCIL_DEFAULT_PROVIDERS', None)
        self.env.pop('_octo_vibe_check_context', None)
        self.env.pop('PYTHONUSERBASE', None)
        self.write_module('return "inert-fixture-value"')

    def write_module(self, body):
        self.module.write_text('import os\nfrom pathlib import Path\n'
                               f'Path({str(self.import_marker)!r}).touch()\n'
                               'def get_api_key_from_keyring(*args, **kwargs):\n'
                               '    raise RuntimeError("migration-capable lookup forbidden")\n'
                               'def probe_api_key_from_keyring(key):\n'
                               '    assert key == "MISTRAL_API_KEY"\n'
                               f'    Path({str(self.marker)!r}).write_text(str(os.getpid()))\n'
                               + '\n'.join('    ' + line for line in body.splitlines()) + '\n')

    def shell(self, command):
        return subprocess.run(['bash', '-c', f'source {shlex.quote(str(ROOT / "scripts/lib/preflight.sh"))}; '
                               f'source {shlex.quote(str(ROOT / "scripts/lib/providers.sh"))}; {command}'],
                              cwd=self.home, env=self.env, capture_output=True, text=True, timeout=30)

    def test_keyring_only_auth_reaches_every_readiness_consumer(self):
        result = self.shell('octo_provider_readiness_result vibe static; check_provider_health vibe && detect_providers')
        self.assertEqual(result.returncode, 0, result.stderr)
        readiness = json.loads(result.stdout.splitlines()[0])
        self.assertEqual((readiness['status'], readiness['reason_code']), ('available', 'ready'))
        self.assertIn('vibe:none', result.stdout)
        self.assertNotIn('inert-fixture-value', result.stdout + result.stderr)
        self.assertTrue(self.marker.exists())

    def test_missing_blank_and_broken_keyring_fail_closed_and_silent(self):
        for body in ('return None', 'return "  "', 'raise RuntimeError("inert-fixture-value")'):
            with self.subTest(body=body):
                self.write_module(body)
                result = self.shell('_octo_vibe_keyring_has_key selected')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout + result.stderr, '')

    def test_import_and_probe_exits_cannot_report_a_credential(self):
        """An installed package exiting successfully is not key-presence proof."""
        for stage in ('import', 'probe'):
            for error in ('SystemExit(0)', 'SystemExit()', 'KeyboardInterrupt()'):
                with self.subTest(stage=stage, error=error):
                    self.write_module(f'raise {error}' if stage == 'probe' else 'return None')
                    if stage == 'import':
                        self.module.write_text(f'raise {error}\n' + self.module.read_text())
                    result = self.shell('_octo_vibe_keyring_has_key selected')
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout + result.stderr, '')

    def test_read_only_fallback_never_uses_migrating_lookup(self):
        self.module.write_text('_KEYRING_SERVICE = "ai.mistral.vibe"\n'
                               '_LEGACY_KEYRING_SERVICES = ("vibe",)\n'
                               'def _get_password(service, key):\n'
                               '    assert key == "MISTRAL_API_KEY"\n'
                               '    return "inert-fixture-value" if service == "vibe" else None\n'
                               'def get_api_key_from_keyring(*args):\n'
                               '    raise RuntimeError("must not migrate")\n')
        result = self.shell('_octo_vibe_keyring_has_key selected')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout + result.stderr, '')

    def test_probe_output_is_suppressed(self):
        self.write_module('print("inert-fixture-value")\nreturn "inert-fixture-value"')
        result = self.shell('_octo_vibe_keyring_has_key selected')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout + result.stderr, '')

    def test_skip_setting_and_non_python_wrapper_do_not_execute(self):
        for skip in ('true', '1'):
            self.env['OCTOPUS_SKIP_PROVIDER_PROBES'] = skip
            self.assertNotEqual(self.shell('_octo_vibe_keyring_has_key selected').returncode, 0)
            self.assertFalse(self.marker.exists())
        self.env['OCTOPUS_SKIP_PROVIDER_PROBES'] = 'false'
        self.vibe.write_text('#!/bin/sh\nexit 99\n')
        self.assertNotEqual(self.shell('_octo_vibe_keyring_has_key selected').returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_env_python_entrypoints_use_the_selected_environment(self):
        for name in ('python', 'python3', f'python3.{sys.version_info.minor}'):
            with self.subTest(name=name):
                self.marker.unlink(missing_ok=True)
                alias = self.python.parent / name
                if not alias.exists():
                    alias.symlink_to(self.python)
                self.env['PATH'] = f'{self.python.parent}:{self.bin}:/usr/bin:/bin'
                self.vibe.write_text(f'#!/usr/bin/env {name}\nraise RuntimeError("CLI must not execute")\n')
                result = self.shell('octo_provider_readiness_result vibe static')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)['status'], 'available')
                self.assertTrue(self.marker.exists())
                self.marker.unlink()
                result = self.shell('octo_provider_readiness_all static')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.marker.exists(), 'env wrapper bypassed automatic discovery deferral')

    def test_env_entrypoints_with_options_or_non_python_commands_fail_closed(self):
        for command in ('-S python3', 'python3 -I', 'bash', 'python3; echo unsafe'):
            with self.subTest(command=command):
                self.vibe.write_text(f'#!/usr/bin/env {command}\nexit 99\n')
                result = self.shell('_octo_vibe_keyring_has_key selected')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout + result.stderr, '')
                self.assertFalse(self.marker.exists())

    def test_existing_credentials_do_not_probe_keyring(self):
        self.env['MISTRAL_API_KEY'] = 'inert-fixture-value'
        result = self.shell('_octo_provider_static_readiness vibe; check_provider_health vibe; detect_providers')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('available|ready|', result.stdout)
        self.assertIn('vibe:api-key', result.stdout)
        self.assertFalse(self.marker.exists())

    def test_existing_file_credentials_keep_automatic_and_selected_checks_ready(self):
        config = self.home / '.vibe'
        config.mkdir()
        for name, assignment in (('.env', 'MISTRAL_API_KEY'), ('config.toml', 'api_key')):
            with self.subTest(name=name):
                credential = config / name
                credential.write_text(f'{assignment}="inert-fixture-value"\n')
                try:
                    for context in ('automatic', 'selected'):
                        result = self.shell(f'_octo_vibe_check_context={context}; '
                                            'octo_provider_readiness_result vibe static; '
                                            'check_provider_health vibe')
                        self.assertEqual(result.returncode, 0, result.stderr)
                        readiness = json.loads(result.stdout)
                        self.assertEqual((readiness['status'], readiness['reason_code']),
                                         ('available', 'ready'))
                        self.assertFalse(self.marker.exists(), 'file credential loaded Vibe code')
                        self.assertNotIn('inert-fixture-value', result.stdout + result.stderr)
                finally:
                    credential.unlink()

    def test_locked_keyring_has_a_real_wall_clock_bound(self):
        self.write_module('import time\ntime.sleep(60)\nreturn "inert-fixture-value"')
        start = time.monotonic()
        result = self.shell('_octo_vibe_keyring_has_key selected')
        elapsed = time.monotonic() - start
        self.assertTrue(self.marker.exists(), 'probe must start for timeout test to count')
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(elapsed, 6)
        self.assertEqual(result.stdout + result.stderr, '')
        pid = int(self.marker.read_text())
        for _ in range(20):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            self.fail(f'timed-out probe process {pid} survived cleanup')

    def test_automatic_discovery_does_not_load_vibe_code(self):
        result = self.shell('detect_providers; octo_provider_readiness_all static; '
                            'octo_provider_ids() { printf "vibe\\n"; }; check_all_providers; '
                            f'bash {shlex.quote(str(ROOT / "scripts/capabilities.sh"))} --json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('vibe:none', result.stdout)
        self.assertFalse(self.marker.exists(), 'unselected Vibe code ran during discovery')
        self.assertFalse(self.import_marker.exists(), 'discovery imported unselected Vibe code')

    def test_preflight_keyring_deferral_names_the_explicit_setup_flow(self):
        """The normal CLI must explain how to authorize the deferred check."""
        result = self.shell(f'bash {shlex.quote(str(ROOT / "scripts/helpers/preflight.sh"))} --json')
        self.assertEqual(result.returncode, 0, result.stderr)
        vibe = next(row for row in json.loads(result.stdout)['results'] if row['provider'] == 'vibe')
        self.assertEqual((vibe['status'], vibe['reason_code']), ('degraded', 'live-check-required'))
        self.assertIn('/octo:setup', vibe['remediation'])
        self.assertIn('select Vibe', vibe['remediation'])
        self.assertIn('MISTRAL_API_KEY', vibe['remediation'])
        self.assertFalse(self.import_marker.exists(), 'automatic preflight imported Vibe')

    def test_broad_live_readiness_does_not_load_vibe_code(self):
        result = self.shell('octo_provider_readiness_all live')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.marker.exists(), 'broad live scan loaded unselected Vibe code')
        self.assertFalse(self.import_marker.exists(), 'broad live scan imported unselected Vibe code')
        vibe = next(json.loads(line) for line in result.stdout.splitlines()
                    if json.loads(line)['provider'] == 'vibe')
        self.assertEqual((vibe['status'], vibe['reason_code']), ('degraded', 'live-check-required'))
        self.assertIn('select Vibe', vibe['remediation'])
        selected = self.shell('octo_provider_readiness_all live vibe')
        self.assertEqual(selected.returncode, 0, selected.stderr)
        self.assertTrue(self.marker.exists(), 'explicit selection must still inspect Vibe')

    def test_single_provider_probe_preserves_explicit_vibe_selection(self):
        """Run the real workflow through preflight, stopping before dispatch."""
        command = (f'source {shlex.quote(str(ROOT / "scripts/lib/workflows.sh"))}; '
                   'log() { :; }; preflight_cache_valid() { return 1; }; '
                   'preflight_cache_write() { :; }; '
                   '_preflight_provider_candidates() { printf "vibe\\n"; }; '
                   'detect_enterprise_backend() { :; }; provider_smoke_test() { :; }; '
                   'WORKSPACE_DIR="$HOME"; RESULTS_DIR="$HOME/results"; LOGS_DIR="$HOME/logs"; '
                   'research_probe_single_begin() { echo reached-dispatch-boundary; return 1; }; '
                   'probe_single_agent vibe "inert research" test-selection')
        result = self.shell(command)
        self.assertIn('reached-dispatch-boundary', result.stdout, result.stdout + result.stderr)
        self.assertTrue(self.marker.exists(), 'explicit workflow never inspected keyring')
        self.assertNotIn('inert-fixture-value', result.stdout + result.stderr)

    def test_selected_preflight_cannot_reuse_or_grant_an_automatic_cache_pass(self):
        command = ('log() { :; }; preflight_cache_valid() { return 0; }; '
                   'preflight_cache_read() { echo 0; }; '
                   'preflight_cache_write() { echo cache-status="$1"; }; '
                   '_preflight_provider_candidates() { printf "vibe\\n"; }; '
                   'detect_enterprise_backend() { :; }; provider_smoke_test() { :; }; '
                   'WORKSPACE_DIR="$HOME"; preflight_check false vibe')
        result = self.shell(command)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.marker.exists(), 'automatic cached pass skipped selected check')
        self.assertNotIn('cache-status=', result.stdout, 'selected result changed the shared cache')

    def test_unselected_workflow_and_invalid_council_roster_do_not_load_vibe(self):
        for selection, roster in (('', ''), ('codex', ''), ('vibe', 'vibe')):
            with self.subTest(selection=selection, roster=roster):
                self.env['OCTOPUS_COUNCIL_DEFAULT_PROVIDERS'] = roster
                result = self.shell('log() { :; }; preflight_cache_valid() { return 1; }; '
                                    'preflight_cache_write() { :; }; '
                                    '_preflight_provider_candidates() { printf "vibe\\n"; }; '
                                    f'preflight_check true {shlex.quote(selection)}')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.import_marker.exists(), 'unselected Vibe was imported')

    def test_selected_vibe_preserves_existing_general_cache_without_granting_one(self):
        """A selected-only success must leave the general cache unchanged."""
        cache = self.base / 'general-cache'
        for initial in (None, '0', '1'):
            with self.subTest(initial=initial):
                cache.unlink(missing_ok=True)
                if initial is not None:
                    cache.write_text(initial)
                result = self.shell('log() { :; }; '
                                    'preflight_cache_valid() { return 1; }; '
                                    'preflight_cache_write() { printf "%s" "$1" > '
                                    + shlex.quote(str(cache)) + '; }; '
                                    'detect_enterprise_backend() { :; }; provider_smoke_test() { :; }; '
                                    'WORKSPACE_DIR="$HOME"; preflight_check true vibe')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(cache.read_text() if cache.exists() else None, initial)
                self.assertTrue(self.marker.exists())

    def test_non_vibe_selection_preserves_automatic_cache_behavior(self):
        self.env['MISTRAL_API_KEY'] = 'inert-fixture-value'
        for force in ('false', 'true'):
            with self.subTest(force=force):
                result = self.shell('log() { :; }; preflight_cache_valid() { return 0; }; '
                                    'preflight_cache_read() { echo 0; }; '
                                    'preflight_cache_write() { echo cache-status="$1"; }; '
                                    '_preflight_provider_candidates() { echo discovery-called >&2; printf "vibe\\n"; }; '
                                    'detect_enterprise_backend() { :; }; provider_smoke_test() { :; }; '
                                    f'WORKSPACE_DIR="$HOME"; preflight_check {force} codex')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if force == 'false':
                    self.assertNotIn('discovery-called', result.stderr, 'non-Vibe selection lost its cached pass')
                else:
                    self.assertIn('cache-status=0', result.stdout, 'automatic-equivalent result was not cached')
                self.assertFalse(self.import_marker.exists())

    def test_keyring_read_can_use_two_seconds_of_total_budget(self):
        self.write_module('import time\ntime.sleep(1.3)\nreturn "inert-fixture-value"')
        result = self.shell('_octo_vibe_keyring_has_key selected')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_total_probe_budget_stays_three_seconds(self):
        budget = self.base / 'budget'
        result = self.shell('run_with_timeout() { printf "%s %s" "$2" '
                            '"$OCTOPUS_TIMEOUT_KILL_GRACE" > ' + shlex.quote(str(budget)) +
                            '; return 1; }; _octo_vibe_keyring_has_key selected')
        self.assertNotEqual(result.returncode, 0)
        term, grace = map(int, budget.read_text().split())
        self.assertEqual(term + grace, 3)

    def test_resumed_setup_preserves_completed_keyring_selection(self):
        for path in ('commands/setup.md', '.cursor-plugin/commands/octo-setup.md'):
            with self.subTest(path=path):
                for receipt in (self.home / '.claude-octopus/setup').glob('*.json'):
                    receipt.unlink()
                text = (ROOT / path).read_text()
                helpers = text.split('SETUP_STATE_HELPER=', 1)[1].split('\n```', 1)[0]
                helpers = 'SETUP_STATE_HELPER=' + helpers
                initial = text.split('### 2. Show shared readiness', 1)[1].split('```bash\n', 1)[1].split('\n```', 1)[0]
                command = (f'OCTO_ROOT={shlex.quote(str(ROOT))}; ' + helpers + '\n'
                           'SETUP_FLOW=one-provider; SETUP_PROVIDER=vibe; '
                           'setup_record selected null >/dev/null; '
                           'setup_record rechecked \'{"result":"passed","reason_code":"ready","checked_at":"test"}\' >/dev/null; '
                           'setup_record verified \'{"result":"passed","reason_code":"ready","checked_at":"test"}\' >/dev/null; '
                           + helpers + '\nunset SETUP_FLOW SETUP_PROVIDER\n' + initial + '\n'
                           'printf "\\nSTAGE=%s" "$(jq -r .record.stage <<<"$SETUP_RECEIPT")"')
                result = self.shell(command)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('STAGE=verified', result.stdout)
                self.assertIn('vibe: available [ready]', result.stdout)

    def test_probe_does_not_receive_other_credentials_or_loader_environment(self):
        self.env.update(OPENAI_API_KEY='inert-fixture-value', GITHUB_TOKEN='inert-fixture-value',
                        ANTHROPIC_API_KEY='inert-fixture-value', PYTHONPATH=str(self.base),
                        HTTP_PROXY='http://example.invalid')
        self.write_module('assert not any(name in os.environ for name in '
                          '("OPENAI_API_KEY", "GITHUB_TOKEN", "ANTHROPIC_API_KEY", '
                          '"PYTHONPATH", "HTTP_PROXY", "VIBE_PROBE_MARKER"))\n'
                          'return "inert-fixture-value"')
        result = self.shell('_octo_vibe_keyring_has_key selected')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout + result.stderr, '')

    def test_user_site_keyring_login_without_processing_pth_or_project_modules(self):
        """Explicit user-site selection must retain Python loader isolation."""
        base_python = getattr(sys, '_base_executable', None) or sys.executable
        result = subprocess.run([base_python, '-I', '-c',
                                 'import site; print(site.getusersitepackages())'],
                                env=self.env, capture_output=True, text=True, check=True, timeout=30)
        packages = Path(result.stdout.strip())
        target = packages / 'vibe/utils/keyring.py'
        target.parent.mkdir(parents=True)
        (packages / 'vibe/__init__.py').touch()
        (packages / 'vibe/utils/__init__.py').touch()
        self.module.rename(target)
        # Exclude host-global packages too, so a developer's real Vibe install
        # cannot be imported or touch its keyring during this inert regression.
        interpreter = self.bin / 'python-user-site'
        interpreter.write_text(f'#!/bin/sh\nexec {shlex.quote(base_python)} -S "$@"\n')
        interpreter.chmod(0o755)
        self.vibe.write_text(f'#!{interpreter}\nraise RuntimeError("CLI must not execute")\n')
        loader_marker = self.base / 'loader-executed'
        malicious = f'open({str(loader_marker)!r}, "w").write("executed")\n'
        (packages / 'unsafe.pth').write_text('import os; ' + malicious)
        (packages / 'sitecustomize.py').write_text(malicious)
        (self.home / 'site.py').write_text(malicious)
        (self.home / 'vibe.py').write_text(malicious)
        self.env.update(PYTHONPATH=str(self.home), PYTHONUSERBASE=str(self.base / 'wrong-user-base'))
        result = self.shell('octo_provider_readiness_result vibe static; check_provider_health vibe')
        self.assertEqual(result.returncode, 0, result.stderr)
        readiness = json.loads(result.stdout)
        self.assertEqual((readiness['status'], readiness['reason_code']), ('available', 'ready'))
        self.assertTrue(self.marker.exists(), 'selected user-site Vibe keyring was not checked')
        self.assertTrue(self.import_marker.exists())
        self.assertFalse(loader_marker.exists(), 'isolated probe executed a Python loader hook')
        self.assertNotIn('inert-fixture-value', result.stdout + result.stderr)

    def test_user_site_precedes_global_packages_without_shadowing_stdlib(self):
        """A user-installed CLI must inspect its own keyring implementation."""
        base_python = getattr(sys, '_base_executable', None) or sys.executable
        result = subprocess.run([base_python, '-I', '-S', '-c',
                                 'import site; print(site.getusersitepackages())'],
                                env=self.env, capture_output=True, text=True, check=True, timeout=30)
        user_site = Path(result.stdout.strip())
        global_site = self.base / 'global-site'
        global_marker = self.base / 'global-imported'
        self.write_module('import sys\n'
                          f'assert sys.path.index({str(user_site)!r}) < '
                          f'sys.path.index({str(global_site)!r})\n'
                          'import fractions\nreturn "inert-fixture-value"')
        for packages, source in ((user_site, self.module.read_text()),
                                 (global_site, 'from pathlib import Path\n'
                                  f'Path({str(global_marker)!r}).touch()\n'
                                  'def probe_api_key_from_keyring(key):\n    return None\n')):
            target = packages / 'vibe/utils/keyring.py'
            target.parent.mkdir(parents=True)
            (packages / 'vibe/__init__.py').touch()
            (packages / 'vibe/utils/__init__.py').touch()
            target.write_text(source)
        loader_marker = self.base / 'loader-executed'
        (user_site / 'fractions.py').write_text('raise RuntimeError("stdlib shadowed")\n')
        (user_site / 'unsafe.pth').write_text(
            f'import pathlib; pathlib.Path({str(loader_marker)!r}).touch()\n')
        (user_site / 'sitecustomize.py').write_text(
            f'from pathlib import Path; Path({str(loader_marker)!r}).touch()\n')
        global_alias = self.base / 'global-alias'
        global_alias.symlink_to(global_site, target_is_directory=True)
        for configured_site in (global_site, global_alias):
            with self.subTest(configured_site=configured_site):
                for marker in (self.marker, self.import_marker, global_marker):
                    marker.unlink(missing_ok=True)
                launcher = ('import runpy, site, sys; '
                            f'sys.path.append({str(global_site)!r}); '
                            f'site.getsitepackages = lambda: [{str(configured_site)!r}]; '
                            'runpy.run_path(sys.argv[-1], run_name="__main__")')
                interpreter = self.bin / 'python-mixed-site'
                interpreter.write_text(f'#!/bin/sh\nexec {shlex.quote(base_python)} -I -S -c '
                                       f'{shlex.quote(launcher)} "$@"\n')
                interpreter.chmod(0o755)
                self.vibe.write_text(f'#!{interpreter}\nraise RuntimeError("CLI must not execute")\n')
                result = self.shell('octo_provider_readiness_result vibe static; check_provider_health vibe')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)['status'], 'available')
                self.assertTrue(self.marker.exists(), 'user-site keyring was not checked')
                self.assertFalse(global_marker.exists(), 'global Vibe shadowed the selected user install')
                self.assertFalse(loader_marker.exists(), 'user-site loader hooks executed')
                self.assertNotIn('inert-fixture-value', result.stdout + result.stderr)

    def test_user_site_fixtures_ignore_inherited_python_user_base(self):
        """An inherited user base must not redirect fixture writes outside HOME."""
        external = self.base / 'outside-user-base'
        environment = dict(self.env, PYTHONUSERBASE=str(external))
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()),
                                 'VibeKeyringTest.test_user_site_keyring_login_without_processing_pth_or_project_modules',
                                 'VibeKeyringTest.test_user_site_precedes_global_packages_without_shadowing_stdlib'],
                                env=environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(external.exists(), 'fixture wrote into the inherited user base')

    def test_one_provider_setup_carries_the_selected_vibe_context(self):
        text = (ROOT / 'commands/setup.md').read_text()
        capture = re.search(r'^setup_readiness_capture\(\) \{.*?^\}', text, re.M | re.S)[0]
        selected = text.split('Before showing provider instructions,', 1)[1].split('```bash\n', 1)[1].split('\n```', 1)[0]
        command = (f'OCTO_ROOT={shlex.quote(str(ROOT))}; '
                   f'READINESS_CONTRACT_HELPER={shlex.quote(str(ROOT / "scripts/helpers/readiness-contract.py"))}; '
                   'SETUP_FLOW=one-provider; SETUP_PROVIDER=vibe; '
                   'READINESS_JSON=\'{"results":[{"provider":"vibe","status":"degraded",'
                   '"reason_code":"live-check-required","checked_at":"test"}]}\'; '
                   'setup_record() { :; }; setup_fail_recheck() { return 1; }; '
                   + capture + '\n' + selected + '\nprintf "%s" "$SETUP_PROVIDER_RESULT"')
        result = self.shell(command)
        self.assertEqual(result.returncode, 0, result.stderr)
        vibe = json.loads(result.stdout)
        self.assertEqual((vibe['status'], vibe['reason_code']), ('available', 'ready'))
        self.assertTrue(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
