# Upgrading to v11.0.1

Claude Octopus no longer ships the OpenClaw extension. The adapter, manifest,
generated registry, build script, and dedicated tests have been removed because
the integration had no observed user adoption and imposed ongoing release and
test maintenance.

If you used the extension, remain on v11.0.0 while moving your client to the
supported MCP server in `mcp-server/`. MCP clients should launch
`mcp-server/dist/index.js` directly. The former `OCTO_CLAW_ENABLED` environment
variable is no longer required.

The Claude Code plugin, Codex plugin package, Cursor integration, provider
routing, and core orchestration commands are unchanged by this release.
