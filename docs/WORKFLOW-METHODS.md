# Workflow methods

The adapted methods shipped in v11.1.0. The command activation improvements
below are tracked under [Unreleased](../CHANGELOG.md#unreleased).

Claude Octopus includes explicit methods for architecture, TDD, debugging,
planning, domain definition, and prototypes. They are available in Claude Code
and generated Codex skills. Within an invoked workflow, Octopus selects only
the methods relevant to the task. Automatic invocation by the host depends on
its installed skills and configuration; this update does not change it.

## Activation paths

| Entry point | Conditional methods | Result |
|---|---|---|
| Develop command or development phase | Debugging for defects; TDD for executable behavior; work slicing | Reproduction or behavior evidence and deliverable slices |
| Review command or delivery phase | Architecture simplification; coverage audit for test removal | Caller evidence and preserved behavior coverage |
| Plan command or planning skill | Domain definitions, decision mapping, pressure testing, prototypes | Resolved terms and dependencies; bounded experiment proposal |
| Define command or definition phase | Domain modeling and decision mapping | Shared definitions and blocking decisions |
| Architecture skill, audit or debate | Simplification and competing interfaces | Migration, rollback and evidence for alternatives |
| TDD or debug command | Direct adapted method | Observed test results or original-scenario verification |
| Skill authoring skill | Authoring method and domain definitions | Trigger, boundaries and compatibility evidence |
| Setup command | Resumable setup | Fresh readiness checks and completion receipt |

The shared selection contract is included in spawned development, definition
and review prompts before context budgeting. Providers load detailed references
only when relevant and accessible. A provider without source access must report
that limitation; receiving the contract does not prove it followed the method.
Explicit multi-provider commands retain their provider execution requirements.

## Choose a method

| Task | Entry point | Expected result |
|------|-------------|-----------------|
| Simplify architecture or compare interfaces | Select the architecture skill | Caller evidence, alternatives, migration and rollback plan |
| Add behavior with tests | `/octo:tdd` | Observed failing test, implementation, passing tests |
| Investigate a bug | `/octo:debug` | Reproduction, tested hypothesis, original-scenario verification |
| Resolve terms and blocking decisions | `/octo:plan` and the definition/planning skills | Shared definitions and a decision dependency graph |
| Test one risky assumption | Select `skill-prototype` | Time-limited experiment and an evidence-based verdict |
| Inspect a routing decision | JSON preview helper below | Decision with explicit verification limits |
| Resume configuration | `/octo:setup` | Fresh readiness checks and a verified completion receipt |

In Codex, select the corresponding packaged skill from its skill picker.
Architecture is named `octopus-architecture`; the other direct methods include
`skill-tdd`, `skill-debug`, and `skill-prototype`.

```text
/octo:debug "Reproduce the checkout timeout and verify the fix"
/octo:tdd "Check invitation expiry and get an independent opinion on the test design"
/octo:plan "Compare two interfaces for the notification service"
/octo:auto "Prototype a parser to measure throughput"
```

## Host-native by default

Routine architecture, TDD, and debugging run on the current host with no extra
provider dispatch. Request an independent opinion in ordinary language when one
bounded review would change the result. `--peer-review` remains an optional
override with the same admission rules. Existing escalation policy must permit
the call under current preferences, budget and billing restrictions. Risk alone
does not grant paid usage permission. An explicit debate, council, or multi-model command still uses
its own provider contract.

Using the current host still consumes that host's normal usage allowance.
`--peer-review` can add provider usage and cost. It requests review through the
existing router and preserves model pins; it is not a shell flag or a promise
that an independent provider is available. Missing source access or a correlated
reviewer limits the evidence and must be reported.

Architecture review now starts with callers, recent churn, and the deletion test.
It produces a concrete interface, migration, rollback, and test impact. When two
designs are useful, both use the same requirements and revision. Two drafts from
one host are labeled as correlated.

TDD retains observed red and green evidence. Test consolidation must map every
removed test to an observable behavior and a mutant that the replacement kills.
Debugging must reproduce the reported symptom, bound intermittent runs, and rerun
the original scenario after the fix.

## Shared definitions and decisions

Provider transport, model identity, installation, authentication, entitlement,
billing, and quota are separate facts. A requested review seat becomes a
contribution only after an artifact arrives with provenance and grounding.

Plans map unresolved decisions before implementation tasks. Decision cycles keep
work out of ready state. Claims use the configured tracker's atomic operation and
are read back before editing. If the tracker fails, Octopus saves an explicitly
unfiled proposal rather than inventing IDs.

## Bounded prototypes

`skill-prototype` answers one question within a deadline. It records the
hypothesis, artifact path, source revision, observations, verdict, and artifact
disposition. Native read-only plan mode can propose a prototype but cannot write
or launch one. A prototype choice does not authorize provider calls, deployment,
browser login, or repository rewrites.

## Offline routing preview

`scripts/helpers/preview-routing.py` accepts one strict JSON request:

```bash
python3 scripts/helpers/preview-routing.py --input request.json
```

Run from the source checkout with Python 3, Bash, and jq available. For example,
save this request as `request.json` outside the installed plugin cache:

```json
{
  "schema_version": 1,
  "kind": "workflow-provider",
  "phase": "tangle",
  "operation": "coding",
  "role": "implementer",
  "default_provider": "claude-sonnet",
  "config": {
    "routing": {
      "roles": {"implementer": "ollama:local-model"},
      "phases": {}
    }
  },
  "environment": {"OCTOPUS_TANGLE_CODING_AGENT": "agy"},
  "available_binaries": ["codex"],
  "observations": []
}
```

This selects `agy` because the phase/operation override wins. The response has
`effective_model: null`, `dispatch_admissibility: "not_checked"`, and
`production_dispatch_verified: false`. `available_binaries` is simulated input,
not discovery of tools installed on this machine. Empty `observations` supplies
no evidence of authentication or billing.

Exit status `0` means the preview completed. Invalid input returns `2`, a
missing local dependency `3`, a resolver failure `4`, timeout `5`, and
interruption `130`. Errors go to stderr; do not treat an error as a route.

`policy` previews call the deterministic evaluation policy. They do not predict
production dispatch. `workflow-provider` previews call the production provider
selector, but stop before model resolution, authentication, entitlement, quota,
fallback, and dispatch admission. Responses always set
`production_dispatch_verified` to `false`.

Availability and billing observations are caller-supplied evidence. The preview
makes no network or provider call, reads no ambient credentials, and writes no
usage or escalation ledger. Supply the effective reviewer preference when parity
depends on persisted consent; otherwise the response names that limitation.

## Resumable setup

`/octo:setup` stores a private receipt under `~/.claude-octopus/setup/`. A receipt
is scoped to the host, physical plugin root, and flow version. Resume always
rechecks current readiness. Human login remains a user-run terminal step, and a
remote session never opens the browser.

Rerun `/octo:setup` to resume. Host-only setup needs no external provider and
uses local verification without a billable provider probe. If login is needed,
complete the displayed provider login step and let setup recheck readiness.
After an upgrade changes the physical plugin path, expect a new receipt rather
than the old installation's completed status.

Setup marks the receipt complete last, after local verification, strict legacy
configuration persistence, and readback. Concurrent sessions use revision checks.
Malformed, linked, or wrong-owner state fails closed without replacing existing
bytes. Older Octopus versions ignore the separate receipt directory.

If setup reports damaged state, stop and retain that file for diagnosis. Do not
delete your configuration to make the success message appear. Use
`/octo:skill-doctor` or [troubleshooting](TROUBLESHOOTING.md) to inspect readiness.
Receipt completion proves the local setup checks passed, not model entitlement,
remaining subscription quota, or a successful live provider task.

## Acceptance evidence

The package includes [acceptance scenarios](../data/evals/workflow-skill-cases.json)
and [test-consolidation evidence](../data/evals/workflow-test-consolidation.json).
Deterministic tests cover routing limits, setup persistence, and the documented
command paths. The consolidation record retains suites that cover different
failure modes; it does not claim a blanket test-suite speedup. Live model
behavior cases remain `not_run`, so no measured model-quality improvement is
claimed.

## Attribution

These methods adapt selected patterns from `mattpocock/skills` under the MIT
License. See [third-party notices](../THIRD_PARTY_NOTICES.md) and the
[complete license](../licenses/mattpocock-skills-MIT.txt) for source mappings and
reuse terms.
