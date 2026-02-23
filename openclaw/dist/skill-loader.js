/**
 * Skill Loader
 *
 * Parses Claude Octopus skill Markdown files and extracts YAML frontmatter
 * metadata to generate OpenClaw-compatible tool registrations.
 *
 * This is the bridge between Claude Code's Markdown-based skill format
 * and OpenClaw's TypeScript tool registration API.
 */
import { readFile, readdir } from "node:fs/promises";
import { resolve } from "node:path";
/**
 * Parse YAML-like frontmatter from a Markdown file.
 * Handles the simple key: value format used by Claude Code skills.
 */
function parseFrontmatter(content) {
    const match = content.match(/^---\n([\s\S]*?)\n---/);
    if (!match)
        return {};
    const result = {};
    const lines = match[1].split("\n");
    let currentKey = "";
    let currentValue = "";
    let inMultiline = false;
    for (const line of lines) {
        if (inMultiline) {
            if (line.match(/^\S/) && line.includes(":")) {
                result[currentKey] = currentValue.trim();
                inMultiline = false;
            }
            else {
                currentValue += "\n" + line;
                continue;
            }
        }
        const keyMatch = line.match(/^(\w[\w-]*):\s*(.*)/);
        if (keyMatch) {
            currentKey = keyMatch[1];
            const value = keyMatch[2].trim();
            if (value === "|" || value === ">") {
                inMultiline = true;
                currentValue = "";
            }
            else {
                result[currentKey] = value.replace(/^["']|["']$/g, "");
            }
        }
    }
    if (inMultiline && currentKey) {
        result[currentKey] = currentValue.trim();
    }
    return result;
}
/**
 * Parse aliases from frontmatter.
 * Handles both inline array and multi-line list formats.
 */
function parseAliases(content) {
    const match = content.match(/^---\n([\s\S]*?)\n---/);
    if (!match)
        return [];
    const aliasMatch = match[1].match(/aliases:\s*\n((?:\s+-\s+.+\n?)*)/m);
    if (!aliasMatch)
        return [];
    return aliasMatch[1]
        .split("\n")
        .map((line) => line.replace(/^\s+-\s+/, "").trim())
        .filter(Boolean);
}
/**
 * Load all skill metadata from the Claude Octopus skills directory.
 */
export async function loadSkills(pluginRoot) {
    const skillsDir = resolve(pluginRoot, ".claude/skills");
    const files = await readdir(skillsDir);
    const skills = [];
    for (const file of files) {
        if (!file.endsWith(".md"))
            continue;
        const filePath = resolve(skillsDir, file);
        const content = await readFile(filePath, "utf-8");
        const frontmatter = parseFrontmatter(content);
        if (!frontmatter.name)
            continue;
        skills.push({
            name: frontmatter.name,
            description: frontmatter.description?.replace(/^["']|["']$/g, "") ??
                "No description",
            aliases: parseAliases(content),
            trigger: frontmatter.trigger ?? "",
            context: frontmatter.context ?? "fork",
            file,
            filePath,
        });
    }
    return skills;
}
/**
 * Load command metadata from the Claude Octopus commands directory.
 */
export async function loadCommands(pluginRoot) {
    const commandsDir = resolve(pluginRoot, ".claude/commands");
    const files = await readdir(commandsDir);
    const commands = [];
    for (const file of files) {
        if (!file.endsWith(".md"))
            continue;
        const filePath = resolve(commandsDir, file);
        const content = await readFile(filePath, "utf-8");
        const frontmatter = parseFrontmatter(content);
        commands.push({
            name: frontmatter.command ?? file.replace(".md", ""),
            description: frontmatter.description ?? "No description",
            aliases: parseAliases(content),
            trigger: frontmatter.trigger ?? "",
            context: frontmatter.context ?? "fork",
            file,
            filePath,
        });
    }
    return commands;
}
//# sourceMappingURL=skill-loader.js.map