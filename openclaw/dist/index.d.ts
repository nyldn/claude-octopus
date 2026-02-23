/**
 * Claude Octopus — OpenClaw Extension
 *
 * Registers Claude Octopus workflows as native OpenClaw tools.
 * Delegates execution to orchestrate.sh (via Claude CLI or MCP server)
 * to preserve exact behavioral parity with the Claude Code plugin.
 *
 * Architecture:
 *   OpenClaw Gateway → This extension → orchestrate.sh → Multi-provider execution
 *
 * This module is the entry point declared in openclaw.extensions.
 */
interface OpenClawToolContext {
    channelId: string;
    userId: string;
    threadId?: string;
    session: {
        id: string;
        transcript: unknown[];
    };
}
interface OpenClawTool {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
    run: (params: Record<string, unknown>, context: OpenClawToolContext) => Promise<string>;
}
interface OpenClawApi {
    registerTool: (tool: OpenClawTool) => void;
    getConfig: () => Record<string, unknown>;
    log: (level: string, message: string) => void;
}
export default function register(api: OpenClawApi): void;
export {};
