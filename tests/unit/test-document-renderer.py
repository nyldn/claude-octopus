#!/usr/bin/env python3
"""Renderer selection uses the host's advertised skills, not plugin ownership."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
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

    def test_deck_red_team_is_opt_in_and_precedes_outline_approval(self):
        """Both hosts must preserve cost consent, real dispatch and the wireframe gate."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                outline = text.split("### Step 3:", 1)[1].split("### Step 4:", 1)[0]
                red_team = outline.split("#### Optional stakeholder red team", 1)[1]
                self.assertLess(red_team.index("orchestrate.sh spawn"),
                                red_team.index("Present the revised outline"))
                self.assertIn("Without `--red-team`, skip this pass", red_team)
                self.assertIn("provider allowlist", red_team)
                self.assertIn("one round", red_team)
                self.assertIn("skill-debate", red_team)
                self.assertIn("orchestrate.sh spawn", red_team)
                self.assertIn("never simulate", red_team)
                self.assertIn("Fewer than two eligible providers", red_team)
                self.assertIn("continue without red teaming", red_team)
                self.assertIn("decision-maker or influencer", text.split("### Step 2:", 1)[0])
                self.assertIn("one stakeholder", red_team)
                self.assertIn("pre-empt", red_team)
                self.assertIn("Q&A", red_team)
                self.assertIn("backup-slide checklist", red_team)
                self.assertIn("unverified", red_team)
                self.assertIn("not completed", red_team)
                self.assertIn("user approves", red_team)
                for requirement in ("octo_launch_advisors", "OCTOPUS_ADVISOR_WAIT_SECONDS",
                                    "successful completion", "at least two distinct providers",
                                    "deadline expires", "not completed",
                                    "Do not count launch logs, partial files or stale artifacts"):
                    self.assertIn(requirement, " ".join(red_team.split()))
                self.assertLess(red_team.index("successful completion"),
                                red_team.index("Merge and deduplicate"))

    def test_deck_red_team_checks_costs_and_two_seat_minimum_before_dispatch(self):
        """A one-stakeholder map cannot authorize an underfunded quorum."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                gate = " ".join(text.split("#### Optional stakeholder red team", 1)[1].split())
                for requirement in ("Even with one stakeholder", "at least two seats",
                                    "increase the budget or continue without red teaming",
                                    "narrowing the map cannot remove this minimum",
                                    "config/model-pricing.tsv", "includes reasoning tokens",
                                    "maximum call count and estimated spend",
                                    "before any provider call", "Unknown costs need explicit acceptance",
                                    "codex:<model>", "OCTOPUS_CODEX_REASONING",
                                    "higher-priority phase/role overrides", "resolved command",
                                    "cannot honor a choice", "No extra calls or retries"):
                    self.assertIn(requirement, gate)
                self.assertLess(gate.index("obtain consent"), gate.index("Use real"))
                self.assertIn("Invoke the installed `skill-deck`", " ".join(text.split()))
                self.assertNotIn("Use `/octo:deck --red-team", text)
                self.assertIn('OCTOPUS_PREFLIGHT_PROBE=0 "$ADVISOR_SELECTOR"', gate)
                self.assertIn("static readiness only", gate)
                self.assertLess(gate.index("OCTOPUS_PREFLIGHT_PROBE=0"),
                                gate.index("obtain consent"))

    def test_deck_command_exposes_optional_red_team(self):
        text = (ROOT / "commands/deck.md").read_text()
        self.assertIn("/octo:deck --red-team", text)
        self.assertIn("provider calls", text)

    def test_deck_agy_recipe_bounds_actual_adapter_invocations(self):
        """Exercise adapter retries using the environment of the shipped recipe."""
        bin_dir = self.base / "agy-bin"
        bin_dir.mkdir()
        agy = bin_dir / "agy"
        agy.write_text('''#!/usr/bin/env bash
printf 'attempt\\n' >> "$AGY_CALLS"
if [[ "$AGY_FAILURE" == tty ]]; then
    if [[ -t 0 || -t 1 ]]; then printf 'Stakeholder objection\\n'; exit 0; fi
    printf 'bubbletea: could not open TTY\\n' >&2
    exit 1
fi
''')
        agy.chmod(0o755)
        # Replace only the collector body; the recipe still sets the actual
        # process environment and waits for the adapter's result.
        stub = self.base / "capture-env"
        stub.write_text('''octo_launch_advisors() {
    printf '%s' "$STAKEHOLDER_PROMPT" | bash "$AGY_ADAPTER"
}
''')
        for tree in (".claude/skills", "skills"):
            text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
            recipe = textwrap.dedent(text.split("<!-- deck-seat-collection:start -->", 1)[1].split(
                "<!-- deck-seat-collection:end -->", 1)[0].split("```bash\n", 1)[1].split("```", 1)[0])
            recipe = recipe.replace('source "$PLUGIN_ROOT/scripts/lib/consultative-advisors.sh"',
                                    'source "$ADAPTER_COLLECTOR_STUB"')
            for failure in ("empty", "tty"):
                with self.subTest(tree=tree, failure=failure):
                    seat_dir = self.base / (tree.replace("/", "-") + failure)
                    seat_dir.mkdir()
                    calls = seat_dir / "calls"
                    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                               AGY_FAILURE=failure, AGY_CALLS=str(calls),
                               AGY_ADAPTER=str(ROOT / "scripts/helpers/agy-exec.sh"),
                               ADAPTER_COLLECTOR_STUB=str(stub), ADVISOR_ID="agy:default",
                               ORCHESTRATOR="inert", STAKEHOLDER_PROMPT="Stakeholder prompt",
                               SEAT_DIR=str(seat_dir), SEAT_WAIT_SECONDS="5",
                               OCTOPUS_AGY_NO_RETRY="0", OCTOPUS_AGY_NO_PTY_FALLBACK="0",
                               OCTOPUS_AGY_FORCE_INLINE="0")
                    # A control proves that the actual adapter replays this
                    # condition when the recipe's overrides are absent.
                    control = subprocess.run(["bash", env["AGY_ADAPTER"]], input="prompt",
                                             env=env, text=True, capture_output=True, timeout=10)
                    self.assertEqual(len(calls.read_text().splitlines()), 2, control.stderr)
                    calls.unlink()
                    result = subprocess.run(["bash", "-euo", "pipefail", "-c", recipe +
                                             '\n[[ "$OCTOPUS_AGY_NO_RETRY" == 0 && "$OCTOPUS_AGY_NO_PTY_FALLBACK" == 0 ]]'],
                                            env=env, text=True, capture_output=True, timeout=10)
                    self.assertEqual(len(calls.read_text().splitlines()), 1, result.stderr)
                    if failure == "tty":
                        self.assertNotEqual(result.returncode, 0)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deck_collection_example_waits_for_answers_and_stops_on_failure(self):
        """Execute the shipped seat recipe against delayed lifecycle events."""
        orchestrator = self.base / "orchestrator"
        orchestrator.write_text('''#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == spawn && "$2" == codex:fixture && "$3" == "$STAKEHOLDER_PROMPT" ]]
[[ "${OCTOPUS_AUTH_RETRIES:-missing}" == 0 ]]
(
    sleep 0.2
    printf '# Started: fixture\\n## Output\\n```\\nStakeholder objection\\n```\\n## Status: SUCCESS\\n' > "$FIXTURE_RESULT"
    printf 'completed\\n' >> "$SEAT_DIR/sequence"
    OCTOPUS_AGENT_PID="$BASHPID" OCTOPUS_AGENT_STATUS="$FIXTURE_STATUS" \\
        OCTOPUS_AGENT_RESULT_FILE="$FIXTURE_RESULT" "$OCTOPUS_AGENT_LIFECYCLE_HOOK" completed
) &
worker=$!
OCTOPUS_AGENT_PID="$worker" OCTOPUS_AGENT_RESULT_FILE="$FIXTURE_RESULT" \\
    "$OCTOPUS_AGENT_LIFECYCLE_HOOK" spawned
printf 'Provider launch log\\n%s\\n' "$worker"
''')
        orchestrator.chmod(0o755)
        for tree in (".claude/skills", "skills"):
            text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
            recipe = text.split("<!-- deck-seat-collection:start -->", 1)[1].split(
                "<!-- deck-seat-collection:end -->", 1)[0].split("```bash\n", 1)[1].split("```", 1)[0]
            recipe = textwrap.dedent(recipe)
            for status in ("completed", "failed"):
                with self.subTest(tree=tree, status=status):
                    seat_dir = self.base / tree.replace("/", "-") / status
                    seat_dir.mkdir(parents=True)
                    response = seat_dir / "answer-codex_fixture.md"
                    response.write_text("stale answer")
                    env = dict(os.environ, PLUGIN_ROOT=str(ROOT), ORCHESTRATOR=str(orchestrator),
                               ADVISOR_ID="codex:fixture", SEAT_DIR=str(seat_dir),
                               STAKEHOLDER_PROMPT='Objection with "quotes"\nand a second line',
                               SEAT_WAIT_SECONDS="5", OCTO_ALLOWED_PROVIDERS="codex",
                               OCTOPUS_AUTH_RETRIES="2",
                               FIXTURE_RESULT=str(seat_dir / "worker.md"), FIXTURE_STATUS=status)
                    env.pop("OCTOPUS_AGENT_LIFECYCLE_HOOK", None)
                    result = subprocess.run(["bash", "-euo", "pipefail", "-c", recipe +
                                             '\n[[ "$OCTOPUS_AUTH_RETRIES" == 2 ]]\nprintf "synthesis\\n" >> "$SEAT_DIR/sequence"\nprintf "SYNTHESIS_READY\\n"'],
                                            env=env, text=True, capture_output=True, timeout=10)
                    if status == "completed":
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(response.read_text(), "Stakeholder objection\n")
                        self.assertEqual((seat_dir / "sequence").read_text(), "completed\nsynthesis\n")
                        self.assertIn("SYNTHESIS_READY", result.stdout)
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertNotIn("SYNTHESIS_READY", result.stdout)
                        self.assertFalse(response.exists())



if __name__ == "__main__":
    unittest.main()
