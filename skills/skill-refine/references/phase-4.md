## 4. Improve, verify, and rescore

Review-only mode stops after the baseline, with suggested changes. Otherwise
choose the highest-impact verified deficits and revise the candidate. Apply the
improvements before rescoring. For code, use the repository's deterministic
checks; for plans, check dependencies, ownership, estimates, and acceptance
evidence; for factual prose, verify claims and citations; for visual work,
inspect the rendered result. Do not replace execution evidence with a promise.

Run guards before requesting new scores. A failed guard consumes a round and
cannot produce an accepted candidate. Do not repeatedly rescore identical
bytes hoping for a higher number. A genuine change starts the next round with
two fresh independent judge calls under the frozen rubric and fixed panel.

Keep a candidate only when its conservative score improves, all guards pass,
and no existing criterion minimum or blocking finding regresses. A candidate
can remain below the target and still be the best valid improvement so far.
Keep the original if no candidate meets these conditions. Reject score gains
caused by unverifiable claims, lost constraints, or rubric drift. Record ties
and rejected candidates as no progress. On material judge disagreement, inspect
the conflicting evidence; do not recruit extra judges until someone passes it.
An unresolved disagreement prevents success and counts toward the stall limit.

After each round, report the score trajectory, accepted changes, remaining
deficits, and budget used. Stop on target success, round/call/time limit,
two-round stall, user cancellation, missing evidence, or a provider failure.
Preserve artifacts and counters on interruption. Resume only after checking
the rubric, candidate, provider panel, and original hashes against the ledger.
