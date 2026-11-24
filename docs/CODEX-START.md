# Start using Octopus in Codex

Claude Octopus helps you research, plan, implement, and review with multiple AI
providers. Enabling the plugin makes its skills available. Invoke a skill
explicitly when you want to use it.

## Check your setup first

Select Doctor in the skill picker, or explicitly mention `$skill-doctor`:

```text
Use $skill-doctor to check my Octopus setup and report provider readiness without repairs.
```

Check which plugin version is loaded and which providers are ready. Install and
sign in to the provider CLIs, or configure API access, required by the workflow
you choose. Review proposed changes before authorizing setup or repairs.

External provider calls use your own accounts and may incur charges or consume
subscription allowances. Availability on PATH does not prove that authentication,
a particular model, or a paid entitlement works. Agree on the task scope and
provider use before dispatch. Keep credentials out of prompts and reports.

## Choose a task

The plugin listing includes starter prompts for common workflows. You can also
type a skill name directly in a prompt. Use Doctor to check readiness before
starting a workflow that calls an external provider.

| Need | Skill to invoke | Result |
| --- | --- | --- |
| Research a question | `$flow-discover` | Findings for the Discover phase |
| Investigate a complex topic in depth | `$octopus-research` | Broader research across sources |
| Agree on requirements | `$flow-define` | Scoped requirements |
| Implement an agreed plan | `$flow-develop` | Changes and verification evidence |
| Review a code diff | `$skill-code-review` | Actionable code feedback |
| Check specification and code quality | `$skill-staged-review` | Separate compliance and quality findings |
| Assess delivery readiness | `$flow-deliver` | Validation findings and readiness assessment |
| Compare competing approaches | `$skill-debate` | Arguments, disagreements, and a synthesis |
| Collect verdicts on an artifact | `$skill-council` | Model verdicts and evidence limits |
| Interpret an existing council result | `$council-verdicts` | Explanation of that run's verdicts |

For example:

```text
Use $flow-discover to research OAuth patterns after checking provider availability and costs.
Use $skill-code-review to review my current changes; present findings without posting to GitHub.
```

Skill selection expresses the task you want to run. It does not grant blanket
permission to publish, merge, deploy, repair accounts, or discard work. If a
provider is unavailable, report the missing coverage instead of attributing an
answer to it. An incomplete run is not a completed multi-provider review.

## If something is missing

Run Doctor and report the loaded version, affected skill, and error without
credentials. Setup is available through `$sys-configure`; follow its instructions
for your current host. After updating the plugin, check the loaded version in a
new session before retrying. Do not edit installed cache files to fix metadata.

See [host compatibility](PLUGIN-COMPATIBILITY.md#codex) for installation and
runtime limitations. Listing layout, ordering, and truncation can also depend
on the Codex version. A valid package does not prove the Desktop UI rendered it.
