# Monthly Agent Review

A lightweight checklist for reviewing Claude Octopus agent performance on a monthly cadence.

## Review Checklist

### 1. Provider Health
- [ ] Codex CLI responds to `codex --version`
- [ ] Gemini CLI responds to `gemini --version`
- [ ] API keys are valid and not expired
- [ ] Run `/octo:doctor` and resolve any warnings

### 2. Agent Quality
- [ ] Review recent `~/.claude-octopus/results/` outputs for accuracy
- [ ] Check consensus scores — sustained low scores may indicate prompt drift
- [ ] Verify debate outcomes are balanced (no single provider dominating)

### 3. Cost & Usage
- [ ] Review API spend across providers (OpenAI, Google, Perplexity)
- [ ] Check for runaway autonomous workflows in scheduler logs
- [ ] Validate that model routing is using cost-appropriate tiers

### 4. Security
- [ ] Run `/octo:security` on the active codebase
- [ ] Verify no API keys leaked into result files or logs
- [ ] Check that `OCTOPUS_SECURITY_V870` hardening is active

### 5. Updates
- [ ] Check for new Claude Octopus releases
- [ ] Review CHANGELOG for breaking changes before updating
- [ ] Run full test suite after updating (`scripts/test-claude-octopus.sh`)

## Frequency

Run this review monthly, or after any major version upgrade.
