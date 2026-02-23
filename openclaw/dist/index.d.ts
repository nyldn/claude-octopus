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
import { type TSchema } from "@sinclair/typebox";
interface TextContent {
    type: "text";
    text: string;
}
interface AgentToolResult {
    content: TextContent[];
    details: unknown;
}
interface AgentTool {
    name: string;
    label: string;
    description: string;
    parameters: TSchema;
    execute: (toolCallId: string, params: Record<string, unknown>, signal?: AbortSignal) => Promise<AgentToolResult>;
}
interface PluginLogger {
    debug?: (message: string) => void;
    info: (message: string) => void;
    warn: (message: string) => void;
    error: (message: string) => void;
}
interface OpenClawPluginApi {
    id: string;
    name: string;
    config: Record<string, unknown>;
    pluginConfig?: Record<string, unknown>;
    logger: PluginLogger;
    registerTool: (tool: AgentTool, opts?: {
        name?: string;
        names?: string[];
        optional?: boolean;
    }) => void;
    resolvePath: (input: string) => string;
}
export default function register(api: OpenClawPluginApi): void;
export {};
