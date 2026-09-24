# GPT-6 and GPT-5.6 Codex Prompting

GPT-6 Sol is Claude Octopus's default independent implementation and review
seat. GPT-6 Luna handles focused, repeatable, mechanical, and budget-sensitive
work. GPT-5.6 Sol remains available as a rollout fallback and explicit pin.
These GPT-6 models expose a 1.05M context window and 128K maximum output through
the OpenAI API, although Codex may apply a lower working context budget.

## Model choice

- `gpt-6-sol`: implementation, terminal-heavy work, edge-case review, and
  independent judgment.
- `gpt-6-luna`: focused or repeatable tasks, mechanical changes, bulk edits,
  and high-volume checks.
- `gpt-5.6-sol`: compatibility fallback when GPT-6 has not reached the user's
  Codex account, workspace, or client.

Use a current Codex CLI for GPT-6. Model visibility can differ between the
OpenAI API and Codex subscription access, and can vary by account, workspace,
rollout, and client version. Existing `OCTOPUS_CODEX_MODEL` and
`providers.json` pins override these defaults; Octopus does not rewrite them.

## Prompt shape

Give Codex:

1. the concrete outcome;
2. repository constraints and files in scope;
3. acceptance tests or observable evidence;
4. explicit non-goals;
5. the required verification and handoff.

Prefer one coherent implementation owner. Use GPT-6 Sol as a peer to Opus 5 when
it has a distinct role—usually implementation or independent review—not as a
duplicate voice. Keep permissions and destructive-action policy in the
harness; model choice does not authorize broader changes.

## Cross-model handoff

When Opus 5 plans and GPT-6 Sol implements, pass the accepted decision, affected
paths, interfaces that must not change, and exact tests. When GPT-6 Sol reviews
Opus work, ask for concrete findings with file/line evidence and omit generic
style commentary.

Sources:

- https://developers.openai.com/api/docs/models/gpt-6-sol
- https://developers.openai.com/api/docs/models/gpt-6-luna
- https://developers.openai.com/codex/models
