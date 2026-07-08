# Goals — Claude Octopus

version: 4

## Mission

Orchestrate up to eight AI models on every task so blind spots surface before you ship — not after.

## North Stars

- A new user goes from install to first multi-LLM workflow in under 5 minutes
- A 75% consensus gate catches real disagreements across providers before code reaches production
- Every major workflow (Discover → Define → Develop → Deliver) completes end-to-end with at least two providers active

## Anti-Stars

- Single-model blind spots slip through undetected
- Provider failures degrade silently instead of loudly
- Gates that validate code metrics but not user-observable outcomes

## Directives

| # | Title | Steer | Description |
|---|-------|-------|-------------|
| 1 | Expand provider coverage in tests | increase | Add integration tests for each supported provider CLI |
| 2 | Reduce provider failure silence | decrease | Fail loud when multi-LLM dispatch does not execute |
| 3 | Quickstart under 5 minutes | increase | Track and enforce onboarding time gate |

## Gates

| ID | Check | Weight | Description |
|----|-------|--------|-------------|
| tests-passing | make test | 9 | Full test suite passes |
| scripts-executable | bash -n scripts/orchestrate.sh | 7 | Orchestration scripts are valid shell |
| preflight-passes | timeout 10 bash scripts/helpers/preflight.sh --exit-code | 6 | Provider health check passes (Claude always available) |
| package-valid | node -e "require('./package.json')" | 5 | package.json is parseable |
| providers-documented | grep -q "Codex\|Antigravity\|Copilot" README.md | 4 | Core providers documented in README |
