---
name: skill-native-escalation-routing
description: "Route ordinary init, review, and security requests to Claude-native capabilities first; escalate to Octopus only when multi-LLM diversity adds value"
---

# Native-First Escalation Routing

Use this skill when the user asks for repository initialization, code review, or security review and it is not yet clear whether Claude-native behavior is sufficient or whether Octopus escalation is warranted.

## Core Policy

Claude-native first:

- `/init`
- `/review`
- `/security-review`

Octopus for escalation:

- `/octo:review`
- `/octo:security`
- `/octo:debate`
- `/octo:multi`

## Route to Claude-Native First

Prefer Claude-native behavior when all of the following are true:

- the request maps directly to init, review, or security review
- the user did not ask for multiple model opinions
- the user did not ask for Codex, Gemini, or another provider explicitly
- the task does not require adversarial debate, consensus scoring, or external-provider specialization

Examples:

- "initialize this repo"
- "review my staged changes"
- "security review this auth module"

## Escalate to Octopus

Escalate when the user asks for or clearly benefits from:

- multiple model opinions
- adversarial review
- debate between providers
- provider-specific analysis
- autonomous codegen verification
- elevated rigor for complex or high-risk work

Examples:

- "get multiple model opinions on this PR"
- "have Codex and Gemini review this architecture"
- "do an adversarial security review"
- "verify this AI-generated implementation before merge"

## Execution Guidance

- If Claude-native is sufficient, do not wrap the task in Octopus unnecessarily.
- If the user explicitly invokes `/octo:review` or `/octo:security`, treat that as an escalation request.
- If the request is ambiguous, prefer Claude-native first and mention Octopus as the escalation path.

## Suggested User Framing

Use wording like:

> Claude-native first, Octopus for escalation. Use Claude-native `/review` or `/security-review` for ordinary requests. Use Octopus when you want multiple model opinions, adversarial review, or stricter multi-LLM workflows.
