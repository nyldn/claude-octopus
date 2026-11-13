#!/usr/bin/env python3
"""Exercise generated host routes without invoking a model or changing logins."""
import re
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(sys.argv.pop(1)).resolve()
GENERATOR = ROOT / "scripts/build-codex-skills.sh"


def adapt(text):
    return subprocess.check_output([
        "/bin/bash", "-eu", "-c",
        'source "$1"; adapt_skill_references_for_codex', "fixture", str(GENERATOR)
    ], input=text, text=True)


class CodexReferences(unittest.TestCase):
    def test_finish_branch_requires_a_common_ancestor_before_review(self):
        for tree in ('.claude/skills', 'skills', 'codex-skills'):
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            blocks = re.findall(r'```bash\n(.*?)\n```', text, re.S)
            resolve = next(b for b in blocks if 'BASE_REF=$(git symbolic-ref' in b)
            summary = next(b for b in blocks if 'DIFF_STAT=' in b)
            for unrelated in (False, True):
                with self.subTest(tree=tree, unrelated=unrelated), tempfile.TemporaryDirectory() as temporary:
                    env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
                    def git(*args):
                        return subprocess.check_output(['git', '-C', temporary, *args], env=env,
                                                       stderr=subprocess.DEVNULL, text=True).strip()
                    git('init', '-q', '-b', 'main')
                    path = Path(temporary) / 'base.txt'
                    path.write_text('base\n')
                    git('add', '.')
                    git('commit', '-qm', 'base')
                    git('checkout', '-q', '--orphan' if unrelated else '-b', 'feature')
                    path.write_text('changed\n')
                    git('add', '.')
                    git('commit', '-qm', 'feature')
                    result = subprocess.run(['/bin/bash', '-c', resolve + '\n' + summary +
                                             '\nprintf "REVIEW_REACHED|%s|%s" "$DIFF_FILES" "$DIFF_STAT"'],
                                            cwd=temporary, env=env, capture_output=True, text=True, timeout=5)
                    if unrelated:
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertNotIn('REVIEW_REACHED', result.stdout)
                        self.assertIn('Cannot determine a common ancestor', result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn('REVIEW_REACHED|base.txt|', result.stdout)
                        self.assertIn('1 file changed', result.stdout)

    def test_finish_branch_does_not_dispatch_without_a_verified_diff(self):
        for tree in ('.claude/skills', 'skills', 'codex-skills'):
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            block = next(b for b in re.findall(r'```bash\n(.*?)\n```', text, re.S)
                         if '# Quick review via orchestrate.sh' in b)
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                plugin = root / 'plugin/scripts'
                plugin.mkdir(parents=True)
                runner = plugin / 'orchestrate.sh'
                runner.write_text('#!/bin/bash\nprintf "%s" "$3" > "$REVIEW_CAPTURE"\n')
                runner.chmod(0o755)
                env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                           GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                           GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                           CLAUDE_PLUGIN_ROOT=str(plugin.parent), REVIEW_CAPTURE=str(root / 'review'))
                env.pop('MERGE_BASE', None)
                def git(*args):
                    return subprocess.check_output(['git', '-C', temporary, *args], env=env,
                                                   stderr=subprocess.DEVNULL, text=True).strip()
                git('init', '-q', '-b', 'main')
                git('commit', '-q', '--allow-empty', '-m', 'base')
                base = git('rev-parse', 'HEAD')
                for merge_base, lines in ((None, 1), ('missing-base', 1), (base, 550), (base, 6000)):
                    with self.subTest(tree=tree, merge_base=merge_base, lines=lines):
                        (root / 'change.txt').write_text('reviewed line\n' * lines + 'TAIL_REQUIRES_REVIEW\n')
                        git('add', 'change.txt')
                        git('commit', '--allow-empty', '-qm', 'feature')
                        capture = root / 'review'
                        capture.unlink(missing_ok=True)
                        call_env = dict(env)
                        if merge_base is not None:
                            call_env['MERGE_BASE'] = merge_base
                        result = subprocess.run(['/bin/bash', '-c', block], cwd=root, env=call_env,
                                                capture_output=True, text=True, timeout=5)
                        if merge_base != base or lines == 6000:
                            self.assertNotEqual(result.returncode, 0, result.stderr)
                            self.assertFalse(capture.exists(), 'reviewer received an incomplete diff')
                            if lines == 6000:
                                self.assertIn('Review incomplete', result.stderr)
                        else:
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertTrue('+TAIL_REQUIRES_REVIEW' in capture.read_text(), 'diff tail was omitted')

    def test_finish_branch_rejects_an_empty_diff(self):
        for tree in ('.claude/skills', 'skills', 'codex-skills'):
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            block = next(b for b in re.findall(r'```bash\n(.*?)\n```', text, re.S)
                         if '# Quick review via orchestrate.sh' in b)
            with self.subTest(tree=tree), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                scripts = root / 'plugin/scripts'
                scripts.mkdir(parents=True)
                capture = root / 'review'
                runner = scripts / 'orchestrate.sh'
                runner.write_text('#!/bin/bash\nprintf "dispatched" > "$REVIEW_CAPTURE"\n')
                runner.chmod(0o755)
                subprocess.run(['git', 'init', '-q', '-b', 'main', temporary], check=True)
                subprocess.run(['git', '-c', 'user.name=Fixture', '-c',
                                'user.email=fixture@example.invalid', 'commit', '-q',
                                '--allow-empty', '-m', 'base'], cwd=root, check=True)
                env = dict(os.environ, MERGE_BASE='HEAD', CLAUDE_PLUGIN_ROOT=str(scripts.parent),
                           REVIEW_CAPTURE=str(capture))
                result = subprocess.run(['/bin/bash', '-c', block], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn('no changes', result.stderr)
                self.assertFalse(capture.exists(), 'reviewer dispatched with an empty diff')

    def test_staged_review_filters_and_retains_successful_answers(self):
        text = (ROOT / '.claude/skills/skill-staged-review/SKILL.md').read_text()
        block = next(b for b in re.findall(r'```bash\n(.*?)\n```', text, re.S)
                     if 'REVIEW_OUTPUT_DIR=$(mktemp' in b)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'scripts/lib').mkdir(parents=True)
            (root / 'bin').mkdir()
            (root / 'scripts/lib/consultative-advisors.sh').write_text(
                'octo_provider_allowed() { [[ ",$OCTO_ALLOWED_PROVIDERS," == *",$1,"* ]]; }\n'
                'octo_launch_advisors() { [[ "$OCTOPUS_ADVISOR_WAIT_SECONDS" == 600 ]] || return 2; [[ "$2" != agy ]] || return 1; printf "successful codex review" > "$3/${4}codex.md"; }\n')
            launcher = root / 'scripts/orchestrate.sh'
            launcher.write_text('#!/bin/bash\nprintf "failed agy partial"\nexit 1\n')
            launcher.chmod(0o755)
            for name in ('codex', 'agy'):
                binary = root / 'bin' / name
                binary.write_text('#!/bin/bash\nexit 0\n')
                binary.chmod(0o755)
            for allowed in ('codex', 'codex,agy', ''):
                env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(root), DIFF_CONTENT='fixture diff',
                           OCTO_ALLOWED_PROVIDERS=allowed, PATH=str(root / 'bin') + ':' + os.environ['PATH'])
                result = subprocess.run(['/bin/bash', '-eu', '-c', block], env=env,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('failed agy partial', result.stdout)
                if 'codex' in allowed:
                    self.assertIn('successful codex review', result.stdout)
                else:
                    self.assertIn('No allowed external provider', result.stdout)
                if 'agy' in allowed:
                    self.assertIn('review incomplete', result.stdout)
                    self.assertIn('Provider review incomplete: agy', result.stderr)
                else:
                    self.assertNotIn('Provider review incomplete', result.stderr)
                output = next(line.split('=', 1)[1] for line in result.stdout.splitlines()
                              if line.startswith('REVIEW_OUTPUT_DIR='))
                shutil.rmtree(output)

    def test_finish_branch_resolves_real_default_refs_before_review(self):
        text = (ROOT / '.claude/skills/skill-finish-branch/SKILL.md').read_text()
        block = next(b for b in re.findall(r'```bash\n(.*?)\n```', text, re.S)
                     if 'BASE_REF=$(git symbolic-ref' in b)
        for branch, remote_head in [('master', False), ('trunk', True), ('main', 'stale')]:
            with self.subTest(branch=branch), tempfile.TemporaryDirectory() as temporary:
                subprocess.run(['git', 'init', '-q', '-b', branch, temporary], check=True)
                def git(*args):
                    return subprocess.run(['git', '-C', temporary, *args], check=True,
                                          capture_output=True, text=True)
                git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                    'commit', '-q', '--allow-empty', '-m', 'base')
                if remote_head == 'stale':
                    git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/missing')
                elif remote_head:
                    git('update-ref', 'refs/remotes/origin/' + branch, 'HEAD')
                    git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/' + branch)
                result = subprocess.run(['/bin/bash', '-eu', '-c', block + '\nprintf "%s|%s" "$BASE_REF" "$BASE_BRANCH"'],
                                        cwd=temporary, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, ('origin/' + branch if remote_head is True else branch) + '|' + branch)

    def test_check_reports_only_the_missing_generated_tree_without_writing(self):
        for missing in (('codex',), ('native',), ('codex', 'native')):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source = root / 'source/demo/SKILL.md'
                source.parent.mkdir(parents=True)
                source.write_text('---\nname: demo\ndescription: fixture\n'
                                  'disable-model-invocation: true\n---\nBody.\n')
                command = ('source "$1"; SKILLS_DIR="$2/source"; OUTPUT_DIR="$2/codex"; '
                           'NATIVE_OUTPUT_DIR="$2/native"; ')
                result = subprocess.run(['/bin/bash', '-eu', '-c', command + 'main',
                                         'fixture', str(GENERATOR), str(root)],
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                for name in missing:
                    shutil.rmtree(root / name)
                before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
                result = subprocess.run(['/bin/bash', '-eu', '-c', command + 'CHECK_MODE=true; main',
                                         'fixture', str(GENERATOR), str(root)],
                                        capture_output=True, text=True, timeout=15)
                self.assertNotEqual(result.returncode, 0)
                for name, label in [('codex', 'Codex'), ('native', 'native')]:
                    self.assertEqual(label + ' skill tree does not exist:' in result.stderr, name in missing)
                after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
                self.assertEqual(after, before)

    def test_source_directory_names_stay_distinct_from_loaded_resource_paths(self):
        source = ('Enumerate `.claude/skills/`, `skills/`, and `codex-skills/`.\n'
                  'Read `skills/blocks/evidence.md` and `$OCTO_ROOT/skills/$SKILL/SKILL.md`.\n'
                  'Read "${OCTO_ROOT}/skills/flow-parallel/SKILL.md".\n')
        expected = ('Enumerate `.claude/skills/`, `skills/`, and `codex-skills/`.\n'
                    'Read `codex-skills/blocks/evidence.md` and `$OCTO_ROOT/codex-skills/$SKILL/SKILL.md`.\n'
                    'Read "${OCTO_ROOT}/codex-skills/flow-parallel/SKILL.md".\n')
        result = subprocess.check_output([
            '/bin/bash', '-eu', '-c',
            'source "$1"; adapt_shared_paths_for_codex', 'fixture', str(GENERATOR)
        ], input=source, text=True)
        self.assertEqual(result, expected)

    def test_delivery_continuations_load_the_host_specific_entries(self):
        names = ("skill-doc-sync", "skill-ship", "skill-finish-branch")
        source = "\n".join(
            "Read ${OCTO_ROOT}/.claude/skills/" + name + "/SKILL.md and execute it."
            for name in names
        ) + "\n"
        result = subprocess.check_output([
            "/bin/bash", "-eu", "-c",
            'source "$1"; adapt_shared_paths_for_codex', "fixture", str(GENERATOR)
        ], input=source, text=True)
        self.assertEqual(result, source.replace(".claude/skills/", "codex-skills/"))
        native = (ROOT / "skills/flow-deliver/SKILL.md").read_text()
        codex = (ROOT / "codex-skills/flow-deliver/SKILL.md").read_text()
        for name in names:
            with self.subTest(name=name):
                self.assertIn(".claude/skills/" + name + "/SKILL.md", native)
                self.assertNotIn(".claude/skills/" + name + "/SKILL.md", codex)
                self.assertIn("codex-skills/" + name + "/SKILL.md", codex)
                self.assertTrue((ROOT / "codex-skills" / name / "SKILL.md").is_file())

    def test_user_routes_reach_installed_skills(self):
        routes = {
            "parallel": "flow-parallel", "quick": "octopus-quick",
            "discover": "flow-discover", "define": "flow-define",
            "develop": "flow-develop", "deliver": "flow-deliver",
            "debate": "skill-debate", "docs": "skill-doc-delivery",
            "deck": "skill-deck", "prd": "skill-prd",
            "brainstorm": "skill-thought-partner", "setup": "sys-configure",
            "status": "skill-status", "debug": "skill-debug",
            "security": "octopus-security-audit", "skill-doctor": "skill-doctor",
        }
        source = "\n".join("Use `/octo:" + n + " topic` next." for n in routes) + "\n"
        expected = "\n".join("Use `$" + n + " topic` next." for n in routes.values()) + "\n"
        self.assertEqual(adapt(source), expected)
        for name in routes.values():
            entry = ROOT / "codex-skills" / name / "SKILL.md"
            self.assertRegex(entry.read_text(), r"(?m)^name: " + re.escape(name) + r"$")

    def test_multiple_routes_and_start_of_line(self):
        self.assertEqual(adapt('/octo:review then `/octo:tdd` or "/octo:research"\n'),
                         '$skill-code-review then `$skill-tdd` or "$octopus-research"\n')

    def test_executable_snippets_keep_command_literals_without_shell_expansion(self):
        shell = '```bash\necho "Run /octo:setup and /octo:ship"\n```\n'
        program = '```javascript\nconst command = "/octo:review";\n```\n'
        self.assertEqual(adapt(shell + program), shell + program)
        self.assertEqual(adapt('```text\n/octo:quick "task"\n```\n'),
                         '```text\n$octopus-quick "task"\n```\n')

    def test_unknown_commands_urls_paths_and_longer_names_stay_literal(self):
        source = "\n".join([
            "/octo:does-not-exist", "/octo:review-extra", "/octo:review.md",
            "https://example.invalid/octo:review", "docs/octo:review.md",
            "/docs/octo:review", "/octo:review/file", "/octo:*",
            "historical /octo:doctor", "/octo:embrace", "octo:review",
        ]) + "\n"
        self.assertEqual(adapt(source), source)

    def test_generation_keeps_native_bytes_and_adapts_alias_and_shared_resource(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source/skill-verification-gate/SKILL.md"
            source.parent.mkdir(parents=True)
            text = ('---\nname: skill-verification-gate\ndescription: "Verify evidence"\n'
                    'disable-model-invocation: true\n---\n\nUse `/octo:review` before `/octo:deliver`.\n')
            source.write_text(text)
            block = root / "native/blocks/routes.md"
            block.parent.mkdir(parents=True)
            block.write_text('Use `/octo:debate` and `skills/blocks/evidence.md`.\n')
            subprocess.run([
                "/bin/bash", "-eu", "-c",
                'source "$1"; SKILLS_DIR="$2/source"; OUTPUT_DIR="$2/codex"; '
                'NATIVE_OUTPUT_DIR="$2/native"; main >/dev/null',
                "fixture", str(GENERATOR), str(root)
            ], check=True, capture_output=True)
            self.assertEqual((root / "native/skill-verification-gate/SKILL.md").read_text(), text)
            for name in ("skill-verification-gate", "skill-verify"):
                generated = (root / "codex" / name / "SKILL.md").read_text()
                self.assertIn('Use `$skill-code-review` before `$flow-deliver`.', generated)
                self.assertRegex(generated, r"(?m)^name: " + name + r"$")
                self.assertIn('allow_implicit_invocation: false',
                              (root / "codex" / name / "agents/openai.yaml").read_text())
            self.assertEqual((root / "codex/blocks/routes.md").read_text(),
                             'Use `$skill-debate` and `codex-skills/blocks/evidence.md`.\n')
            self.assertEqual(block.read_text(), 'Use `/octo:debate` and `skills/blocks/evidence.md`.\n')

    def test_packaged_prose_uses_available_host_routes(self):
        for name, obsolete in {
            "flow-parallel": ("parallel",),
            "octopus-quick": ("quick", "discover", "define", "develop", "deliver"),
            "skill-deck": ("discover", "deck", "docs", "prd", "brainstorm"),
            "skill-doctor": ("setup", "status", "debug", "skill-doctor"),
            "skill-work-slicing": ("parallel",),
            "octopus-ui-ux-design": ("debate",),
        }.items():
            text = (ROOT / "codex-skills" / name / "SKILL.md").read_text()
            prose = []
            in_fence = False
            for line in text.splitlines():
                if re.match(r"^\s*(```|~~~)", line):
                    in_fence = not in_fence
                elif not in_fence:
                    prose.append(line)
            for command in obsolete:
                self.assertNotRegex("\n".join(prose), r"/octo:" + re.escape(command) + r"(?![a-z0-9-])", name)

    def test_authoring_checks_both_hosts_and_verification_alias_uses_registered_names(self):
        authoring = (ROOT / "codex-skills/skill-authoring/SKILL.md").read_text()
        for required in (".codex-plugin/plugin.json", "policy.allow_implicit_invocation: false",
                         "codex-skills/octopus-starter-pack/debate-kickoff/SKILL.md", "derive the plugin root",
                         "test-codex-manifest.sh", "test-native-skill-registration.sh"):
            self.assertIn(required, authoring)
        for name in ("skill-verification-gate", "skill-verify"):
            text = (ROOT / "codex-skills" / name / "SKILL.md").read_text()
            for other in ("flow-develop", "flow-deliver", "skill-code-review", "skill-tdd", "skill-factory"):
                self.assertIn("`" + other + "`", text)
                self.assertNotIn("`" + other + ".md`", text)
        audit = (ROOT / "codex-skills/skill-audit/SKILL.md").read_text()
        self.assertIn("octopus-security-audit", audit)
        self.assertNotIn("skill-security-audit", audit)

    def test_codex_debug_does_not_claim_unbound_freeze_enforcement(self):
        native = (ROOT / "skills/skill-debug/SKILL.md").read_text()
        codex = (ROOT / "codex-skills/skill-debug/SKILL.md").read_text()
        self.assertIn("## Scoped freeze guard", native)
        self.assertIn("os.open", native)
        self.assertIn("does not bind its Claude freeze-check hook to Codex", codex)
        self.assertNotIn("/tmp/octopus-freeze-", codex)
        self.assertNotIn("os.open", codex)
        sample = "## Scoped freeze guard\nunsafe activation\n## Next section\nkeep me\n"
        result = subprocess.check_output([
            "/bin/bash", "-eu", "-c", 'source "$1"; adapt_freeze_for_codex',
            "fixture", str(GENERATOR)
        ], input=sample, text=True)
        self.assertNotIn("unsafe activation", result)
        self.assertIn("## Next section\nkeep me", result)

    def test_nested_entries_and_continuations_keep_their_installation(self):
        starter = ROOT / "codex-skills/octopus-starter-pack/debate-kickoff/SKILL.md"
        self.assertTrue(starter.is_file())
        authoring = (ROOT / "codex-skills/skill-authoring/SKILL.md").read_text()
        self.assertNotIn("immediate child", authoring)
        self.assertIn("full relative path", authoring)
        delivery = (ROOT / "codex-skills/flow-deliver/SKILL.md").read_text()
        self.assertIn("${OCTO_ROOT}/codex-skills/skill-doc-sync/SKILL.md", delivery)
        self.assertIn("${OCTO_ROOT}/codex-skills/skill-ship/SKILL.md", delivery)
        self.assertNotIn("from the stable plugin root", delivery)
        self.assertIn("same verified `OCTO_ROOT`", delivery)
        self.assertIn('"${OCTO_ROOT}/scripts/octo-state.sh" update_state', delivery)

    def test_host_routes_and_evidence_claims_are_supported(self):
        decision = (ROOT / "codex-skills/skill-decision-support/SKILL.md").read_text()
        self.assertNotRegex(decision, r"flow-(probe|tangle)")
        resume = (ROOT / "codex-skills/skill-resume/SKILL.md").read_text()
        self.assertNotIn("/octo:embrace", resume)
        self.assertIn("$flow-discover", resume)
        self.assertIn("Do not restart Discover", resume)
        self.assertIn("OCTOPUS_PROJECT_PERSISTENCE=true", resume)
        self.assertNotIn("Initialize .octo/ directory with STATE.md, PROJECT.md, ROADMAP.md", resume)
        rollback = (ROOT / "codex-skills/skill-rollback/SKILL.md").read_text()
        self.assertNotIn("/octo:rollback", rollback)
        self.assertIn("$skill-rollback $SAFETY_CHECKPOINT_TAG", rollback)
        ship = (ROOT / "codex-skills/skill-ship/SKILL.md").read_text()
        self.assertNotIn("Claude: Available", ship)
        self.assertNotIn("Providers Used:** Claude", ship)
        pipeline = (ROOT / "skills/skill-content-pipeline/SKILL.md").read_text().split("---", 2)[1]
        self.assertNotIn("context: fork", pipeline)

    def test_loaded_block_paths_belong_to_the_codex_tree(self):
        for name in ("skill-authoring", "skill-audit", "skill-meta-prompt"):
            text = (ROOT / "codex-skills" / name / "SKILL.md").read_text()
            self.assertNotRegex(text, r"(?<![a-z/.-])skills/blocks/")
            for relative in re.findall(r"`(codex-skills/blocks/[a-z0-9-]+\.md)`", text):
                self.assertTrue((ROOT / relative).is_file(), relative)


if __name__ == "__main__":
    unittest.main()
