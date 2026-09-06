# Workflow methods

Claude Octopus includes explicit methods for architecture, TDD, debugging,
planning, domain definition, and prototypes. They are available in Claude Code
and generated Codex skills, but ordinary prompts do not activate them.

## Host-native by default

Routine architecture, TDD, and debugging run on the current host with no extra
provider dispatch. Add `--peer-review` when one bounded independent review would
change the result. An explicit debate, council, or multi-model command still uses
its own provider contract.

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

Setup marks the receipt complete last, after local verification, strict legacy
configuration persistence, and readback. Concurrent sessions use revision checks.
Malformed, linked, or wrong-owner state fails closed without replacing existing
bytes. Older Octopus versions ignore the separate receipt directory.

## Attribution

These methods adapt selected patterns from `mattpocock/skills` under the MIT
License. See `THIRD_PARTY_NOTICES.md` and
`licenses/mattpocock-skills-MIT.txt` for the mapping and complete notice.
