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

    def test_deck_storyline_is_confirmed_and_checked_before_outline_approval(self):
        """Topic labels must not satisfy the deck's pre-render argument gate."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                deck = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                step = " ".join(deck.split("### Step 3: Generate Outline", 1)[1]
                                .split("### Step 4:", 1)[0].split())
                for requirement in ("governing question", "threshold for yes", "out-of-scope",
                                    "Confirm the governing question with the user before",
                                    "situation", "complication", "confirmed governing question",
                                    "working hypothesis", "two to four pillars",
                                    "one declarative sentence per storyline slide", "titles-only read",
                                    "question to the ask", "Market overview",
                                    "Label titles fail", "revise the skeleton and repeat",
                                    "MUST approve the sentence skeleton before PPTX generation"):
                    self.assertIn(requirement, step)
                self.assertLess(step.index("Confirm the governing question"),
                                step.index("working hypothesis"))
                read = step.index("Read only the slide-title sentences, top to bottom.")
                revise = step.index("revise the skeleton and repeat the titles-only read before")
                approve = step.index("Present the confirmed question, opener, hypothesis and sentence skeleton")
                self.assertLess(read, revise)
                self.assertLess(revise, approve)
                self.assertLess(step.index("#### Board outline check"), read)
                self.assertIn("For executive and board decision briefs, the board content check and the titles-only read must both pass before outline approval", step)
                skeleton, gate = step.split("#### Storyline gate:", 1)
                self.assertIn("Exclude the cover slide", skeleton)
                self.assertIn("approved slide-count target", skeleton)
                self.assertIn("Exclude the cover slide", gate)
                self.assertIn("Exclude appendix backup slides from the main-deck argument read", gate)
                self.assertIn("Check appendix titles separately against their expected questions and evidence", gate)
                self.assertIn("Changing the governing question or slide claims after approval returns to this gate", gate)
                self.assertIn("approved cover title", gate)
                self.assertIn("informational", step)
                self.assertIn("Do not invent a decision", step)
                self.assertNotIn("[First Content Section]", step)
                self.assertNotIn("[Agenda / Overview]", step)
                audience = " ".join(deck.split("**Executives / Board:**", 1)[1]
                                    .split("**Engineers / Technical:**", 1)[0].split())
                self.assertIn("For decision briefs, end with the specific decision needed", audience)
                self.assertIn("For informational briefs, end with the supported conclusion", audience)
                investors = " ".join(deck.split("**Investors / Fundraising:**", 1)[1]
                                     .split("**General / Mixed:**", 1)[0].split())
                with self.subTest(contract="investor-purpose"):
                    self.assertIn("For decision briefs", investors)
                    self.assertIn("For informational briefs", investors)
                    self.assertIn("supported conclusion and follow-up", investors)
                    self.assertIn("Do not add a funding ask", investors)
                    self.assertIn("fundraising example", investors)
                    self.assertIn("optional", investors)
                    self.assertIn("confirmed question", investors)
                    self.assertIn("approved pillars and out-of-scope list", investors)
                example = deck.split("```markdown", 1)[1].split("```", 1)[0]
                slides = example.split("## Slide ")[1:]
                self.assertEqual(len(slides), 4)
                self.assertIn("[Presentation name]", slides[0].splitlines()[0])
                for slide in slides[1:]:
                    with self.subTest(slide=slide.splitlines()[0]):
                        self.assertRegex(slide, r"(?m)^- Evidence: .+")
                        self.assertRegex(slide, r"(?m)^- Visual: .+")


    def test_native_skills_use_the_resolver_and_no_plugin_presence_gate(self):
        for name in ("skill-deck", "skill-doc-delivery"):
            text = (ROOT / f".claude/skills/{name}/SKILL.md").read_text()
            self.assertNotIn("/plugin list | grep document-skills", text)
            self.assertNotIn("When document-skills plugin not installed", text)
            self.assertIn("document-renderer.py", text)
            self.assertIn("advertised", text)

    def test_board_outline_carries_decision_materials_before_approval(self):
        """The shipped board example must not fall back to an agenda-first deck."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                deck = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                outline_step = deck.split("### Step 3: Generate Outline", 1)[1].split("### Step 4:", 1)[0]
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
                gate = outline_step.split("#### Board outline check", 1)[1]
                self.assertIn("before asking for outline approval", gate)
                self.assertIn("Do not invent", gate)
                self.assertIn("If decision material is missing, identify the gap and ask for it before presenting the outline as ready for approval.",
                              " ".join(gate.split()))
                self.assertIn("one backup slide per expected question", gate)
                self.assertIn("MUST approve", gate)

                purpose = outline_step.split("#### Executive and board outline", 1)[0]
                self.assertIn("informational", purpose)
                self.assertIn("Q1 results", purpose)
                self.assertIn("do not require a decision or approval ask", purpose)
                self.assertIn("key findings and implications, including results when applicable", " ".join(purpose.split()))
                self.assertIn("slide 2", purpose)
                sizing = outline_step.split("#### Executive and board outline", 1)[1].split("```markdown", 1)[0]
                self.assertIn("combine", sizing.lower())
                self.assertIn("five-slide", sizing)
                self.assertIn("approve a larger target", sizing)
                sizing = " ".join(sizing.split())
                self.assertRegex(sizing, r"If the user selects a five-slide target, combine")
                self.assertIn("Preserve the selected slide range for longer targets", sizing)
                rules = deck.split("## Slide Structure Best Practices", 1)[1].split("### By Audience Type", 1)[0]
                cta_rule = next(line for line in rules.splitlines() if "**Next steps / CTA**" in line)
                self.assertIn("last main-deck slide", cta_rule)
                self.assertIn("appendix", cta_rule)
                self.assertIn("**Storyline**: Slide titles carry the argument", rules)
                self.assertNotIn("**Agenda slide**", rules)
                summary_rule = next(line for line in rules.splitlines() if "**Summary slide**" in line)
                self.assertIn("supported answer to the governing question", summary_rule)
                self.assertIn("Executives / Board briefs put the executive summary on slide 2", summary_rule)
                for number in ("2", "3", "4", "5", "6"):
                    self.assertRegex(slides[number], r"(?m)^- Evidence: .+")
                    self.assertRegex(slides[number], r"(?m)^- Visual: .+")
                audience = deck.split("**Executives / Board:**", 1)[1].split("**Engineers / Technical:**", 1)[0]
                self.assertIn("brief's purpose", audience)
                self.assertIn("decision or informational purpose in Step 3", " ".join(audience.split()))
                self.assertIn("only when a decision is requested", " ".join(audience.split()))


if __name__ == "__main__":
    unittest.main()
