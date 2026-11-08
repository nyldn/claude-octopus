## Post-Discovery: State Update

After discovery completes:
1. Verify the synthesis file exists and is non-empty.
2. Present its findings to the user.
3. If project-local persistence was explicitly enabled, populate
   `.octo/PROJECT.md`, then update `.octo/STATE.md`:
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
cat "$SYNTHESIS_FILE"

# Project-local lifecycle documents are a separate, explicit opt-in.
if [[ "${OCTOPUS_PROJECT_PERSISTENCE:-false}" == "true" ]]; then
  echo "📝 Updating opt-in .octo/PROJECT.md with discovery findings..."
  if ! "${OCTO_ROOT:?}/scripts/octo-state.sh" update_project \
      --section "vision" \
      --content-file "$SYNTHESIS_FILE"; then
    echo "Discover incomplete: could not persist findings to .octo/PROJECT.md." >&2
    exit 1
  fi
  if ! "${OCTO_ROOT:?}/scripts/octo-state.sh" update_state \
      --status "complete" \
      --history "Discover phase completed"; then
    echo "Discover incomplete: could not persist completion state." >&2
    exit 1
  fi
fi
```


## Terminal State

The Discover phase is complete ONLY when the synthesis file exists and its complete findings
are presented to the user. When `OCTOPUS_PROJECT_PERSISTENCE=true`, the findings must also
be persisted in `.octo/PROJECT.md`. Then
either invoke `flow-define` (embrace workflow, or the user wants requirements next) or
stop with research delivered. Do NOT begin scoping, designing, or implementation from
here — that work belongs to later phases.

**Ready to research!** This skill is used after explicit invocation when users request research or exploration.
