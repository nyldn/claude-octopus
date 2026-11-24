### STEP 6: Synthesize In-Conversation (MANDATORY - Claude Synthesizes)

**You (Claude) synthesize the collected results directly in conversation.** This replaces the previous direct-provider synthesis call that frequently timed out.

**Use this exact structure** (structured research report format):

1. **Executive Summary** — 2-3 sentence overview answering the original question directly
2. **Key Findings** — Top 3-5 actionable insights, ranked by relevance to the original question
3. **Themes & Patterns** — Where multiple sources agree, grouped by theme
4. **Conflicts & Trade-offs** — Where sources disagree, with your reasoned resolution
5. **Gaps** — What's still unknown and needs more research
6. **Priority Matrix** — Rank findings by impact (High/Medium/Low) and effort (Low/Medium/High) in a table
7. **Recommended Approach** — Specific next steps based on findings
8. **Sources** — List each source with provider attribution and what it contributed
9. **Methodology** — Brief note on providers used, intensity level, and research approach

**Quality rules:**
- Every claim MUST cite its source provider or be explicitly marked as `[inference]`
- Write tickets, issues and requirements by their full ID (`PLAT-1931`, not `1931`) and probe results as `probe-4` (not `probe 4`). The evidence gate checks numbers classified as numeric claims unless explicitly marked `[inference]`; standalone ordinal references are not quantities
- Short but specific findings may be MORE valuable than lengthy general analysis
- Minority opinions and dissenting views MUST be preserved — they often contain critical insights
- Concrete examples (code, file paths, commands) outweigh abstract discussion
- Attribute findings to their source provider (🔴 Codex, 🧭 Antigravity, 🔵 Claude Sonnet, 🟣 Perplexity)

**Write synthesis to file:**

```bash
SYNTHESIS_FILE="${HOME}/.claude-octopus/results/probe-synthesis-${RUN_ID}.md"
mkdir -p "$(dirname "$SYNTHESIS_FILE")"
```

Write the synthesis content to `$SYNTHESIS_FILE`. The file MUST exist for the validation gate.

Before presenting the synthesis, run the mechanical evidence gate when the durable run is available:

```bash
if ! "$OCTO_RESEARCH_ROOT/scripts/orchestrate.sh" research-verify \
    "$RUN_ID" "$SYNTHESIS_FILE"; then
  echo "VALIDATION FAILED: Research evidence verification failed"
  exit 1
fi
```

If verification reports an unfetched source, retain the warning in the report; do not present that claim as independently verified.


### STEP 7: Verify, Update State & Present (Only After Steps 1-6 Complete)

**Verify synthesis file exists (probe-synthesis-*.md pattern):**

```bash
# Verify the synthesis file was written (matches probe-synthesis-*.md pattern)
if [[ ! -f "$SYNTHESIS_FILE" || ! -r "$SYNTHESIS_FILE" || ! -s "$SYNTHESIS_FILE" ]]; then
  echo "❌ VALIDATION FAILED: Synthesis must be a readable, non-empty regular file"
  exit 1
fi
echo "✅ VALIDATION PASSED: $SYNTHESIS_FILE"
```

**Update state:** Save up to three nonblank lines from Key Findings. If that
section is empty or missing, use Executive Summary or the older Summary
heading. If neither section has content, stop before updating state and
correct the synthesis.

```bash
if ! key_findings=$(awk '
    { sub(/\r$/, "") }
    /^##?[[:blank:]]/ {
        section = ""
        if ($0 ~ /^##[[:blank:]]+Key Findings[[:blank:]]*$/) section = "findings"
        if ($0 ~ /^##[[:blank:]]+(Executive Summary|Summary)[[:blank:]]*$/) section = "summary"
        next
    }
    /^###+[[:blank:]]/ { next }
    section != "" && NF && counts[section] < 3 {
        snippets[section] = snippets[section] (counts[section] ? " " : "") $0
        counts[section]++
    }
    END { print counts["findings"] ? snippets["findings"] : snippets["summary"] }
' < "$SYNTHESIS_FILE"); then
  echo "VALIDATION FAILED: Could not read synthesis context" >&2
  exit 1
fi
if [[ -z "$key_findings" ]]; then
  echo "VALIDATION FAILED: Synthesis needs a non-empty Key Findings or Summary section" >&2
  exit 1
fi

"${OCTO_ROOT:?}/scripts/state-manager.sh" update_context "discover" "$key_findings" || exit 1
# Track actual providers used (dynamic — from fleet output, not hardcoded)
for _provider in $(echo "$FLEET_OUTPUT" | cut -d'|' -f1 | sort -u); do
  "${OCTO_ROOT:?}/scripts/state-manager.sh" update_metrics "provider" "$_provider" || exit 1
done
"${OCTO_ROOT:?}/scripts/state-manager.sh" update_metrics "phases_completed" "1" || exit 1
```

If any state operation fails, stop before presenting results, publishing the
handoff or marking the task complete. Preserve earlier successful writes for
inspection. On recovery, resume at the failed operation with the same synthesis
and provider list. Do not repeat successful provider counts or the completed-phase
increment. Do not rerun the entire state block after a partial success.

**Present results** formatted according to context (Dev vs Knowledge):

**For Dev Context:**
- Technical research summary
- Recommended implementation approach
- Library/tool comparison (if applicable)
- Perspectives from all providers
- Next steps

**For Knowledge Context:**
- Strategic research summary
- Recommended approach with business rationale
- Framework analysis (if applicable)
- Perspectives from all providers
- Next steps

**Include attribution:**
```
*Multi-AI Research powered by Claude Octopus*
*Providers: available external providers + 🔵 Claude*
*Full synthesis: $SYNTHESIS_FILE*
```
