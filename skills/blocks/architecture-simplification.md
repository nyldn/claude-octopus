# Architecture simplification method

Use this method for a design review or a request to simplify an existing
subsystem. It does not authorize production edits.

1. Pin the source revision and scope. Inspect recent churn, follow-up fixes,
   and at least one representative caller.
2. Write the caller contract: call order, invariants, configuration precedence,
   failure semantics, performance constraints, and dependencies.
3. Apply the deletion test. Keep a wrapper when removing it would spread needed
   complexity across callers. File size alone is not evidence of waste.
4. Draft the smallest interface that hides repeated complexity. Include a real
   caller example and every observable failure path.
5. Map old callers and tests to the interface. Include migration, rollback, and
   test changes.

For competing designs, hold requirements and revision fixed. Draft A minimizes
caller knowledge and configuration. Draft B makes the next demonstrated
extension easier. Each draft includes an interface, caller, error behavior,
migration, test effects, and unresolved assumptions.

Host-generated drafts are correlated alternatives from one model. Independent
review is optional unless the user requested it or the risk policy requires it.
An external reviewer must receive the same source and requirements without the
first draft. A reviewer without artifact access may contribute questions, not a
grounded approval. Unknown model family means unknown independence. Preserve an
evidence-backed minority finding even when more reviewers prefer another design.

Return these sections: `Evidence`, `Caller contract`, `Proposed interface`,
`Migration`, `Test impact`, and `Decision`. The decision is `keep`, `simplify`,
or `investigate`. `simplify` requires source evidence and a concrete caller.
