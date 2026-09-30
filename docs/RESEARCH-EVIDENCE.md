# Evidence-backed research

Claude Octopus research keeps a small, local run record so a long discovery
session can be inspected or resumed without repeating provider calls.

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
