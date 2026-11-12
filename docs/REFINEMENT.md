# Rubric scoring and iterative improvement

Use `/octo:refine <artifact>` or `/octo:ladder <artifact>` to score an artifact,
apply improvements, verify them, and rescore with independent models. The host
coordinates the rounds using the installed `skill-refine`. This is a prompt
workflow, not an unattended scheduler or a new `orchestrate.sh refine` command.

The default target is 95/100, with five improvement rounds, 30 minutes, and 14
external calls. The first limit reached ends the run. Two rounds without
verified improvement also stop it. Research and retries share the call budget.
`--review-only` scores the artifact and returns recommendations without edits.
Explicit model choices and project approval requirements remain in force.

Set a budget with `--max-rounds <1..10>`, `--max-minutes <positive integer>`,
and `--max-calls <positive integer>`. Use `--target <0..100>` to change the
score target or `--rubric <file>` to supply a rubric. These are instructions to
the host workflow, not flags for `orchestrate.sh`.

```text
/octo:refine plan.md --max-rounds 3 --max-minutes 15 --max-calls 10
/octo:refine draft.md --review-only
```

## Rubric strategy

Use a supplied rubric first. Otherwise start with
[`config/refinement-rubrics.md`](../config/refinement-rubrics.md), adapt it to
the artifact, and research only uncovered domain requirements. Freeze the
criteria, weights, minimums, target, and guards before the baseline. If a rubric
must change, rescore the original and best artifact against the new version.
Scores from different rubrics are not an improvement trajectory.

Two independent providers judge the same candidate without prior scores or the
target in their prompts. The host preserves their actual responses and runtime
identities. The lower total is the reported aggregate. This conservative rule
does not remove model bias or turn the score into a probability of correctness.

Before any external call, including model-assisted research, the host must
inspect the candidate, supporting evidence, and accessible project context for
credentials and private tokens. Repeat the inspection for new content before
dispatch. If secrets are found, stop the run and identify the affected input or
file without quoting its secret values. The current adapter cannot isolate
judges from the secret-bearing original or other readable files. A sanitized
copy, a changed working directory, or an instruction to ignore the original
does not establish that isolation and must not be used to continue the run.
Secret-bearing inputs are unsupported until an execution boundary prevents
those reads. This host inspection is not an automatic secret scanner or a
guarantee of data isolation.

The initial judge adapter supports Claude and Codex. It forces a read-only
Codex sandbox, disables configured Codex MCP servers, apps, and plugins, and limits Claude
to Read/Glob/Grep with ambient MCP disabled. Codex MCP inventory failures stop
dispatch without printing its configuration or credential values.
Other judge providers are rejected until they have an enforced read-only
adapter. Authentication retries are disabled; one reserved call is one attempt.

The workflow keeps the best verified candidate. It cannot pass with a blocking
finding, failed or unverified required check, a criterion below its minimum, or
a total-score gap above 10 points. CI and approval requirements still apply.

## Score file contract

`scripts/refinement-score.py` uses Python 3's standard library. It validates
structure, exact artifact and rubric hashes, criterion coverage, weights,
evidence presence, guard results, and score arithmetic. It does not execute
checks or prove that model evidence is correct. The host must inspect the
actual artifact, provider results, and check outputs before supplying them.

Example `rubric.json` with one criterion for brevity:

```json
{
  "schema_version": 1,
  "target": 95,
  "criteria": [{
    "id": "requirements",
    "description": "Every stated requirement has an implementation and acceptance check",
    "weight": 100,
    "minimum": 3,
    "anchors": {
      "0": "No requirement is addressed",
      "1": "Most requirements have no proposed implementation",
      "2": "Some requirements lack an owner or acceptance check",
      "3": "All requirements have owners and checks, with minor ambiguity",
      "4": "All requirements have traceable implementations and verified acceptance evidence"
    }
  }],
  "guards": [{"id": "acceptance", "description": "Run the project's acceptance checks"}]
}
```

Use 3 to 8 criteria for ordinary artifacts. Preserve more criteria when a user
rubric or the existing PRD framework requires them. Weights must be positive and
total 100. Scores and minimums range from 0 to 4; fractional values are allowed.
Every criterion needs five nonempty anchors. A 0-to-10 input score maps to
`score * 4 / 10`. Each contribution is `weight * score / 4`.

Each judge returns `criteria` and `blockers`. The host adds verified provider,
model, effort, and hashes from dispatch metadata, then assembles this envelope:

```json
{
  "artifact_sha256": "<SHA-256 of the exact artifact snapshot bytes>",
  "judges": [
    {
      "provider": "claude",
      "model": "<actual resolved model ID>",
      "effort": "<actual effort or unsupported>",
      "rubric_sha256": "<SHA-256 of the full frozen rubric bytes>",
      "artifact_sha256": "<same artifact hash>",
      "criteria": [{"id": "requirements", "score": 3.5, "evidence": "Section 4 leaves retry acceptance untested"}],
      "blockers": []
    },
    {
      "provider": "codex",
      "model": "<actual distinct resolved model ID>",
      "effort": "<actual effort or unsupported>",
      "rubric_sha256": "<same rubric hash>",
      "artifact_sha256": "<same artifact hash>",
      "criteria": [{"id": "requirements", "score": 3.8, "evidence": "Section 4 covers requirements R1-R8; retry bounds need clarification"}],
      "blockers": []
    }
  ],
  "guards": [{"id": "acceptance", "status": "pass", "evidence": "Acceptance command exited 0; output saved in checks.log"}]
}
```

The values above are illustrative placeholders. Never substitute a guessed
identity for a real result. Exactly one canonical `claude` provider and one
canonical `codex` provider are required, with distinct model IDs. The host takes
these identities from verified dispatch metadata, resolving executor aliases
through the shared provider registry rather than trusting the judge's labels.
The validator rejects executor aliases, alternate casing, and unknown provider
labels; it cannot independently prove the provenance of host-supplied metadata.
Every judge must include exactly the rubric's criterion IDs and a
nonempty evidence string per criterion. All required guards must appear once,
with status `pass`, `fail`, or `unverified` and evidence. Use an empty guard list
only when the artifact has no additional acceptance checks, with that limitation
recorded in the run report. Blockers are nonempty finding strings.

```bash
python3 "$OCTO_ROOT/scripts/refinement-score.py" \
  rubric.json candidate.md assessment.json > score.json
```

Exit 0 means a structurally valid assessment, including a valid assessment
below target. Read `target_met` in the JSON. Invalid input exits 2 with
`valid: false` and `target_met: false`. The validator compares unrounded totals.
Do not round 94.999 up to claim a 95-point pass.

For a set of files, use a deterministic snapshot manifest with ordered relative
paths and per-file SHA-256 hashes. Bind the scores to that manifest and verify
every listed file against it before delivery. For visual or binary artifacts,
hash the delivered bytes and preserve the inspected render beside them.

## Run evidence and limits

Store each candidate and raw provider response in a unique run directory. The
append-only ledger records round, rubric and artifact hashes, actual model IDs,
effort, score report path, calls consumed, elapsed time, usage and known cost,
changes, keep/reject decision, and stop reason. Do not store credentials or
hidden chain-of-thought. Preserve the initial dirty state and concurrent edits.

The host checks budgets and the ledger between actions. The score validator is
not a process supervisor or a spending cap. Provider runtime limits must bound
each call. Missing authentication, a provider failure, an unavailable viewer,
or a limit ends the run with an honest partial result and a named blocker.

Use the final score report only for the exact delivered artifact. Report target
not met when appropriate, plus the best candidate and remaining work. The
command does not commit, merge, deploy, publish, or send artifacts by itself.

## Progress report

The final report includes the original score and every attempted round, with
the changes made and whether the candidate was accepted. It preserves flat
rounds and regressions. Failed assessments have no numeric score. The best
delivered candidate is identified separately from the last attempted round.

On hosts with chart rendering, show horizontal bars on a fixed 0-to-100 scale,
numeric score labels, and a visible target marker. A success color requires a
passing validator result, including its guards and blocking-finding checks.
Different rubric versions get separate progress views. A compact table remains
available when chart rendering is unsupported.

The host builds this view from `trajectory.json`, derived from the saved score
reports and iteration ledger. Each entry includes its round, conservative score,
per-model scores, decision, target result, rubric and artifact hashes, and score
report path. The report also states elapsed time, budget used, and stop reason.

## Persisted run control

`scripts/refinement-run.py` owns the iteration journal and derived trajectory.
It performs no model calls and never modifies the supplied source repository.
Initialize it with the original file or deterministic manifest, provisional
rubric, fixed panel and absolute limits before external research or judging:

```bash
python3 "$OCTO_ROOT/scripts/refinement-run.py" init "$RUN_DIR" \
  "$ORIGINAL_SNAPSHOT" "$RUBRIC_FILE" --deadline "$DEADLINE" \
  --max-calls 14 --max-rounds 5 --claude claude-opus:claude-opus-5-5 \
  --codex codex:gpt-6.1-sol --claude-effort high --codex-effort high
python3 "$OCTO_ROOT/scripts/refinement-run.py" begin "$RUN_DIR" baseline
python3 "$OCTO_ROOT/scripts/refinement-run.py" prepare "$RUN_DIR" \
  "$ORIGINAL_SNAPSHOT" "$GUARDS_FILE"
# Run the mandatory paired dispatch below, then assemble its assessment.
python3 "$OCTO_ROOT/scripts/refinement-run.py" record "$RUN_DIR" "$ASSESSMENT_FILE"
```

Each improvement starts with `begin` before editing and ends with `prepare`
and `record`. Guard results are a JSON array using the score contract. Failed
or unverified improvement guards close the round without model calls. Rejected,
unchanged and guard-failed candidates count toward the two-round stall limit.
The baseline is round zero and does not consume an improvement round. Pending
rounds must be closed before another begins. Target success, elapsed time,
round limits, stalls and required provider failures stop further admission.

`record` verifies both successful pair exits, input hashes, fixed identities and
prepared guards. It recomputes the score from the assessment. Improvements need
a higher conservative score, passing guards and criterion minima, no blockers,
and disagreement of at most 10 points. Valid improvements below the target can
be retained. The best snapshot stays separate from later rejected attempts.
Rubric corrections retain the existing explicit transition and rescore the
original first; counters and call limits are preserved.

Use `reserve RUN_DIR UNIQUE_ID COUNT` before research or model-assisted edits.
It protects capacity for two scoring calls. All calls share `calls.jsonl` and
`.dispatch-lock`. Use `status RUN_DIR` after interruption and `stop RUN_DIR
REASON` when ending an incomplete run. `iterations.jsonl` is authoritative;
`trajectory.json` is a derived view. Never hand-write decisions in either file.
Existing unmanaged runs are preserved as read-only evidence. Initialization
refuses an existing call or iteration ledger. Do not move a stopped run to a
new directory to bypass a limit.

The host still verifies secret inspection, declared guard evidence, original
source preservation and manifest backing files. The controller cannot prove a
model judgment, a visual inspection, account access or a native application
result. The generic classifier treats successful structured assessments as
answer data, so quoted context-limit text does not become a provider refusal.
Nonzero exits and actual provider error envelopes still fail.

## Paired dispatch and readiness evidence

The host resolves explicit Claude and Codex models and efforts, inspects inputs
for secrets, freezes one blind request, and runs guards before scoring. It calls
`scripts/refinement-pair.py` with the private run directory, unique pair ID,
prompt path, candidate path, rubric path, absolute run deadline, total call limit,
Claude `executor:model`, Claude effort, Codex `executor:model`, and Codex effort.
The helper reserves both calls in `calls.jsonl` and saves the pair manifest before
launch. Both seats run through the mandatory `refinement-judge.sh` adapter.

Reserve other external calls with `refinement-run.py reserve`. It records
`pair_id`, `calls`, `deadline`, and `max_calls` under `.dispatch-lock`. Preserve the deadline and total
budget on resume. Failed and interrupted reservations remain spent. A pair ID
cannot dispatch twice. A stale lock requires inspection of its saved evidence.
The pair helper waits for both seats under one deadline and cancels only its own
process groups. It produces raw responses, never valid-score claims. The host
must inspect both result identities, assemble the assessment, and run the score
validator. One successful seat cannot become a passing pair.

A material rubric correction uses the same run and ledger. Append
`--rubric-correction PREVIOUS_SHA256 REASON` to the first pair command under
the corrected rubric, with the latest rubric hash and a specific reason of at
most 2,000 characters. That pair must rescore the original candidate. The helper
records the new `rubric_version`, both hashes and the reason before dispatch.
Rescore the best candidate next under that version with a new pair ID. Keep
the fixed models, efforts, deadline and total call limit; both pairs consume
the remaining budget. Silent changes and stale hashes fail. Restoring historical
rubric bytes also creates a new version rather than reusing earlier assessments.
Retain earlier assessments and compare scores only within a rubric version.

Use `scripts/helpers/preflight.sh --providers claude,codex --json` for this fixed
panel. The public dashboard still checks all detectable providers when neither
a panel nor council roster is pinned. A panel does not change the council roster.
Optional version/model diagnostics check the selected providers only.

To preserve selection evidence, add `--run-id RUN --report-out PRIVATE_PATH`.
Reuse it with the same panel and run ID using `--report-in PRIVATE_PATH` within
120 seconds. Reports refuse changed scope, schema version, configuration metadata,
binary metadata, quota/policy metadata, or readiness status/reason/check kind.
They contain no credential values. Every reuse performs fresh readiness checks.
Pass it through preparation with `OCTOPUS_PREFLIGHT_PROVIDERS=claude,codex`,
`OCTOPUS_PREFLIGHT_REPORT=PRIVATE_PATH`, and `OCTOPUS_PREFLIGHT_RUN_ID=RUN`.
These reports are selection evidence only. They cannot authorize dispatch or skip
current per-seat credential, quota, and policy checks.

## Phase resources and delivery checks

`skills/skill-refine/SKILL.md` and `skills/flow-discover/SKILL.md` are canonical
always-loaded contracts. Their nested `references/` files contain ordered phase
instructions. Hosts resolve these resources under the installed plugin root.
Skill sync preserves both canonical directories and generates their Claude entry
copies under `.claude/skills/`. Both hosts use the same root phase files.
Do not edit those generated Claude copies. Native plugin packaging retains the
root resources; standalone entry-file copies alone are insufficient.

Run these focused offline checks before integration:

```bash
python3 tests/unit/test-refinement-efficiency.py
bash tests/unit/test-provider-readiness-contract.sh
bash tests/unit/test-preflight-roster.sh
bash tests/unit/test-refinement-judge.sh
bash tests/unit/test-refinement-score.sh
python3 tests/unit/test-refinement-run.py
bash tests/unit/test-provider-rejection-classification.sh
bash -n scripts/lib/preflight.sh scripts/helpers/preflight.sh scripts/helpers/check-versions.sh scripts/build-codex-skills.sh
```

The efficiency suite tests packaging in a disposable fixture, including repeated
sync, resource discovery, inert judge overlap, reservation rejection, failure,
deadline and cancellation. It invokes no live models. Root integration runs
`make sync`, `make ci-quick`, and exact-head hosted checks. Local tests do not
establish installed-host acceptance or authorize publishing a release.

A rubric correction recalibrates the original, including any known failed
baseline guards, before rescoring the retained best. Success remains pending
until both distinct artifacts have been rescored. If the retained best is the
original itself, the original pair covers both; do not score identical bytes
again. A correction preserves stalled-round counts and needs capacity for both
rescores before it starts.

If correction stops before both rescores finish, the controller retains the
previously accepted artifact and its score under the previous rubric. It marks
the correction incomplete and clears target success. Delivery preserves the
first recorded stop reason.
