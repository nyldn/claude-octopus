# Debug feedback loop

Reproduce the user's symptom before changing production code. A nearby passing
unit test is not proof that the symptom is fixed.

1. Run the smallest command that still produces the same failure signature.
2. Record the command as an argument array, never an executable string.
3. Add temporary instrumentation only to distinguish named hypotheses. Tag it
   and remove it before completion.
4. Make one change, rerun the minimal reproduction, then rerun the original
   larger scenario.
5. Keep a stable reproduction as a regression test.

For intermittent failures, set a fixed run or time budget and record observed
frequency before and after. Use synchronization barriers in race fixtures, not
sleep timing. When the required environment is unavailable, return
`inconclusive` and name the missing evidence.

Before declaring a fix, produce a JSON record with `schema_version`, `status`,
`symptom`, `command_argv`, `failure_signature`, `runs`, `failures_before`,
`failures_after`, `seed`, `original_scenario_verified`, and
`instrumentation_removed`. This is evidence, not a replay queue. Never evaluate
commands from the record.
