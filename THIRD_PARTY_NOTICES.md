# Third-party notices

Claude Octopus includes methods adapted from
[mattpocock/skills](https://github.com/mattpocock/skills) at commit
`3cca18b368ae95cdbdebbff572ccafa662551015`. The source is licensed under the
MIT License. The complete notice is distributed in
`licenses/mattpocock-skills-MIT.txt`.

| Upstream method | Claude Octopus destination | Local adaptation |
|---|---|---|
| `writing-great-skills` | `skill-authoring` | Explicit invocation, host compatibility, and repository checks |
| `triage` | `skill-intake` | Public issue and pull-request intake |
| `to-tickets` | `skill-work-slicing` | Tracker-neutral vertical slices and claim safety |
| `grilling` | `skill-pressure-test` | One-question decision pressure testing |
| `codebase-design` and `DESIGN-IT-TWICE` | `octopus-architecture`, `skill-audit`, architecture reference | Evidence-led simplification and competing interfaces |
| `DEEPENING` | `skill-tdd`, `skill-coverage-audit` | Behavior-led test consolidation |
| `diagnosing-bugs` | `skill-debug` and debugging reference | Reproduction records and bounded feedback loops |
| `domain-modeling` | `flow-define`, `skill-design-lineage`, `skill-authoring`, provider glossary | Shared domain definitions |
| `wayfinder` | `skill-writing-plans`, `skill-work-slicing`, `skill-pressure-test` | Decision dependencies and safe claims |
| `prototype` | `skill-prototype` | Time-boxed, permission-safe prototypes |
| `wizard` | `sys-configure` and `/octo:setup` | Resumable staged setup; no upstream shell writer was copied |

The adaptations change structure, terminology, execution policy, and safety
rules to fit Claude Code, Codex, and Claude Octopus. They do not synchronize
automatically with the upstream repository.
