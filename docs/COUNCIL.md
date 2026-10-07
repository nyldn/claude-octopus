# Council evidence

Council file access depends on the provider and dispatch transport. Consultative
CLI seats run in a disposable working-tree copy and can inspect project files
present there. A tracked relative path such as `./src/service.ts` can therefore
be reviewed without inline context when that seat has file tools. File-tool
availability and permission enforcement follow the selected transport.

Pass a readable file with `--context-file` to give every seat the same artifact
bytes without depending on file tools or workspace visibility. Repeat the flag
for each artifact. Council includes its contents in every seat's prompt as
untrusted data. This is useful for artifacts absent from the copied workspace
and seats without file tools.

```text
/octo:council --goal review --context-file ./src/service.ts "Review ./src/service.ts"
```

## Missing artifact context

Council warns before the advice phase when the task names a supported artifact
path and no context file was supplied. Supported forms include `/tmp/plan.md`,
`~/plans/review.diff`, `./src/service.ts`, and `../docs/design.md`. Bare filenames
such as `package.json` and prose without a supported path pass silently. The
check recognizes path text; it does not test whether that path exists, whether
it is present in a copied workspace, or whether the selected seat can read it.
It can warn about a tracked-file review that a CLI seat could perform.

Set `OCTOPUS_COUNCIL_REQUIRE_CONTEXT=1` in the runner environment to return exit
code 2 instead of warning. Strict mode enforces an inline-context policy and can
reject an otherwise workable tracked-file review. Supplying any context file
suppresses this guard. Include every artifact needed for the review; the guard
does not check that supplied files cover all task references.

## Source quote checks

Council can match distinctive response quotes against bounded source reads.
Injected instruction files do not count as source evidence. Excluded basenames
include `CLAUDE.md`, `AGENTS.md`, `CLAUDE-OCTO.md`, `AGENTS-OCTO.md`, `GEMINI.md`,
`copilot-instructions.md`, `cursor.md`, and `cursorrules.md`, regardless of case
or directory. Existing hidden-path, private-file, symlink and scan limits apply.

By default, a matching source quote is sufficient for the content-match check.
To require a nearby filename mention as well, set
`OCTOPUS_COUNCIL_CONTENT_MATCH_PROXIMITY_CHARS=N` to a positive integer. Unset or
`0` retains the default. Values are capped at the response size limit.

The mention must have a basename reached by the bounded source scan, and one
quote occurrence must fall within `N` characters of that mention. Fenced lines
use their own response offsets. Duplicate source content can match before the
named file; scanning continues within the existing budgets to resolve names.

This option tightens the content-match signal. Basename resolution and proximity
do not prove that the quote came from that exact file or that a seat read it.
Validated citations and the council's other grounding paths still apply.
