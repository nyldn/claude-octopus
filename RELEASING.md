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
| `README.md` | version badge (line ~15) |
| `CHANGELOG.md` | new `## [X.Y.Z] - YYYY-MM-DD` section (fold Unreleased into it) |

## 3. Regenerate derived artifacts (`make sync`)

Do NOT hand-edit these; CI diffs them against their generators:

| Generated artifact | Generator | CI check that fails if stale |
|--------------------|-----------|------------------------------|
| `.claude-plugin/marketplace.json` (octo entry description + counts) | `./scripts/sync-marketplace.sh` | Smoke job step "Verify marketplace.json is up to date" |
| `openclaw/src/tools/index.ts` | `./scripts/build-openclaw.sh` | `tests/unit/test-openclaw-compat.sh` |

Rules learned the hard way:
- The marketplace generator derives the feature summary from `plugin.json`'s `description` and appends its own component counts ("32 personas, N commands, N skills"). To change the marketplace blurb, edit `plugin.json`'s description and run `make sync` — never edit `marketplace.json` directly. Never hand-write counts into `plugin.json`'s description; the generator appends them and `--check` will fail on the collision (the v9.50 description did this and shipped doubled counts until v9.51).
- README body prose counts must match `plugin.json`: the "**N commands** ... **N skills**" sentence (README ~line 28) and the "[All N skills]" link (~line 367) are asserted by `tests/unit/test-docs-sync.sh`.

`make sync` runs both generators; `make sync-check` runs both `--check` modes.

## 4. Validate locally with CI parity

```bash
make ci-local
```

This mirrors the required checks plus the CI-only verifications that targeted test runs miss (`sync-check`, docs-sync, openclaw-compat, plugin expert review). Local green here predicts remote green; targeted suites alone do not (v9.50.0 passed every targeted suite locally and still failed three CI-only checks).

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

## 7. Tag AFTER the squash-merge

The tag must point at the merge commit on `main`, not at the branch head (squash rewrites the SHA):

```bash
sha=$(gh pr view <pr> --json mergeCommit --jq .mergeCommit.oid)
git fetch origin main
git tag -a vX.Y.Z "$sha" -m "vX.Y.Z: one-line summary"
git push origin vX.Y.Z
```

## 8. GitHub Release

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <(awk '/^## \[X.Y.Z\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md)
```

Marketplace consumers pin by release; a bare tag is not enough.

## 9. Post-merge verification

Watch the main-branch Test Suite run on the merge commit until `completed/success`. A release is not done while main is red.
