#!/usr/bin/env node
/**
 * Claude Octopus MCP Server
 *
 * Exposes Claude Octopus workflows (Double Diamond phases, debate, review)
 * as MCP tools that any MCP client (OpenClaw, Claude.ai, Cursor, etc.) can consume.
 *
 * This server delegates to the existing orchestrate.sh infrastructure,
 * preserving all existing behavior without duplication.
 *
 * Command mapping (MCP tool → orchestrate.sh command):
 *   octopus_discover → probe
 *   octopus_define   → grasp
 *   octopus_develop  → tangle
 *   octopus_deliver  → ink
 *   octopus_embrace  → embrace
 *   octopus_debate   → grapple
 *   octopus_council  → council
 *   octopus_review   → codex-review
 *   octopus_security → squeeze
 *
 * IDE integration tools:
 *   octopus_set_editor_context → Inject IDE state (file, selection, cursor) into orchestration
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
// --- IDE Context State ---
/** Editor context injected by IDE extensions via octopus_set_editor_context */
let editorContext = {};
// Security: these env vars must never be overridden via MCP client environment.
// They control security hardening, sandbox modes, and autonomy levels.
const BLOCKED_ENV_VARS = new Set([
    "OCTOPUS_SECURITY_V870",
    "OCTOPUS_AGY_SANDBOX",
    "OCTOPUS_CODEX_SANDBOX",
    "CLAUDE_OCTOPUS_AUTONOMY",
]);
const MAX_SELECTION_LENGTH = 50_000; // 50KB max for editor selection
// --- Helpers ---
async function runOrchestrate(command, prompt, flags = [], postFlags = []) {
    // Global flags MUST come before the command; subcommand flags go after
    const args = [...flags, command, ...postFlags, prompt];
    try {
        const { stdout, stderr } = await execFileAsync(ORCHESTRATE_SH, args, {
            cwd: PLUGIN_ROOT,
            timeout: 300_000,
            env: {
                // Security: only forward required env vars, not the full process.env
                PATH: process.env.PATH,
                HOME: process.env.HOME,
                TMPDIR: process.env.TMPDIR,
                SHELL: process.env.SHELL,
                USER: process.env.USER,
                // v8.32.0: Provider keys forwarded to orchestrate.sh which handles
                // per-agent credential isolation via build_provider_env().
                // Only forward keys that are set (avoid undefined in env).
                ...(process.env.OPENAI_API_KEY && { OPENAI_API_KEY: process.env.OPENAI_API_KEY }),
                ...(process.env.AGY_AUTH_TOKEN && { AGY_AUTH_TOKEN: process.env.AGY_AUTH_TOKEN }),
                ...(process.env.ANTIGRAVITY_API_KEY && { ANTIGRAVITY_API_KEY: process.env.ANTIGRAVITY_API_KEY }),
                ...(process.env.OPENROUTER_API_KEY && { OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY }),
                ...(process.env.PERPLEXITY_API_KEY && { PERPLEXITY_API_KEY: process.env.PERPLEXITY_API_KEY }),
                // Ollama Anthropic-compatible path (ANTHROPIC_BASE_URL=http://localhost:11434)
                ...(process.env.ANTHROPIC_BASE_URL && { ANTHROPIC_BASE_URL: process.env.ANTHROPIC_BASE_URL }),
                ...(process.env.ANTHROPIC_AUTH_TOKEN && { ANTHROPIC_AUTH_TOKEN: process.env.ANTHROPIC_AUTH_TOKEN }),
                // GitHub Copilot CLI auth (checked in precedence order by copilot CLI)
                ...(process.env.COPILOT_GITHUB_TOKEN && { COPILOT_GITHUB_TOKEN: process.env.COPILOT_GITHUB_TOKEN }),
                ...(process.env.GH_TOKEN && { GH_TOKEN: process.env.GH_TOKEN }),
                ...(process.env.GITHUB_TOKEN && { GITHUB_TOKEN: process.env.GITHUB_TOKEN }),
                // Octopus config — explicit allowlist (never forward security-governing vars)
                ...Object.fromEntries(Object.entries(process.env).filter(([k]) => (k.startsWith("CLAUDE_OCTOPUS_") || k.startsWith("OCTOPUS_")) &&
                    !BLOCKED_ENV_VARS.has(k))),
                CLAUDE_OCTOPUS_MCP_MODE: "true",
                // IDE context — injected by octopus_set_editor_context tool
                ...(editorContext.filename && { OCTOPUS_IDE_FILENAME: editorContext.filename }),
                ...(editorContext.selection && { OCTOPUS_IDE_SELECTION: editorContext.selection }),
                ...(editorContext.cursorLine !== undefined && { OCTOPUS_IDE_CURSOR_LINE: String(editorContext.cursorLine) }),
                ...(editorContext.languageId && { OCTOPUS_IDE_LANGUAGE: editorContext.languageId }),
                ...(editorContext.workspaceRoot && { OCTOPUS_IDE_WORKSPACE: editorContext.workspaceRoot }),
            },
        });
        return { text: stdout || stderr || "Command completed with no output.", isError: false };
    }
    catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        // Sanitize potential API key leaks from error messages
        const sanitized = msg.replace(/[A-Za-z_]+KEY=[^\s]+/g, "[REDACTED]");
        return { text: `Error executing ${command}: ${sanitized}`, isError: true };
    }
}
async function loadSkillMetadata() {
    const skillsDir = resolve(PLUGIN_ROOT, ".claude/skills");
    let files;
    try {
        files = await readdir(skillsDir);
    }
    catch {
        return [];
    }
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
    name: "octo-claw",
    version: "1.0.0",
});
const registerTool = server.tool.bind(server);
// --- Double Diamond Phase Tools ---
registerTool("octopus_discover", "Run the Discover (Probe) phase — multi-provider research using Codex and Antigravity CLIs for broad exploration of a topic.", { prompt: z.string().describe("The topic or question to research") }, async ({ prompt }) => {
    const { text, isError } = await runOrchestrate("probe", prompt);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_define", "Run the Define (Grasp) phase — consensus building on requirements, scope, and approach.", { prompt: z.string().describe("The requirements or scope to define") }, async ({ prompt }) => {
    const { text, isError } = await runOrchestrate("grasp", prompt);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_develop", "Run the Develop (Tangle) phase — implementation with quality gates and multi-provider validation.", {
    prompt: z.string().describe("What to implement"),
    quality_threshold: z
        .number()
        .min(0)
        .max(100)
        .default(75)
        .describe("Minimum quality score to pass (0-100)"),
}, async ({ prompt, quality_threshold }) => {
    const flags = quality_threshold !== undefined && quality_threshold !== 75
        ? ["-q", `${quality_threshold}`]
        : [];
    const { text, isError } = await runOrchestrate("tangle", prompt, flags);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_deliver", "Run the Deliver (Ink) phase — final validation, adversarial review, and delivery.", { prompt: z.string().describe("What to validate and deliver") }, async ({ prompt }) => {
    const { text, isError } = await runOrchestrate("ink", prompt);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_embrace", "Run the full Double Diamond workflow (Discover → Define → Develop → Deliver) end-to-end.", {
    prompt: z.string().describe("The full task or project to execute"),
    autonomy: z
        .enum(["supervised", "semi-autonomous", "autonomous"])
        .default("supervised")
        .describe("How much human oversight to apply"),
}, async ({ prompt, autonomy }) => {
    const flags = [`--autonomy`, autonomy];
    const { text, isError } = await runOrchestrate("embrace", prompt, flags);
    return { content: [{ type: "text", text }], isError };
});
// --- Utility Tools ---
registerTool("octopus_debate", "Run a structured AI debate between Claude, Sonnet, Antigravity, and Codex on a topic.", {
    question: z.string().describe("The question or topic to debate"),
    rounds: z
        .number()
        .min(1)
        .max(10)
        .default(1)
        .describe("Number of debate rounds"),
    mode: z
        .enum(["cross-critique", "blinded"])
        .default("cross-critique")
        .describe("Evaluation mode: cross-critique (ACH falsification) or blinded (independent evaluation, prevents anchoring bias)"),
}, async ({ question, rounds, mode }) => {
    // orchestrate.sh grapple parses -r/--mode AFTER the subcommand, not as global flags
    const postFlags = [`-r`, `${rounds}`, `--mode`, mode];
    const { text, isError } = await runOrchestrate("grapple", question, [], postFlags);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_council", "Run a configurable multi-LLM council with personas, budget caps, synthesis, veto gates, and optional implementation handoff.", {
    prompt: z.string().describe("The task, question, or decision for the council"),
    goal: z
        .enum(["advice", "decision", "plan", "implement", "review"])
        .optional()
        .describe("Council goal"),
    domain: z
        .enum(["auto", "architecture", "product", "security", "business", "research", "docs"])
        .optional()
        .describe("Domain used for persona recommendation"),
    style: z
        .enum(["balanced", "adversarial", "implementation", "executive", "red-team"])
        .optional()
        .describe("Council discussion style"),
    depth: z
        .enum(["quick", "standard", "deep"])
        .optional()
        .describe("Depth preset"),
    members: z
        .enum(["auto", "3", "5", "7"])
        .optional()
        .describe("Council size; explicit values override depth defaults"),
    persona: z
        .string()
        .optional()
        .describe("Comma-separated pinned persona names"),
    implement: z
        .enum(["never", "after-approval", "plan-only"])
        .optional()
        .describe("Implementation permission gate"),
    worktree: z
        .enum(["auto", "on", "off"])
        .optional()
        .describe("Implementation worktree preference"),
    benchmark: z
        .enum(["auto", "on", "off"])
        .optional()
        .describe("BullshitBench snapshot usage"),
    providers: z
        .string()
        .optional()
        .describe("auto or comma-separated provider list: claude,codex,agy,opencode,openrouter"),
    max_cost: z
        .string()
        .optional()
        .describe("USD decimal budget cap, for example 2.00"),
    dry_run: z
        .boolean()
        .optional()
        .describe("Preview council selection and cost without dispatching providers"),
    json: z
        .boolean()
        .optional()
        .describe("Print summary.json to stdout"),
    output_dir: z
        .string()
        .optional()
        .describe("Parent directory for council run artifacts"),
}, async ({ prompt, goal, domain, style, depth, members, persona, implement, worktree, benchmark, providers, max_cost, dry_run, json, output_dir, }) => {
    const postFlags = [];
    const add = (flag, value) => {
        if (value !== undefined && value !== "")
            postFlags.push(flag, value);
    };
    add("--goal", goal);
    add("--domain", domain);
    add("--style", style);
    add("--depth", depth);
    add("--members", members);
    add("--persona", persona);
    add("--implement", implement);
    add("--worktree", worktree);
    add("--benchmark", benchmark);
    add("--providers", providers);
    add("--max-cost", max_cost);
    add("--output-dir", output_dir);
    if (dry_run)
        postFlags.push("--dry-run");
    if (json)
        postFlags.push("--json");
    const { text, isError } = await runOrchestrate("council", prompt, [], postFlags);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_review", "Run multi-LLM code review pipeline (Codex + Antigravity + Claude + Perplexity fleet). Loads REVIEW.md customization if present. Supports inline PR comment publishing.", {
    target: z
        .string()
        .optional()
        .describe("What to review: 'staged' (default), 'working-tree', a PR number, or a file path"),
    focus: z
        .array(z.enum(["correctness", "security", "performance", "architecture", "style", "tests"]))
        .optional()
        .describe("Review focus areas (default: correctness)"),
    provenance: z
        .enum(["human-authored", "ai-assisted", "autonomous", "unknown"])
        .optional()
        .describe("How the code was produced — triggers elevated rigor for AI/autonomous output"),
    autonomy: z
        .enum(["supervised", "semi-autonomous", "autonomous"])
        .optional()
        .describe("Review autonomy level (default: supervised)"),
    publish: z
        .enum(["ask", "auto", "never"])
        .optional()
        .describe("Whether to post findings as inline PR comments (default: ask)"),
    debate: z
        .enum(["auto", "on", "off"])
        .optional()
        .describe("Whether to debate contested findings via multi-LLM gate (default: auto)"),
}, async ({ target, focus, provenance, autonomy, publish, debate }) => {
    // Build JSON profile and dispatch to review_run() via code-review command
    const profile = JSON.stringify({
        target: target ?? "staged",
        focus: focus ?? ["correctness"],
        provenance: provenance ?? "unknown",
        autonomy: autonomy ?? "supervised",
        publish: publish ?? "ask",
        debate: debate ?? "auto",
    });
    const { text, isError } = await runOrchestrate("code-review", profile);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_security", "Run comprehensive security audit with OWASP compliance and vulnerability detection.", {
    target: z
        .string()
        .describe("File path, directory, or description of what to audit"),
}, async ({ target }) => {
    // orchestrate.sh uses "squeeze" for security audits
    const { text, isError } = await runOrchestrate("squeeze", target);
    return { content: [{ type: "text", text }], isError };
});
// --- IDE Integration Tools ---
registerTool("octopus_set_editor_context", "Inject IDE editor state (active file, selection, cursor position) into Octopus workflows. Call this before running any workflow tool to give Octopus awareness of what the user is working on in their IDE.", {
    filename: z
        .string()
        .optional()
        .describe("Absolute path to the active editor file"),
    selection: z
        .string()
        .optional()
        .describe("Currently selected text in the editor"),
    cursor_line: z
        .number()
        .optional()
        .describe("Current cursor line number (1-based)"),
    language_id: z
        .string()
        .optional()
        .describe("Language identifier of the active file (e.g., typescript, python, rust)"),
    workspace_root: z
        .string()
        .optional()
        .describe("Root directory of the current IDE workspace"),
}, async ({ filename, selection, cursor_line, language_id, workspace_root }) => {
    // Validate paths — reject path traversal attempts
    for (const [label, value] of [["filename", filename], ["workspace_root", workspace_root]]) {
        if (value && /\.\.[\\/]/.test(value)) {
            return {
                content: [{ type: "text", text: `Error: ${label} cannot contain '..'` }],
                isError: true,
            };
        }
    }
    // Truncate oversized selections to prevent env var size exhaustion
    const safeSel = selection && selection.length > MAX_SELECTION_LENGTH
        ? selection.slice(0, MAX_SELECTION_LENGTH)
        : selection;
    editorContext = {
        filename,
        selection: safeSel,
        cursorLine: cursor_line,
        languageId: language_id,
        workspaceRoot: workspace_root,
    };
    const parts = [];
    if (filename)
        parts.push(`file: ${filename}`);
    if (cursor_line)
        parts.push(`line: ${cursor_line}`);
    if (language_id)
        parts.push(`lang: ${language_id}`);
    if (safeSel)
        parts.push(`selection: ${safeSel.length} chars`);
    if (workspace_root)
        parts.push(`workspace: ${workspace_root}`);
    return {
        content: [
            {
                type: "text",
                text: `Editor context updated: ${parts.join(", ") || "cleared"}`,
            },
        ],
        isError: false,
    };
});
// --- Introspection Tools ---
registerTool("octopus_list_skills", "List all available Claude Octopus skills with their descriptions.", {}, async () => {
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
registerTool("octopus_status", "Check Claude Octopus provider availability and configuration status.", {}, async () => {
    const { text, isError } = await runOrchestrate("status", "");
    return { content: [{ type: "text", text }], isError };
});
// --- Start Server ---
async function main() {
    // Opt-in guard: only start when explicitly enabled.
    // Users who want the MCP server must set OCTO_CLAW_ENABLED=true in their
    // environment or add the server manually to their .mcp.json / settings.json.
    // This prevents a permanent "failed" status in `/mcp` for users who don't
    // use OpenClaw or external MCP clients.
    if (process.env.OCTO_CLAW_ENABLED !== "true") {
        console.error("octo-claw MCP server is disabled by default. " +
            "Set OCTO_CLAW_ENABLED=true to start it. " +
            "See README.md § MCP Server for setup instructions.");
        process.exit(0);
    }
    // SECURITY: stdio transport is scoped to the spawning process (local IDE only).
    // If switching to HTTP/SSE/WebSocket, add bearer token authentication.
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch((error) => {
    console.error("Failed to start MCP server:", error);
    process.exit(1);
});
//# sourceMappingURL=index.js.map