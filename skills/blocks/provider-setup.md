**Check provider availability:**

```bash
command -v codex &> /dev/null && codex_status="Available ✓" || codex_status="Not installed ✗"
command -v gemini &> /dev/null && gemini_status="Available ✓" || gemini_status="Not installed ✗"
```

**Validation:**
- If BOTH Codex and Gemini unavailable -> STOP, suggest: `/octo:setup`
- If ONE unavailable -> Continue with available provider(s)
- If BOTH available -> Proceed normally