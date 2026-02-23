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

// --- Types (OpenClaw API interface) ---

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
  run: (
    params: Record<string, unknown>,
    context: OpenClawToolContext
  ) => Promise<string>;
}

interface OpenClawApi {
  registerTool: (tool: OpenClawTool) => void;
  getConfig: () => Record<string, unknown>;
  log: (level: string, message: string) => void;
}

// --- Execution ---

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
        ...process.env,
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

const WORKFLOW_TOOLS: OpenClawTool[] = [
  {
    name: "octopus_discover",
    description:
      "Run multi-provider research using Codex and Gemini CLIs for broad exploration.",
    parameters: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "Topic to research" },
      },
      required: ["prompt"],
    },
    run: async (params) => executeOrchestrate("probe", params.prompt as string),
  },
  {
    name: "octopus_define",
    description:
      "Build consensus on requirements, scope, and approach using multi-AI synthesis.",
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
    run: async (params) => executeOrchestrate("grasp", params.prompt as string),
  },
  {
    name: "octopus_develop",
    description:
      "Implement with quality gates and multi-provider validation.",
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
    run: async (params) =>
      executeOrchestrate("tangle", params.prompt as string),
  },
  {
    name: "octopus_deliver",
    description:
      "Final validation, adversarial review, and delivery of completed work.",
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
    run: async (params) => executeOrchestrate("ink", params.prompt as string),
  },
  {
    name: "octopus_embrace",
    description:
      "Full Double Diamond workflow: Discover → Define → Develop → Deliver.",
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
    run: async (params) =>
      executeOrchestrate("embrace", params.prompt as string, [
        `--autonomy`, (params.autonomy as string) ?? "supervised",
      ]),
  },
  {
    name: "octopus_debate",
    description:
      "Three-way AI debate between Claude, Gemini, and Codex on any topic.",
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
    description:
      "Expert code review with multi-provider security and architecture analysis.",
    parameters: {
      type: "object",
      properties: {
        target: { type: "string", description: "File or directory to review" },
      },
      required: ["target"],
    },
    run: async (params) =>
      executeOrchestrate("codex-review", params.target as string),
  },
  {
    name: "octopus_security",
    description:
      "Comprehensive security audit with OWASP compliance and vulnerability detection.",
    parameters: {
      type: "object",
      properties: {
        target: { type: "string", description: "File or directory to audit" },
      },
      required: ["target"],
    },
    run: async (params) =>
      executeOrchestrate("squeeze", params.target as string),
  },
];

// --- Extension Entry Point ---

export default function register(api: OpenClawApi) {
  const config = api.getConfig() ?? {};
  const enabledWorkflows = (config.enabledWorkflows as string[]) ?? [
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

  api.log(
    "info",
    `Claude Octopus extension loaded: ${enabledWorkflows.length} workflows registered.`
  );
}
