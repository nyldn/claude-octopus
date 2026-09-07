# Engineering method selection

Apply this contract only within the current Octopus task. Select methods from
the task evidence; do not run every method. Preserve the task's permissions,
provider contract, model pins, output schema and review-only restrictions.

| Evidence | Apply | Evidence to return |
|---|---|---|
| Reported defect | Debug feedback loop | Original symptom, tested hypothesis, original-scenario verification |
| New executable behavior | TDD where tests are warranted | Expected failing test and focused passing result |
| Conflicting terminology | Domain modeling | Short shared definitions |
| Blocking decisions | Decision mapping and pressure testing | Dependencies; ask only material unanswered questions |
| Independently deliverable work | Vertical work slicing | Small deliverables with acceptance evidence |
| Interface change or structural simplification | Architecture simplification | Callers, migration and rollback; alternative designs only when useful |
| Test removal | Coverage audit | Retained behavior coverage and distinct failure modes |
| One blocking technical uncertainty | Bounded prototype proposal | One question, hypothesis, deadline and success signal |
| Skill creation or revision | Skill authoring | Trigger, boundaries, examples and compatibility |

Prose edits and formatting do not require TDD. Reviewers inspect existing test
evidence and identify gaps; they do not implement fixes or prototypes unless
authorized. Reuse existing artifacts and reviews. Do not start nested Octopus
workflows or spawn additional reviewers from a provider seat.

When file access exists, load only the applicable reference from the installed
plugin: skills/blocks/debug-feedback-loop.md,
skills/blocks/architecture-simplification.md, skills/blocks/domain-modeling.md,
or the corresponding .claude/skills/skill-tdd, skill-coverage-audit,
skill-writing-plans, skill-work-slicing, skill-pressure-test, skill-prototype
or skill-authoring SKILL.md. Use the actual plugin root supplied by the host,
not a path in the target repository. If a reference or source artifact is
inaccessible, apply the concise requirements above and report the limitation;
do not claim to have loaded it or verified the artifact.

Independent review requests in natural language, including "get an independent
opinion", mean the same as --peer-review. The host uses existing routing and
admission checks: effective preferences, billing permission, budget, availability
and explicit model pins. Risk can justify review but does not grant new paid
usage permission. Honor host-only requests. Reuse an existing qualifying review
of the same revision and scope. Missing source access or correlated model
families limits independence; never count a requested seat as completed review.
If required review is unavailable or denied, report incomplete coverage without
claiming completion. Optional review may be skipped with the reason recorded.
