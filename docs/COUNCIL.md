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

## Citation quote verification

Council also checks specific code quotes beside `path:line` citations against
the cited files and reviewed diff. A seat whose checked quotes are fabricated
receives `invalid-ungrounded` and cannot count toward approval. An attributed
quote that fails verification also rejects the seat, even if other quotes match.

The verifier recognizes inline code, fenced blocks and blockquotes. It checks
removed and added lines from attached diff context and `git diff` against
`OCTOPUS_COUNCIL_DIFF_BASE`, which defaults to `HEAD`. Repository textconv,
external diff drivers and fsmonitor commands are disabled. Quotes of proposed
code, shell commands, unattributed prose, unreadable files or unresolved paths
are unverifiable rather than fabricated. Ordinary sentence punctuation does not
make inline prose a code quote. Plain-text spans explicitly attributed to source
still undergo verification. A truncated diff sets `diff_truncated`;
unmatched quotes remain unverifiable because the omitted suffix may contain
their evidence. Git diff capture stops after 8 MiB plus one truncation byte,
terminates and reaps an oversized producer, and retains a ten-second deadline.
Distinct citations share a sorted path suffix index instead of scanning every
indexed file for each missing path. `quotes_omitted` reports units beyond the
256-unit scan limit.
A multi-line quote can verify as a whole or when two thirds of its specific
lines match. These checks cannot establish that a provider read the source.

Counts appear in each seat's `grounding` object in `summary.json`. Set
`OCTOPUS_COUNCIL_QUOTE_VERIFY=0` to disable citation quote verification.

## Failed provider diagnostics

A failed council seat retains redacted diagnostics in `stderr/<seat>.log`.
Its `summary.json` record names the failure code, detail and diagnostic file.
Failed retries retain earlier attempt evidence; an accepted response removes
the diagnostic capture.

Failed synchronous provider calls also log a redacted stdout tail. This keeps
errors such as "Not logged in" visible when a CLI writes warnings to stderr
and its actual error to stdout. `OCTOPUS_SYNC_FAILURE_OUTPUT_TAIL_BYTES` sets
the tail length, with a default of 2000 bytes. Accepted values are decimal
integers from 1 through 65536 without a sign or leading zeroes. Invalid values
use the default. Redaction and credential checks run before truncation; their
failure omits provider output from the log.
