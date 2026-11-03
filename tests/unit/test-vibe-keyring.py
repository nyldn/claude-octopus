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
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        OCTOPUS_SKIP_PROVIDER_PROBES='false', OCTO_ALLOWED_PROVIDERS='vibe',
                        MISTRAL_API_KEY='', VIBE_PROBE_MARKER=str(self.marker))
        self.env.pop('OCTOPUS_COUNCIL_DEFAULT_PROVIDERS', None)
        self.env.pop('_octo_vibe_check_context', None)
        self.write_module('return "inert-fixture-value"')

    def write_module(self, body):
        self.module.write_text('import os\nfrom pathlib import Path\n'
                               'def get_api_key_from_keyring(*args, **kwargs):\n'
                               '    raise RuntimeError("migration-capable lookup forbidden")\n'
                               'def probe_api_key_from_keyring(key):\n'
                               '    assert key == "MISTRAL_API_KEY"\n'
                               f'    Path({str(self.marker)!r}).touch()\n'
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

    def test_existing_credentials_do_not_probe_keyring(self):
        self.env['MISTRAL_API_KEY'] = 'inert-fixture-value'
        result = self.shell('_octo_provider_static_readiness vibe; check_provider_health vibe; detect_providers')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('available|ready|', result.stdout)
        self.assertIn('vibe:api-key', result.stdout)
        self.assertFalse(self.marker.exists())

    def test_locked_keyring_has_a_real_wall_clock_bound(self):
        self.write_module('import time\ntime.sleep(60)\nreturn "inert-fixture-value"')
        start = time.monotonic()
        result = self.shell('_octo_vibe_keyring_has_key selected')
        elapsed = time.monotonic() - start
        self.assertTrue(self.marker.exists(), 'probe must start for timeout test to count')
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(elapsed, 6)
        self.assertEqual(result.stdout + result.stderr, '')

    def test_automatic_discovery_does_not_load_vibe_code(self):
        result = self.shell('detect_providers; octo_provider_readiness_all static; '
                            'octo_provider_ids() { printf "vibe\\n"; }; check_all_providers; '
                            f'bash {shlex.quote(str(ROOT / "scripts/capabilities.sh"))} --json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('vibe:none', result.stdout)
        self.assertFalse(self.marker.exists(), 'unselected Vibe code ran during discovery')

    def test_broad_live_readiness_does_not_load_vibe_code(self):
        result = self.shell('octo_provider_readiness_all live')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.marker.exists(), 'broad live scan loaded unselected Vibe code')
        selected = self.shell('octo_provider_readiness_all live vibe')
        self.assertEqual(selected.returncode, 0, selected.stderr)
        self.assertTrue(self.marker.exists(), 'explicit selection must still inspect Vibe')

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
