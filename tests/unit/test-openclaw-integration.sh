#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "OpenClaw project binding"

test_case "every OpenClaw workflow call requires an immutable project_root"
count="$(grep -c 'project_root: PROJECT_ROOT_PARAMETER' "$PROJECT_ROOT/openclaw/src/index.ts" || true)"
if [[ "$count" == "9" ]]; then
    test_pass
else
    test_fail "expected project_root on nine OpenClaw workflows, found $count"
fi

test_case "built OpenClaw runner binds concurrent calls to their own validated projects"
if ! (cd "$PROJECT_ROOT/openclaw" && npm run build >/dev/null); then
    test_fail "OpenClaw build failed"
elif node --input-type=module - "$PROJECT_ROOT/openclaw/dist/index.js" <<'JS'
import assert from "node:assert/strict";
import { mkdtemp, realpath, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const { executeOrchestrate } = await import(pathToFileURL(modulePath));
assert.equal(typeof executeOrchestrate, "function");
process.env.CLAUDE_SDK_API_KEY = "sdk-fixture";
process.env.CURSOR_API_KEY = "cursor-fixture";
process.env.XAI_API_KEY = "xai-fixture";
process.env.OCTOPUS_CREDENTIAL_ENV_NAMES = "ROUTER_API_KEY";
process.env.ROUTER_API_KEY = "router-fixture";
process.env.UNRELATED_AUDIT_SENTINEL = "must-not-cross";
process.env.OCTOPUS_SECURITY_V870 = "false";
const first = await mkdtemp(join(tmpdir(), "octo-openclaw-a-"));
const second = await mkdtemp(join(tmpdir(), "octo-openclaw-b-"));
const canonicalFirst = await realpath(first);
const canonicalSecond = await realpath(second);
const calls = [];
const runner = async (file, args, options) => {
  calls.push({ file, args, options });
  return { stdout: options.cwd, stderr: "" };
};
const [a, b] = await Promise.all([
  executeOrchestrate("probe", "a", first, [], [], runner),
  executeOrchestrate("probe", "b", second, [], [], runner),
]);
assert.equal(a, canonicalFirst);
assert.equal(b, canonicalSecond);
const callsByPrompt = new Map(calls.map((call) => [call.args.at(-1), call]));
const firstCall = callsByPrompt.get("a");
const secondCall = callsByPrompt.get("b");
assert.equal(firstCall.options.cwd, canonicalFirst);
assert.equal(secondCall.options.cwd, canonicalSecond);
assert.equal(firstCall.options.env.OCTOPUS_PROJECT_DIR, canonicalFirst);
assert.equal(secondCall.options.env.OCTOPUS_PROJECT_DIR, canonicalSecond);
assert.equal(firstCall.options.env.CLAUDE_SDK_API_KEY, "sdk-fixture");
assert.equal(firstCall.options.env.CURSOR_API_KEY, "cursor-fixture");
assert.equal(firstCall.options.env.XAI_API_KEY, "xai-fixture");
assert.equal(firstCall.options.env.ROUTER_API_KEY, "router-fixture");
assert.equal(firstCall.options.env.UNRELATED_AUDIT_SENTINEL, undefined);
assert.equal(firstCall.options.env.OCTOPUS_SECURITY_V870, undefined);

const file = join(first, "not-a-directory");
await writeFile(file, "fixture");
for (const invalid of ["", "relative/path", file, "/"]) {
  const before = calls.length;
  const result = await executeOrchestrate("probe", "x", invalid, [], [], runner);
  assert.match(result, /^Error:/, invalid);
  assert.equal(calls.length, before, invalid);
}
JS
then
    test_pass
else
    test_fail "built OpenClaw runner did not preserve per-call project authority"
fi

test_case "OpenClaw errors redact API key and token assignments"
if node --input-type=module - "$PROJECT_ROOT/openclaw/dist/index.js" "$PROJECT_ROOT" <<'JS'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const projectRoot = process.argv[3];
const { executeOrchestrate } = await import(pathToFileURL(modulePath));
const result = await executeOrchestrate(
  "probe", "credential-failure", projectRoot, [], [], async () => {
    throw new Error("request failed: OPENAI_API_KEY=openclaw-secret ANTHROPIC_AUTH_TOKEN=openclaw-token AWS_SECRET_ACCESS_KEY=openclaw-access");
  }
);
assert.doesNotMatch(result, /openclaw-secret|openclaw-token|openclaw-access/);
assert.equal((result.match(/\[REDACTED\]/g) ?? []).length, 3);
JS
then
    test_pass
else
    test_fail "OpenClaw error returned a credential value"
fi

test_summary
