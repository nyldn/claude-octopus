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
import { readFileSync } from "node:fs";
import { promisify } from "node:util";
import { resolve, dirname, isAbsolute, parse } from "node:path";
import { fileURLToPath } from "node:url";
import { Type } from "@sinclair/typebox";
import { loadSkills } from "./skill-loader.js";
import { realpath, stat } from "node:fs/promises";
const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "../..");
const PROVIDER_ENV_ALLOWLIST = loadProviderEnvAllowlist();
const BLOCKED_ENV_VARS = new Set([
    "OCTOPUS_SECURITY_V870",
    "OCTOPUS_AGY_SANDBOX",
    "OCTOPUS_CODEX_SANDBOX",
    "CLAUDE_OCTOPUS_AUTONOMY",
]);
// --- Helpers ---
function textResult(text) {
    return { content: [{ type: "text", text }], details: {} };
}
function loadProviderEnvAllowlist() {
    const path = resolve(PLUGIN_ROOT, "config/provider-env-allowlist.json");
    const parsed = JSON.parse(readFileSync(path, "utf-8"));
    if (parsed.schema_version !== 1 || !Array.isArray(parsed.names) ||
        parsed.names.some((name) => typeof name !== "string" || !/^[A-Z][A-Z0-9_]*$/.test(name))) {
        throw new Error("invalid provider environment allowlist");
    }
    return [...new Set(parsed.names)];
}
function providerEnvironment() {
    const dynamicNames = [
        process.env.OPENAI_COMPAT_API_KEY_ENV,
        ...(process.env.OCTOPUS_CREDENTIAL_ENV_NAMES ?? "").split(","),
    ].filter((name) => typeof name === "string" &&
        /^[A-Z][A-Z0-9_]*(?:API_KEY|TOKEN|CREDENTIALS?)$/.test(name) &&
        !name.startsWith("OCTOPUS_") && !name.startsWith("CLAUDE_OCTOPUS_"));
    const names = [...new Set([...PROVIDER_ENV_ALLOWLIST, ...dynamicNames])];
    return Object.fromEntries(names.flatMap((name) => {
        const value = process.env[name];
        return value === undefined ? [] : [[name, value]];
    }));
}
// --- Execution ---
// Allowed autonomy values for runtime validation
const VALID_AUTONOMY = new Set(["supervised", "semi-autonomous", "autonomous"]);
const PROJECT_ROOT_PARAMETER = Type.String({
    description: "Absolute root directory of the project for this call",
});
async function validateProjectRoot(projectRoot) {
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
export async function executeOrchestrate(command, prompt, projectRoot, flags = [], postFlags = [], executor = execFileAsync) {
    const orchestrateSh = resolve(PLUGIN_ROOT, "scripts/orchestrate.sh");
    // Global flags MUST come before the command; subcommand flags go after
    const args = [...flags, command, ...postFlags, prompt];
    try {
        const effectiveProjectRoot = await validateProjectRoot(projectRoot);
        const { stdout, stderr } = await executor(orchestrateSh, args, {
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
                ...providerEnvironment(),
                // Octopus config
                ...Object.fromEntries(Object.entries(process.env).filter(([k]) => (k.startsWith("CLAUDE_OCTOPUS_") || k.startsWith("OCTOPUS_")) &&
                    !BLOCKED_ENV_VARS.has(k))),
                CLAUDE_OCTOPUS_MCP_MODE: "true",
                CLAUDE_OCTOPUS_OPENCLAW: "true",
                OCTOPUS_PROJECT_DIR: effectiveProjectRoot,
            },
        });
        return stdout || stderr || "Command completed with no output.";
    }
    catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        return `Error: ${msg}`;
    }
}
const WORKFLOW_DEFS = [
    {
        name: "octopus_discover",
        label: "Octopus Discover",
        description: "Run multi-provider research using Codex and Antigravity CLIs for broad exploration.",
        parameters: Type.Object({
            prompt: Type.String({ description: "Topic to research" }),
            project_root: PROJECT_ROOT_PARAMETER,
        }),
        run: async (params) => executeOrchestrate("probe", params.prompt, params.project_root),
    },
    {
        name: "octopus_define",
        label: "Octopus Define",
        description: "Build consensus on requirements, scope, and approach using multi-AI synthesis.",
        parameters: Type.Object({
            prompt: Type.String({ description: "Requirements or scope to define" }),
            project_root: PROJECT_ROOT_PARAMETER,
        }),
        run: async (params) => executeOrchestrate("grasp", params.prompt, params.project_root),
    },
    {
        name: "octopus_develop",
        label: "Octopus Develop",
        description: "Implement with quality gates and multi-provider validation.",
        parameters: Type.Object({
            prompt: Type.String({ description: "What to implement" }),
            project_root: PROJECT_ROOT_PARAMETER,
            quality_threshold: Type.Optional(Type.Number({ description: "Minimum quality score (0-100)", default: 75 })),
        }),
        run: async (params) => {
            const qt = params.quality_threshold;
            const flags = qt !== undefined && qt !== 75 ? ["-q", `${qt}`] : [];
            return executeOrchestrate("tangle", params.prompt, params.project_root, flags);
        },
    },
    {
        name: "octopus_deliver",
        label: "Octopus Deliver",
        description: "Final validation, adversarial review, and delivery of completed work.",
        parameters: Type.Object({
            prompt: Type.String({ description: "What to validate and deliver" }),
            project_root: PROJECT_ROOT_PARAMETER,
        }),
        run: async (params) => executeOrchestrate("ink", params.prompt, params.project_root),
    },
    {
        name: "octopus_embrace",
        label: "Octopus Embrace",
        description: "Full Double Diamond workflow: Discover → Define → Develop → Deliver.",
        parameters: Type.Object({
            prompt: Type.String({ description: "Full task or project" }),
            project_root: PROJECT_ROOT_PARAMETER,
            autonomy: Type.Optional(Type.Union([
                Type.Literal("supervised"),
                Type.Literal("semi-autonomous"),
                Type.Literal("autonomous"),
            ], { default: "supervised" })),
        }),
        run: async (params) => {
            const autonomy = params.autonomy ?? "supervised";
            if (!VALID_AUTONOMY.has(autonomy)) {
                return `Error: invalid autonomy value '${autonomy}'. Allowed: supervised, semi-autonomous, autonomous`;
            }
            return executeOrchestrate("embrace", params.prompt, params.project_root, [
                `--autonomy`, autonomy,
            ]);
        },
    },
    {
        name: "octopus_debate",
        label: "Octopus Debate",
        description: "Multi-provider AI debate between Claude, Sonnet, Antigravity, and Codex on any topic.",
        parameters: Type.Object({
            question: Type.String({ description: "Question to debate" }),
            project_root: PROJECT_ROOT_PARAMETER,
            rounds: Type.Optional(Type.Number({ default: 1, description: "Debate rounds" })),
            mode: Type.Optional(Type.Union([
                Type.Literal("cross-critique"),
                Type.Literal("blinded"),
            ], { default: "cross-critique", description: "Evaluation mode: cross-critique (ACH falsification) or blinded (independent)" })),
        }),
        // orchestrate.sh grapple parses -r/--mode AFTER the subcommand, not as global flags
        run: async (params) => executeOrchestrate("grapple", params.question, params.project_root, [], [
            "-r",
            `${params.rounds ?? 1}`,
            "--mode",
            params.mode ?? "cross-critique",
        ]),
    },
    {
        name: "octopus_council",
        label: "Octopus Council",
        description: "Use Octopus to turn a project brief, roadmap, implementation plan, or decision into a structured council output. For planning-only handoffs from main, set goal=plan and implement=never.",
        parameters: Type.Object({
            prompt: Type.String({ description: "Project brief, roadmap path, implementation plan, or decision to pass to Octopus. Include explicit no-edit/no-implementation constraints for planning-only handoffs." }),
            project_root: PROJECT_ROOT_PARAMETER,
            goal: Type.Optional(Type.Union([
                Type.Literal("advice"),
                Type.Literal("decision"),
                Type.Literal("plan"),
                Type.Literal("implement"),
                Type.Literal("review"),
            ], { description: "Council goal" })),
            domain: Type.Optional(Type.Union([
                Type.Literal("auto"),
                Type.Literal("architecture"),
                Type.Literal("product"),
                Type.Literal("security"),
                Type.Literal("business"),
                Type.Literal("research"),
                Type.Literal("docs"),
            ], { description: "Domain used for persona recommendation" })),
            style: Type.Optional(Type.Union([
                Type.Literal("balanced"),
                Type.Literal("adversarial"),
                Type.Literal("implementation"),
                Type.Literal("executive"),
                Type.Literal("red-team"),
            ], { description: "Council discussion style" })),
            depth: Type.Optional(Type.Union([
                Type.Literal("quick"),
                Type.Literal("standard"),
                Type.Literal("deep"),
            ], { description: "Depth preset" })),
            members: Type.Optional(Type.Union([
                Type.Literal("auto"),
                Type.Literal("3"),
                Type.Literal("5"),
                Type.Literal("7"),
            ], { description: "Council size; explicit values override depth defaults" })),
            persona: Type.Optional(Type.String({ description: "Comma-separated pinned persona names" })),
            implement: Type.Optional(Type.Union([
                Type.Literal("never"),
                Type.Literal("after-approval"),
                Type.Literal("plan-only"),
            ], { description: "Implementation permission gate" })),
            worktree: Type.Optional(Type.Union([
                Type.Literal("auto"),
                Type.Literal("on"),
                Type.Literal("off"),
            ], { description: "Implementation worktree preference" })),
            benchmark: Type.Optional(Type.Union([
                Type.Literal("auto"),
                Type.Literal("on"),
                Type.Literal("off"),
            ], { description: "BullshitBench snapshot usage" })),
            providers: Type.Optional(Type.String({ description: "auto or comma-separated provider list: claude,codex,agy,opencode,openrouter" })),
            max_cost: Type.Optional(Type.String({ description: "USD decimal budget cap, for example 2.00" })),
            simulate: Type.Optional(Type.Boolean({ description: "Explicit single-model simulation mode; never used implicitly" })),
            single_model: Type.Optional(Type.Boolean({ description: "Alias for explicit single-model simulation mode" })),
            research_first: Type.Optional(Type.Boolean({ description: "Gather research evidence before council fanout" })),
            corpus_mode: Type.Optional(Type.Union([
                Type.Literal("off"),
                Type.Literal("append"),
                Type.Literal("require"),
            ], { description: "Whether findings, synthesis, and plans must be retained in a project corpus" })),
            dry_run: Type.Optional(Type.Boolean({ description: "Preview council selection and cost without dispatching providers" })),
            json: Type.Optional(Type.Boolean({ description: "Print summary.json to stdout" })),
            output_dir: Type.Optional(Type.String({ description: "Parent directory for council run artifacts" })),
        }),
        run: async (params) => {
            const postFlags = [];
            const add = (flag, value) => {
                if (typeof value === "string" && value !== "")
                    postFlags.push(flag, value);
            };
            add("--goal", params.goal);
            add("--domain", params.domain);
            add("--style", params.style);
            add("--depth", params.depth);
            add("--members", params.members);
            add("--persona", params.persona);
            add("--implement", params.implement);
            add("--worktree", params.worktree);
            add("--benchmark", params.benchmark);
            add("--providers", params.providers);
            add("--max-cost", params.max_cost);
            add("--corpus-mode", params.corpus_mode);
            if (params.simulate === true)
                postFlags.push("--simulate");
            if (params.single_model === true)
                postFlags.push("--single-model");
            if (params.research_first === true)
                postFlags.push("--research-first");
            add("--output-dir", params.output_dir);
            if (params.dry_run === true)
                postFlags.push("--dry-run");
            if (params.json === true)
                postFlags.push("--json");
            return executeOrchestrate("council", params.prompt, params.project_root, [], postFlags);
        },
    },
    {
        name: "octopus_review",
        label: "Octopus Review",
        description: "Multi-LLM code review pipeline (Codex + Antigravity + Claude + Perplexity fleet). Loads REVIEW.md customization, supports inline PR comment publishing.",
        parameters: Type.Object({
            project_root: PROJECT_ROOT_PARAMETER,
            target: Type.Optional(Type.String({ description: "What to review: 'staged' (default), 'working-tree', PR number, or file path" })),
            focus: Type.Optional(Type.Array(Type.Union([
                Type.Literal("correctness"),
                Type.Literal("security"),
                Type.Literal("performance"),
                Type.Literal("architecture"),
                Type.Literal("style"),
                Type.Literal("tests"),
            ]), { description: "Review focus areas (default: correctness)" })),
            provenance: Type.Optional(Type.Union([
                Type.Literal("human-authored"),
                Type.Literal("ai-assisted"),
                Type.Literal("autonomous"),
                Type.Literal("unknown"),
            ], { description: "Code provenance — triggers elevated rigor for AI/autonomous output" })),
            autonomy: Type.Optional(Type.Union([
                Type.Literal("supervised"),
                Type.Literal("semi-autonomous"),
                Type.Literal("autonomous"),
            ], { description: "Review autonomy level (default: supervised)" })),
            publish: Type.Optional(Type.Union([
                Type.Literal("ask"),
                Type.Literal("auto"),
                Type.Literal("never"),
            ], { description: "Whether to post findings as inline PR comments (default: ask)" })),
            debate: Type.Optional(Type.Union([
                Type.Literal("auto"),
                Type.Literal("on"),
                Type.Literal("off"),
            ], { description: "Whether to debate contested findings via multi-LLM gate (default: auto)" })),
        }),
        run: async (params) => {
            const profile = JSON.stringify({
                target: params.target ?? "staged",
                focus: params.focus ?? ["correctness"],
                provenance: params.provenance ?? "unknown",
                autonomy: params.autonomy ?? "supervised",
                publish: params.publish ?? "ask",
                debate: params.debate ?? "auto",
            });
            return executeOrchestrate("code-review", profile, params.project_root);
        },
    },
    {
        name: "octopus_security",
        label: "Octopus Security",
        description: "Comprehensive security audit with OWASP compliance and vulnerability detection.",
        parameters: Type.Object({
            project_root: PROJECT_ROOT_PARAMETER,
            target: Type.String({ description: "File or directory to audit" }),
        }),
        run: async (params) => executeOrchestrate("squeeze", params.target, params.project_root),
    },
];
// --- Extension Entry Point ---
export default function register(api) {
    const pluginConfig = api.pluginConfig ?? {};
    const enabledWorkflows = pluginConfig.enabledWorkflows ?? [
        "discover",
        "define",
        "develop",
        "deliver",
        "embrace",
        "debate",
        "council",
        "review",
        "security",
    ];
    api.logger.info(`Claude Octopus OpenClaw extension loading...`);
    api.logger.info(`Plugin root: ${PLUGIN_ROOT}`);
    // Register workflow tools
    for (const def of WORKFLOW_DEFS) {
        const workflowName = def.name.replace("octopus_", "");
        if (enabledWorkflows.includes(workflowName)) {
            const tool = {
                name: def.name,
                label: def.label,
                description: def.description,
                parameters: def.parameters,
                execute: async (_toolCallId, params) => textResult(await def.run(params)),
            };
            api.registerTool(tool);
            api.logger.info(`Registered tool: ${def.name}`);
        }
    }
    // Register introspection tool
    api.registerTool({
        name: "octopus_list_skills",
        label: "Octopus List Skills",
        description: "List all available Claude Octopus skills.",
        parameters: Type.Object({}),
        execute: async () => {
            const skills = await loadSkills(PLUGIN_ROOT);
            const text = skills
                .map((s) => `- ${s.name}: ${s.description}`)
                .join("\n");
            return textResult(text);
        },
    });
    api.logger.info(`Claude Octopus extension loaded: ${enabledWorkflows.length} workflows registered.`);
}
//# sourceMappingURL=index.js.map