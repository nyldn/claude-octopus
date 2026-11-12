# Evidence-backed research

Claude Octopus research keeps a small, local run record so a long discovery
session can be inspected or resumed without repeating provider calls.

## Optional web search suggestions

Set `OCTOPUS_RESEARCH_WEB_SEARCH=keenable` to run one search for the research
question before `probe_discover` dispatches its perspectives. When a provider
allowlist is active, it must include `keenable` as well as the model providers.
This source adds no seat and works at quick, standard and deep intensity.
Default runs, dry runs, cache hits and resumed runs perform no lookup.

Each perspective receives up to five titles, URLs and 500-character excerpts,
wrapped as untrusted content. These are leads for the existing evidence pipeline,
not verified claims. Seats must inspect and cite the linked pages. Existing
source-fetch restrictions and citation verification still apply. Failed, empty,
oversized or malformed searches leave the original prompts unchanged. One lookup
has a 15-second deadline and does not retry or follow redirects. Interpreters
without the signal alarm APIs skip the optional lookup so the total deadline
is preserved. Failed or empty lookups emit one fixed warning without provider
output or credentials, then research continues with its original prompts.

Python 3's standard library handles the request; no SDK or CLI installation is
needed. The question is sent to Keenable only when this option and the allowlist
permit it. With no key, the helper uses `/v1/search/public` and identifies Claude
Octopus with `X-Keenable-Title`. An optional `KEENABLE_API_KEY` selects `/v1/search`
with `X-API-Key`; it is excluded from model-child environments, subscription
tier probes and prompts.
The helper normalizes title and snippet whitespace and bounds their lengths.
The resulting formatted suggestions are preserved literally inside their
untrusted boundaries; they are not exact quotations of the source fields.
Keyless limits are shared by egress IP. Authenticated usage follows the account's
credits and rate limits.
No live search or model request is required by the offline tests.

HTTP contract checked on 2026-11-08 against the official
[search reference](https://docs.keenable.ai/api-reference/search),
[quickstart](https://docs.keenable.ai/) and
[authentication documentation](https://docs.keenable.ai/authentication).

## Choose the depth

Research uses one of three intensity levels:

| Intensity | Use it for | External fetch budget |
| --- | --- | ---: |
| quick | A fast orientation or a small decision | 0 |
| standard | Normal multi-provider discovery | 8 |
| deep | High-stakes research and current web evidence | 20 |

The default is standard. Select it from a command:

    "$HOME/.claude-octopus/plugin/scripts/orchestrate.sh" discover \
      --intensity deep "Compare current approaches to signed webhooks"

The `--breadth light|standard|exhaustive` values are aliases for `quick`,
`standard`, and `deep`.

## What is saved

Each run has a stable ID and a local directory containing:

- manifest.json — question, intensity, stage, limits, the original provider-results location, and the workspace root that local citations resolve against
- events.jsonl — append-only lifecycle events
- sources.jsonl — deduplicated URLs, provider artifact, retrieval status, and independence key
- snapshots/ — bounded fetched bodies used for mechanical checks
- claims.jsonl — claims, cited source IDs, and cited workspace files found in the synthesis
- verification.json — citation, quote, number, and independence checks

These files stay local. Provider credentials and raw prompts are not sent to fetched sites.

## Resume and verify

If a provider or synthesis step is interrupted, resume the saved run:

    "$HOME/.claude-octopus/plugin/scripts/orchestrate.sh" research-resume <run-id>

When a host-native workflow writes its synthesis in conversation, verify that file before presenting it as a completed research result:

    "$HOME/.claude-octopus/plugin/scripts/orchestrate.sh" research-verify \
      <run-id> /absolute/path/to/synthesis.md

The verifier fails closed for unknown source IDs, unsupported consensus claims, and quoted or numeric claims that disagree with a fetched snapshot. Claims whose source was not fetched are retained with an explicit warning instead of being silently presented as verified.

Digits that belong to an identifier are not numeric claims: a ticket or requirement ID such as `PLAT-1181`, `T-1` or `R2`, a reference such as `#1728` or `§4.2`, a name such as `p95` or `k8s`, and a git SHA such as `89a941fda`. Standalone numbers, percentages, decimals, numbers with a unit suffix such as `15m` or `5xx`, and ranges such as `10-13` are still checked.

A reference to the synthesis's own numbered points is not a numeric claim either: a whole number after `point`, `points`, `item` or `items`, as in `See point 2.`, `Corrected in point 2:` or `points 2 and 3`, `points 2,3` or `points: 2 and 3`, when no other word follows the number. Labels must stand alone, including Markdown list items, or use an explicit reference such as `See` or `Corrected in`. Paired inline emphasis around reference numbers and labels is accepted, including `See point **2**` and `**Points:** 2 and 3`. Explicit references also include `Refer to point 2`. A label after "and" or "or" continues a reference only when the number before the conjunction was itself a skipped reference or a section number, so both numbers in `Score in points: 50 and items: 10` remain checked. Prose quantities such as `The mean score in points: 50` and `Total items 30` remain checked, as do emphasized quantities with units. Formatted units such as `5 **MiB**` and `5 (MiB)`, degree units such as `5 °C`, linked units such as `5 [MiB](https://example.com)`, decimals, spaced or unspaced range endpoints using hyphens, en dashes, em dashes or Unicode minus signs, fraction numerators such as the 5 in `Items: 5/10` and thousands-formatted values remain numeric claims. Ordinary and narrow nonbreaking spaces are accepted around units and in reference lists. `2 retries`, `point 40 requests`, `16 MiB` and `section 2` are still checked.

Emphasis markers inside inline code or link destinations remain literal.
Relative, fragment and reference-style linked units still require numeric
evidence. Nested emphasis around an ordered-list label does not turn that label
into a numeric claim.

The same reference rules apply to standalone `Finding`, `Risk`, `Probe`,
`Conflict`, `Decision` and `Gap` labels and their plurals. `(Finding 4)` and
`See conflicts 1 & 2` refer to sections. `Risk 3 of the services` still states
a quantity that needs evidence.

In totals, numbers written separately are checked individually.
`Findings: 3 or 4 in total`, `Findings: 3 or 4, in total` and
`Findings: 3, 4 in total` each keep `3` and `4` for evidence checks.
Without a space, `3,4` is one numeric token. Write `3, 4` to check them
separately. Thresholds such as `Risk 3 or higher` and `Risk 3 & above`
also remain numeric claims.

When a probe synthesis fails verification, its synthesizer gets one repair
pass with the findings, evidence catalog and numbered draft. Missing citations,
unresolved workspace paths, unknown source IDs, unsupported consensus, number
mismatches and quote mismatches qualify for repair. Cache and normalization
failures do not. The corrected draft must pass verification before publication.
A failed repair blocks publication, and the run does not ask for another.

A repair may return the draft inside one complete Markdown code fence. The
repair step removes that wrapper and echoed line numbers before verification.
It rejects empty text and an unmatched opening fence. Separate code blocks keep
their fences so the verifier still checks claims between them.

When every synthesizer fails, the run writes a compact fallback with source
counts and the original question. It does not cache that fallback or request a
repair, so a later retry can produce a new synthesis.

## Workspace citations

Research about the codebase itself cites files, not web pages. A claim may cite a file in the workspace as a workspace-relative path with line numbers: `src/app.ts:42`, `src/app.ts:40-48`, or `src/app.ts:12,40`. An absolute path inside the workspace also works. The workspace root is the directory the providers read (`PROJECT_ROOT`), recorded in the manifest when the run starts, so a later `research-verify` or `research-resume` resolves the same files from any directory.

A workspace citation counts as evidence only when the file exists inside the workspace root after symlinks are resolved, is no larger than `OCTOPUS_RESEARCH_MAX_RESPONSE_BYTES` (2 MiB by default, the same cap as fetched sources), and every cited line exists. Normalized workspace files share a 16 MiB per-verification cache budget, set by `OCTOPUS_RESEARCH_MAX_LOCAL_CACHE_BYTES`; exceeding it fails verification. The file then plays the role of a snapshot: every quote and number in the claim must appear in the cited file's text, or the claim fails with `quote_mismatch` or `number_mismatch`. Each file is its own independence group. A path that does not resolve is not a citation. That includes a bare `:42`, a basename such as `app.ts:42` when the file lives in `src/`, an elided path, and a path that leaves the workspace. A `path:line` citation that does not resolve fails the claim with `unresolved_local_citation`, which names it, and its line numbers are not checked as numbers. A bare `:42` has no path to name, so its digits count as numbers in the claim: with no other citation the claim fails with `missing_citation`, and next to a valid citation they must appear in the cited file.

## Synthesis context

Synthesis reads a bounded excerpt of each provider artifact. By default the total excerpt budget follows the synthesizer's configured context budget (for example `OCTOPUS_CLAUDE_CONTEXT_BUDGET` for a Claude synthesizer), after the synthesizer role's share and the rest of the prompt. It is never less than 120000 bytes. Each artifact gets an even share of that total, never less than 24000 bytes. Set `OCTOPUS_PROBE_SYNTHESIS_CONTEXT_CHARS` or `OCTOPUS_PROBE_SYNTHESIS_FILE_CHARS` to pin either limit explicitly.

## Source and network boundaries

Research only fetches public HTTPS targets on port 443. It resolves the host before each request, rejects loopback, private, link-local, metadata, and local-only names, and re-checks every redirect. Responses are streamed through a byte cap and are never followed automatically by curl.

Set OCTOPUS_RESEARCH_FETCH=false when provider URLs should be recorded but no network fetches should occur. Set OCTOPUS_RESEARCH_FETCH_MAX to lower the fetch count for a particular run.

## Independence-aware synthesis

Two URLs are not automatically two independent sources. Identical fetched content shares one independence group; otherwise, sources are grouped by normalized host until fetched content is available. Provider-artifact identity is not itself an independence boundary. The synthesis prompt and verifier require at least two independence groups before describing evidence as corroborated or consensus.
