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

breadth light, standard, and exhaustive are aliases for quick, standard, and deep.

## What is saved

Each run has a stable ID and a local directory containing:

- manifest.json — question, intensity, stage, limits, and the original provider-results location
- events.jsonl — append-only lifecycle events
- sources.jsonl — deduplicated URLs, provider artifact, retrieval status, and independence key
- snapshots/ — bounded fetched bodies used for mechanical checks
- claims.jsonl — claims and cited source IDs found in the synthesis
- verification.json — citation, quote, number, and independence checks

These files stay local. Provider credentials and raw prompts are not sent to fetched sites.

## Resume and verify

If a provider or synthesis step is interrupted, resume the saved run:

    "$HOME/.claude-octopus/plugin/scripts/orchestrate.sh" research-resume <run-id>

When a host-native workflow writes its synthesis in conversation, verify that file before presenting it as a completed research result:

    "$HOME/.claude-octopus/plugin/scripts/orchestrate.sh" research-verify \
      <run-id> /absolute/path/to/synthesis.md

The verifier fails closed for unknown source IDs, unsupported consensus claims, and quoted or numeric claims that disagree with a fetched snapshot. Claims whose source was not fetched are retained with an explicit warning instead of being silently presented as verified.

## Source and network boundaries

Research only fetches public HTTPS targets on port 443. It resolves the host before each request, rejects loopback, private, link-local, metadata, and local-only names, and re-checks every redirect. Responses are streamed through a byte cap and are never followed automatically by curl.

Set OCTOPUS_RESEARCH_FETCH=false when provider URLs should be recorded but no network fetches should occur. Set OCTOPUS_RESEARCH_FETCH_MAX to lower the fetch count for a particular run.

## Independence-aware synthesis

Two URLs are not automatically two independent sources. Identical fetched content shares one independence group, and citations from the same provider artifact remain one voice. The synthesis prompt and verifier require at least two independence groups before describing evidence as corroborated or consensus.
