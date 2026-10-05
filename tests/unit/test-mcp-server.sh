#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "MCP project binding"

test_case "every MCP workflow call requires an immutable project_root"
count="$(grep -c 'project_root: projectRootSchema' "$PROJECT_ROOT/mcp-server/src/index.ts" || true)"
if [[ "$count" == "10" ]]; then
    test_pass
else
    test_fail "expected project_root on nine workflows plus status, found $count"
fi

test_case "built MCP runner binds concurrent calls to their own validated projects"
if ! (cd "$PROJECT_ROOT/mcp-server" && npm run build >/dev/null); then
    test_fail "MCP build failed"
elif node --input-type=module - "$PROJECT_ROOT/mcp-server/dist/index.js" <<'JS'
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, realpath, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const modulePath = process.argv[2];
const { runOrchestrate } = await import(pathToFileURL(modulePath));
assert.equal(typeof runOrchestrate, "function");
process.env.CLAUDE_SDK_API_KEY = "sdk-fixture";
process.env.CURSOR_API_KEY = "cursor-fixture";
process.env.XAI_API_KEY = "xai-fixture";
process.env.API_ROUTE_API_KEY = "api-route-fixture";
process.env.API_ROUTE_MODEL = "route-model";
process.env.OCTOPUS_API_ROUTE_MODEL = "alias-model";
process.env.API_ROUTE_ALLOWED_MODELS = "route-model";
process.env.API_ROUTE_UNRELATED_SENTINEL = "must-not-cross";
process.env.OPENAI_COMPAT_API_KEY_ENV = "ROUTER_API_KEY";
process.env.ROUTER_API_KEY = "router-fixture";
process.env.OCTOPUS_CREDENTIAL_ENV_NAMES = "CUSTOM_MCP_API_KEY";
process.env.CUSTOM_MCP_API_KEY = "custom-mcp-fixture";
process.env.UNRELATED_AUDIT_SENTINEL = "must-not-cross";
process.env.OCTOPUS_SECURITY_V870 = "false";
const first = await mkdtemp(join(tmpdir(), "octo-mcp-a-"));
const second = await mkdtemp(join(tmpdir(), "octo-mcp-b-"));
const canonicalFirst = await realpath(first);
const canonicalSecond = await realpath(second);
const calls = [];
const runner = async (file, args, options) => {
  calls.push({ file, args, options });
  return { stdout: options.cwd, stderr: "" };
};
const [a, b] = await Promise.all([
  runOrchestrate("status", "first-request", first, [], [], runner),
  runOrchestrate("status", "second-request", second, [], [], runner),
]);
assert.equal(a.text, canonicalFirst);
assert.equal(b.text, canonicalSecond);
assert.equal(calls.length, 2);
const callsByPrompt = new Map(calls.map((call) => [call.args.at(-1), call]));
const firstCall = callsByPrompt.get("first-request");
const secondCall = callsByPrompt.get("second-request");
assert.equal(firstCall.options.cwd, canonicalFirst);
assert.equal(secondCall.options.cwd, canonicalSecond);
assert.equal(firstCall.options.env.OCTOPUS_PROJECT_DIR, canonicalFirst);
assert.equal(secondCall.options.env.OCTOPUS_PROJECT_DIR, canonicalSecond);
assert.equal(calls[0].options.env.CLAUDE_SDK_API_KEY, "sdk-fixture");
assert.equal(calls[0].options.env.CURSOR_API_KEY, "cursor-fixture");
assert.equal(calls[0].options.env.XAI_API_KEY, "xai-fixture");
assert.equal(calls[0].options.env.API_ROUTE_API_KEY, "api-route-fixture");
assert.equal(calls[0].options.env.API_ROUTE_MODEL, "route-model");
assert.equal(calls[0].options.env.OCTOPUS_API_ROUTE_MODEL, "alias-model");
assert.equal(calls[0].options.env.API_ROUTE_ALLOWED_MODELS, "route-model");
assert.equal(calls[0].options.env.API_ROUTE_UNRELATED_SENTINEL, undefined);

// Exercise shell admission with the environment the MCP adapter actually sent.
// Reading the key alone would miss model loss and exact-seat restriction bypass.
const pluginRoot = fileURLToPath(new URL("../..", pathToFileURL(modulePath)));
const admission = spawnSync("bash", ["-c", `
  set -euo pipefail
  PLUGIN_DIR="$1"
  source "$1/scripts/lib/model-resolver.sh"
  source "$1/scripts/lib/dispatch.sh"
  log() { :; }
  resolve_provider_env() { return 1; }
  PROVIDER_CODEX_INSTALLED=false
  PROVIDER_CLAUDE_INSTALLED=false
  is_agent_available_v2 api-route-agent
  is_agent_available_v2 api-route-agent:route-model
  ! is_agent_available_v2 api-route-agent:blocked || exit 1
  command=$(get_agent_command api-route-agent review code-reviewer)
  [[ "$command" == *'--model route-model '* && "$command" == *'--tool-policy none'* ]]
  ! get_agent_command api-route-agent:blocked review code-reviewer >/dev/null 2>&1
`, "_", pluginRoot], { env: firstCall.options.env, cwd: canonicalFirst, encoding: "utf8" });
assert.equal(admission.status, 0, admission.stderr || admission.stdout);
assert.equal(calls[0].options.env.ROUTER_API_KEY, "router-fixture");
assert.equal(calls[0].options.env.CUSTOM_MCP_API_KEY, "custom-mcp-fixture");
assert.equal(calls[0].options.env.UNRELATED_AUDIT_SENTINEL, undefined);
assert.equal(calls[0].options.env.OCTOPUS_SECURITY_V870, undefined);

const file = join(first, "not-a-directory");
await writeFile(file, "fixture");
for (const invalid of ["", "relative/path", file, "/"]) {
  const before = calls.length;
  const result = await runOrchestrate("status", "", invalid, [], [], runner);
  assert.equal(result.isError, true, invalid);
  assert.equal(calls.length, before, invalid);
}
JS
then
    test_pass
else
    test_fail "built MCP runner did not preserve per-call project authority"
fi

test_case "MCP errors redact API key and token assignments"
if node --input-type=module - "$PROJECT_ROOT/mcp-server/dist/index.js" "$PROJECT_ROOT" <<'JS'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const projectRoot = process.argv[3];
const { runOrchestrate } = await import(pathToFileURL(modulePath));
const result = await runOrchestrate(
  "status", "credential-failure", projectRoot, [], [], async () => {
    throw new Error("request failed: OPENAI_API_KEY=mcp-secret ANTHROPIC_AUTH_TOKEN=mcp-token AWS_SECRET_ACCESS_KEY=mcp-access");
  }
);
assert.equal(result.isError, true);
assert.doesNotMatch(result.text, /mcp-secret|mcp-token|mcp-access/);
assert.equal((result.text.match(/\[REDACTED\]/g) ?? []).length, 3);
JS
then
    test_pass
else
    test_fail "MCP error returned a credential value"
fi

test_case "MCP entrypoint starts when invoked through a symlink"
if ! (cd "$PROJECT_ROOT/mcp-server" && npm run build >/dev/null); then
    test_fail "MCP build failed"
elif node --input-type=module - "$PROJECT_ROOT/mcp-server/dist/index.js" <<'JS'
import assert from "node:assert/strict";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const modulePath = process.argv[2];
const directory = await mkdtemp(join(tmpdir(), "octo-mcp-entrypoint-"));
const linkedPath = join(directory, "server.js");
try {
  await symlink(modulePath, linkedPath);
  const result = spawnSync(process.execPath, [linkedPath], {
    encoding: "utf8",
    input: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "symlink-test", version: "1.0.0" },
      },
    }) + "\n",
  });
  assert.equal(result.status, 0);
  assert.equal(result.stderr, "");
  const response = JSON.parse(result.stdout.trim());
  assert.equal(response.id, 1);
  assert.equal(response.result.serverInfo.name, "claude-octopus");
} finally {
  await rm(directory, { recursive: true, force: true });
}
JS
then
    test_pass
else
    test_fail "symlinked MCP entrypoint did not start the server"
fi

test_case "MCP skill discovery reads recursive canonical SKILL.md files"
expected_count="$(find "$PROJECT_ROOT/skills" -type f -name SKILL.md | wc -l | tr -d ' ')"
if node --input-type=module - "$PROJECT_ROOT/mcp-server/dist/index.js" "$expected_count" <<'JS'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const expectedCount = Number(process.argv[3]);
const { loadSkillMetadata } = await import(pathToFileURL(modulePath));
const skills = await loadSkillMetadata();
assert.equal(skills.length, expectedCount);
assert.equal(new Set(skills.map((skill) => skill.file)).size, expectedCount);
assert.ok(skills.some((skill) => skill.name === "skill-code-review"));
assert.ok(skills.some((skill) => skill.file === "skills/octopus-starter-pack/provider-health/SKILL.md"));
assert.ok(skills.every((skill) => skill.file.startsWith("skills/") && skill.file.endsWith("/SKILL.md")));
JS
then
    test_pass
else
    test_fail "MCP skill discovery did not return the canonical recursive inventory"
fi

test_summary
