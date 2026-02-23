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
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadSkills } from "./skill-loader.js";
const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "../..");
// --- Execution ---
async function executeOrchestrate(command, prompt, flags = []) {
    const orchestrateSh = resolve(PLUGIN_ROOT, "scripts/orchestrate.sh");
    const args = [command, ...flags, prompt];
    try {
        const { stdout, stderr } = await execFileAsync(orchestrateSh, args, {
            cwd: PLUGIN_ROOT,
            timeout: 300000,
            env: {
                ...process.env,
                CLAUDE_OCTOPUS_MCP_MODE: "true",
                CLAUDE_OCTOPUS_OPENCLAW: "true",
            },
        });
        return stdout || stderr || "Command completed with no output.";
    }
    catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        return `Error: ${msg}`;
    }
}
// --- Tool Definitions ---
const WORKFLOW_TOOLS = [
    {
        name: "octopus_discover",
        description: "Run multi-provider research using Codex and Gemini CLIs for broad exploration.",
        parameters: {
            type: "object",
            properties: {
                prompt: { type: "string", description: "Topic to research" },
            },
            required: ["prompt"],
        },
        run: async (params) => executeOrchestrate("probe", params.prompt),
    },
    {
        name: "octopus_define",
        description: "Build consensus on requirements, scope, and approach using multi-AI synthesis.",
        parameters: {
            type: "object",
            properties: {
                prompt: {
                    type: "string",
                    description: "Requirements or scope to define",
                },
            },
            required: ["prompt"],
        },
        run: async (params) => executeOrchestrate("grasp", params.prompt),
    },
    {
        name: "octopus_develop",
        description: "Implement with quality gates and multi-provider validation.",
        parameters: {
            type: "object",
            properties: {
                prompt: { type: "string", description: "What to implement" },
                quality_threshold: {
                    type: "number",
                    description: "Minimum quality score (0-100)",
                    default: 75,
                },
            },
            required: ["prompt"],
        },
        run: async (params) => executeOrchestrate("tangle", params.prompt, [
            `--quality-threshold=${params.quality_threshold ?? 75}`,
        ]),
    },
    {
        name: "octopus_deliver",
        description: "Final validation, adversarial review, and delivery of completed work.",
        parameters: {
            type: "object",
            properties: {
                prompt: {
                    type: "string",
                    description: "What to validate and deliver",
                },
            },
            required: ["prompt"],
        },
        run: async (params) => executeOrchestrate("ink", params.prompt),
    },
    {
        name: "octopus_embrace",
        description: "Full Double Diamond workflow: Discover → Define → Develop → Deliver.",
        parameters: {
            type: "object",
            properties: {
                prompt: { type: "string", description: "Full task or project" },
                autonomy: {
                    type: "string",
                    enum: ["supervised", "semi-autonomous", "autonomous"],
                    default: "supervised",
                },
            },
            required: ["prompt"],
        },
        run: async (params) => executeOrchestrate("embrace", params.prompt, [
            `--autonomy=${params.autonomy ?? "supervised"}`,
        ]),
    },
    {
        name: "octopus_debate",
        description: "Three-way AI debate between Claude, Gemini, and Codex on any topic.",
        parameters: {
            type: "object",
            properties: {
                question: { type: "string", description: "Question to debate" },
                rounds: { type: "number", default: 1, description: "Debate rounds" },
                style: {
                    type: "string",
                    enum: ["quick", "thorough", "adversarial", "collaborative"],
                    default: "quick",
                },
            },
            required: ["question"],
        },
        run: async (params) => executeOrchestrate("debate", params.question, [
            "-r",
            `${params.rounds ?? 1}`,
            "-d",
            params.style ?? "quick",
        ]),
    },
    {
        name: "octopus_review",
        description: "Expert code review with multi-provider security and architecture analysis.",
        parameters: {
            type: "object",
            properties: {
                target: { type: "string", description: "File or directory to review" },
            },
            required: ["target"],
        },
        run: async (params) => executeOrchestrate("review", params.target),
    },
    {
        name: "octopus_security",
        description: "Comprehensive security audit with OWASP compliance and vulnerability detection.",
        parameters: {
            type: "object",
            properties: {
                target: { type: "string", description: "File or directory to audit" },
            },
            required: ["target"],
        },
        run: async (params) => executeOrchestrate("security", params.target),
    },
];
// --- Extension Entry Point ---
export default function register(api) {
    const config = api.getConfig() ?? {};
    const enabledWorkflows = config.enabledWorkflows ?? [
        "discover",
        "define",
        "develop",
        "deliver",
        "embrace",
        "debate",
        "review",
        "security",
    ];
    api.log("info", `Claude Octopus OpenClaw extension loading...`);
    api.log("info", `Plugin root: ${PLUGIN_ROOT}`);
    // Register workflow tools
    for (const tool of WORKFLOW_TOOLS) {
        const workflowName = tool.name.replace("octopus_", "");
        if (enabledWorkflows.includes(workflowName)) {
            api.registerTool(tool);
            api.log("info", `Registered tool: ${tool.name}`);
        }
    }
    // Register introspection tool
    api.registerTool({
        name: "octopus_list_skills",
        description: "List all available Claude Octopus skills.",
        parameters: { type: "object", properties: {} },
        run: async () => {
            const skills = await loadSkills(PLUGIN_ROOT);
            return skills
                .map((s) => `- ${s.name}: ${s.description}`)
                .join("\n");
        },
    });
    api.log("info", `Claude Octopus extension loaded: ${enabledWorkflows.length} workflows registered.`);
}
//# sourceMappingURL=index.js.map