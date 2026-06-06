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
import { Type, type TSchema, type Static } from "@sinclair/typebox";
import { loadSkills } from "./skill-loader.js";

const execFileAsync = promisify(execFile);

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "../..");

// --- Types (OpenClaw Plugin API — matching openclaw@2026.2.22-2) ---

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
  execute: (
    toolCallId: string,
    params: Record<string, unknown>,
    signal?: AbortSignal
  ) => Promise<AgentToolResult>;
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
  registerTool: (tool: AgentTool, opts?: { name?: string; names?: string[]; optional?: boolean }) => void;
  resolvePath: (input: string) => string;
}

// --- Helpers ---

function textResult(text: string): AgentToolResult {
  return { content: [{ type: "text", text }], details: {} };
}

// --- Execution ---

// Allowed autonomy values for runtime validation
const VALID_AUTONOMY = new Set(["supervised", "semi-autonomous", "autonomous"]);

async function executeOrchestrate(
  command: string,
  prompt: string,
  flags: string[] = [],
  postFlags: string[] = []
): Promise<string> {
  const orchestrateSh = resolve(PLUGIN_ROOT, "scripts/orchestrate.sh");
  // Global flags MUST come before the command; subcommand flags go after
  const args = [...flags, command, ...postFlags, prompt];

  try {
    const { stdout, stderr } = await execFileAsync(orchestrateSh, args, {
      cwd: PLUGIN_ROOT,
      timeout: 300_000,
      env: {
        // Security: only forward required env vars, not the full process.env
        PATH: process.env.PATH,
        HOME: process.env.HOME,
        TMPDIR: process.env.TMPDIR,
        SHELL: process.env.SHELL,
        USER: process.env.USER,
        // AI provider keys
        OPENAI_API_KEY: process.env.OPENAI_API_KEY,
        GEMINI_API_KEY: process.env.GEMINI_API_KEY,
        GOOGLE_API_KEY: process.env.GOOGLE_API_KEY,
        OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY,
        PERPLEXITY_API_KEY: process.env.PERPLEXITY_API_KEY,
        // Ollama Anthropic-compatible path (ANTHROPIC_BASE_URL=http://localhost:11434)
        ANTHROPIC_BASE_URL: process.env.ANTHROPIC_BASE_URL,
        ANTHROPIC_AUTH_TOKEN: process.env.ANTHROPIC_AUTH_TOKEN,
        // GitHub Copilot CLI auth (checked in precedence order by copilot CLI)
        COPILOT_GITHUB_TOKEN: process.env.COPILOT_GITHUB_TOKEN,
        GH_TOKEN: process.env.GH_TOKEN,
        GITHUB_TOKEN: process.env.GITHUB_TOKEN,
        // Octopus config
        ...Object.fromEntries(
          Object.entries(process.env).filter(([k]) =>
            k.startsWith("CLAUDE_OCTOPUS_") || k.startsWith("OCTOPUS_")
          )
        ),
        CLAUDE_OCTOPUS_MCP_MODE: "true",
        CLAUDE_OCTOPUS_OPENCLAW: "true",
      },
    });
    return stdout || stderr || "Command completed with no output.";
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    return `Error: ${msg}`;
  }
}

// --- Tool Definitions ---

interface WorkflowDef {
  name: string;
  label: string;
  description: string;
  parameters: TSchema;
  run: (params: Record<string, unknown>) => Promise<string>;
}

const WORKFLOW_DEFS: WorkflowDef[] = [
  {
    name: "octopus_discover",
    label: "Octopus Discover",
    description:
      "Run multi-provider research using Codex and Gemini CLIs for broad exploration.",
    parameters: Type.Object({
      prompt: Type.String({ description: "Topic to research" }),
    }),
    run: async (params) => executeOrchestrate("probe", params.prompt as string),
  },
  {
    name: "octopus_define",
    label: "Octopus Define",
    description:
      "Build consensus on requirements, scope, and approach using multi-AI synthesis.",
    parameters: Type.Object({
      prompt: Type.String({ description: "Requirements or scope to define" }),
    }),
    run: async (params) => executeOrchestrate("grasp", params.prompt as string),
  },
  {
    name: "octopus_develop",
    label: "Octopus Develop",
    description:
      "Implement with quality gates and multi-provider validation.",
    parameters: Type.Object({
      prompt: Type.String({ description: "What to implement" }),
      quality_threshold: Type.Optional(
        Type.Number({ description: "Minimum quality score (0-100)", default: 75 })
      ),
    }),
    run: async (params) => {
      const qt = params.quality_threshold as number | undefined;
      const flags = qt !== undefined && qt !== 75 ? ["-q", `${qt}`] : [];
      return executeOrchestrate("tangle", params.prompt as string, flags);
    },
  },
  {
    name: "octopus_deliver",
    label: "Octopus Deliver",
    description:
      "Final validation, adversarial review, and delivery of completed work.",
    parameters: Type.Object({
      prompt: Type.String({ description: "What to validate and deliver" }),
    }),
    run: async (params) => executeOrchestrate("ink", params.prompt as string),
  },
  {
    name: "octopus_embrace",
    label: "Octopus Embrace",
    description:
      "Full Double Diamond workflow: Discover → Define → Develop → Deliver.",
    parameters: Type.Object({
      prompt: Type.String({ description: "Full task or project" }),
      autonomy: Type.Optional(
        Type.Union(
          [
            Type.Literal("supervised"),
            Type.Literal("semi-autonomous"),
            Type.Literal("autonomous"),
          ],
          { default: "supervised" }
        )
      ),
    }),
    run: async (params) => {
      const autonomy = (params.autonomy as string) ?? "supervised";
      if (!VALID_AUTONOMY.has(autonomy)) {
        return `Error: invalid autonomy value '${autonomy}'. Allowed: supervised, semi-autonomous, autonomous`;
      }
      return executeOrchestrate("embrace", params.prompt as string, [
        `--autonomy`, autonomy,
      ]);
    },
  },
  {
    name: "octopus_debate",
    label: "Octopus Debate",
    description:
      "Four-way AI debate between Claude, Sonnet, Gemini, and Codex on any topic.",
    parameters: Type.Object({
      question: Type.String({ description: "Question to debate" }),
      rounds: Type.Optional(
        Type.Number({ default: 1, description: "Debate rounds" })
      ),
      mode: Type.Optional(
        Type.Union(
          [
            Type.Literal("cross-critique"),
            Type.Literal("blinded"),
          ],
          { default: "cross-critique", description: "Evaluation mode: cross-critique (ACH falsification) or blinded (independent)" }
        )
      ),
    }),
    // orchestrate.sh grapple parses -r/--mode AFTER the subcommand, not as global flags
    run: async (params) =>
      executeOrchestrate("grapple", params.question as string, [], [
        "-r",
        `${params.rounds ?? 1}`,
        "--mode",
        (params.mode as string) ?? "cross-critique",
      ]),
  },
  {
    name: "octopus_council",
    label: "Octopus Council",
    description:
      "Use Octopus to turn a project brief, roadmap, implementation plan, or decision into a structured council output. For planning-only handoffs from main, set goal=plan and implement=never.",
    parameters: Type.Object({
      prompt: Type.String({ description: "Project brief, roadmap path, implementation plan, or decision to pass to Octopus. Include explicit no-edit/no-implementation constraints for planning-only handoffs." }),
      goal: Type.Optional(
        Type.Union([
          Type.Literal("advice"),
          Type.Literal("decision"),
          Type.Literal("plan"),
          Type.Literal("implement"),
          Type.Literal("review"),
        ], { description: "Council goal" })
      ),
      domain: Type.Optional(
        Type.Union([
          Type.Literal("auto"),
          Type.Literal("architecture"),
          Type.Literal("product"),
          Type.Literal("security"),
          Type.Literal("business"),
          Type.Literal("research"),
          Type.Literal("docs"),
        ], { description: "Domain used for persona recommendation" })
      ),
      style: Type.Optional(
        Type.Union([
          Type.Literal("balanced"),
          Type.Literal("adversarial"),
          Type.Literal("implementation"),
          Type.Literal("executive"),
          Type.Literal("red-team"),
        ], { description: "Council discussion style" })
      ),
      depth: Type.Optional(
        Type.Union([
          Type.Literal("quick"),
          Type.Literal("standard"),
          Type.Literal("deep"),
        ], { description: "Depth preset" })
      ),
      members: Type.Optional(
        Type.Union([
          Type.Literal("auto"),
          Type.Literal("3"),
          Type.Literal("5"),
          Type.Literal("7"),
        ], { description: "Council size; explicit values override depth defaults" })
      ),
      persona: Type.Optional(Type.String({ description: "Comma-separated pinned persona names" })),
      implement: Type.Optional(
        Type.Union([
          Type.Literal("never"),
          Type.Literal("after-approval"),
          Type.Literal("plan-only"),
        ], { description: "Implementation permission gate" })
      ),
      worktree: Type.Optional(
        Type.Union([
          Type.Literal("auto"),
          Type.Literal("on"),
          Type.Literal("off"),
        ], { description: "Implementation worktree preference" })
      ),
      benchmark: Type.Optional(
        Type.Union([
          Type.Literal("auto"),
          Type.Literal("on"),
          Type.Literal("off"),
        ], { description: "BullshitBench snapshot usage" })
      ),
      providers: Type.Optional(
        Type.String({ description: "auto or comma-separated provider list: claude,codex,gemini,opencode,openrouter" })
      ),
      max_cost: Type.Optional(Type.String({ description: "USD decimal budget cap, for example 2.00" })),
      simulate: Type.Optional(Type.Boolean({ description: "Explicit single-model simulation mode; never used implicitly" })),
      single_model: Type.Optional(Type.Boolean({ description: "Alias for explicit single-model simulation mode" })),
      research_first: Type.Optional(Type.Boolean({ description: "Gather research evidence before council fanout" })),
      corpus_mode: Type.Optional(
        Type.Union([
          Type.Literal("off"),
          Type.Literal("append"),
          Type.Literal("require"),
        ], { description: "Whether findings, synthesis, and plans must be retained in a project corpus" })
      ),
      dry_run: Type.Optional(Type.Boolean({ description: "Preview council selection and cost without dispatching providers" })),
      json: Type.Optional(Type.Boolean({ description: "Print summary.json to stdout" })),
      output_dir: Type.Optional(Type.String({ description: "Parent directory for council run artifacts" })),
    }),
    run: async (params) => {
      const postFlags: string[] = [];
      const add = (flag: string, value: unknown) => {
        if (typeof value === "string" && value !== "") postFlags.push(flag, value);
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
      if (params.simulate === true) postFlags.push("--simulate");
      if (params.single_model === true) postFlags.push("--single-model");
      if (params.research_first === true) postFlags.push("--research-first");
      add("--output-dir", params.output_dir);
      if (params.dry_run === true) postFlags.push("--dry-run");
      if (params.json === true) postFlags.push("--json");

      return executeOrchestrate("council", params.prompt as string, [], postFlags);
    },
  },
  {
    name: "octopus_review",
    label: "Octopus Review",
    description:
      "Multi-LLM code review pipeline (Codex + Gemini + Claude + Perplexity fleet). Loads REVIEW.md customization, supports inline PR comment publishing.",
    parameters: Type.Object({
      target: Type.Optional(
        Type.String({ description: "What to review: 'staged' (default), 'working-tree', PR number, or file path" })
      ),
      focus: Type.Optional(
        Type.Array(
          Type.Union([
            Type.Literal("correctness"),
            Type.Literal("security"),
            Type.Literal("performance"),
            Type.Literal("architecture"),
            Type.Literal("style"),
            Type.Literal("tests"),
          ]),
          { description: "Review focus areas (default: correctness)" }
        )
      ),
      provenance: Type.Optional(
        Type.Union([
          Type.Literal("human-authored"),
          Type.Literal("ai-assisted"),
          Type.Literal("autonomous"),
          Type.Literal("unknown"),
        ], { description: "Code provenance — triggers elevated rigor for AI/autonomous output" })
      ),
      autonomy: Type.Optional(
        Type.Union([
          Type.Literal("supervised"),
          Type.Literal("semi-autonomous"),
          Type.Literal("autonomous"),
        ], { description: "Review autonomy level (default: supervised)" })
      ),
      publish: Type.Optional(
        Type.Union([
          Type.Literal("ask"),
          Type.Literal("auto"),
          Type.Literal("never"),
        ], { description: "Whether to post findings as inline PR comments (default: ask)" })
      ),
      debate: Type.Optional(
        Type.Union([
          Type.Literal("auto"),
          Type.Literal("on"),
          Type.Literal("off"),
        ], { description: "Whether to debate contested findings via multi-LLM gate (default: auto)" })
      ),
    }),
    run: async (params) => {
      const profile = JSON.stringify({
        target: (params.target as string) ?? "staged",
        focus: (params.focus as string[]) ?? ["correctness"],
        provenance: (params.provenance as string) ?? "unknown",
        autonomy: (params.autonomy as string) ?? "supervised",
        publish: (params.publish as string) ?? "ask",
        debate: (params.debate as string) ?? "auto",
      });
      return executeOrchestrate("code-review", profile);
    },
  },
  {
    name: "octopus_security",
    label: "Octopus Security",
    description:
      "Comprehensive security audit with OWASP compliance and vulnerability detection.",
    parameters: Type.Object({
      target: Type.String({ description: "File or directory to audit" }),
    }),
    run: async (params) =>
      executeOrchestrate("squeeze", params.target as string),
  },
];

// --- Extension Entry Point ---

export default function register(api: OpenClawPluginApi) {
  const pluginConfig = api.pluginConfig ?? {};
  const enabledWorkflows = (pluginConfig.enabledWorkflows as string[]) ?? [
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
      const tool: AgentTool = {
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

  api.logger.info(
    `Claude Octopus extension loaded: ${enabledWorkflows.length} workflows registered.`
  );
}
