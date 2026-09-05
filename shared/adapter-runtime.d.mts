export function loadProviderEnvAllowlist(pluginRoot: string): string[];

export function providerEnvironment(
  providerEnvAllowlist: readonly string[],
  environment?: Readonly<Record<string, string | undefined>>
): Record<string, string>;

export function validateProjectRoot(projectRoot: string): Promise<string>;

export function sanitizeAdapterError(error: unknown): string;

export function isDirectExecution(moduleUrl: string, entrypoint?: string): boolean;
