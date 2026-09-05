# Releasing claude-octopus

Ordered checklist for shipping a release. Every step exists because skipping it has already broken CI at least once (v9.50.0 shipped in three CI rounds; all three failures were steps on this list). Human and agent contributors follow the same list.

## 0. Preconditions

- Work on a branch cut from current `main`. Branch protection is strict: the branch must be up to date with `main` at merge time, and the required checks are exactly **Smoke Tests**, **Unit Tests**, **Integration Tests**.
- Never build a release on top of a dirty working tree you do not own. Use a separate worktree (`git worktree add <dir> -b release/<name> origin/main`).

## 1. Decide the version

Minor (9.x+1.0) for additive changes: new providers, new commands/skills/hooks, new env vars with safe defaults. Precedent: grok (9.48.0) and atlascloud shipped as minors. Major only for: breaking an existing config or provider contract, incompatible plugin manifest schema changes, or removing a provider category.

## 2. Bump every version location

Run `scripts/release.sh <version> "<summary>"` — it bumps every location below plus README count surfaces. The table is the verification list, not a manual procedure; after the script, `grep -rn "<old-version>" --include="*.json" --include="*.md" .` to catch anything it missed (e.g. the `routines.json` `$comment` version):

| File | Field |
|------|-------|
| `package.json` | `version` |
| `.claude-plugin/plugin.json` | `version`, `description` (starts with `vX.Y.Z - ...`) |
| `.claude-plugin/marketplace.json` | GENERATED, see step 3 |
| `.claude-plugin/plugin-manifest.json` | `version`, component counts |
| `.codex-plugin/plugin.json` | `version` |
| `.cursor-plugin/plugin.json` | `version` |
| `.factory-plugin/plugin.json` | `version` |
| `.factory-plugin/marketplace.json` | `metadata.version`, plugin entry `version` + `description` |
| `README.md` | version badge, current-release highlight/table row, component counts, model defaults, Claude Code capability floor/ceiling |
| `.claude-plugin/README.md` | public provider roster, minimum runtime, component counts |
| `PRODUCT.md` | current release, provider/component counts, Claude Code capability count/ceiling |
| `CHANGELOG.md` | new `## [X.Y.Z] - YYYY-MM-DD` section (fold Unreleased into it) |

## 3. Regenerate derived artifacts (`make sync`)

Do NOT hand-edit these; CI diffs them against their generators:

| Generated artifact | Generator | CI check that fails if stale |
|--------------------|-----------|------------------------------|
| `README.md`, `.claude-plugin/README.md`, `PRODUCT.md`, `docs/AGENTS.md`, `docs/COMMAND-REFERENCE.md`, and `docs/README.md` mechanical release facts | `./scripts/sync-readme.py` | `tests/unit/test-readme-release-sync.sh` and `make sync-check` |
| `.claude-plugin/plugin-manifest.json`, `.codex-plugin/plugin.json`, `.factory-plugin/plugin.json`, and `.factory-plugin/marketplace.json` component counts | `./scripts/sync-readme.py` | `tests/unit/test-readme-release-sync.sh` and `make sync-check` |
| `.claude-plugin/marketplace.json` (octo entry description + counts) | `./scripts/sync-marketplace.sh` | Smoke job step "Verify marketplace.json is up to date" |
| `openclaw/src/tools/index.ts` | `./scripts/build-openclaw.sh` | `tests/unit/test-openclaw-compat.sh` |

Rules learned the hard way:
- The marketplace generator derives the feature summary from `plugin.json`'s `description` and appends current persona, command, and skill counts. To change the marketplace blurb, edit `plugin.json`'s description and run `make sync` — never edit `marketplace.json` directly. Never hand-write counts into `plugin.json`'s description; the generator appends them and `--check` will fail on the collision (the v9.50 description did this and shipped doubled counts until v9.51).
- The README generator derives the current release copy from `plugin.json`, model defaults from `scripts/lib/model-resolver.sh`, and Claude Code floor/ceiling facts from `scripts/orchestrate.sh` plus `scripts/lib/providers.sh`. Keep the `CURRENT RELEASE` and `CURRENT MODEL DEFAULTS` markers intact, plus exactly one version-table row marked `(new)`.
- README body prose counts must match `plugin.json`: the "**N commands** ... **N skills**" sentence and the "[All N skills]" link are asserted by `tests/unit/test-docs-sync.sh`.

`make sync` runs all generators; `make sync-check` runs every corresponding
check mode.

## 4. Validate locally with CI parity

```bash
make ci-local
```

This runs generated-file checks and the complete local smoke, unit, and
integration suites, including docs sync, OpenClaw compatibility, and plugin
expert review. Hosted CI separately checks Linux/macOS portability, ShellCheck,
package artifacts, and symlink paths. Local success does not replace those
checks on the exact release commit.

Known scanner gotcha: `tests/integration/test-plugin-expert-review.sh` greps tracked non-md files for `(API_KEY|SECRET|PASSWORD)\s*=\s*['\"]<20+ chars>`. A shell line like `ANTHROPIC_API_KEY="${VAR}"` false-positives. Quote the whole env argument instead: `"ANTHROPIC_API_KEY=${VAR}"`.

## 5. Check file modes

```bash
git diff origin/main...HEAD --summary | grep "mode change"
```

Must be empty. Shell scripts and Python helpers must stay `100755`; both contributor tooling and editor-based rewrites have silently dropped exec bits before (root cause of PR #579's "Permission denied" CI failures). CI enforces this via the executable-bit lint in the Portability Lint job; the `allow-mode-change` PR label bypasses it for intentional mode changes.

## 6. PR and CI

- Open the PR against `main`. Same-repo branches run CI immediately; **fork PRs stall at `action_required`** until approved: `gh api -X POST repos/nyldn/claude-octopus/actions/runs/<run-id>/approve` (needed after every push to the fork branch).
- Known flake: macOS runner timing in `tests/unit/test-agent-lifecycle-events.sh` ("hook timeout did not return promptly"). If it hits, `gh run rerun <run-id> --failed` once before investigating.
- Squash-merge is the repo convention.
- `scripts/release.sh` waits up to 15 minutes by default so the macOS unit
  matrix can finish. Override only when necessary with
  `OCTO_RELEASE_CI_TIMEOUT_SECONDS=<seconds>`.
- Automatic merge requires an explicit approved review and zero unresolved
  review threads across every paginated result page.

## 7. Tag AFTER the squash-merge

The tag must point at the merge commit on `main`, not at the branch head (squash rewrites the SHA):

`scripts/release.sh` creates and pushes this annotated tag automatically. If a
release is being recovered manually, use:

```bash
sha=$(gh pr view <pr> --json mergeCommit --jq .mergeCommit.oid)
git fetch origin main
git tag -a vX.Y.Z "$sha" -m "vX.Y.Z: one-line summary"
git push origin vX.Y.Z
```

## 8. GitHub Release

```bash
gh release create vX.Y.Z --verify-tag --title "vX.Y.Z" --notes-file <(awk '/^## \[X.Y.Z\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md)
```

Marketplace consumers pin by release; a bare tag is not enough.

## 9. Post-merge verification

`scripts/release.sh` waits for the main-branch Test Suite on the exact squash
commit before it creates the tag or GitHub release. For manual recovery, watch
that run until `completed/success`. A release is not done while main is red.
