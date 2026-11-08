# Refinement rubric profiles

These profiles are starting points. Adapt the observable criteria to the user's
purpose before scoring, then freeze the rubric for the entire run. They are
not external standards or claims of validated measurement accuracy.

| Profile | Starting criteria and weights |
|---------|-------------------------------|
| Plan | Outcome and scope 20; dependency and sequence correctness 25; feasibility and ownership 20; acceptance and verification 25; risks and recovery 10 |
| Code change | Correctness 35; security and data integrity 25; reliability and maintainability 20; tests and acceptance evidence 20 |
| Prose or proposal | Audience and purpose 20; factual support 30; reasoning and completeness 25; clarity and structure 25 |
| Visual artifact | Task and audience fit 25; hierarchy and readability 25; accessibility 25; rendered consistency and interaction evidence 25 |
| General artifact | Purpose fit 25; correctness and evidence 30; completeness and usability 25; clarity and constraints 20 |

For a PRD, reuse the existing `/octo:prd-score` rubric rather than inventing a
second PRD scoring standard. Preserve its 25/25/30/20 category weights and
subcriteria. A score of x points out of y maps to `4 * x / y` on this scale.

Each criterion needs artifact-specific anchors. Use this common scale only as
a guide, then write concrete evidence requirements for each level:

| Score | Meaning |
|-------|---------|
| 0 | Missing, contradicted, or unusable |
| 1 | Major gaps prevent the intended use |
| 2 | Partially supported; material work remains |
| 3 | Meets the stated requirements with minor weaknesses |
| 4 | Fully supported and verified for the stated purpose |

Fractional values are allowed when evidence falls between anchors. Do not
invent precise confidence from these scores. Default criterion minimum is 3/4.
Default aggregate target is 95/100. Required constraints remain blocking even
when the aggregate exceeds the target.

Choose guards before the baseline. Examples include the repository's required
tests, valid links and grounded factual claims, complete dependency references,
rendered desktop and narrow-width inspection, or a user-supplied acceptance
check. Record what was actually checked. A missing tool or unavailable source
means `unverified`, not `pass`. Some checks are human or model judgments rather
than executable tests; label their evidence accordingly.

Research a new criterion only when a profile does not cover a material domain
requirement. Use authoritative sources and record their URLs and access date.
Do not browse on every round or add criteria after seeing an inconvenient score.
