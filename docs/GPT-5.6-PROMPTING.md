# GPT-5.6 Codex Prompting

GPT-5.6 Sol is Claude Octopus's default independent implementation and review
seat. Terra and Luna provide balanced and budget alternatives with the same
1.05M context / 128K output envelope.

## Model choice

- `gpt-5.6-sol`: difficult implementation, terminal-heavy work, edge-case
  review, and independent frontier judgment.
- `gpt-5.6-terra`: routine coding where balanced cost and capability matter.
- `gpt-5.6-luna`: mechanical changes, bulk edits, and high-volume checks.

Codex CLI v0.144.0 or later is required. Existing `OCTOPUS_CODEX_MODEL` and
`providers.json` pins override these defaults.

## Prompt shape

Give Codex:

1. the concrete outcome;
2. repository constraints and files in scope;
3. acceptance tests or observable evidence;
4. explicit non-goals;
5. the required verification and handoff.

Prefer one coherent implementation owner. Use GPT-5.6 as a peer to Opus 5 when
it has a distinct role—usually implementation or independent review—not as a
duplicate voice. Keep permissions and destructive-action policy in the
harness; model choice does not authorize broader changes.

## Cross-model handoff

When Opus 5 plans and GPT-5.6 implements, pass the accepted decision, affected
paths, interfaces that must not change, and exact tests. When GPT-5.6 reviews
Opus work, ask for concrete findings with file/line evidence and omit generic
style commentary.

Source: https://developers.openai.com/api/docs/guides/latest-model
