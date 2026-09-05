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
import { resolve, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, readdir } from "node:fs/promises";
import { isDirectExecution, loadProviderEnvAllowlist, providerEnvironment, sanitizeAdapterError, validateProjectRoot, } from "../../shared/adapter-runtime.mjs";
const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "../..");
const ORCHESTRATE_SH = resolve(PLUGIN_ROOT, "scripts/orchestrate.sh");
const PROVIDER_ENV_ALLOWLIST = loadProviderEnvAllowlist(PLUGIN_ROOT);
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
export async function runOrchestrate(command, prompt, projectRoot, flags = [], postFlags = [], executor = execFileAsync) {
    // Global flags MUST come before the command; subcommand flags go after
    const args = [...flags, command, ...postFlags, prompt];
    try {
        const effectiveProjectRoot = await validateProjectRoot(projectRoot);
        const { stdout, stderr } = await executor(ORCHESTRATE_SH, args, {
            cwd: effectiveProjectRoot,
            timeout: 300_000,
            env: {
                // Security: only forward required env vars, not the full process.env
                PATH: process.env.PATH,
                HOME: process.env.HOME,
                TMPDIR: process.env.TMPDIR,
                SHELL: process.env.SHELL,
                USER: process.env.USER,
                // The shared list covers every supported adapter. The shell dispatch
                // plan forwards only the credential selected for the current seat.
                ...providerEnvironment(PROVIDER_ENV_ALLOWLIST),
                // Octopus config — explicit allowlist (never forward security-governing vars)
                ...Object.fromEntries(Object.entries(process.env).filter(([k]) => (k.startsWith("CLAUDE_OCTOPUS_") || k.startsWith("OCTOPUS_")) &&
                    !BLOCKED_ENV_VARS.has(k))),
                CLAUDE_OCTOPUS_MCP_MODE: "true",
                // IDE context — injected by octopus_set_editor_context tool
                ...(editorContext.filename && { OCTOPUS_IDE_FILENAME: editorContext.filename }),
                ...(editorContext.selection && { OCTOPUS_IDE_SELECTION: editorContext.selection }),
                ...(editorContext.cursorLine !== undefined && { OCTOPUS_IDE_CURSOR_LINE: String(editorContext.cursorLine) }),
                ...(editorContext.languageId && { OCTOPUS_IDE_LANGUAGE: editorContext.languageId }),
                OCTOPUS_PROJECT_DIR: effectiveProjectRoot,
            },
        });
        return { text: stdout || stderr || "Command completed with no output.", isError: false };
    }
    catch (error) {
        const sanitized = sanitizeAdapterError(error);
        return { text: `Error executing ${command}: ${sanitized}`, isError: true };
    }
}
async function findSkillFiles(directory) {
    let entries;
    try {
        entries = await readdir(directory, { withFileTypes: true });
    }
    catch {
        return [];
    }
    const files = [];
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        const path = resolve(directory, entry.name);
        if (entry.isDirectory()) {
            files.push(...(await findSkillFiles(path)));
        }
        else if (entry.isFile() && entry.name === "SKILL.md") {
            files.push(path);
        }
    }
    return files;
}
export async function loadSkillMetadata() {
    const files = await findSkillFiles(resolve(PLUGIN_ROOT, "skills"));
    const skills = [];
    for (const file of files) {
        const content = await readFile(file, "utf-8");
        const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
        if (!frontmatterMatch)
            continue;
        const fm = frontmatterMatch[1];
        const name = fm.match(/^name:\s*(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "") ??
            dirname(relative(PLUGIN_ROOT, file)).split("/").pop() ?? "unknown";
        const description = fm
            .match(/^description:\s*["']?(.+?)["']?\s*$/m)?.[1]
            ?.trim() ?? "No description";
        skills.push({ name, description, file: relative(PLUGIN_ROOT, file) });
    }
    return skills;
}
// --- Server Setup ---
const server = new McpServer({
    name: "octo-claw",
    version: "1.0.0",
});
const registerTool = server.tool.bind(server);
const projectRootSchema = z
    .string()
    .describe("Absolute root directory of the project for this call");
// --- Double Diamond Phase Tools ---
registerTool("octopus_discover", "Run the Discover (Probe) phase — multi-provider research using Codex and Antigravity CLIs for broad exploration of a topic.", { prompt: z.string().describe("The topic or question to research"), project_root: projectRootSchema }, async ({ prompt, project_root }) => {
    const { text, isError } = await runOrchestrate("probe", prompt, project_root);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_define", "Run the Define (Grasp) phase — consensus building on requirements, scope, and approach.", { prompt: z.string().describe("The requirements or scope to define"), project_root: projectRootSchema }, async ({ prompt, project_root }) => {
    const { text, isError } = await runOrchestrate("grasp", prompt, project_root);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_develop", "Run the Develop (Tangle) phase — implementation with quality gates and multi-provider validation.", {
    prompt: z.string().describe("What to implement"),
    project_root: projectRootSchema,
    quality_threshold: z
        .number()
        .min(0)
        .max(100)
        .default(75)
        .describe("Minimum quality score to pass (0-100)"),
}, async ({ prompt, project_root, quality_threshold }) => {
    const flags = quality_threshold !== undefined && quality_threshold !== 75
        ? ["-q", `${quality_threshold}`]
        : [];
    const { text, isError } = await runOrchestrate("tangle", prompt, project_root, flags);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_deliver", "Run the Deliver (Ink) phase — final validation, adversarial review, and delivery.", { prompt: z.string().describe("What to validate and deliver"), project_root: projectRootSchema }, async ({ prompt, project_root }) => {
    const { text, isError } = await runOrchestrate("ink", prompt, project_root);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_embrace", "Run the full Double Diamond workflow (Discover → Define → Develop → Deliver) end-to-end.", {
    prompt: z.string().describe("The full task or project to execute"),
    project_root: projectRootSchema,
    autonomy: z
        .enum(["supervised", "semi-autonomous", "autonomous"])
        .default("supervised")
        .describe("How much human oversight to apply"),
}, async ({ prompt, project_root, autonomy }) => {
    const flags = [`--autonomy`, autonomy];
    const { text, isError } = await runOrchestrate("embrace", prompt, project_root, flags);
    return { content: [{ type: "text", text }], isError };
});
// --- Utility Tools ---
registerTool("octopus_debate", "Run a structured AI debate between Claude, Sonnet, Antigravity, and Codex on a topic.", {
    question: z.string().describe("The question or topic to debate"),
    project_root: projectRootSchema,
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
}, async ({ question, project_root, rounds, mode }) => {
    // orchestrate.sh grapple parses -r/--mode AFTER the subcommand, not as global flags
    const postFlags = [`-r`, `${rounds}`, `--mode`, mode];
    const { text, isError } = await runOrchestrate("grapple", question, project_root, [], postFlags);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_council", "Run a configurable multi-LLM council with personas, budget caps, synthesis, veto gates, and optional implementation handoff.", {
    prompt: z.string().describe("The task, question, or decision for the council"),
    project_root: projectRootSchema,
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
}, async ({ prompt, project_root, goal, domain, style, depth, members, persona, implement, worktree, benchmark, providers, max_cost, dry_run, json, output_dir, }) => {
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
    const { text, isError } = await runOrchestrate("council", prompt, project_root, [], postFlags);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_review", "Run multi-LLM code review pipeline (Codex + Antigravity + Claude + Perplexity fleet). Loads REVIEW.md customization if present. Supports inline PR comment publishing.", {
    project_root: projectRootSchema,
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
}, async ({ project_root, target, focus, provenance, autonomy, publish, debate }) => {
    // Build JSON profile and dispatch to review_run() via code-review command
    const profile = JSON.stringify({
        target: target ?? "staged",
        focus: focus ?? ["correctness"],
        provenance: provenance ?? "unknown",
        autonomy: autonomy ?? "supervised",
        publish: publish ?? "ask",
        debate: debate ?? "auto",
    });
    const { text, isError } = await runOrchestrate("code-review", profile, project_root);
    return { content: [{ type: "text", text }], isError };
});
registerTool("octopus_security", "Run comprehensive security audit with OWASP compliance and vulnerability detection.", {
    project_root: projectRootSchema,
    target: z
        .string()
        .describe("File path, directory, or description of what to audit"),
}, async ({ project_root, target }) => {
    // orchestrate.sh uses "squeeze" for security audits
    const { text, isError } = await runOrchestrate("squeeze", target, project_root);
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
registerTool("octopus_status", "Check Claude Octopus provider availability and configuration status.", { project_root: projectRootSchema }, async ({ project_root }) => {
    const { text, isError } = await runOrchestrate("status", "", project_root);
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
if (isDirectExecution(import.meta.url)) {
    main().catch((error) => {
        console.error("Failed to start MCP server:", error);
        process.exit(1);
    });
}
//# sourceMappingURL=index.js.map