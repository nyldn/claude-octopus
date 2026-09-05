import { readFileSync, realpathSync } from "node:fs";
import { realpath, stat } from "node:fs/promises";
import { isAbsolute, parse, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const CREDENTIAL_NAME = /^[A-Z][A-Z0-9_]*(?:API_KEY|TOKEN|CREDENTIALS?)$/;
const CREDENTIAL_ASSIGNMENT = /\b[A-Z][A-Z0-9_]*(?:KEY|TOKEN|CREDENTIALS?)=[^\s]+/g;

export function loadProviderEnvAllowlist(pluginRoot) {
  const path = resolve(pluginRoot, "config/provider-env-allowlist.json");
  const parsed = JSON.parse(readFileSync(path, "utf-8"));
  if (parsed.schema_version !== 1 || !Array.isArray(parsed.names) ||
      parsed.names.some((name) => typeof name !== "string" || !/^[A-Z][A-Z0-9_]*$/.test(name))) {
    throw new Error("invalid provider environment allowlist");
  }
  return [...new Set(parsed.names)];
}

export function providerEnvironment(providerEnvAllowlist, environment = process.env) {
  const dynamicNames = [
    environment.OPENAI_COMPAT_API_KEY_ENV,
    ...(environment.OCTOPUS_CREDENTIAL_ENV_NAMES ?? "").split(","),
  ].filter((name) =>
    typeof name === "string" &&
    CREDENTIAL_NAME.test(name) &&
    !name.startsWith("OCTOPUS_") && !name.startsWith("CLAUDE_OCTOPUS_")
  );
  const names = [...new Set([...providerEnvAllowlist, ...dynamicNames])];
  return Object.fromEntries(
    names.flatMap((name) => {
      const value = environment[name];
      return value === undefined ? [] : [[name, value]];
    })
  );
}

export async function validateProjectRoot(projectRoot) {
  if (typeof projectRoot !== "string" || projectRoot.trim() === "") {
    throw new Error("project_root is required");
  }
  if (!isAbsolute(projectRoot)) {
    throw new Error("project_root must be an absolute path");
  }
  const canonicalRoot = await realpath(projectRoot);
  const metadata = await stat(canonicalRoot);
  if (!metadata.isDirectory()) {
    throw new Error("project_root must be a directory");
  }
  if (canonicalRoot === parse(canonicalRoot).root) {
    throw new Error("project_root cannot be the filesystem root");
  }
  return canonicalRoot;
}

export function sanitizeAdapterError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(CREDENTIAL_ASSIGNMENT, "[REDACTED]");
}

export function isDirectExecution(moduleUrl, entrypoint = process.argv[1]) {
  if (!entrypoint) return false;
  try {
    return realpathSync(entrypoint) === realpathSync(fileURLToPath(moduleUrl));
  } catch {
    return false;
  }
}
