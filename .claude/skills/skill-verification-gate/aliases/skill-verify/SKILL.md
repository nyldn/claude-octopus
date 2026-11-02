---
name: skill-verify
disable-model-invocation: true
description: "Use when a nontrivial change needs end-to-end verification before committing or shipping"
---

# Verification gate compatibility alias

Read `${CLAUDE_PLUGIN_ROOT}/.claude/skills/skill-verification-gate/SKILL.md`
and follow that native Claude Code workflow. If `CLAUDE_PLUGIN_ROOT` is absent,
use `${HOME}/.claude-octopus/plugin` as the plugin root. Stop if the source is
unavailable. Require fresh verification evidence before declaring completion.
