#!/usr/bin/env python3
"""Renderer selection uses the host's advertised skills, not plugin ownership."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/helpers/document-renderer.py"


class DocumentRendererTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.config = self.base / "renderers.json"

    def run_helper(self, *args):
        return subprocess.run([sys.executable, str(HELPER), "--format", "pptx",
                               "--config", str(self.config), *args],
                              text=True, capture_output=True, timeout=5)

    def selection(self, *args):
        result = self.run_helper(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_standalone_and_alternate_plugin_pptx_skills_are_available(self):
        for skill in ("pptx", "anthropic-skills:pptx"):
            with self.subTest(skill=skill):
                self.assertEqual(self.selection("--available-skill", skill)["skill"], skill)

    def test_default_plugin_wins_only_when_advertised(self):
        result = self.selection("--available-skill", "pptx", "--available-skill", "document-skills:pptx")
        self.assertEqual((result["skill"], result["selection"]), ("document-skills:pptx", "default"))

    def test_saved_house_renderer_and_template_are_preserved(self):
        template = self.base / "House template.pptx"
        template.touch()
        self.config.write_text(json.dumps({"pptx": {"skill": "house:slides", "template": str(template)}}))
        result = self.selection("--available-skill", "house:slides", "--available-skill", "document-skills:pptx")
        self.assertEqual((result["skill"], result["template"], result["selection"]),
                         ("house:slides", str(template), "config"))

    def test_explicit_renderer_does_not_inherit_another_renderers_template(self):
        self.config.write_text(json.dumps({"pptx": {"skill": "house:slides", "template": "missing.pptx"}}))
        result = self.selection("--renderer", "google-drive:google-slides", "--available-skill", "google-drive:google-slides")
        self.assertEqual(result["skill"], "google-drive:google-slides")
        self.assertIsNone(result["template"])
        self.assertEqual(result["selection"], "request")

    def test_explicit_template_overrides_saved_template(self):
        template = self.base / "request.pptx"
        template.touch()
        self.config.write_text(json.dumps({"pptx": {"skill": "house:slides", "template": "missing.pptx"}}))
        result = self.selection("--available-skill", "house:slides", "--template", str(template))
        self.assertEqual(result["template"], str(template))

    def test_explicit_renderer_bypasses_malformed_saved_configuration(self):
        template = self.base / "explicit.pptx"
        template.touch()
        for config in ("not json", '{"pptx":42}'):
            for template_args in ((), ("--template", str(template))):
                with self.subTest(config=config, template_args=template_args):
                    self.config.write_text(config)
                    result = self.selection("--renderer", "pptx", "--available-skill", "pptx", *template_args)
                    self.assertEqual(result["skill"], "pptx")
                    self.assertEqual(result["template"], str(template) if template_args else None)

    def test_literal_tilde_config_path_keeps_the_saved_selection(self):
        self.config.write_text('{"pptx":{"skill":"house:slides"}}')
        # Reach the fixture through ~ without writing to the host home.
        config_path = "~/" + os.path.relpath(self.config.resolve(), Path.home().resolve())
        result = subprocess.run([sys.executable, str(HELPER), "--format", "pptx",
                                 "--config", config_path, "--available-skill", "house:slides",
                                 "--available-skill", "document-skills:pptx"],
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["skill"], "house:slides")

    def test_missing_explicit_or_saved_renderer_never_falls_back(self):
        self.config.write_text('{"pptx":{"skill":"house:slides"}}')
        for args in ((), ("--renderer", "other:slides")):
            with self.subTest(args=args):
                result = self.run_helper("--available-skill", "document-skills:pptx", *args)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("Renderer selection failed:", result.stderr)
                self.assertIn("not advertised", result.stderr)

    def test_missing_renderer_and_ambiguous_discovery_require_a_choice(self):
        cases = (((), "No advertised pptx renderer"),
                 (("--available-skill", "one:pptx", "--available-skill", "two:pptx"),
                  "Multiple advertised renderers"))
        for args, diagnostic in cases:
            with self.subTest(args=args):
                result = self.run_helper(*args)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("Renderer selection failed:", result.stderr)
                self.assertIn(diagnostic, result.stderr)

    def test_invalid_config_template_and_skill_fail_without_execution(self):
        for config in ("not json", "[]", '{"pptx":"house:slides"}',
                       '{"pptx":{"skill":"house:slides","template":42}}',
                       '{"pptx":{"skill":"house:slides","template":"missing.pptx"}}',
                       '{"pptx":{"skill":"house:slides;touch marker"}}'):
            with self.subTest(config=config):
                self.config.write_text(config)
                result = self.run_helper("--available-skill", "house:slides")
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("Renderer selection failed:", result.stderr)
        self.assertFalse((ROOT / "marker").exists())

    def test_other_document_formats_use_the_same_selection_contract(self):
        for format_name in ("docx", "xlsx", "pdf"):
            result = subprocess.run([sys.executable, str(HELPER), "--format", format_name,
                                     "--config", str(self.config), "--available-skill", format_name],
                                    text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["skill"], format_name)

    def test_document_quick_reference_does_not_require_installation(self):
        """A working standalone renderer must not trigger an install instruction."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                text = (ROOT / tree / "skill-doc-delivery/SKILL.md").read_text()
                quick_reference = text.split("## Quick Reference Commands", 1)[1].split("## Getting Help", 1)[0]
                self.assertIn("document-renderer.py", quick_reference)
                self.assertNotIn("/plugin install", quick_reference)
                self.assertEqual(self.selection("--available-skill", "pptx")["skill"], "pptx")

    def test_renderer_handoff_preserves_direct_export_and_output_contracts(self):
        """Native and generated skills must agree about approval and deliverables."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                delivery = (ROOT / tree / "skill-doc-delivery/SKILL.md").read_text()
                invocation = delivery.split("### Step 3: Invoke the selected renderer", 1)[1].split("### Step 4:", 1)[0]
                self.assertIn("For slides with approved materials", invocation)
                self.assertIn("without implying that an outline or slide materials were approved", invocation)
                self.assertIn("actual artifact path", invocation)
                deck = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                render = deck.split("### Step 4: Render the approved deck", 1)[1].split("## Slide Structure", 1)[0]
                self.assertIn("actual saved artifact path", render)
                self.assertIn("actual deck URL", render)
                self.assertIn("Quote each argument as data", delivery)

    def test_document_examples_prepare_formatting_before_rendering(self):
        """Rendering must include the promised document formatting."""
        for tree in (".claude/skills", "skills"):
            text = (ROOT / tree / "skill-doc-delivery/SKILL.md").read_text()
            business = text.split("### Example 2:", 1)[1].split("### Example 3:", 1)[0]
            academic = text.split("### Example 3:", 1)[1].split("## Handling Edge Cases", 1)[0]
            with self.subTest(tree=tree):
                render = business.index("Convert with the resolved DOCX renderer")
                self.assertLess(business.index("Add table of contents"), render)
                self.assertLess(business.index("Format tables and charts properly"), render)
                self.assertLess(academic.index("Apply academic formatting"),
                                academic.index("Resolve and invoke the PDF renderer"))

    def test_native_skills_use_the_resolver_and_no_plugin_presence_gate(self):
        for name in ("skill-deck", "skill-doc-delivery"):
            text = (ROOT / f".claude/skills/{name}/SKILL.md").read_text()
            self.assertNotIn("/plugin list | grep document-skills", text)
            self.assertNotIn("When document-skills plugin not installed", text)
            self.assertIn("document-renderer.py", text)
            self.assertIn("advertised", text)


if __name__ == "__main__":
    unittest.main()
