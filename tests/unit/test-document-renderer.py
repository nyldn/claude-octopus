#!/usr/bin/env python3
"""Renderer selection uses the host's advertised skills, not plugin ownership."""
import json
import itertools
import os
from pathlib import Path
import re
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
                self.assertIn("For executive and board decision briefs, use two or three pillars so the hypothesis matches the executive summary", skeleton)
                self.assertIn("Exclude the cover slide", gate)
                self.assertIn("Exclude appendix backup slides from the main-deck argument read", gate)
                self.assertIn("Check appendix titles separately against their expected questions and evidence", gate)
                self.assertIn("Changing the governing question or slide claims after approval returns to this gate", gate)
                self.assertIn("approved cover title", gate)
                self.assertIn("conclusion instead, with follow-up only when the brief calls for it", gate)
                self.assertIn("supported conclusion for informational decks", deck.split("### Step 5:", 1)[1])
                self.assertIn("informational", step)
                self.assertIn("Do not invent a decision", step)
                self.assertNotIn("[First Content Section]", step)
                self.assertNotIn("[Agenda / Overview]", step)
                audience = " ".join(deck.split("**Executives / Board:**", 1)[1]
                                    .split("**Engineers / Technical:**", 1)[0].split())
                self.assertIn("For decision briefs, end with the specific decision needed", audience)
                self.assertIn("For informational briefs, end with the supported conclusion", audience)
                self.assertIn("include follow-up only when the brief calls for it", audience)
                investors = " ".join(deck.split("**Investors / Fundraising:**", 1)[1]
                                     .split("**General / Mixed:**", 1)[0].split())
                with self.subTest(contract="investor-purpose"):
                    self.assertIn("For decision briefs", investors)
                    self.assertIn("For informational briefs", investors)
                    self.assertIn("supported conclusion; include follow-up only when the brief calls for it", investors)
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

    def test_deck_red_team_is_opt_in_and_precedes_outline_approval(self):
        """Both hosts must preserve cost consent, real dispatch and the wireframe gate."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                outline = text.split("### Step 3:", 1)[1].split("### Step 4:", 1)[0]
                red_team = outline.split("#### Optional stakeholder red team", 1)[1]
                # Objection-driven edits must pass both existing outline gates.
                collect = outline.index("<!-- deck-seat-collection:start -->")
                board_check = outline.index("#### Board outline check")
                storyline_check = outline.index("#### Storyline gate:")
                approval = outline.index("Present the confirmed question")
                self.assertLess(collect, board_check)
                self.assertLess(board_check, storyline_check)
                self.assertLess(storyline_check, approval)
                # The executable recipes below cover launch, retries and waiting.
                # Keep prose checks to the opt-in, quorum and output contract.
                self.assertIn("Without `--red-team`", red_team)
                self.assertIn("provider allowlist", red_team)
                self.assertIn("at least two distinct providers", " ".join(red_team.split()))
                self.assertIn("pre-empt", red_team)
                self.assertIn("Q&A", red_team)
                self.assertIn("unverified", red_team)

    def test_deck_red_team_checks_costs_and_two_seat_minimum_before_dispatch(self):
        """A one-stakeholder map cannot authorize an underfunded quorum."""
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
                gate = " ".join(text.split("#### Optional stakeholder red team", 1)[1].split())
                for identifier in ("config/model-pricing.tsv", "codex:<model>",
                                   "OCTOPUS_CODEX_REASONING", "at least two seats",
                                   "maximum call count", "estimated spend", "Unknown costs"):
                    self.assertIn(identifier, gate)
                self.assertLess(gate.index("obtain consent"), gate.index("Use real"))
                self.assertIn('OCTOPUS_PREFLIGHT_PROBE=0 "$ADVISOR_SELECTOR"', gate)
                self.assertLess(gate.index("OCTOPUS_PREFLIGHT_PROBE=0"),
                                gate.index("obtain consent"))

    def test_deck_command_exposes_optional_red_team(self):
        text = (ROOT / "commands/deck.md").read_text()
        self.assertIn("/octo:deck --red-team", text)
        self.assertIn("provider calls", text)

    def test_deck_collection_refuses_an_unexecutable_hook_before_dispatch(self):
        """Simulate a no-exec temporary directory without mounting a filesystem."""
        orchestrator = self.base / "orchestrator"
        orchestrator.write_text('#!/bin/sh\nprintf "called\\n" >> "$DISPATCH_CALLS"\n')
        orchestrator.chmod(0o755)
        script = r'''source "$PLUGIN_ROOT/scripts/lib/consultative-advisors.sh"
# Emulate an execute-denied hook even though chmod itself succeeds.
chmod() { command chmod "$@"; command chmod -x "${@: -1}"; }
octo_launch_advisors "$ORCHESTRATOR" codex "$SEAT_DIR" answer- evidence 1
'''
        calls = self.base / "calls"
        result = subprocess.run(["bash", "-c", script],
            env=dict(os.environ, PLUGIN_ROOT=str(ROOT), ORCHESTRATOR=str(orchestrator),
                     SEAT_DIR=str(self.base), DISPATCH_CALLS=str(calls),
                     OCTO_ALLOWED_PROVIDERS="codex", OCTOPUS_ADVISOR_WAIT_SECONDS="1"),
            text=True, capture_output=True, timeout=8)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("advisor lifecycle hook cannot execute", result.stderr)
        self.assertFalse(calls.exists(), result.stderr)

    def _seat_recipe(self, tree, source_replacement=None):
        """Read the shipped Bash collection recipe with clear marker failures."""
        text = (ROOT / tree / "skill-deck/SKILL.md").read_text()
        start, end = "<!-- deck-seat-collection:start -->", "<!-- deck-seat-collection:end -->"
        self.assertIn(start, text, f"{tree}: missing seat-recipe start marker")
        section = text.split(start, 1)[1]
        self.assertIn(end, section, f"{tree}: missing seat-recipe end marker")
        section = section.split(end, 1)[0]
        self.assertIn("```bash\n", section, f"{tree}: missing Bash recipe fence")
        recipe = textwrap.dedent(section.split("```bash\n", 1)[1].split("```", 1)[0])
        if source_replacement is not None:
            recipe = recipe.replace('source "$PLUGIN_ROOT/scripts/lib/consultative-advisors.sh"',
                                    source_replacement)
        return recipe

    def test_deck_recipe_rejects_oversize_without_summarizer_calls(self):
        """Use the production budget enforcer with an inert summarizer."""
        stub = self.base / "budget-collector"
        stub.write_text('''source "$PLUGIN_ROOT/scripts/lib/dispatch.sh"
log() { :; }
get_provider_context_limit() { printf '16\\n'; }
octo_summarizer_candidates() { printf 'agy\\n'; }
run_agent_sync() { printf 'attempt\\n' >> "$SUMMARY_CALLS"; printf 'Condensed prompt\\n'; }
octo_launch_advisors() { enforce_context_budget "$STAKEHOLDER_PROMPT" "" codex review; }
''')
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                seat_dir = self.base / tree.replace("/", "-")
                seat_dir.mkdir()
                calls = seat_dir / "summary-calls"
                env = dict(os.environ, PLUGIN_ROOT=str(ROOT), BUDGET_STUB=str(stub),
                           ADVISOR_ID="codex:fixture", ORCHESTRATOR="inert",
                           STAKEHOLDER_PROMPT="Stakeholder evidence " * 300,
                           SEAT_DIR=str(seat_dir), SEAT_WAIT_SECONDS="5",
                           SUMMARY_CALLS=str(calls), OCTOPUS_OVERSIZE_STRATEGY="summarize")
                control = subprocess.run(["bash", "-c", 'source "$BUDGET_STUB"; octo_launch_advisors'],
                                         env=env, text=True, capture_output=True, timeout=10)
                self.assertTrue(calls.exists(), control.stderr)
                self.assertEqual(calls.read_text(), "attempt\n", control.stderr)
                calls.unlink()
                recipe = self._seat_recipe(tree, 'source "$BUDGET_STUB"')
                result = subprocess.run(["bash", "-euo", "pipefail", "-c", recipe],
                                        env=env, text=True, capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(calls.exists(), result.stderr)

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
        has_pty = subprocess.run(["bash", "-c", "command -v script"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        for tree in (".claude/skills", "skills"):
            recipe = self._seat_recipe(tree, 'source "$ADAPTER_COLLECTOR_STUB"')
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
                    expected_calls = 2 if failure == "empty" or has_pty else 1
                    self.assertEqual(len(calls.read_text().splitlines()), expected_calls, control.stderr)
                    calls.unlink()
                    result = subprocess.run(["bash", "-euo", "pipefail", "-c", recipe +
                                             '\n[[ "$OCTOPUS_AGY_NO_RETRY" == 0 && "$OCTOPUS_AGY_NO_PTY_FALLBACK" == 0 ]]'],
                                            env=env, text=True, capture_output=True, timeout=10)
                    self.assertEqual(len(calls.read_text().splitlines()), 1, result.stderr)
                    if failure == "tty":
                        self.assertNotEqual(result.returncode, 0)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deck_recipe_excludes_unbounded_compatible_transports(self):
        """Unbounded helper routes cannot spend any of the consented seat budget."""
        probe = self.base / "compatible-probe.py"
        probe.write_text('''import importlib.util,io,json,os,sys,urllib.error
from pathlib import Path
spec=importlib.util.spec_from_file_location("compat", Path(os.environ["PLUGIN_ROOT"])/"scripts/helpers/openai-compatible-agent.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def transport(request, **kwargs):
    with open(os.environ["COMPAT_CALLS"], "a") as out: out.write("attempt\\n")
    payload=json.loads(request.data)
    code=int(os.environ["COMPAT_RESPONSE"])
    if code == 503 or (code == 400 and "reasoning_effort" in payload):
        body=b"Unsupported parameter: reasoning_effort" if code == 400 else b"unavailable"
        raise urllib.error.HTTPError(request.full_url,code,"fixture",{},io.BytesIO(body))
    count=len(Path(os.environ["COMPAT_CALLS"]).read_text().splitlines())
    content="" if code == 200 and count == 1 else "Stakeholder objection"
    return io.BytesIO(json.dumps({"choices":[{"message":{"content":content},"finish_reason":"stop"}]}).encode())
mod.open_credentialed_request=transport
mod.time.sleep=lambda seconds:None
sys.argv=["fixture", "--provider","generic","--base-url","https://example.invalid/v1", "--api-key-env","COMPAT_FIXTURE_KEY", "--model","fixture-model", "--cwd",os.environ["SEAT_DIR"], "--reasoning-effort","high", "--reasoning-policy",os.environ["COMPAT_EFFECTIVE_POLICY"], "--tool-policy","none"]
sys.exit(mod.main())
''')
        collector = self.base / "compatible-collector"
        collector.write_text('''source "$PLUGIN_ROOT/scripts/lib/execution-profile.sh"
_octopus_profile_field() { :; }
_octopus_profile_config_file() { printf '%s' "$SEAT_DIR/nonexistent-config"; }
octo_launch_advisors() {
    local policy
    policy="$(octopus_resolve_reasoning_policy openai-compatible-agent review reviewer)" || return 1
    COMPAT_EFFECTIVE_POLICY="$policy" python3 "$COMPAT_PROBE"
}
''')
        for tree in (".claude/skills", "skills"):
            for response, advisor in itertools.product((503, 400, 200),
                    ("openai-compatible", "openai-tools", "atlascloud-agent",
                     "cheaperinference-agent", "uberllm-agent", "api-route-agent", "litellm-agent")):
                with self.subTest(tree=tree, response=response, advisor=advisor):
                    seat_dir = self.base / (tree.replace("/", "-") + str(response) + advisor)
                    seat_dir.mkdir()
                    calls = seat_dir / "calls"
                    env = dict(os.environ, PLUGIN_ROOT=str(ROOT), COMPAT_PROBE=str(probe),
                               COMPAT_COLLECTOR=str(collector), COMPAT_CALLS=str(calls),
                               COMPAT_RESPONSE=str(response), COMPAT_FIXTURE_KEY="inert-fixture",
                               OPENAI_COMPAT_MAX_RETRIES="3", OCTOPUS_REASONING_POLICY="best_effort",
                               ADVISOR_ID=f"{advisor}:fixture-model", ORCHESTRATOR="inert",
                               STAKEHOLDER_PROMPT="Stakeholder prompt", SEAT_DIR=str(seat_dir),
                               SEAT_WAIT_SECONDS="5")
                    control = subprocess.run(["bash", "-c", 'source "$COMPAT_COLLECTOR"; octo_launch_advisors'],
                                             env=env, input="prompt", text=True, capture_output=True,
                                             check=False, timeout=10)
                    self.assertEqual(len(calls.read_text().splitlines()), 3 if response == 503 else 2, control.stderr)
                    calls.unlink()
                    recipe = self._seat_recipe(tree, 'source "$COMPAT_COLLECTOR"')
                    result = subprocess.run(["bash", "-euo", "pipefail", "-c", recipe],
                                            env=env, input="prompt", text=True, capture_output=True,
                                            check=False, timeout=10)
                    self.assertFalse(calls.exists(), result.stderr)
                    self.assertNotEqual(result.returncode, 0)

    def test_deck_fable_recipe_does_not_spend_an_unapproved_fallback_call(self):
        """Exercise the SDK adapter's real refusal retry under the shipped recipe."""
        bin_dir = self.base / "sdk-bin"
        bin_dir.mkdir()
        sdk = bin_dir / "claude-agent"
        sdk.write_text('''#!/usr/bin/env bash
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == --model ]]; then model="$2"; break; fi
    shift
done
printf '%s\\n' "$model" >> "$SDK_CALLS"
[[ "$model" != claude-fable-5-1 ]] || exit 1
printf 'Stakeholder objection\\n'
''')
        sdk.chmod(0o755)
        collector = self.base / "sdk-collector"
        collector.write_text('''octo_launch_advisors() {
    printf '%s' "$STAKEHOLDER_PROMPT" | bash "$SDK_ADAPTER"
}
''')
        for tree in (".claude/skills", "skills"):
            with self.subTest(tree=tree):
                seat_dir = self.base / tree.replace("/", "-")
                seat_dir.mkdir()
                calls = seat_dir / "calls"
                env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                           CLAUDE_SDK_API_KEY="inert-fixture", OCTOPUS_CLAUDE_SDK_MODEL="claude-fable-5-1",
                           OCTOPUS_FABLE5_NO_RETRY="0", OCTOPUS_FABLE5_MODE="auto",
                           OCTOPUS_FABLE5_FALLBACK_MODEL="claude-opus-5", SDK_CALLS=str(calls),
                           SDK_ADAPTER=str(ROOT / "scripts/helpers/claude-sdk-exec.sh"),
                           SDK_COLLECTOR=str(collector), ADVISOR_ID="claude-sdk:claude-fable-5-1",
                           ORCHESTRATOR="inert", STAKEHOLDER_PROMPT="Stakeholder prompt",
                           SEAT_DIR=str(seat_dir), SEAT_WAIT_SECONDS="5")
                control = subprocess.run(["bash", env["SDK_ADAPTER"]], input="prompt",
                                         env=env, text=True, capture_output=True, timeout=10, check=False)
                self.assertEqual(control.returncode, 0, control.stderr)
                self.assertEqual(calls.read_text().splitlines(), ["claude-fable-5-1", "claude-opus-5"])
                calls.unlink()
                recipe = self._seat_recipe(tree, 'source "$SDK_COLLECTOR"')
                result = subprocess.run(["bash", "-euo", "pipefail", "-c", recipe],
                                        env=env, text=True, capture_output=True, timeout=10, check=False)
                self.assertEqual(calls.read_text().splitlines(), ["claude-fable-5-1"], result.stderr)
                self.assertNotEqual(result.returncode, 0)

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
    for attempt in {1..100}; do
        [[ -s "$SEAT_DIR/worker-pid" ]] && break
        sleep 0.01
    done
    worker_pid="$(cat "$SEAT_DIR/worker-pid")"
    OCTOPUS_AGENT_PID="$worker_pid" OCTOPUS_AGENT_STATUS="$FIXTURE_STATUS" \\
        OCTOPUS_AGENT_RESULT_FILE="$FIXTURE_RESULT" "$OCTOPUS_AGENT_LIFECYCLE_HOOK" completed
) &
worker=$!
printf '%s\\n' "$worker" > "$SEAT_DIR/worker-pid"
OCTOPUS_AGENT_PID="$worker" OCTOPUS_AGENT_RESULT_FILE="$FIXTURE_RESULT" \\
    "$OCTOPUS_AGENT_LIFECYCLE_HOOK" spawned
printf 'Provider launch log\\n%s\\n' "$worker"
''')
        orchestrator.chmod(0o755)
        bash_env = self.base / "portable-bash-env"
        bash_env.write_text("unset BASHPID\n")
        for tree in (".claude/skills", "skills"):
            recipe = self._seat_recipe(tree)
            for status in ("completed", "failed"):
                with self.subTest(tree=tree, status=status):
                    seat_dir = self.base / tree.replace("/", "-") / status
                    seat_dir.mkdir(parents=True)
                    response = seat_dir / "answer-codex_fixture.md"
                    response.write_text("stale answer")
                    env = dict(os.environ, BASH_ENV=str(bash_env), PLUGIN_ROOT=str(ROOT), ORCHESTRATOR=str(orchestrator),
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
                for number in ("2", "3", "4", "5", "6"):
                    self.assertRegex(slides[number], r"(?m)^- Evidence: .+")
                    self.assertRegex(slides[number], r"(?m)^- Visual: .+")

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
                self.assertNotIn("[Summary / Next Steps]", purpose)
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
                self.assertIn("**Storyline**: Slide titles carry the argument", rules)
                self.assertNotIn("**Agenda slide**", rules)
                summary_rule = next(line for line in rules.splitlines() if "**Summary slide**" in line)
                self.assertIn("supported answer to the governing question", summary_rule)
                self.assertIn("Executives / Board briefs put the executive summary on slide 2", summary_rule)
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
