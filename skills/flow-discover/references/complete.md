## Post-Discovery: State Update

After discovery completes:
1. Verify the synthesis file exists and is non-empty.
2. Present its findings to the user.
3. If project-local persistence was explicitly enabled, save the synthesis in
   `.octo/phases/phase-1-summary.md`, then update `.octo/STATE.md`:
   - status: "complete" (for this phase)
   - Add history entry: "Discover phase completed"

```bash
# The phase remains incomplete unless there is a synthesis to present.
if [[ ! -s "${SYNTHESIS_FILE:-}" ]]; then
  echo "Discover incomplete: synthesis file is missing or empty." >&2
  exit 1
fi

# Present findings before recording the phase as complete.
echo "Discovery findings:"
cat "$SYNTHESIS_FILE" || exit 1

# Project-local lifecycle documents are a separate, explicit opt-in.
if [[ "${OCTOPUS_PROJECT_PERSISTENCE:-false}" == "true" ]]; then
  echo "📝 Saving opt-in discovery phase summary..."
  # Phase summaries are read by the existing execution context loader.
  # Replace the whole summary so nested headings cannot retain old findings.
  if ! (
    SUMMARY_DIR=".octo/phases"
    SUMMARY_FILE="$SUMMARY_DIR/phase-1-summary.md"
    [[ ! -L .octo && ! -L "$SUMMARY_DIR" && ! -L "$SUMMARY_FILE" && ! -d "$SUMMARY_FILE" ]] || exit 1
    mkdir -p "$SUMMARY_DIR" || exit 1
    SUMMARY_TEMP=$(mktemp "${SUMMARY_FILE}.tmp.XXXXXX") || exit 1
    trap 'rm -f "$SUMMARY_TEMP"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    cp "$SYNTHESIS_FILE" "$SUMMARY_TEMP" || exit 1
    mv "$SUMMARY_TEMP" "$SUMMARY_FILE"
  ); then
    echo "Discover incomplete: could not persist the discovery phase summary." >&2
    exit 1
  fi
  if ! "${OCTO_ROOT:?}/scripts/octo-state.sh" update_state \
      --status "complete" \
      --history "Discover phase completed"; then
    echo "Discover incomplete: could not persist completion state." >&2
    exit 1
  fi
fi

# Publish only after presentation and all requested project persistence succeed.
HANDOFF_STATE_FILE=$("${OCTO_ROOT:?}/scripts/state-manager.sh" state_path) || exit 1
python3 "$OCTO_ROOT/scripts/helpers/discovery-handoff.py" publish "$HANDOFF_STATE_FILE" "$RUN_ID" "$SYNTHESIS_FILE" || exit 1
```


## Terminal State

The Discover phase is complete ONLY when the synthesis file exists and its complete findings
are presented to the user. When `OCTOPUS_PROJECT_PERSISTENCE=true`, the findings must also
be persisted in `.octo/phases/phase-1-summary.md`. Preserve `.octo/PROJECT.md`,
including the user's vision, requirements, constraints and decisions. Then
either invoke `flow-define` (embrace workflow, or the user wants requirements next) or
stop with research delivered. Do NOT begin scoping, designing, or implementation from
here — that work belongs to later phases.

When resuming into Define, use the full artifact recorded in the project-scoped
host state for the current discovery run. Define verifies its project, run and
content hash and rejects symlinks before dispatch. Define passes a private
snapshot of those verified bytes to the engine and removes it on exit. Starting another discovery
invalidates the previous binding, including when project persistence is off.
An old `.octo` summary or a short context preview cannot replace this binding.

**Ready to research!** This skill is used after explicit invocation when users request research or exploration.
