# Claude Octopus — Developer Reference

> Moved from CLAUDE.md to save ~1,000 tokens per user session. These sections are for plugin developers and maintainers, not end users.

See [workflow methods](WORKFLOW-METHODS.md) for user-facing behavior and the
[delivery contract](../RELEASING.md#delivery-contract-for-workflow-methods) for
installation, package, and setup verification. Current workflow additions are
documented under [Unreleased](../CHANGELOG.md#unreleased).

---

## Enforcement Best Practices (Mandatory for Workflow Skills)

Host-native advisory methods do not need a provider execution block. Keep them
explicit-only and test that ordinary prompts cannot activate them. A literal
`orchestrate.sh` reference in a method means it spends or dispatches and must keep
the repository's mandatory execution and prohibited-action checks.

Runtime JSON helpers reject duplicate keys, non-finite values, unknown fields,
oversized input, and mixed resolver output. Routing preview tests use fixed
expected decisions plus separate parity checks against the production selector.
Setup-state tests cover revisions, state transitions, linked files, malformed
state, and concurrent supported writers.

Skills that invoke orchestrate.sh MUST use the **Validation Gate Pattern** to ensure proper execution.

### Required Pattern

1. **Add to frontmatter:**
   ```yaml
   execution_mode: enforced
   pre_execution_contract:
     - interactive_questions_answered
     - visual_indicators_displayed
   validation_gates:
     - orchestrate_sh_executed
     - synthesis_file_exists
   ```

2. **Add EXECUTION CONTRACT section** with:
   - Blocking steps (numbered, mandatory)
   - Explicit Bash tool calls (not just markdown examples)
   - Validation gates that verify execution
   - Clear prohibition statements (what NOT to do)

3. **Use imperative language:**
   - "You MUST execute..." / "PROHIBITED from..." / "CANNOT SKIP..."
   - NOT "You should..." / "It's recommended..." / "Consider..."

4. **Validate artifacts:**
   - Check synthesis files exist and are recent
   - Verify via filesystem checks, not assumptions
   - Fail explicitly if validation doesn't pass

See `.claude/skills/skill-deep-research/SKILL.md` for reference implementation.

### Enforcement patterns that hold under pressure

Prefer the three patterns in `skills/blocks/enforcement-patterns.md` over adding more
capitalized emphasis: one **Iron Law** per discipline, a **rationalization table**
pre-refuting the model's observed excuses, and a **terminal state** that names the
successor skill instead of offering a next-steps menu. Emphasis inflation
("MANDATORY" on every step) decays over long sessions; these do not.

---

## Skill Quality Gate (new or substantially changed skills)

Ship a skill only after it clears an eval pass. Thresholds adopted from the strongest
public skill factories (alirezarezvani SKILL_PIPELINE, obra writing-skills):

1. **Baseline first** — run 3-5 representative task prompts in a fresh session WITHOUT
   the skill; save the transcripts. A skill that cannot beat its baseline is deleted,
   not shipped.
2. **With-skill pass rate ≥ 85%** on the same prompts, and a visible improvement over
   baseline on the behaviors the skill exists to change.
3. **Description trigger test** — descriptions state ONLY triggering conditions, never a
   workflow summary (a summarized workflow becomes a shortcut the model takes instead of
   loading the skill). Test with ~10 should-trigger and ~10 should-not-trigger phrasings;
   the skill must load on the former and stay quiet on the latter.
4. **Rationalization capture** — when the skill fails in the field, record the exact
   excuse the model generated and add a row to the skill's rationalization table, then
   re-run the failing scenario.
5. **Budget** — frontmatter description under ~100 tokens; skill body under 500 lines;
   frequently auto-loaded content under 200 words.

---

## Modular Configuration (Claude Code v2.1.20+)

### Directory Structure

```
claude-octopus/
├── CLAUDE.md                    # Main instructions
├── config/
│   ├── providers/
│   │   ├── codex/CLAUDE.md     # Codex-specific
│   │   ├── claude/CLAUDE.md    # Claude orchestrator
│   │   ├── ollama/CLAUDE.md    # Ollama local LLM
│   │   ├── copilot/CLAUDE.md   # GitHub Copilot CLI
│   │   └── cursor-agent/CLAUDE.md  # Cursor CLI (`agent`)
│   └── workflows/CLAUDE.md      # Double Diamond methodology
```

### Loading Modules

```bash
claude --add-dir=config/providers/codex    # Codex context
claude --add-dir=config/workflows          # Double Diamond
```

| Module | When to Load |
|--------|--------------|
| `providers/codex` | Working with Codex CLI integration |
| `providers/claude` | Understanding Claude's orchestrator role |
| `providers/ollama` | Working with Ollama local LLM |
| `providers/copilot` | Working with GitHub Copilot CLI |
| `providers/cursor-agent` | Working with Cursor CLI (`agent`) |
| `workflows` | Learning about Double Diamond methodology |

---

## Test gates

Run affected suites while editing and `make ci-quick` before push. Inspect
`scripts/ci-changed.sh --list` to use its audited focused mapping from
`tests/changed-scope.tsv`. Shared or unmapped changes select the complete local
matrix for offline diagnosis. Do not repeat that full matrix locally when
successful exact-commit hosted coverage is available.

Hosted checks use focused PR coverage or the full weighted-shard tier. Main,
nightly, manual, and merge-queue runs always use the full unit inventory on
Linux and macOS. Required Smoke Tests, Unit Tests, and Integration Tests,
exact-commit approval, and resolved threads still gate merge and publication.
See [test tiers](../tests/README.md#test-tiers) and [releasing](../RELEASING.md)
for the delivery contract. `make ci-local` remains the complete offline fallback.

Test fixtures default to a separate `octopus-tests-<pid>` directory under
`TMPDIR`, or `/tmp` when unset. Set `TMPDIR` to a private directory with readable
ancestors when a host's temporary-file policy prevents descriptor traversal.
Relative `TMPDIR` values are anchored to the suite's original working directory.
Leave `TEST_TMP_DIR` unset for nested suites so each process owns its cleanup.
Keep UTF-8 character classification enabled; use `LC_COLLATE=C` for consistent
sorting rather than forcing `LC_ALL=C` across Unicode tests.

## Tangle Input and Migration Safety

Keep `OCTOPUS_TANGLE_RUN_WORKTREE=true` (the default). A clean source checkout
may contain one explicit untracked context input: reference a bare
`PLAN.md`, `SPEC.md`, or `BRIEF.md` name, or prefix another Markdown path with
`plan:`, `spec:`, or `brief:`. Octopus injects that file's contents into the
isolated run; it does not admit unrelated dirty paths or copy the input into the
implementation branch. Additional untracked context files are unsupported;
commit or stash every other source change.

Tangle does not authorize agents to apply, push, or repair migrations on a
persistent local, linked, remote, or shared database by default. When a run
changes `supabase/migrations/*.sql` and the Supabase CLI is available, validation
runs the read-only `supabase migration list --local` check and fails if applied
versions differ from disk. Use a project-owned disposable reset/test workflow.
`OCTOPUS_TANGLE_ALLOW_DB_APPLY=true` authorizes application but never permits
history drift; `OCTOPUS_TANGLE_ALLOW_UNVERIFIED_MIGRATIONS=true` explicitly
accepts the risk when local history cannot be queried.

---

## E2E Testing Infrastructure

V10 includes a hermetic failure-injection suite that drives the real
`scripts/orchestrate.sh spawn` entrypoint. Its expected exit codes, lifecycle
transitions, provider-call counts, contribution eligibility, and required or
forbidden artifacts live in `tests/fixtures/v10-failure-oracles.tsv`; do not
weaken an oracle to accommodate an implementation.

Automated smoke testing runs on a remote VPS, checking for new releases every 2 hours.

- **Phase A (Docker):** Install → structure verify → unit tests → uninstall
- **Phase B (Native):** Live command tests with authenticated Claude Code, Codex, and Antigravity

E2E test scripts are in the private dev repo (`docs/e2e/`), not in this public plugin.

### Dynamic Fleet Dispatch

`scripts/helpers/build-fleet.sh` is the single source of truth for provider-to-perspective assignment. Enforces model family diversity (OpenAI, Google, Microsoft, Alibaba, Anthropic). Never hardcode provider names in skills.

---

## Release Validation

Run the local release validator before tagging a plugin release:

```bash
bash scripts/validate-release.sh
```

The validator checks manifest syntax, command registration, plugin validation through `claude plugin validate`, and a packaged zip smoke build. On Claude Code v2.1.128+, `--plugin-dir` can load a plugin zip archive; on v2.1.129+, `--plugin-url` can load that archive from an HTTP URL for the current session.

Runtime plugin loading is opt-in because it invokes Claude Code:

```bash
OCTOPUS_RELEASE_RUNTIME_SMOKE=1 bash scripts/validate-release.sh
```

That mode creates a temporary plugin zip, loads it with `claude --plugin-dir <zip>`, serves it locally, then loads it with `claude --plugin-url http://127.0.0.1:<port>/octo-plugin.zip`. Both calls use stream-json with hook events enabled so `init.plugin_errors` surfaces plugin load failures in the release log.

Use `OCTOPUS_RELEASE_SMOKE_MAX_BUDGET_USD` to lower or raise the Claude Code budget cap for the runtime smoke, and `OCTOPUS_RELEASE_SMOKE_PORT` if the default localhost port is busy.

## Agent lifecycle events

Octopus emits provider and dispatch telemetry to the JSONL event stream controlled by `OCTO_EVENT_LOG`. Agent spawn/completion events use the same surface:

```bash
export OCTO_EVENT_LOG=auto
```

Event names:

```text
agent.spawned
agent.completed
```

Lifecycle event attributes include `provider`, `agent_type`, `task_id`, `role`, `phase`, `pid`, `result_file`, `results_dir`, `workspace_dir`, `exit_code`, `status`, `root_session_id`, and `parent_session_id`.

External control planes that need an immediate callback instead of tailing the JSONL file can also set an optional best-effort hook:

```bash
export OCTOPUS_AGENT_LIFECYCLE_HOOK=/path/to/hook
export OCTOPUS_AGENT_LIFECYCLE_HOOK_LOG=/tmp/octopus-agent-hook.log  # optional
```

The hook is invoked as:

```bash
$OCTOPUS_AGENT_LIFECYCLE_HOOK spawned
$OCTOPUS_AGENT_LIFECYCLE_HOOK completed
```

The hook receives the same lifecycle metadata through `OCTOPUS_AGENT_*` environment variables. Hook stdout/stderr are redirected to the optional hook log or `/dev/null`; hook failures are ignored so observer outages never fail agent execution.

## Command safety acceptance

Run `bash tests/unit/test-command-safety-regressions.sh` for deletion target
checks and stable guard-state identity across Claude and Codex hosts. The
fixture passes command text to hooks without running deletion commands.
`tests/unit/test-review-external-cli-unwrap.sh` covers failed, timed-out, and
malformed verification and the publication gate using inert providers.
`tests/unit/test-command-discovery.sh` checks host root precedence across the
command catalog. Regenerate portable skills and command adapters with
`make sync` after changing their source instructions.

Metric loops are host-managed candidate-copy workflows. Their contract requires
preservation of the index and existing edits, concurrent-edit checks, bounded
subprocesses and persistent budgets. Static tests do not prove a host complied
with that contract; retain the run's snapshots, hashes, checks, and ledger when
validating an actual experiment. A missing capability stops the run.

### Tangle output coverage

Managed Tangle validation checks the parent-owned `Files:` / `Creates:` scopes against the integration checkout. Existing regular files, nonempty output directories and tracked deletions from the immutable baseline can supply artifact evidence; model prose cannot create that evidence. Read-only input references, linked plans and shared documentation are not output obligations. Symlink aliases and paths outside the checkout cannot satisfy coverage. A missing declared output still fails, and an unavailable coverage check fails closed.

The unstructured `check_explicit_file_coverage` compatibility path remains textual for standalone callers and considers direct write instructions rather than preceding read context. Managed workflows supply the explicit scope contract and do not depend on textual echoes. Scope authorization, mechanical tests and independent quality review remain separate gates; existence is coverage evidence, not proof of correctness.

## Complete review verification

Round 2 builds byte-bounded requests from complete findings and the matching
patches or numbered excerpts. Every batch preserves finding identity; a missing,
duplicate or invalid verdict leaves that batch unverified. The builder plans all
batches before dispatch, so a finding that cannot fit fails admission before any
verifier calls. Final dispatch uses `OCTOPUS_OVERSIZE_STRATEGY=fail` to account for
method and persona additions without silently clipping required input.

The contextual Tangle gate never dispatches corrections for unverified findings.
Verified findings from a partial reviewer fleet may receive corrections while
validation remains incomplete. The gate records `reviewVerification` and
`reviewFindings` in the existing attempt manifest. A complete retry updates the
same marker. Consumers must treat an incomplete review as unfinished validation,
not as a list of confirmed product defects. No provider retry policy is changed.

New review/correction work marks verification pending unless an earlier review
remains incomplete. Pending attempts preserve incomplete and partial-verified
markers until a completed review replaces them. Failed fleet or malformed
review artifacts keep it incomplete until a genuinely completed review replaces
them. Completion is checked before local scope findings are added, so a scope
violation cannot authorize corrections after the reviewer fleet fails.
The existing unmanaged fallback replans a failed batch for its own context
window; this does not restrict the initial provider or alter pinned review seats.

`tests/unit/test-review-verifier-batches.sh` exercises large Unicode finding
sets, relevant evidence, admission refusal and preservation without corrections.
Patch windows retain adjacent removals at the finding's new-file coordinates
and shrink before rejecting a complete finding. Verification may add a verdict
and the newly-reachable flag, but cannot change original fields such as confidence.
Missing or invalid final verdicts keep Tangle verification incomplete. A failed
manifest replacement stops the gate instead of reporting a successful update.
Context setup failures stop both initial and retry review even when a caller
handles the gate's exit status. Verified findings from a partial fleet can still
receive corrections, while the manifest remains incomplete until a full review.

Synthesis may reorder verified findings, but cannot remove them, invent findings,
or change their fields. A changed set uses deterministic local synthesis instead.
Incomplete verification returns failure after saving findings and proof artifacts.

Final synthesis compares the full verified finding multiset before any display
normalization. Distinct records at the same location remain in the saved artifact,
ranked with blockers first. Deleted-file excerpts use the cited old-file line.

A completed review with partial fleet coverage returns status 3 from the
contextual wrapper only after the underlying review succeeds. Its manifest
keeps `reviewVerification: incomplete` and records `reviewOutcome: partial-verified`.
Other nonzero review results cannot authorize corrections, even when a verified
findings file survived a proof or publication failure. A complete retry clears
both markers. Patch excerpts bound adjacent removal context separately and label
unmatched short patches as unrelated context requiring repository inspection.

Verifier input directories use private permissions and subprocess-scoped cleanup
for normal exits, interrupts and termination. Caller traps remain intact. Valid
synthesis ordering is retained within each severity tier; a changed finding
multiset still uses the complete deterministic fallback.

Accepted synthesis contributes only findings. Document-level warnings and
verification status come from local review state. Reports and publication
preserve distinct verified records at the same location and collapse only
fully identical verified records.

An incomplete retry that produces no findings file retains the previous
`reviewFindings` path for recovery. A new findings file replaces that path, and
a complete retry records its own artifact and clears the incomplete state.
