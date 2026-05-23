# octo:council Command Design

Status: approved design draft, revised after review
Date: 2026-05-22
Branch: `design/octo-council-command`

## Summary

Add `/octo:council` as a new multi-LLM workflow for advice, decision support, planning, and optional implementation. It should reuse Octopus' existing provider dispatch, persona library, result storage, cost controls, and implementation workflows rather than creating a separate hosted service.

The command is distinct from existing multi-LLM commands:

- `/octo:debate`: adversarial comparison and falsification.
- `/octo:multi`: power-user override that sends a task to all available providers.
- `/octo:council`: role-based expert panel that recommends a path and can hand off into implementation after explicit user approval.

## Goals

- Provide an interactive council setup similar to other Octopus commands.
- Automatically recommend a council using the existing persona library in `agents/personas/` and routing metadata in `agents/config.yaml`.
- Let users customize council size, domain, depth, debate style, and implementation permission.
- Use model/provider selection that accounts for provider availability, cost, role fit, diversity, and hallucination-resistance benchmarks.
- Produce structured council output that is immediately useful: recommendation, agreement, disagreement, risks, implementation plan, confidence, and next action.
- Allow implementation after the council result through an explicit gate, using existing Octopus implementation paths.
- Enforce per-run budget caps, quorum rules, provider diversity, and veto handling so council runs fail predictably.

## Non-Goals

- Do not replace `/octo:debate`; council may invoke debate gates but should remain advice/action oriented.
- Do not vendor a large external council framework into Octopus for the first version.
- Do not require hosted infrastructure, MCP Tunnels, Managed Agents, or a remote job service.
- Do not silently implement changes after council synthesis. Implementation requires explicit two-step confirmation.

## Existing Assets To Reuse

- `agents/personas/*.md`: 32 curated personas including architects, researchers, implementers, reviewers, product/business specialists, security, docs, UX, and deployment roles.
- `agents/config.yaml`: persona-to-CLI/model routing, phase defaults, capability tags, permission modes, and worktree isolation hints.
- `scripts/lib/debate.sh`: existing adversarial debate mechanics and synthesis style.
- `scripts/lib/agent-sync.sh`: provider dispatch, persona injection, timeout handling, and provider error behavior.
- `scripts/lib/personas.sh`: user and project persona-pack overrides.
- `scripts/lib/cost.sh`: cost awareness and confirmation patterns.
- `~/.claude-octopus/results`: existing result artifact pattern.

## OSS Research

The first version should borrow implementation patterns, not code-heavy dependencies.

| Project | License finding | Pattern to borrow |
| --- | --- | --- |
| `amiable-dev/llm-council` / `llm-council-core` | MIT | Three-stage flow: independent answers, anonymized peer review/ranking, chairman synthesis. Also useful: Borda-style ranking, fallback synthesis, MCP/HTTP/library separation. |
| `sherifkozman/the-llm-council` | MIT | Persona/subagent modes, schema-shaped outputs, artifact storage, planner/critic/researcher/implementer/reviewer/red-team role taxonomy. |
| `MakiDevelop/agent-council-cli` | MIT | Local CLI wrapper around Claude/Codex/Gemini, custom agent config, JSONL audit trail, read-only worker directive. |
| `JZtt-kyle/making-debate` | MIT | Propose, critique, revise, synthesize, ratify/veto debate loop. |
| `karpathy/llm-council` | No license file found in temp clone | Concept only: council pattern and peer-ranking idea. Do not copy code. |
| `valorisa/llm-council-skill` | No license file found in temp clone | Concept only: compact five-advisor skill shape. Do not copy code. |

## Benchmark-Aware Model Selection

`/octo:council` should account for Peter Gostev's BullshitBench v2, but treat it as one routing signal rather than the sole ranking source.

BullshitBench measures whether models challenge nonsensical prompts instead of accepting broken premises. That is especially relevant for council roles that must resist flawed assumptions:

- chair / synthesizer
- skeptic / critic
- security auditor
- legal / compliance reviewer
- finance / medical / high-stakes domain advisors
- final verifier before implementation

It is less decisive for implementation roles, where code ability, local tool compatibility, and repo-context handling matter more.

Current source snapshot checked on 2026-05-23:

- BullshitBench v2 has 100 prompts across software, finance, legal, medical, and physics.
- It uses 13 nonsense techniques and a 3-judge aggregation panel.
- The published v2 leaderboard includes 158 model/reasoning rows in the normalized checked-in snapshot.
- The data manifest was generated at `2026-05-19T23:13:46Z`.
- The current top rows in `leaderboard_with_launch.csv` include:
  - `anthropic/claude-sonnet-4.6@reasoning=high`: 91% clear pushback, 3% accepted nonsense.
  - `anthropic/claude-sonnet-4.6@reasoning=none`: 89% clear pushback, 2% accepted nonsense.
  - `anthropic/claude-opus-4.5@reasoning=high`: 90% clear pushback, 2% accepted nonsense.
  - `anthropic/claude-opus-4.6@reasoning=high`: 87% clear pushback, 3% accepted nonsense.
  - `qwen/qwen3.5-397b-a17b@reasoning=high`: 78% clear pushback, 5% accepted nonsense.

Routing must not hardcode these exact models forever. Add a checked-in benchmark snapshot and refresh script:

- `data/benchmarks/bullshitbench-v2-leaderboard.csv`
- `data/benchmarks/bullshitbench-v2-manifest.json`
- `scripts/refresh-benchmarks.sh`

The refresh script should pull the latest raw GitHub CSV/manifest, validate the expected columns, update the snapshot date, and produce a diff that can be reviewed in git. Runtime council execution should use the checked-in snapshot by default so normal runs do not depend on network access.

Proposed scoring formula:

```text
model_score = Σ(weight_i * normalized_signal_i) - penalty

where every normalized_signal_i is in [0, 1] and each role weight vector sums to 1.0.

Signals:
- role_fit: match between council role and model/provider capability.
- provider_available: local CLI/API/auth availability and current circuit-breaker status.
- provider_diversity: marginal value of adding this provider organization to the council.
- cost_budget: fit with the selected depth and remaining `--max-cost`.
- benchmark_resistance: BullshitBench clear-pushback rate adjusted for accepted-nonsense rate.
- user_preference: explicit user/provider/model preferences.
- penalty: stale metadata, unknown model mapping, or known provider instability.
```

Benchmark weight by role:

| Role family | role_fit | availability | diversity | cost | benchmark | preference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| chair, skeptic, verifier, red-team, security, legal, finance, medical | 0.20 | 0.15 | 0.15 | 0.10 | 0.30 | 0.10 |
| strategy, product, architecture, research | 0.30 | 0.15 | 0.20 | 0.10 | 0.15 | 0.10 |
| implementation, test writing, docs, UI | 0.35 | 0.20 | 0.15 | 0.15 | 0.05 | 0.10 |

Benchmark freshness:

- 0-30 days since snapshot generation: full benchmark signal.
- 31-90 days: linearly decay benchmark signal to zero.
- More than 90 days: benchmark signal is zero and `/octo:council` warns that benchmark routing is stale.
- Unknown model mapping: benchmark signal is zero, with a small `0.05` unknown-metadata penalty unless the user explicitly selected that model.

Provider diversity still matters. A council of only top-ranked Anthropic rows may be safer against nonsense, but it loses the multi-provider disagreement that makes Octopus valuable. If available, the council should prefer at least two provider organizations for standard/deep runs.

### Council Selection Algorithm

1. Classify the task into goal, domain, style, depth, and implementation permission.
2. Build persona candidates from `agents/config.yaml`, `agents/personas/`, and active persona packs.
3. Remove near-duplicate personas before filling seats:
   - compute overlap from role family, phases, expertise, and capabilities;
   - use `OCTOPUS_COUNCIL_DEDUP_THRESHOLD`, default `0.65`, as a tunable config constant rather than a claimed universal threshold;
   - if Jaccard overlap is greater than the configured threshold, keep the higher-scoring candidate unless the user explicitly selected both with `--persona` or the interactive selector.
   - persona packs being installed is not explicit user selection; pack-provided overlaps are still deduped.
4. Score every eligible persona/provider/model tuple using the weighted normalized formula.
5. Fill required seats: chair, domain advisors, skeptic/red-team, implementer if implementation is allowed, verifier if implementation is allowed.
6. Enforce diversity for standard/deep runs:
   - require at least two provider organizations when available;
   - if top-N seats violate this, replace the lowest-scoring non-chair duplicate-provider seat with the highest-scoring candidate from a missing provider organization;
   - do not replace the chair unless no synthesis-capable model is available.
7. If diversity cannot be satisfied, continue with a visible warning and record the reason in `summary.json`.

Synthesis-capable means the persona/provider/model tuple can produce a final integrative recommendation, not just a narrow critique. In v1 this is configured through `agents/config.yaml` capability tags:

```yaml
agents:
  strategy-analyst:
    capabilities: [strategy, synthesis, decision-support]
```

The default synthesis-capable personas are `strategy-analyst`, `research-synthesizer`, `code-reviewer`, `exec-communicator`, and `business-analyst`. Existing capability terms that imply synthesis also qualify: `workshop-synthesis`, `executive-communication`, `stakeholder-analysis`, `architecture-review`, and `requirements`. The selected provider model must support structured output, the target context window, and the run's read-only or implementation permission mode. If no configured tuple satisfies this, preflight aborts for standard/deep runs and asks the user to select a chair manually.

## User Experience

`/octo:council <task>` starts with an interactive setup unless flags make the configuration explicit.

Recommended questions:

1. **Goal**
   - Advice only
   - Decision / go-no-go
   - Implementation plan
   - Implement after approval
   - Review an existing plan/code

2. **Domain**
   - Auto-recommend
   - Architecture / engineering
   - Product / UX
   - Security / compliance
   - Business / finance
   - Research / synthesis
   - Documentation / communication

3. **Council Style**
   - Balanced advisory
   - Adversarial
   - Implementation-focused
   - Executive readout
   - Red-team first

4. **Depth / Budget**
   - Quick: default 3 council members, one round
   - Standard: default 4-5 members, critique and synthesis
   - Deep: default 5-7 members, critique, revision, ratify/veto

5. **Implementation Permission**
   - Advise only
   - Write plan after synthesis
   - Implement only after explicit approval
   - Implement after approval using isolated worktrees

6. **Budget Cap**
   - Use default cap for selected depth
   - Enter custom cap
   - Dry run only

After answers, Octopus shows the recommended council and asks the user to accept or adjust it.

Example recommendation:

```text
Recommended Council

Chair: strategy-analyst via Claude Sonnet/Opus
Architect: backend-architect via Codex
Skeptic: security-auditor via Claude/Gemini
Implementer: typescript-pro via Codex
Verifier: code-reviewer via Codex Spark or Claude

Rationale:
- Architecture + implementation task detected.
- Security risk present because auth/data-flow keywords were found.
- Chair/skeptic models prefer high BullshitBench resistance.
- Council keeps at least two provider families for disagreement.
```

## Council Flow

### Phase 0: Preflight

- Detect providers and configured model availability.
- Load `agents/config.yaml`.
- Load user/project persona packs.
- Load checked-in benchmark metadata if `--benchmark auto|on` permits it.
- Estimate cost/depth and show the user before provider fanout.
- Enforce `--max-cost` before dispatch and before each additional phase.
- If `--dry-run` is set, stop after showing council selection, diversity decisions, benchmark freshness, quorum requirements, and cost estimate.

Benchmark flag behavior:

- `--benchmark auto`: use checked-in metadata when it is 90 days old or newer; warn and disable when older.
- `--benchmark on`: require fresh enough metadata; abort if missing, invalid, or older than 90 days.
- `--benchmark off`: ignore benchmark signal and do not warn about staleness.

Budget defaults:

- quick: `--max-cost 0.50`
- standard: `--max-cost 2.00`
- deep: `--max-cost 5.00`

The cap is an estimated hard ceiling. If projected remaining cost would exceed the cap before a phase starts, abort before dispatching that phase and write a partial artifact. Provider APIs and CLIs do not all expose exact live costs, so estimates must be conservative.

Cost estimation uses existing `scripts/lib/cost.sh` pricing and token estimation as the source of truth:

```text
estimated_tokens = ceil((prompt_chars / 4) * 1.25)
# /4 is the chars-per-token heuristic; *1.25 is the safety margin.
input_tokens = estimated_tokens from prompt
output_tokens = input_tokens * role_depth_output_multiplier
estimated_call_cost = (input_tokens / 1_000_000 * provider_input_usd_per_mtok)
                    + (output_tokens / 1_000_000 * provider_output_usd_per_mtok)
estimated_phase_cost = Σ(estimated_call_cost for selected members in the phase)
projected_remaining_cost = actual_recorded_cost_so_far + Σ(remaining estimated_phase_cost)
```

Output token defaults are role/depth based: quick advice `0.75x` input tokens, standard advice/critique `1.0x`, deep revision/synthesis `1.5x`, implementation planning `2.0x`. Unknown provider pricing uses the conservative highest configured per-MTok rate unless the provider is explicitly marked subscription/included. `--max-cost` is a USD decimal float only; reject currency symbols or non-USD input such as `EUR 2.00` with exit code `2` and a usage hint.

### Phase 1: Independent Advice

Each selected persona receives the task independently with:

- task context
- role-specific persona content
- goal/domain/style/depth config
- enforced read-only execution unless the selected goal requires file access
- response schema: recommendation, assumptions, risks, implementation notes, confidence

Read-only enforcement is not instruction-only. For Codex-backed agents, council advice and decision phases must dispatch with `OCTOPUS_CODEX_SANDBOX=read-only`. For configured persona routes, `permissionMode: plan` in `agents/config.yaml` is required before a persona can be selected for advice-only seats. Provider CLIs without an enforceable read-only mode receive no file context by default; if the user explicitly includes file context, they receive delimited excerpts only and still cannot edit through council phases. Implementation access is granted only after the implementation gate and only through existing `tangle`/`flow-develop` machinery.

Quorum:

- quick requires at least one non-chair member response plus a synthesis-capable chair.
- standard/deep require at least two non-chair member responses plus a synthesis-capable chair.
- if chair fails, use the highest-scoring available synthesis-capable fallback once.
- if quorum is lost, abort synthesis by default and present partial outputs; allow the user to request a partial synthesis explicitly.

Retry policy:

- retry transient provider failures once with short backoff if no usable output was returned;
- do not retry deterministic validation failures, missing binaries, missing credentials, or oversize prompt rejections;
- follow existing `agent-sync.sh` skip-not-fail behavior for oversize provider rejections and record skipped providers in `summary.json`.

### Phase 2: Cross-Critique

For standard/deep runs:

- semi-anonymize council responses
- ask each council member to critique gaps, assumptions, and risks
- require `PASS` if there is nothing new to add
- preserve dissent rather than forcing consensus

V1 uses semi-anonymized review: critique prompts show role labels but hide model and provider names. True anonymization is deferred because personas are central to council quality.

`PASS` parsing is case-insensitive after trimming leading/trailing whitespace and final punctuation. Accepted forms include `PASS`, `Pass`, `pass.`, and `PASS - nothing to add`. Longer responses that include substantive content are treated as critiques, not passes.

### Phase 3: Revision

For deep runs or high disagreement:

- re-check quorum and `--max-cost` before dispatching revision prompts;
- if revision would exceed the cap, skip revision and synthesize from existing artifacts with `status: "partial"`;
- let each member revise their position after critique
- call out changed positions explicitly

### Phase 4: Chair Synthesis

Chair produces:

- recommendation
- points of agreement
- material disagreements
- minority reports
- risk register
- implementation path
- confidence level
- conditions that would change the recommendation

### Phase 5: Ratify / Veto

For implementation-allowed runs:

- verifier/red-team gets final veto power for critical risk
- if vetoed, council returns a revised plan or asks for user decision
- if ratified, present implementation gate

Veto triggers:

- any verifier, red-team, security, legal, finance, or medical role marks a risk as `critical` in the structured risk schema;
- a verifier reports likely data loss, credential exposure, destructive command risk, legal/compliance breach, or safety issue;
- implementation plan lacks tests or rollback for a high-risk code change;
- cost estimate now exceeds `--max-cost`.

Risk schema:

```json
{
  "severity": "low|medium|high|critical",
  "confidence": 0.0,
  "reason": "string",
  "affected_area": "string"
}
```

`confidence` is advisory in v1 because model self-reporting is not comparable across providers. Prompt text defines the scale as `0.0 = speculative` and `1.0 = certain`, but the v1 veto trigger is severity-only for `critical` risks from veto-capable roles.

Veto handling:

- chair must include the veto verbatim in synthesis;
- default action is to stop implementation and propose a revised plan;
- user can override only by explicitly choosing "Override veto and proceed";
- override is logged in `summary.json` and does not bypass existing destructive-command or git safety gates.

### Phase 6: Implementation Gate

Ask the user:

- Implement recommended path
- Save implementation plan only
- Run `/octo:debate` on the disputed point using a generated debate brief
- Adjust council and rerun
- Stop

The debate brief includes the disputed point, the relevant council positions, the chair synthesis excerpt, risk register entries tied to the dispute, and artifact paths. It does not pass full raw transcripts unless the user selects deep context.

If implementation is selected, hand off to existing workflow machinery:

- `tangle` / `flow-develop` for implementation
- `ink` / `flow-deliver` for final validation
- worktree isolation for multi-file or multi-agent edits

Implementation gate granularity:

1. Gate A: user accepts the council synthesis or asks for revision.
2. Gate B: user accepts the concrete implementation plan generated from the synthesis.
3. Gate C: execution proceeds through existing Octopus implementation safety behavior. It is a one-shot authorization for the accepted plan, not per-file approval, unless existing safety hooks detect destructive/risky actions and require a separate confirmation.

The interactive option "Implement after approval using isolated worktrees" maps to `--implement after-approval --worktree on`. There is no separate implementation permission beyond the three `--implement` values; worktree behavior is an isolation setting.

## Output Contract

Primary chat output:

```markdown
## Council Recommendation

## Why This Council Was Selected

## Agreement

## Disagreement

## Risks And Unknowns

## Implementation Path

## Confidence

## Next Step
```

Artifacts:

- `~/.claude-octopus/councils/<timestamp>-<short-uuid>/config.json`
- `~/.claude-octopus/councils/<timestamp>-<short-uuid>/responses/*.md`
- `~/.claude-octopus/councils/<timestamp>-<short-uuid>/critiques/*.md`
- `~/.claude-octopus/councils/<timestamp>-<short-uuid>/synthesis.md`
- `~/.claude-octopus/councils/<timestamp>-<short-uuid>/summary.json`

`summary.json` schema:

```json
{
  "run_id": "20260522-142530-a1b2c3",
  "command": "council",
  "status": "completed|partial|aborted|implemented",
  "goal": "advice|decision|plan|implement|review",
  "domain": "auto|architecture|product|security|business|research|docs",
  "style": "balanced|adversarial|implementation|executive|red-team",
  "depth": "quick|standard|deep",
  "benchmark": {
    "mode": "auto|on|off",
    "snapshot_generated_at": "2026-05-19T23:13:46Z",
    "freshness_days": 3,
    "used": true
  },
  "budget": {
    "max_cost_usd": 2.0,
    "estimated_cost_usd": 0.84,
    "aborted_for_cost": false
  },
  "quorum": {
    "required_non_chair": 2,
    "received_non_chair": 4,
    "met": true
  },
  "council": [
    {
      "seat": "chair",
      "persona": "strategy-analyst",
      "provider": "claude",
      "model": "anthropic/claude-sonnet-4.6",
      "provider_org": "anthropic",
      "score": 0.87,
      "benchmark_signal": 0.91
    },
    {
      "seat": "skeptic",
      "persona": "security-auditor",
      "provider": "codex",
      "model": "gpt-5.3-codex",
      "provider_org": "openai",
      "score": 0.81,
      "benchmark_signal": 0.78
    }
  ],
  "veto": {
    "triggered": false,
    "severity": null,
    "confidence": null,
    "reason": null,
    "overridden": false
  },
  "artifacts": {
    "synthesis": "synthesis.md",
    "responses_dir": "responses",
    "critiques_dir": "critiques"
  },
  "implementation": {
    "permission": "never|plan-only|after-approval",
    "worktree": "auto|on|off",
    "gate_a_approved": true,
    "gate_b_approved": true,
    "handoff": {
      "workflow": "tangle|flow-develop",
      "worktree": "/Users/chris/git/claude-octopus-dev/.worktrees/council-20260522-a1b2c3",
      "started_at": "2026-05-22T14:36:10Z",
      "status": "started|completed|failed|skipped",
      "plan_artifact": "implementation-plan.md"
    }
  }
}
```

`implementation.handoff` is `null` until Gate C starts. Once implementation is handed off, it is an object with the fields shown above.

## Command And Flags

Initial command:

```text
/octo:council [task]
```

Useful flags:

```text
--goal advice|decision|plan|implement|review
--domain auto|architecture|product|security|business|research|docs
--style balanced|adversarial|implementation|executive|red-team
--depth quick|standard|deep
--members auto|3|5|7
--persona <name>[,<name>]
--implement never|after-approval|plan-only
--worktree auto|on|off
--benchmark auto|on|off
--providers auto
--providers claude,codex,gemini,opencode,openrouter
--max-cost <usd>
--dry-run
--json
--output-dir <path>
```

`--providers auto` and `--providers <comma-list>` are mutually exclusive forms of the same flag. `auto` means Octopus selects from all available configured providers after preflight.

`--members` precedence: explicit `--members 3|5|7` wins for council size; `--depth` still controls default rounds, gates, and budget. `--members auto` uses the selected depth preset (`quick` = 3, `standard` = 4-5, `deep` = 5-7). If a user sets a surprising combination such as `--depth quick --members 7`, run it as seven members with quick's one-round flow and print a warning in the recommendation summary.

`--persona <name>[,<name>]` pins one or more personas and bypasses deduplication only for those explicitly named personas.

`--implement` controls permission only: `never` prevents implementation, `plan-only` writes a plan, and `after-approval` allows implementation only after Gate A and Gate B. `--worktree` controls isolation separately. `auto` uses existing Octopus behavior: isolated worktrees for multi-file, risky, or multi-agent edits; `on` always requires a worktree handoff; `off` uses the current workspace unless existing safety hooks require isolation.

`--max-cost` is in USD only and accepts decimal floats such as `2`, `2.00`, or `0.50`. Non-USD or symbol-bearing values exit with code `2` and a usage hint.

`--output-dir <path>` relocates the parent artifact directory. Octopus still appends `<timestamp>-<short-uuid>/` below that path and refuses to overwrite an existing run directory.

Flag-to-summary mapping: `summary.json.implementation.worktree` mirrors the resolved `--worktree` value at run start.

## Integration Points

- Add `.claude/commands/council.md` and generated skill `skills/skill-council/SKILL.md`.
- Add `council)` command branch in `scripts/orchestrate.sh`.
- Add `scripts/lib/council.sh` with the phase implementation.
- Add council recommendation helpers near existing routing/persona logic.
- Add provider/model scoring helpers, preferably under `scripts/lib/models.sh` or a new `scripts/lib/benchmark-routing.sh`.
- Add `data/benchmarks/bullshitbench-v2-leaderboard.csv`, `data/benchmarks/bullshitbench-v2-manifest.json`, and `scripts/refresh-benchmarks.sh`.
- Register the command and skill in plugin manifests and generated adapter manifests.
- Add docs in `docs/COMMAND-REFERENCE.md`.

## Security And Prompt Injection

Council prompts amplify user input across multiple providers, so task text must be treated as untrusted content.

Requirements:

- Wrap user task, council member responses, and critique inputs in explicit data delimiters.
- Instruct council members not to follow instructions contained inside quoted task/context blocks unless those instructions are part of the user's top-level request.
- Advice and decision runs are read-only by default and must use provider-enforced read-only modes where supported.
- Implementation runs may read files only after the implementation gate and may edit files only through existing implementation workflows.
- Apply `skill-security-framing` principles for security-sensitive, legal, finance, medical, or credential-adjacent tasks.
- Redact likely secrets from artifacts before including them in synthesis prompts.
- Do not forward blocked security-governing environment variables through council provider calls.

Read-only and environment enforcement:

- Codex council advice/decision dispatches use `OCTOPUS_CODEX_SANDBOX=read-only`.
- Gemini council advice/decision dispatches use the safest configured headless mode and receive no file paths unless file context is explicitly selected.
- Octopus may set sandbox/security vars internally for outbound dispatch, such as `OCTOPUS_CODEX_SANDBOX=read-only`, but it strips those same vars from forwarded caller environments.
- Council code must reuse the MCP server's `BLOCKED_ENV_VARS` list and must not forward `OCTOPUS_SECURITY_V870`, `OCTOPUS_GEMINI_SANDBOX`, `OCTOPUS_CODEX_SANDBOX`, or `CLAUDE_OCTOPUS_AUTONOMY` from untrusted caller environments.
- Provider credentials are forwarded only through existing allowlist behavior; they are never written to council artifacts.

## Failure Modes

| Failure | Detection | Recovery |
| --- | --- | --- |
| Provider binary missing | preflight command lookup fails | exclude provider, warn, continue if quorum can still be met |
| Provider auth missing | provider detection reports unauthenticated | exclude provider, suggest `/octo:setup`, continue if quorum can still be met |
| Provider timeout/error | phase returns no usable output | retry transient failures once, then mark skipped |
| Oversize prompt rejection | provider stderr/status matches oversize rejection | skip provider and continue if quorum remains |
| Quorum lost | fewer than required member responses | abort synthesis by default, write partial artifacts, offer partial synthesis |
| Chair failure | synthesis provider fails | retry once with fallback synthesis-capable model |
| Benchmark metadata missing/stale | snapshot missing, invalid, or over TTL | `auto`: warn and disable; `on`: abort; `off`: ignore |
| Cost overrun | projected remaining cost exceeds cap | abort before next phase and write partial artifacts |
| Veto deadlock | verifier triggers veto and chair cannot resolve | stop implementation, offer revise/debate/user override |
| Persona overlap | recommendation selects near-duplicate personas | dedupe before seat filling unless explicitly user-selected |
| Artifact path collision | target directory exists | append short UUID/PID suffix; never overwrite existing council artifacts |

## Testing

Unit tests:

- council config parsing
- domain-to-persona recommendation
- benchmark metadata parsing
- model scoring with and without BullshitBench data
- provider diversity replacement
- persona overlap deduplication
- cost cap enforcement
- benchmark freshness decay
- quorum loss behavior
- veto trigger and override serialization
- implementation gate defaults
- `PASS` parsing
- artifact path generation
- `summary.json` schema validation

Smoke tests:

- `/octo:council --depth quick --goal advice "Should we use Redis here?"`
- `/octo:council --dry-run --goal implement "Refactor auth flow"`
- `OCTOPUS_COUNCIL_FIXTURE=critical-veto /octo:council --goal implement --depth standard "Ship this without tests"` triggers the Phase 5 veto path
- provider unavailable fallback
- benchmark disabled fallback
- no implementation without explicit approval
- cost cap abort before fanout
- council-to-`tangle` implementation handoff in a controlled fixture

`OCTOPUS_COUNCIL_FIXTURE` is test-only and ignored unless the test harness enables fixture mode.

Release validation:

- command registered in `.claude-plugin/plugin.json`
- version bumped in `package.json`, `.claude-plugin/plugin.json`, and adapter manifests that carry plugin versions
- `CHANGELOG.md` entry added under the new release version
- skill registered
- docs sync count updated
- marketplace/package validation still passes

## V1 Decisions

- BullshitBench metadata is checked in as a CSV/JSON snapshot and refreshed by `scripts/refresh-benchmarks.sh`; normal runtime does not fetch network data.
- V1 uses semi-anonymized peer review: role labels are visible, model/provider names are hidden.
- Deep-mode implementation produces and confirms a concrete plan first, then records a `tangle` handoff with worktree isolation when Gate A and Gate B are explicitly approved. It does not directly launch multiple implementation agents from the council phase.
- MCP/OpenClaw exposure is included in v1 through the existing adapter surfaces.

## Future Work

- Add true anonymized peer review as an optional mode if it improves quality without losing persona context.
- Add hosted/job-runner support only if council artifacts become useful outside Claude Code.
- Add richer benchmark blends beyond BullshitBench, such as code benchmarks for implementation seats and security benchmarks for red-team seats.

## References

- BullshitBench viewer: https://petergpt.github.io/bullshit-benchmark/viewer/index.v2.html
- BullshitBench repository and v2 scope: https://github.com/petergpt/bullshit-benchmark
- BullshitBench v2 leaderboard data snapshot source, checked 2026-05-23: https://raw.githubusercontent.com/petergpt/bullshit-benchmark/main/data/v2/latest/leaderboard_with_launch.csv
- BullshitBench v2 manifest snapshot source, checked 2026-05-23: https://raw.githubusercontent.com/petergpt/bullshit-benchmark/main/data/v2/latest/manifest.json
- LLM Council Core: https://llm-council.dev/
- amiable-dev/llm-council: https://github.com/amiable-dev/llm-council
- sherifkozman/the-llm-council: https://github.com/sherifkozman/the-llm-council
- MakiDevelop/agent-council-cli: https://github.com/MakiDevelop/agent-council-cli
- JZtt-kyle/making-debate: https://github.com/JZtt-kyle/making-debate

## Recommendation

Implement `/octo:council` natively in Octopus, borrowing the strongest patterns from MIT-licensed council projects while preserving Octopus' core advantage: local multi-provider orchestration with existing personas and implementation handoff.

For model selection, add benchmark-aware scoring as a routing input. Use BullshitBench heavily for chair/skeptic/verifier roles, moderately for advisory roles, and lightly for implementation roles. Keep provider diversity and local availability as first-class constraints.
