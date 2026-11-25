# Model catalog review, November 24, 2026

This update addresses the five public entries left unresolved by the weekly
catalog review. It changes shipped defaults and fresh configurations, preserves
existing user pins, and does not install or release the plugin. Resolver cache
keys carry a new revision so pre-upgrade cached defaults cannot restore the
retired choices.

## Decisions

| Entry | Decision | Reason |
|---|---|---|
| OpenRouter `anthropic/claude-sonnet-4` | Replace the bare default and standard task selectors with `anthropic/claude-sonnet-4.6` | Sonnet 4 is absent from the public listing. Sonnet 4.6 supports the existing Chat Completions path and retains the $3/$15 base token price. Explicit saved routes are unchanged. |
| `opencode/deepseek-v4-flash-free` | Replace with `opencode/deepseek-v4.1-flash-free` | The current public free route replaces the retired V4 Flash generation. Default and fast work stay free. Availability is limited-time. No paid fallback is added. |
| `opencode/glm-5.1` | Replace with `opencode/glm-5.3` | OpenCode deprecated GLM 5.1 on November 19. GLM 5.3 is a paid research route, now priced explicitly rather than reported as zero-cost. |
| `opencode/gpt-5.4` | Keep; correct context, reasoning and pricing metadata | The public listing confirms availability, a 1,050,000-token context and reasoning support. |
| `opencode/gpt-5.4-mini` | Keep; confirm limits and correct the zero-cost tariff | The public listing confirms availability, a 400,000-token context and reasoning support. |

## OpenCode limits and estimated prices

The public [OpenCode model list](https://opencode.ai/inference/v1/models)
returned these values on November 24. The selected response fields are recorded
in [the test fixture](../tests/fixtures/model-catalog-20261124.json).

| OpenCode ID | Context tokens | Maximum output tokens | Input/output USD per million tokens |
|---|---:|---:|---:|
| `deepseek-v4.1-flash-free` | 200,000 | 32,000 | $0 / $0 |
| `glm-5.3` | 1,000,000 | 131,072 | $0.56 / $1.76 |
| `gpt-5.4` | 1,050,000 | 128,000 | $2.50 / $15 |
| `gpt-5.4-mini` | 400,000 | 128,000 | $0.75 / $4.50 |

GLM 5.3's listed price includes a current 60% discount and can change. GPT-5.4
requests above 272,000 input tokens use $5/$22.50 for the whole request.
OpenCode also lists input caps of 922,000 for GPT-5.4 and 272,000 for Mini.
The plugin's seven-field catalog records context size. OpenCode owns input and
output enforcement; the full limits remain in the evidence fixture.

These are uncached token estimates. Cache discounts, service tiers, credit
purchase fees and account restrictions can change actual billing. The free
route remains priced at zero; OpenCode research and explicit GPT routes do not.

## Sources and verification boundary

- [OpenCode model documentation](https://opencode.ai/docs/console/models/)
  lists current IDs, prices, free-access terms and deprecation dates.
- [OpenCode model-list API contract](https://opencode.ai/docs/console/api/models/)
  defines the public listing's limits, capabilities and cost fields.
- [OpenRouter public model list](https://openrouter.ai/api/v1/models)
  lists Sonnet 4.6 with a 1,000,000-token context, 128,000-token output and
  $3/$15 base pricing. Routing suffixes remain supported.

The checks use public listings and offline regression tests. No authenticated
inference, provider charge, Forge installation or successful weekly runner
receipt is claimed.
