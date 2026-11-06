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
identity for a real result. Exactly two distinct providers and models are
required. Every judge must include exactly the rubric's criterion IDs and a
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
