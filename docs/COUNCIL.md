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
Direct citation lead-ins include `reads`, `defines` and `declares`, including
the base and past forms of `define` and `declare`. Proposal lead-ins still mark
the following quote as a suggestion rather than current source.

The verifier recognizes inline code, backtick or tilde fenced blocks and
blockquotes. Marker lines with malformed info strings also open a quote block,
matching verdict parsing. Backticks in an info string cannot hide source quotes.
Closing fences must use the opening marker and at least its width;
an unterminated fence extends to the end of the response. Whole-line
inline backticks inside blockquotes are formatting; backticks within source
expressions remain literal. A blockquote counts as one quote unit, including
any inline spans inside it. It checks
removed and added lines from attached diff context and `git diff` against
`OCTOPUS_COUNCIL_DIFF_BASE`, which defaults to `HEAD`. Repository textconv,
external diff drivers, clean/process filters and fsmonitor commands are disabled.
Filter driver names are read within a 64 KiB budget and overridden for the
diff, including drivers selected by `.git/info/attributes` or a configured
attributes file. Failed or oversized configuration lookup, or a driver name
containing `=`, leaves the diff unavailable. Quotes of proposed
code, shell commands, unattributed prose, unreadable files or unresolved paths
are unverifiable rather than fabricated. A proposal lead-in can precede its
quote across blank lines; another nonempty line ends that local context.
Ordinary sentence punctuation and
dotted names within prose do not make it a code quote. Plain-text spans explicitly
attributed to source still undergo verification. A truncated diff sets
`diff_truncated`; a failed or timed-out Git diff sets `diff_unavailable`.
Unmatched quotes remain unverifiable when diff evidence is incomplete. A plain
evidence directory without a Git worktree has no default diff to check.
Git diff capture stops after 8 MiB plus one truncation byte,
terminates and reaps an oversized producer, and retains a ten-second deadline.
Distinct citations share a sorted path suffix index instead of scanning every
indexed file for each missing path. Directory entries stream within a 50,000-entry
budget. Suffix inference stays unresolved when the index reaches its entry or
depth limit, or a directory cannot be scanned. Direct paths and attached context
files still resolve independently. Only units with specific, checkable variants
bound to a resolving citation consume the 256-unit matching limit. Short inline
identifiers, distant uncited spans and unresolved citations do not count.
`quotes_omitted` reports checkable units beyond that limit.
Any omitted units cause `invalid-ungrounded`, even if
earlier quotes verify. Responses above 1 MiB set `response_oversized` and also
receive `invalid-ungrounded`. Neither limit labels unchecked quotes fabricated.
A crashed or timed-out verifier sets `verification_failed` and rejects the seat
without labeling its quotes fabricated. The whole verifier runs under a fixed
15-second portable process-group budget, including parsing and evidence reads.
Missing supervision also fails closed. Malformed grounding reports reject
the seat. Partial output from a failed verifier is discarded. Without Python,
the prior prose fallback remains available and does not validate evidence.
A multi-line quote can verify as a whole or when two thirds of its specific
lines match, including matches against either side of the diff. Removed-only diff fences undergo the same fabrication checks.
A match in any cited file or the reviewed diff verifies a quote; exact file
attribution is not proven. These checks cannot establish that a provider read
the source.

Preliminary checks may share a cached report. Contribution records always run
verification again, including when cited files, attached context contents or a
resolved diff change without a configuration change. Advice and chair fallback
admit only valid contributions before updating response counts, chair presence or
provider and model-family votes. Votes use the contribution's serialized verdict;
a rejected or unavailable record cannot contribute to quorum. Verification and
evidence digest collection use separate reads, so the record is not an atomic snapshot.
Keep review evidence unchanged while council validates and records responses.

Rejected dispatched chair fallbacks retain their contribution record, grounding
report and response while trying the next fallback. They cannot establish chair
presence or increase response counts. Failed-attempt diagnostics remain available
for rejected fallbacks, including when the last retry exits zero.

Evidence-rejected advice seats retain `blind` status and remain in
`quorum.blind_seats`, but their warning reports a grounding verification failure.
Inspect `seats[].contribution.grounding` and the response for verifier failures,
verification limits or unverified source quotes. Provider mode/model and file-read
guidance applies to other blind seats.

For a committed change, set `OCTOPUS_COUNCIL_DIFF_BASE` to the reviewed base
in the runner environment, or attach the reviewed diff with `--context-file`.
The default `HEAD` covers uncommitted working-tree changes. Council accepts
general review tasks, so it cannot infer a committed review's base from the task
text. For example, attach a diff produced against the intended base:

```bash
git diff --no-ext-diff --no-textconv origin/main -- > /tmp/reviewed.diff
```

```text
/octo:council --goal review --context-file /tmp/reviewed.diff "Review the attached change"
```

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
use the default. Disallowed control bytes are removed before redaction, preserving
tabs, carriage returns and newlines. Redaction and credential checks run before
truncation; their failure omits provider output from the log. The same checks protect stderr
diagnostics. The logger preserves literal backslashes in messages after
certification, so provider text cannot introduce control bytes through escape
interpretation.
