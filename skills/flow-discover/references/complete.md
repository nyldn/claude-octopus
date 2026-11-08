## Post-Discovery: State Update

After discovery completes:
1. Verify the synthesis file exists and is non-empty.
2. Present its findings to the user.
3. If project-local persistence was explicitly enabled, save the synthesis in
   `.octo/phases/phase-1-summary.md`, then update `.octo/STATE.md`:
   - status: "complete" (for this phase)
   - Add history entry: "Discover phase completed"
4. Publish the host handoff record. The helper journals the previous project
   summary and incomplete state before writing, and restores them on failure.
   After interruption, the next handoff operation recovers the transaction
   before starting, selecting or discarding research. A running or failed
   discovery blocks Define until completion or explicit discard.

```bash
# Restore the literal OCTO_ROOT and RUN_ID from the bootstrap, including on resume.
# The helper validates, presents, persists and publishes under one run lock.
HANDOFF_STATE_FILE=$("${OCTO_ROOT:?}/scripts/state-manager.sh" handoff_path) || exit 1
python3 "$OCTO_ROOT/scripts/helpers/discovery-handoff.py" publish "$HANDOFF_STATE_FILE" "${RUN_ID:?Restore the discovery run ID}" "${SYNTHESIS_FILE:?Restore the synthesis path}" || exit 1
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
