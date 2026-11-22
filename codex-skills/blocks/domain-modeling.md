# Shared domain definitions

Load a project's existing glossary and decisions before adding terms. If none
exists, add a short definitions section to the current design document. Do not
create a parallel memory or task system.

| Term | Meaning |
|---|---|
| provider | Executable or API transport, not proof of model family |
| model | Requested or resolved model identity, with its source stated |
| installed | A binary was found; login and access remain unproven |
| authenticated | Credential or session evidence, not model entitlement |
| entitlement | Account access to a service or model, when established |
| readiness | Timestamped local check with reason and remediation |
| billing mode | `subscription`, `api`, `local`, `mixed`, or `unknown`; never inferred from installation |
| quota | Remaining allowance from an authoritative source |
| seat | Requested reviewer job, not a completed contribution |
| contribution | Received artifact with provenance and grounding status |
| vote | Admissible judgment after contribution validation |

Registry `cost_class=bundled` does not prove an account's billing mode. Record
observations with value, evidence source, check time, and scope. Keep unknowns
explicit. Never store raw credentials, account email, or token material.
