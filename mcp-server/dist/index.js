#!/usr/bin/env node
/**
 * Claude Octopus MCP Server
 *
 * Exposes Claude Octopus workflows (Double Diamond phases, debate, review)
 * as MCP tools that any MCP client (OpenClaw, Claude.ai, Cursor, etc.) can consume.
 *
 * This server delegates to the existing orchestrate.sh infrastructure,
 * preserving all existing behavior without duplication.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, readdir } from "node:fs/promises";
const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "../..");
const ORCHESTRATE_SH = resolve(PLUGIN_ROOT, "scripts/orchestrate.sh");
// --- Helpers ---
async function runOrchestrate(command, prompt, flags = []) {
    const args = [command, ...flags, prompt];
    try {
        const { stdout, stderr } = await execFileAsync(ORCHESTRATE_SH, args, {
            cwd: PLUGIN_ROOT,
            timeout: 300000,
            env: {
                ...process.env,
                CLAUDE_OCTOPUS_MCP_MODE: "true",
            },
        });
        return stdout || stderr || "Command completed with no output.";
    }
    catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        return `Error executing ${command}: ${msg}`;
    }
}
async function loadSkillMetadata() {
    const skillsDir = resolve(PLUGIN_ROOT, ".claude/skills");
    const files = await readdir(skillsDir);
    const skills = [];
    for (const file of files) {
        if (!file.endsWith(".md"))
            continue;
        const content = await readFile(resolve(skillsDir, file), "utf-8");
        const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
        if (!frontmatterMatch)
            continue;
        const fm = frontmatterMatch[1];
        const name = fm.match(/^name:\s*(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "") ??
            file.replace(".md", "");
        const description = fm
            .match(/^description:\s*["']?(.+?)["']?\s*$/m)?.[1]
            ?.trim() ?? "No description";
        skills.push({ name, description, file });
    }
    return skills;
}
// --- Server Setup ---
const server = new McpServer({
    name: "claude-octopus",
    version: "1.0.0",
});
// --- Double Diamond Phase Tools ---
server.tool("octopus_discover", "Run the Discover (Probe) phase — multi-provider research using Codex and Gemini CLIs for broad exploration of a topic.", { prompt: z.string().describe("The topic or question to research") }, async ({ prompt }) => {
    const result = await runOrchestrate("probe", prompt);
    return { content: [{ type: "text", text: result }] };
});
server.tool("octopus_define", "Run the Define (Grasp) phase — consensus building on requirements, scope, and approach.", { prompt: z.string().describe("The requirements or scope to define") }, async ({ prompt }) => {
    const result = await runOrchestrate("grasp", prompt);
    return { content: [{ type: "text", text: result }] };
});
server.tool("octopus_develop", "Run the Develop (Tangle) phase — implementation with quality gates and multi-provider validation.", {
    prompt: z.string().describe("What to implement"),
    quality_threshold: z
        .number()
        .min(0)
        .max(100)
        .default(75)
        .describe("Minimum quality score to pass (0-100)"),
}, async ({ prompt, quality_threshold }) => {
    const flags = [`--quality-threshold=${quality_threshold}`];
    const result = await runOrchestrate("tangle", prompt, flags);
    return { content: [{ type: "text", text: result }] };
});
server.tool("octopus_deliver", "Run the Deliver (Ink) phase — final validation, adversarial review, and delivery.", { prompt: z.string().describe("What to validate and deliver") }, async ({ prompt }) => {
    const result = await runOrchestrate("ink", prompt);
    return { content: [{ type: "text", text: result }] };
});
server.tool("octopus_embrace", "Run the full Double Diamond workflow (Discover → Define → Develop → Deliver) end-to-end.", {
    prompt: z.string().describe("The full task or project to execute"),
    autonomy: z
        .enum(["supervised", "semi-autonomous", "autonomous"])
        .default("autonomous")
        .describe("How much human oversight to apply"),
}, async ({ prompt, autonomy }) => {
    const flags = [`--autonomy=${autonomy}`];
    const result = await runOrchestrate("embrace", prompt, flags);
    return { content: [{ type: "text", text: result }] };
});
// --- Utility Tools ---
server.tool("octopus_debate", "Run a structured three-way AI debate between Claude, Gemini, and Codex on a topic.", {
    question: z.string().describe("The question or topic to debate"),
    rounds: z
        .number()
        .min(1)
        .max(10)
        .default(1)
        .describe("Number of debate rounds"),
    style: z
        .enum(["quick", "thorough", "adversarial", "collaborative"])
        .default("quick")
        .describe("Debate style"),
}, async ({ question, rounds, style }) => {
    const flags = [`-r`, `${rounds}`, `-d`, style];
    const result = await runOrchestrate("debate", question, flags);
    return { content: [{ type: "text", text: result }] };
});
server.tool("octopus_review", "Run expert code review with multi-provider analysis (security, performance, architecture).", {
    target: z
        .string()
        .describe("File path, directory, or description of what to review"),
}, async ({ target }) => {
    const result = await runOrchestrate("review", target);
    return { content: [{ type: "text", text: result }] };
});
server.tool("octopus_security_audit", "Run comprehensive security audit with OWASP compliance and vulnerability detection.", {
    target: z
        .string()
        .describe("File path, directory, or description of what to audit"),
}, async ({ target }) => {
    const result = await runOrchestrate("security", target);
    return { content: [{ type: "text", text: result }] };
});
// --- Introspection Tools ---
server.tool("octopus_list_skills", "List all available Claude Octopus skills with their descriptions.", {}, async () => {
    const skills = await loadSkillMetadata();
    const listing = skills
        .map((s) => `- **${s.name}**: ${s.description}`)
        .join("\n");
    return {
        content: [
            {
                type: "text",
                text: `# Claude Octopus Skills (${skills.length} available)\n\n${listing}`,
            },
        ],
    };
});
server.tool("octopus_status", "Check Claude Octopus provider availability and configuration status.", {}, async () => {
    const result = await runOrchestrate("status", "");
    return { content: [{ type: "text", text: result }] };
});
// --- Start Server ---
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch((error) => {
    console.error("Failed to start MCP server:", error);
    process.exit(1);
});
//# sourceMappingURL=index.js.map