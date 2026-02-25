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
  flags: string[] = []
): Promise<string> {
  const orchestrateSh = resolve(PLUGIN_ROOT, "scripts/orchestrate.sh");
  // Flags MUST come before the command per orchestrate.sh's argument parser
  const args = [...flags, command, prompt];

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
    run: async (params) =>
      executeOrchestrate("tangle", params.prompt as string),
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
      "Three-way AI debate between Claude, Gemini, and Codex on any topic.",
    parameters: Type.Object({
      question: Type.String({ description: "Question to debate" }),
      rounds: Type.Optional(
        Type.Number({ default: 1, description: "Debate rounds" })
      ),
      style: Type.Optional(
        Type.Union(
          [
            Type.Literal("quick"),
            Type.Literal("thorough"),
            Type.Literal("adversarial"),
            Type.Literal("collaborative"),
          ],
          { default: "quick" }
        )
      ),
    }),
    run: async (params) =>
      executeOrchestrate("grapple", params.question as string, [
        "-r",
        `${params.rounds ?? 1}`,
        "-d",
        (params.style as string) ?? "quick",
      ]),
  },
  {
    name: "octopus_review",
    label: "Octopus Review",
    description:
      "Expert code review with multi-provider security and architecture analysis.",
    parameters: Type.Object({
      target: Type.String({ description: "File or directory to review" }),
    }),
    run: async (params) =>
      executeOrchestrate("codex-review", params.target as string),
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
