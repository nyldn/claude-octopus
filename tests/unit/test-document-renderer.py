#!/usr/bin/env python3
"""Renderer selection uses the host's advertised skills, not plugin ownership."""
import json
import os
from pathlib import Path
import re
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

    def _board_outlines(self):
        """Read the outline contract from each shipped host tree."""
        for tree in (".claude/skills", "skills"):
            deck = (ROOT / tree / "skill-deck/SKILL.md").read_text()
            outline = deck.split("### Step 3: Generate Outline", 1)[1].split("### Step 4:", 1)[0]
            yield tree, deck, outline

    def test_board_outline_carries_decision_materials_before_approval(self):
        """Decision slides include the recommendation, alternatives and sourced proof."""
        for tree, deck, outline_step in self._board_outlines():
            with self.subTest(tree=tree):
                board = outline_step.split("#### Executive and board outline", 1)[1].split("#### Board outline check", 1)[0]
                slides = dict(re.findall(r"^## Slide (\d+): (.*?)(?=^## Slide |^```)",
                                         board, re.MULTILINE | re.DOTALL))
                self.assertIn("Executive summary", slides["2"])
                for requirement in ("recommendation", "by-when", "context", "pillars", "ask", "unlocks"):
                    self.assertIn(requirement, slides["2"])
                for requirement in ("Do nothing", "cost", "alternative"):
                    self.assertIn(requirement, slides["3"])
                self.assertIn("highlight", slides["4"])
                self.assertIn("title", slides["4"])
                self.assertIn("proof point", slides["4"])
                self.assertIn("source", slides["4"])
                for requirement in ("approval", "amount", "resource"):
                    self.assertIn(requirement, slides["5"])
                self.assertIn("Appendix", slides["6"])
                self.assertIn("expected question", slides["6"])

    def test_board_outline_requests_missing_material_before_approval(self):
        """Readiness requires missing material and explicit user approval."""
        for tree, deck, outline_step in self._board_outlines():
            with self.subTest(tree=tree):
                gate = outline_step.split("#### Board outline check", 1)[1]
                self.assertIn("before asking for outline approval", gate)
                self.assertIn("Do not invent", gate)
                self.assertIn("identify the gap", gate)
                self.assertIn("ask for it before presenting the outline as ready", " ".join(gate.split()))
                self.assertIn("one backup slide per expected question", gate)
                self.assertIn("MUST approve", gate)

    def test_board_outline_preserves_informational_purpose_and_target(self):
        """Informational briefs and selected slide targets retain their scope."""
        for tree, deck, outline_step in self._board_outlines():
            with self.subTest(tree=tree):
                purpose = outline_step.split("#### Executive and board outline", 1)[0]
                self.assertIn("informational", purpose)
                self.assertIn("Q1 results", purpose)
                self.assertIn("do not require a decision or approval ask", purpose)
                self.assertIn("key findings", purpose)
                self.assertIn("implications", purpose)
                self.assertIn("results when applicable", purpose)
                self.assertIn("follow-up only when the brief calls for it", " ".join(purpose.split()))
                self.assertIn("Call to action only when the brief calls for one", purpose)
                self.assertIn("slide 2", purpose)
                sizing = outline_step.split("#### Executive and board outline", 1)[1].split("```markdown", 1)[0]
                self.assertIn("combine", sizing.lower())
                self.assertIn("five-slide", sizing)
                self.assertIn("approve a larger target", sizing)
                sizing = " ".join(sizing.split())
                self.assertIn("user selects a five-slide target", sizing)
                self.assertIn("selected slide range", sizing)
                self.assertIn("longer targets", sizing)

    def test_board_audience_and_closing_rules_preserve_purpose(self):
        """Audience and closing rules keep actions conditional and before the appendix."""
        for tree, deck, outline_step in self._board_outlines():
            with self.subTest(tree=tree):
                rules = deck.split("## Slide Structure Best Practices", 1)[1].split("### By Audience Type", 1)[0]
                cta_rule = next(line for line in rules.splitlines() if "**Next steps / CTA**" in line)
                self.assertIn("last main-deck slide", cta_rule)
                self.assertIn("appendix", cta_rule)
                self.assertIn("When the brief calls for action", cta_rule)
                self.assertIn("otherwise end the main deck with a supported conclusion", cta_rule)
                for label in ("Agenda slide", "Summary slide"):
                    rule = next(line for line in rules.splitlines() if f"**{label}**" in line)
                    self.assertIn("general agenda-first structure", rule)
                    self.assertIn("Executives / Board briefs", rule)
                    self.assertIn("purpose-specific structure", rule)
                audience = deck.split("**Executives / Board:**", 1)[1].split("**Engineers / Technical:**", 1)[0]
                self.assertIn("brief's purpose", audience)
                self.assertIn("decision or informational purpose in Step 3", " ".join(audience.split()))
                self.assertIn("only when a decision is requested", " ".join(audience.split()))
                self.assertIn("financial implications only when relevant", " ".join(audience.split()))
                self.assertIn("supported by sources", audience)

    def test_board_decisions_allow_qualitative_evidence(self):
        """A nonnumeric decision must not require an invented chart or figure."""
        for tree, deck, outline in self._board_outlines():
            with self.subTest(tree=tree):
                evidence = outline.split("## Slide 4:", 1)[1].split("## Slide 5:", 1)[0]
                self.assertIn("qualitative", evidence)
                self.assertIn("no relevant numerical proof", " ".join(evidence.split()))
                self.assertIn("For numerical data", evidence)
                self.assertIn("single figure", evidence)

    def test_board_data_highlights_allow_tables(self):
        """The data check accepts a highlighted table instead of a chart."""
        for tree, deck, outline in self._board_outlines():
            with self.subTest(tree=tree):
                gate = outline.split("#### Board outline check", 1)[1]
                data_check = next(item for item in gate.split("\n- ") if "every data slide" in item)
                for requirement in ("proof point", "title", "numerical evidence", "single figure",
                                    "chart, table or other data display"):
                    self.assertIn(requirement, " ".join(data_check.split()))

    def test_deck_completion_requires_rendered_slide_evidence(self):
        """Saving an artifact alone cannot satisfy the deck completion gate."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                gate = text.split("### Step 5: Verify the rendered deck", 1)[1].split("## Slide Structure", 1)[0]
                gate = " ".join(gate.split())
                for requirement in ("every slide, including appendix slides",
                                    "text overflow", "empty placeholders", "broken images",
                                    "rendered titles", "titles-only read",
                                    "supported conclusion for informational decks",
                                    "one highlighted proof point supports its title", "source data",
                                    "slide number", "thumbnail", "pass, fail or unverified"):
                    self.assertIn(requirement, gate)
                self.assertIn("draft, with verification incomplete", gate)
                self.assertIn("do not claim a finished deck", gate)
                self.assertIn("at most two repair-and-verification rounds", gate)
                self.assertIn("reopen every thumbnail after each rerender", gate)
                self.assertIn("Repeat all checks for every slide,", gate)
                self.assertIn("Rebuild the verification table against the final artifact;", gate)
                self.assertIn("final artifact", gate)
                self.assertIn("any fail or unverified result keeps the deck a draft", gate)


    def test_deck_command_includes_verification_after_rendering(self):
        text = (ROOT / "commands/deck.md").read_text()
        self.assertLess(text.index("4. **Render**"), text.index("5. **Verify**"))


if __name__ == "__main__":
    unittest.main()
