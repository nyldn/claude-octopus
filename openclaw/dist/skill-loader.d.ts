/**
 * Skill Loader
 *
 * Parses Claude Octopus skill Markdown files and extracts YAML frontmatter
 * metadata to generate OpenClaw-compatible tool registrations.
 *
 * This is the bridge between Claude Code's Markdown-based skill format
 * and OpenClaw's TypeScript tool registration API.
 */
export interface SkillMetadata {
    name: string;
    description: string;
    aliases: string[];
    trigger: string;
    context: string;
    file: string;
    filePath: string;
}
/**
 * Load all skill metadata from the Claude Octopus skills directory.
 */
export declare function loadSkills(pluginRoot: string): Promise<SkillMetadata[]>;
/**
 * Load command metadata from the Claude Octopus commands directory.
 */
export declare function loadCommands(pluginRoot: string): Promise<SkillMetadata[]>;
