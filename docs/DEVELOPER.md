# Claude Octopus — Developer Reference

> Moved from CLAUDE.md to save ~1,000 tokens per user session. These sections are for plugin developers and maintainers, not end users.

---

## Enforcement Best Practices (Mandatory for Workflow Skills)

Skills that invoke orchestrate.sh MUST use the **Validation Gate Pattern** to ensure proper execution.

### Required Pattern

1. **Add to frontmatter:**
   ```yaml
   execution_mode: enforced
   pre_execution_contract:
     - interactive_questions_answered
     - visual_indicators_displayed
   validation_gates:
     - orchestrate_sh_executed
     - synthesis_file_exists
   ```

2. **Add EXECUTION CONTRACT section** with:
   - Blocking steps (numbered, mandatory)
   - Explicit Bash tool calls (not just markdown examples)
   - Validation gates that verify execution
   - Clear prohibition statements (what NOT to do)

3. **Use imperative language:**
   - "You MUST execute..." / "PROHIBITED from..." / "CANNOT SKIP..."
   - NOT "You should..." / "It's recommended..." / "Consider..."

4. **Validate artifacts:**
   - Check synthesis files exist and are recent
   - Verify via filesystem checks, not assumptions
   - Fail explicitly if validation doesn't pass

See `.claude/skills/skill-deep-research/SKILL.md` for reference implementation.

### Enforcement patterns that hold under pressure

Prefer the three patterns in `skills/blocks/enforcement-patterns.md` over adding more
capitalized emphasis: one **Iron Law** per discipline, a **rationalization table**
pre-refuting the model's observed excuses, and a **terminal state** that names the
successor skill instead of offering a next-steps menu. Emphasis inflation
("MANDATORY" on every step) decays over long sessions; these do not.

---

## Skill Quality Gate (new or substantially changed skills)

Ship a skill only after it clears an eval pass. Thresholds adopted from the strongest
public skill factories (alirezarezvani SKILL_PIPELINE, obra writing-skills):

1. **Baseline first** — run 3-5 representative task prompts in a fresh session WITHOUT
   the skill; save the transcripts. A skill that cannot beat its baseline is deleted,
   not shipped.
2. **With-skill pass rate ≥ 85%** on the same prompts, and a visible improvement over
   baseline on the behaviors the skill exists to change.
3. **Description trigger test** — descriptions state ONLY triggering conditions, never a
   workflow summary (a summarized workflow becomes a shortcut the model takes instead of
   loading the skill). Test with ~10 should-trigger and ~10 should-not-trigger phrasings;
   the skill must load on the former and stay quiet on the latter.
4. **Rationalization capture** — when the skill fails in the field, record the exact
   excuse the model generated and add a row to the skill's rationalization table, then
   re-run the failing scenario.
5. **Budget** — frontmatter description under ~100 tokens; skill body under 500 lines;
   frequently auto-loaded content under 200 words.

---

## Modular Configuration (Claude Code v2.1.20+)

### Directory Structure

```
claude-octopus/
├── CLAUDE.md                    # Main instructions
├── config/
│   ├── providers/
│   │   ├── codex/CLAUDE.md     # Codex-specific
│   │   ├── gemini/CLAUDE.md    # Gemini-specific
│   │   ├── claude/CLAUDE.md    # Claude orchestrator
│   │   ├── ollama/CLAUDE.md    # Ollama local LLM
│   │   └── copilot/CLAUDE.md   # GitHub Copilot CLI
│   └── workflows/CLAUDE.md      # Double Diamond methodology
```

### Loading Modules

```bash
claude --add-dir=config/providers/codex    # Codex context
claude --add-dir=config/providers/gemini   # Gemini context
claude --add-dir=config/workflows          # Double Diamond
```

| Module | When to Load |
|--------|--------------|
| `providers/codex` | Working with Codex CLI integration |
| `providers/gemini` | Working with Gemini CLI integration |
| `providers/claude` | Understanding Claude's orchestrator role |
| `providers/ollama` | Working with Ollama local LLM |
| `providers/copilot` | Working with GitHub Copilot CLI |
| `workflows` | Learning about Double Diamond methodology |

---

## E2E Testing Infrastructure

Automated smoke testing runs on a remote VPS, checking for new releases every 2 hours.

- **Phase A (Docker):** Install → structure verify → unit tests → uninstall
- **Phase B (Native):** Live command tests with authed Claude Code, Codex, Gemini

E2E test scripts are in the private dev repo (`docs/e2e/`), not in this public plugin.

### Dynamic Fleet Dispatch

`scripts/helpers/build-fleet.sh` is the single source of truth for provider-to-perspective assignment. Enforces model family diversity (OpenAI, Google, Microsoft, Alibaba, Anthropic). Never hardcode provider names in skills.

---

## Release Validation

Run the local release validator before tagging a plugin release:

```bash
bash scripts/validate-release.sh
```

The validator checks manifest syntax, command registration, plugin validation through `claude plugin validate`, and a packaged zip smoke build. On Claude Code v2.1.128+, `--plugin-dir` can load a plugin zip archive; on v2.1.129+, `--plugin-url` can load that archive from an HTTP URL for the current session.

Runtime plugin loading is opt-in because it invokes Claude Code:

```bash
OCTOPUS_RELEASE_RUNTIME_SMOKE=1 bash scripts/validate-release.sh
```

That mode creates a temporary plugin zip, loads it with `claude --plugin-dir <zip>`, serves it locally, then loads it with `claude --plugin-url http://127.0.0.1:<port>/octo-plugin.zip`. Both calls use stream-json with hook events enabled so `init.plugin_errors` surfaces plugin load failures in the release log.

Use `OCTOPUS_RELEASE_SMOKE_MAX_BUDGET_USD` to lower or raise the Claude Code budget cap for the runtime smoke, and `OCTOPUS_RELEASE_SMOKE_PORT` if the default localhost port is busy.

## Agent lifecycle events

Octopus emits provider and dispatch telemetry to the JSONL event stream controlled by `OCTO_EVENT_LOG`. Agent spawn/completion events use the same surface:

```bash
export OCTO_EVENT_LOG=auto
```

Event names:

```text
agent.spawned
agent.completed
```

Lifecycle event attributes include `provider`, `agent_type`, `task_id`, `role`, `phase`, `pid`, `result_file`, `results_dir`, `workspace_dir`, `exit_code`, `status`, `root_session_id`, and `parent_session_id`.

External control planes that need an immediate callback instead of tailing the JSONL file can also set an optional best-effort hook:

```bash
export OCTOPUS_AGENT_LIFECYCLE_HOOK=/path/to/hook
export OCTOPUS_AGENT_LIFECYCLE_HOOK_LOG=/tmp/octopus-agent-hook.log  # optional
```

The hook is invoked as:

```bash
$OCTOPUS_AGENT_LIFECYCLE_HOOK spawned
$OCTOPUS_AGENT_LIFECYCLE_HOOK completed
```

The hook receives the same lifecycle metadata through `OCTOPUS_AGENT_*` environment variables. Hook stdout/stderr are redirected to the optional hook log or `/dev/null`; hook failures are ignored so observer outages never fail agent execution.
