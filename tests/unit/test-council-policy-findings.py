#!/usr/bin/env python3
"""Keep policy extraction and council quote exemptions on the same wire format."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
FINDINGS = [{"source": "RULES.md", "quote": "run `the audit` before &quot;shipping&quot;"}]
FAKE = "const price = inventedLookup(cabin.id, { cache: true });"


class PolicyFindings(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "pricing.ts").write_text("const price = cabin.basePrice ?? sailing.defaultPrice;\n")
        self.response = self.root / "response.md"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, env=self.env)
        subprocess.run(["git", "-C", str(self.root), "add", "pricing.ts"], check=True, env=self.env)
        subprocess.run([
            "git", "-C", str(self.root), "-c", "core.hooksPath=/dev/null",
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
            "commit", "-qm", "fixture",
        ], check=True, env=self.env)

    def tearDown(self):
        self.temp.cleanup()

    def extract(self, text):
        self.response.write_text(text)
        return subprocess.run([
            "python3", str(REPO / "scripts/helpers/feature-workflow.py"), "extract",
            "--input", str(self.response), "--label", "octopus-policy-findings",
        ], capture_output=True, text=True, env=self.env, timeout=20)

    def grounding(self, text):
        self.response.write_text(text)
        result = subprocess.run([
            "bash", "-c", 'source "$1/scripts/lib/council.sh"; '
            'council_response_quote_verification_json "$2" "$3"',
            "policy-test", str(REPO), str(self.response), str(self.root),
        ], capture_output=True, text=True, env=self.env, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertFalse(report["verification_failed"], report)
        return report

    def test_supported_forms_extract_without_becoming_quotes(self):
        for marker, indent, container in [
            ("```", "", FINDINGS),
            ("~~~", "", FINDINGS),
            ("````", "    ", {"findings": FINDINGS, "summary": "one gap"}),
            ("~~~~", "\t", {"findings": FINDINGS}),
        ]:
            with self.subTest(marker=marker, indent=indent):
                block = f"{indent}{marker}octopus-policy-findings\n{json.dumps(container)}\n{marker}"
                # Entities before the block change decoded coordinates too.
                text = "&amp;&#10; pricing.ts:1 needs an audit.\n\n" + block
                extracted = self.extract(text)
                self.assertEqual(extracted.returncode, 0, extracted.stderr)
                self.assertEqual(json.loads(extracted.stdout), FINDINGS)
                report = self.grounding(text)
                self.assertEqual(report["quotes_checked"], 0, report)
                self.assertFalse(report["fabricated"], report)
                report = self.grounding(text + f"\n\npricing.ts:1 reads `{FAKE}`.")
                self.assertEqual(report["quotes_checked"], 1, report)
                self.assertTrue(report["fabricated"], report)

    def test_runtime_rejects_invalid_json_and_shapes(self):
        for body in [
            '{"findings": [], "findings": []}',
            '[{"quote": NaN}]',
            '{"summary": "no findings"}',
            '["not a finding object"]',
            '{"findings": null}',
            'not JSON',
        ]:
            with self.subTest(body=body):
                result = self.extract(f"```octopus-policy-findings\n{body}\n```\n")
                self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_runtime_ignores_nested_example_fences(self):
        text = '````markdown\n```octopus-policy-findings\n' + json.dumps(FINDINGS) + '\n```\n````\n'
        result = self.extract(text)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [])

    def test_runtime_rejects_unclosed_findings(self):
        result = self.extract('~~~octopus-policy-findings\n' + json.dumps(FINDINGS))
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_rejected_findings_cannot_receive_a_quote_exemption(self):
        def block(findings):
            return '```octopus-policy-findings\n' + json.dumps(findings, indent=2) + '\n```\n'
        finding = {"quote": FAKE}
        for text in (block([finding] * 101),
                     block([finding] * 60) + '\n' + block([finding] * 41),
                     block([finding]) + '\n' + block({"findings": "invalid"}),
                     block([finding]) + '\n```octopus-policy-findings\nnot JSON'):
            with self.subTest(blocks=text.count('octopus-policy-findings')):
                text = 'pricing.ts:1 needs an audit.\n\n' + text
                self.assertNotEqual(self.extract(text).returncode, 0)
                report = self.grounding(text)
                self.assertGreaterEqual(report["quotes_checked"], 1, report)
                self.assertTrue(report["fabricated"], report)

        for text in (block([finding] * 100),
                     block([finding] * 60) + '\n' + block([finding] * 40)):
            with self.subTest(accepted_blocks=text.count('octopus-policy-findings')):
                text = 'pricing.ts:1 needs an audit.\n\n' + text
                self.assertEqual(self.extract(text).returncode, 0)
                self.assertEqual(self.grounding(text)["quotes_checked"], 0)

    def test_encoded_markers_do_not_create_an_exemption(self):
        text = 'pricing.ts:1 needs an audit.\n\n&#96;&#96;&#96;octopus-policy-findings\n'
        text += json.dumps([{"quote": FAKE}]) + '\n&#96;&#96;&#96;\n'
        self.assertEqual(json.loads(self.extract(text).stdout), [])
        report = self.grounding(text)
        self.assertGreaterEqual(report["quotes_checked"], 1, report)
        self.assertTrue(report["fabricated"], report)


if __name__ == "__main__":
    unittest.main()
