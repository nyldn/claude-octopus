## 2. Select and freeze the rubric

Use a hybrid approach. A user-provided rubric takes precedence. Otherwise read
`config/refinement-rubrics.md` in the installed plugin root. Select the nearest
profile and adapt it to the artifact's purpose before scoring. For PRDs, reuse
the criteria and point allocations from `commands/prd-score.md`; normalize them
to the common scale without running its interactive command.

Test rubric fit against the requested outcome. Research only a material domain
gap, using authoritative sources and a maximum of two research calls within the
run budget. Prefer local standards the user already supplied. Keep URLs and
dates with the rubric. If browsing is unavailable, mark the limitation; do not
invent standards or imply researched coverage. Regulated or unfamiliar domains
may require user-supplied standards before a meaningful score is possible.

Write `rubric.json` following the contract in
`docs/REFINEMENT.md`. Include 3 to 8 observable criteria, weights totaling 100,
anchors at 0, 1, 2, 3, and 4, and a minimum score for each criterion. Set the
target and list required validation guards before the baseline. Use minimum
3/4 by default. Criteria specific to the user's rubric may have a different
count or minimum when justified. Translate a supplied scale transparently;
preserve its weights, thresholds, and veto conditions.

Show the rubric, scope, selected providers, and budget briefly, then proceed
within the user's authorization. Do not demand approval at every iteration.
Freeze the rubric bytes and hash. Do not change weights, lower standards, remove
hard findings, or increase verbosity merely to raise the score. A necessary
rubric correction starts a new version and requires rescoring the original and
best candidate under the new version, within the same remaining budget.

Record the defect and supporting evidence before correcting the rubric. Keep
the previous pair's frozen rubric and assessments. Reserve enough remaining
time and at least four calls to rescore the original and best candidate. If
that budget is unavailable, stop and report the correction as unscored.

For the first pair under the corrected rubric, use the original candidate
snapshot and append these arguments to the mandatory phase 3 pair command:

```bash
--rubric-correction "$PREVIOUS_RUBRIC_SHA256" "$CORRECTION_REASON"
```

Use the latest rubric hash from `calls.jsonl` and a specific correction reason,
at most 2,000 characters. The helper records the old and new hashes, reason and
incremented `rubric_version` in its reservation. It rejects a stale hash,
an unchanged rubric, or scoring an edited candidate before the original.
Restoring historical rubric bytes also requires a new version. Rescore the best
candidate with another unique pair ID and the same corrected rubric, without
the correction flag.
Preserve the ledger, fixed panel, absolute deadline and total call limit.
Compare scores only within the same rubric version.
