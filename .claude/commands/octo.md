---
command: octo
description: "[Legacy] Redirects to /octo:auto — the smart router"
version: 3.0.0
category: workflow
tags: [router, legacy, redirect]
created: 2025-02-03
updated: 2026-03-18
---

# /octo:octo → /octo:auto (Legacy Redirect)

This command has been renamed to `/octo:auto`. Invoking `/octo:octo` still works for backward compatibility.

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:octo <query>`, you MUST:

1. Inform the user: "Note: `/octo:octo` has been renamed to `/octo:auto`. Routing your request now."
2. Immediately invoke: `Skill(skill: "octo:auto", args: "<full user query>")`

Do NOT duplicate the routing logic here — delegate entirely to `/octo:auto`.
