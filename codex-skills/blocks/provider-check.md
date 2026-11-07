**MANDATORY: You MUST use the Bash tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/helpers/check-providers.sh"
```

**Use the ACTUAL results below. PROHIBITED: Showing only "🔵 Claude: Available ✓" without listing all providers.**

If `OCTO_ALLOWED_PROVIDERS` is set, treat it as the source of truth for which providers may participate. Providers filtered out by that allowlist are intentionally reported as unavailable; do not invoke or recommend them in the workflow.
