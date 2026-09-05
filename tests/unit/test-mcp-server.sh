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
import { mkdtemp, realpath, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const { runOrchestrate } = await import(pathToFileURL(modulePath));
assert.equal(typeof runOrchestrate, "function");
process.env.CLAUDE_SDK_API_KEY = "sdk-fixture";
process.env.CURSOR_API_KEY = "cursor-fixture";
process.env.XAI_API_KEY = "xai-fixture";
process.env.OPENAI_COMPAT_API_KEY_ENV = "ROUTER_API_KEY";
process.env.ROUTER_API_KEY = "router-fixture";
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
  runOrchestrate("status", "", first, [], [], runner),
  runOrchestrate("status", "", second, [], [], runner),
]);
assert.equal(a.text, canonicalFirst);
assert.equal(b.text, canonicalSecond);
assert.equal(calls.length, 2);
assert.deepEqual(new Set(calls.map((call) => call.options.cwd)), new Set([canonicalFirst, canonicalSecond]));
for (const call of calls) {
  assert.equal(call.options.env.OCTOPUS_PROJECT_DIR, call.options.cwd);
}
assert.equal(calls[0].options.env.CLAUDE_SDK_API_KEY, "sdk-fixture");
assert.equal(calls[0].options.env.CURSOR_API_KEY, "cursor-fixture");
assert.equal(calls[0].options.env.XAI_API_KEY, "xai-fixture");
assert.equal(calls[0].options.env.ROUTER_API_KEY, "router-fixture");
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
