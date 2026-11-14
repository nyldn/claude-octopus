## 5. Return the best verified result

Report the original and best scores, per-model scores, criterion breakdown,
implemented changes, checks performed, remaining blockers, rounds/calls/cost,
stop reason, and run directory. Label target success only when the validator
returns `target_met: true` for the exact delivered artifact. State `target not
met` when a limit or blocker ends the run, even if the artifact improved.
Report review-only results as assessments, without claiming edits were applied.
Use the validator's computed per-model totals in the report, never a judge's
self-reported arithmetic. Distinguish the resolved model serialized on the
dispatch command from any server-reported identity; do not claim verification
of the latter when the provider does not expose it.

### Show the score trajectory

Use the controller-generated `trajectory.json`, derived from its saved decisions.
Run `refinement-run.py status RUN_DIR` and preserve any unfinished attempt with
`refinement-run.py stop RUN_DIR REASON` before delivery. Do not reconstruct
acceptance decisions or edit the generated trajectory by hand.
Include the original and every attempted round in order, with its conservative
score, per-model scores, accepted/rejected decision, `target_met`, rubric hash,
artifact hash, and score report path. Use null for a round without a valid
assessment and label its failure. Preserve plateaus, regressions, and rejected
candidates. Do not substitute the running best score for a round's actual score.

When the host supports rendered charts, show a horizontal bar chart with a fixed
0-to-100 axis, an Original row, one row per round, numeric score labels, and a
visible target marker. Highlight success only when that round's validator says
`target_met: true`; a high score with a blocking finding remains unpassed.
Distinguish rejected candidates and identify the best delivered version. Use
separate charts for different rubric versions rather than joining incomparable
scores. Build the chart from `trajectory.json`, never from recalled numbers.

Always include a compact table of round, score, change, and decision so the
report is usable in terminals and without a chart renderer. A charting tool
failure must not lose the result or trigger another scoring call. Keep the
trajectory and report beside the existing run evidence. State the elapsed time
and stop reason below the progress view.

95/100 means attainment against this rubric, not a probability of correctness.
It does not waive approval, CI, merge, deployment, sending, publishing, or
domain-specific acceptance requirements. Do not perform those actions as part
of this command without the user's existing authorization for them.
