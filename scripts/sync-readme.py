#!/usr/bin/env python3
"""Synchronize mechanical release facts across public README surfaces.

The plugin manifest and runtime capability/model resolvers are the source of
truth. Run without arguments to update files, or with --check to fail when a
tracked surface has drifted.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


CURRENT_RELEASE_START = "<!-- BEGIN CURRENT RELEASE -->"
CURRENT_RELEASE_END = "<!-- END CURRENT RELEASE -->"
CURRENT_MODELS_START = "<!-- BEGIN CURRENT MODEL DEFAULTS -->"
CURRENT_MODELS_END = "<!-- END CURRENT MODEL DEFAULTS -->"

PUBLIC_EXTERNAL_PROVIDERS = (
    ("Codex", "Codex CLI"),
    ("Antigravity CLI", "Antigravity CLI (`agy`)"),
    ("Copilot", "Copilot"),
    ("Qwen", "Qwen"),
    ("Ollama", "Ollama"),
    ("Perplexity", "Perplexity API key"),
    ("OpenRouter", "OpenRouter API key"),
    ("OrcaRouter", "OrcaRouter API key"),
    ("OpenCode", "OpenCode CLI"),
    ("Cursor CLI", "Cursor CLI (`agent`)"),
    ("Grok", "xAI API key (Grok)"),
    ("Kimi Code", "Kimi Code CLI"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root (defaults to the script's parent repository)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="report drift without writing files",
    )
    return parser.parse_args()


def require_match(pattern: str, text: str, label: str, flags: int = 0) -> re.Match[str]:
    match = re.search(pattern, text, flags)
    if not match:
        raise ValueError(f"unable to derive {label}")
    return match


def replace_marker_block(
    text: str,
    start: str,
    end: str,
    body: str,
    label: str,
) -> str:
    pattern = rf"{re.escape(start)}.*?{re.escape(end)}"
    replacement = f"{start}\n{body.rstrip()}\n{end}"
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f"{label} markers are missing or duplicated")
    return updated


def function_echo_values(shell_text: str, function_name: str) -> list[str]:
    block = require_match(
        rf"^{re.escape(function_name)}\(\) \{{\n(.*?)^\}}",
        shell_text,
        function_name,
        re.MULTILINE | re.DOTALL,
    ).group(1)
    return re.findall(r'echo "([^"$]+)"', block)


def display_model(model: str) -> str:
    if model.startswith("claude-"):
        words = model.removeprefix("claude-").split("-")
        return "Claude " + " ".join(word.capitalize() for word in words)
    if model.startswith("gpt-"):
        words = model.split("-")
        return "GPT-" + words[1] + "".join(
            f" {word.capitalize()}" for word in words[2:]
        )
    return model


def semver_key(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


def release_summary(description: str, version: str) -> str:
    summary = re.sub(
        rf"^v{re.escape(version)}\s*[-—]\s*",
        "",
        description.strip(),
    )
    summary = re.sub(r"\s*Run /octo:setup\.\s*$", "", summary)
    return summary.rstrip().rstrip(".")


def markdown_table_text(value: str) -> str:
    return value.replace("|", r"\|")


def human_join(values: tuple[str, ...]) -> str:
    if len(values) < 2:
        return "".join(values)
    return f"{', '.join(values[:-1])}, and {values[-1]}"


def number_word(value: int) -> str:
    words = {
        0: "zero",
        1: "one",
        2: "two",
        3: "three",
        4: "four",
        5: "five",
        6: "six",
        7: "seven",
        8: "eight",
        9: "nine",
        10: "ten",
        11: "eleven",
        12: "twelve",
    }
    return words.get(value, str(value))


def derive_facts(root: Path) -> dict[str, object]:
    plugin = json.loads((root / ".claude-plugin/plugin.json").read_text())
    version = plugin["version"]
    summary = release_summary(plugin["description"], version)
    command_count = len(plugin.get("commands", []))
    skill_count = len(plugin.get("skills", []))
    persona_count = len(list((root / "agents/personas").glob("*.md")))
    droid_dir = root / "agents/droids"
    if not droid_dir.is_dir():
        raise ValueError("agents/droids is missing")
    droid_count = len(list(droid_dir.glob("*.md")))
    orchestrate = (root / "scripts/orchestrate.sh").read_text()
    providers = (root / "scripts/lib/providers.sh").read_text()
    resolver = (root / "scripts/lib/model-resolver.sh").read_text()

    minimum_version = require_match(
        r'local min_version="([0-9]+\.[0-9]+\.[0-9]+)"',
        orchestrate,
        "minimum Claude Code version",
    ).group(1)
    capability_flags = set(
        re.findall(r"^(SUPPORTS_[A-Z0-9_]+)=(?:false|true)\b", orchestrate, re.MULTILINE)
    )
    capability_versions = re.findall(
        r'version_compare "\$CLAUDE_CODE_VERSION" "([0-9]+\.[0-9]+\.[0-9]+)"',
        providers,
    )
    if not capability_flags or not capability_versions:
        raise ValueError("unable to derive Claude Code capability facts")
    capability_ceiling = max(capability_versions, key=semver_key)

    opus_models = function_echo_values(resolver, "opus_default_model")
    sonnet_models = function_echo_values(resolver, "sonnet_default_model")
    codex_models = function_echo_values(resolver, "codex_default_model")
    if not opus_models or not sonnet_models or not codex_models:
        raise ValueError("current model resolver functions have no model values")

    changelog = (root / "CHANGELOG.md").read_text()
    release_date = require_match(
        rf"^## \[{re.escape(version)}\] - ([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})$",
        changelog,
        f"release date for {version}",
        re.MULTILINE,
    ).group(1)

    return {
        "version": version,
        "summary": summary,
        "command_count": command_count,
        "skill_count": skill_count,
        "persona_count": persona_count,
        "droid_count": droid_count,
        "minimum_version": minimum_version,
        "capability_count": len(capability_flags),
        "capability_ceiling": capability_ceiling,
        "opus_model": opus_models[0],
        "sonnet_model": sonnet_models[0],
        "codex_model": codex_models[0],
        "release_date": release_date,
        "provider_count": len(PUBLIC_EXTERNAL_PROVIDERS),
        "provider_names": human_join(tuple(item[0] for item in PUBLIC_EXTERNAL_PROVIDERS)),
        "provider_prerequisites": human_join(
            tuple(item[1] for item in PUBLIC_EXTERNAL_PROVIDERS)
        ),
    }


def sync_main_readme(text: str, facts: dict[str, object]) -> str:
    version = str(facts["version"])
    summary = str(facts["summary"])
    command_count = int(facts["command_count"])
    skill_count = int(facts["skill_count"])
    persona_count = int(facts["persona_count"])
    minimum = str(facts["minimum_version"])
    capability_count = int(facts["capability_count"])
    ceiling = str(facts["capability_ceiling"])
    opus = display_model(str(facts["opus_model"]))
    sonnet = display_model(str(facts["sonnet_model"]))
    codex = display_model(str(facts["codex_model"]))
    provider_count = int(facts["provider_count"])
    provider_names = str(facts["provider_names"])
    provider_word = number_word(provider_count)

    text = re.sub(r"Version-[0-9]+\.[0-9]+\.[0-9]+-blue", f"Version-{version}-blue", text)
    text = re.sub(r"Version [0-9]+\.[0-9]+\.[0-9]+", f"Version {version}", text)
    text = re.sub(
        r"Claude_Code-v[0-9]+\.[0-9]+\.[0-9]+\+_required",
        f"Claude_Code-v{minimum}+_required",
        text,
    )
    text = re.sub(
        r"Requires Claude Code v[0-9]+\.[0-9]+\.[0-9]+\+",
        f"Requires Claude Code v{minimum}+",
        text,
    )
    text = re.sub(
        r"\*\*\d+ specialized personas\*\*",
        f"**{persona_count} specialized personas**",
        text,
    )
    text = re.sub(r"\*\*\d+ commands\*\*", f"**{command_count} commands**", text)
    text = re.sub(r"\*\*\d+ skills\*\*", f"**{skill_count} skills**", text)
    text = re.sub(r"\[All \d+ skills\]", f"[All {skill_count} skills]", text)
    text = re.sub(
        r"^### \d+ Specialist Personas$",
        f"### {persona_count} Specialist Personas",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(r"\ball \d+ personas\b", f"all {persona_count} personas", text)
    text = re.sub(r"\bAll \d+ personas\b", f"All {persona_count} personas", text)
    text, category_count = re.subn(
        (
            r"^(?:"
            r"Categories: Software Engineering \(\d+\), "
            r"Specialized Development \(\d+\), "
            r"Documentation & Communication \(\d+\), "
            r"Research & Strategy \(\d+\), "
            r"Business & Compliance \(\d+\), "
            r"Creative & Design \(\d+\)"
            r"|Categories span Software Engineering, Specialized Development, "
            r"Documentation & Communication, Research & Strategy, "
            r"Business & Compliance, and Creative & Design"
            r")\.$"
        ),
        (
            "Categories span Software Engineering, Specialized Development, "
            "Documentation & Communication, Research & Strategy, "
            "Business & Compliance, and Creative & Design."
        ),
        text,
        flags=re.MULTILINE,
    )
    if category_count != 1:
        raise ValueError("README persona category summary is missing or duplicated")
    provider_intro = (
        f"Every AI model has blind spots. Claude Octopus supports {provider_word} external "
        f"provider integrations — {provider_names} — alongside the built-in Claude Code "
        "host, with consensus gates that flag disagreements before you ship."
    )
    text, provider_intro_count = re.subn(
        r"^Every AI model has blind spots\..*$",
        provider_intro,
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if provider_intro_count != 1:
        raise ValueError("main README provider introduction is missing")
    text = re.sub(
        r"with (?:[a-z]+|\d+) external providers checking the host's work",
        f"with {provider_word} external providers checking the host's work",
        text,
    )
    text = re.sub(
        r"up to \d+ external integrations cross-checking each other",
        f"up to {provider_count} external integrations cross-checking each other",
        text,
    )
    text, provider_row_count = re.subn(
        r"^\| \*\*Providers\*\* \| Claude only \| Claude only \|.*\|$",
        f"| **Providers** | Claude only | Claude only | Claude host; {provider_names} |",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if provider_row_count != 1:
        raise ValueError("README provider comparison row is missing or duplicated")
    text = re.sub(
        r"^### How \d+ External Providers Work Together$",
        f"### How {provider_count} External Providers Work Together",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"Claude Octopus coordinates (?:[a-z]+|\d+) external provider integrations alongside",
        f"Claude Octopus coordinates {provider_word} external provider integrations alongside",
        text,
    )
    text = re.sub(
        r"Adds up to (?:[a-z]+|\d+) external provider integrations\.",
        f"Adds up to {provider_word} external provider integrations.",
        text,
    )
    release_body = (
        f"> 🆕 **v{version} — {summary}.**\n"
        ">\n"
        f"> **Default roster:** {opus} leads architecture, planning, security reasoning, "
        f"and final judgment; {codex} is the independent implementation/review peer; "
        f"{sonnet} is the standard Claude seat; Fable 5.1 remains an opt-in judgment "
        "escalation. Existing model pins and provider configuration still win. "
        "See [the routing strategy](docs/MODEL-ROUTING-STRATEGY.md)."
    )
    text = replace_marker_block(
        text,
        CURRENT_RELEASE_START,
        CURRENT_RELEASE_END,
        release_body,
        "current release",
    )
    text, release_row_count = re.subn(
        r"^\| \*\*v[0-9]+\.[0-9]+\.[0-9]+\*\* \(new\) \|.*\|$",
        f"| **v{version}** (new) | {markdown_table_text(summary)}. |",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if release_row_count != 1:
        raise ValueError("current release table row is missing or duplicated")

    model_body = (
        f"- Current fresh configurations use **{codex}** for Codex implementation/review, "
        f"**{opus}** for premium Claude work, and **{sonnet}** for the standard Claude "
        "seat. Existing environment, session, and `providers.json` pins remain unchanged; "
        "`OCTOPUS_LEGACY_ROLES=1` restores the pre-frontier role mapping."
    )
    text = replace_marker_block(
        text,
        CURRENT_MODELS_START,
        CURRENT_MODELS_END,
        model_body,
        "current model defaults",
    )

    text = re.sub(
        r"\d+\+ (?:CC|Claude Code) (?:feature|capability) flags through v[0-9]+\.[0-9]+\.[0-9]+",
        f"{capability_count} Claude Code capability flags through v{ceiling}",
        text,
    )
    text = re.sub(
        (
            r"current plugin tracks(?: \d+ Claude Code capability flags| feature flags) "
            r"through \*\*Claude Code v[0-9]+\.[0-9]+\.[0-9]+\*\*"
        ),
        (
            f"current plugin tracks {capability_count} Claude Code capability flags "
            f"through **Claude Code v{ceiling}**"
        ),
        text,
    )
    text = re.sub(
        r"Claude Code \*\*v[0-9]+\.[0-9]+\.[0-9]+\+\*\* is the minimum supported runtime",
        f"Claude Code **v{minimum}+** is the minimum supported runtime",
        text,
    )
    return text


def sync_plugin_readme(text: str, facts: dict[str, object]) -> str:
    command_count = int(facts["command_count"])
    skill_count = int(facts["skill_count"])
    persona_count = int(facts["persona_count"])
    minimum = str(facts["minimum_version"])
    provider_count = int(facts["provider_count"])
    providers = str(facts["provider_names"])
    prerequisites = str(facts["provider_prerequisites"])

    provider_word = number_word(provider_count)
    first_paragraph = (
        f"**One prompt. Up to {provider_word} external AI integrations checking each "
        "other's work.** Claude Octopus turns Claude Code into a multi-LLM orchestration "
        f"engine — {providers} all contribute perspectives, then a 75% consensus gate "
        "catches disagreements before they ship."
    )
    text, count = re.subn(
        r"\*\*One prompt\..*?before they ship\.",
        first_paragraph,
        text,
        count=1,
        flags=re.DOTALL,
    )
    if count != 1:
        raise ValueError("plugin README provider introduction is missing")
    text = re.sub(r"\b\d+ commands\b", f"{command_count} commands", text)
    text = re.sub(r"\b\d+ skills\b", f"{skill_count} skills", text)
    text = re.sub(r"\b\d+ specialized personas\b", f"{persona_count} specialized personas", text)
    text = re.sub(r"\ball \d+ commands\b", f"all {command_count} commands", text)
    text = re.sub(
        r"\b\d+ specialized agents\b",
        f"{persona_count} specialized agents",
        text,
    )
    text = re.sub(
        r"Claude Code v[0-9]+\.[0-9]+\.[0-9]+\+",
        f"Claude Code v{minimum}+",
        text,
    )
    text, prerequisite_count = re.subn(
        r"^- Optional: .*$",
        f"- Optional: {prerequisites}",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if prerequisite_count != 1:
        raise ValueError("plugin README optional provider list is missing")
    return text


def sync_product(text: str, facts: dict[str, object]) -> str:
    version = str(facts["version"])
    command_count = int(facts["command_count"])
    skill_count = int(facts["skill_count"])
    persona_count = int(facts["persona_count"])
    capability_count = int(facts["capability_count"])
    ceiling = str(facts["capability_ceiling"])
    release_date = str(facts["release_date"])
    provider_count = int(facts["provider_count"])

    text = re.sub(r"^last_reviewed: [0-9-]+$", f"last_reviewed: {release_date}", text, flags=re.MULTILINE)
    text = re.sub(
        r"\bup to \d+ (?:AI models|AI CLIs|external AI integrations)\b",
        f"up to {provider_count} external AI integrations",
        text,
    )
    text = re.sub(
        r"\b\d+ slash commands, \d+ skills, (?:and )?\d+ specialized personas\b",
        f"{command_count} slash commands, {skill_count} skills, and {persona_count} specialized personas",
        text,
    )
    text = re.sub(
        r"\b\d+ (?:providers|external integrations) rarely agree\b",
        f"{provider_count} external integrations rarely agree",
        text,
    )
    text = re.sub(
        r"^- Version: [0-9]+\.[0-9]+\.[0-9]+ \(active release cadence\)$",
        f"- Version: {version} (active release cadence)",
        text,
        flags=re.MULTILINE,
    )
    text, traction_count = re.subn(
        r"^\*\*Traction \(as of [0-9-]+\):\*\*$",
        f"**Traction (as of {release_date}):**",
        text,
        flags=re.MULTILINE,
    )
    if traction_count != 1:
        raise ValueError("PRODUCT traction evidence heading is missing or duplicated")
    # Deliberately not a count. The suite totals were derived by globbing the
    # test tree and written here, which made every pair of test-adding PRs
    # conflict on this one line — and neither side of that conflict was ever
    # correct, only a regenerate was (see issue #729). The claim worth making is
    # that local and CI run the same suites, which is stable.
    text = re.sub(
        r"^- Local CI parity: .*$",
        "- Local CI parity: `make ci-local` runs the same smoke, unit, and integration suites as CI",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^- \d+\+ Claude Code feature flags tracked through v[0-9]+\.[0-9]+\.[0-9]+$",
        f"- {capability_count} Claude Code capability flags tracked through v{ceiling}",
        text,
        flags=re.MULTILINE,
    )
    return text


def sync_agent_catalog(text: str, facts: dict[str, object]) -> str:
    persona_count = int(facts["persona_count"])
    updated, count = re.subn(
        r"\b\d+ specialized personas\b",
        f"{persona_count} specialized personas",
        text,
    )
    if count != 1:
        raise ValueError("agent catalog persona count is missing or duplicated")
    return updated


def sync_command_reference(text: str, facts: dict[str, object]) -> str:
    command_count = int(facts["command_count"])
    updated, count = re.subn(
        r"Complete reference for all \d+ Claude Octopus slash commands",
        f"Complete reference for all {command_count} Claude Octopus slash commands",
        text,
    )
    if count != 1:
        raise ValueError("command reference count is missing or duplicated")
    return updated


def sync_docs_index(text: str, facts: dict[str, object]) -> str:
    command_count = int(facts["command_count"])
    persona_count = int(facts["persona_count"])
    droid_count = int(facts["droid_count"])
    updated, command_matches = re.subn(
        r"All \d+ slash commands",
        f"All {command_count} slash commands",
        text,
    )
    updated, agent_matches = re.subn(
        r"\d+ persona agents and \d+ native agents",
        f"{persona_count} persona agents and {droid_count} native agents",
        updated,
    )
    if command_matches != 1 or agent_matches != 1:
        raise ValueError("docs index count surface is missing or duplicated")
    return updated


def sync_plugin_manifest(text: str, facts: dict[str, object]) -> str:
    data = json.loads(text)
    command_count = int(facts["command_count"])
    skill_count = int(facts["skill_count"])
    persona_count = int(facts["persona_count"])
    droid_count = int(facts["droid_count"])
    components = data.setdefault("components", {})
    components.setdefault("commands", {})["count"] = command_count
    agents = components.setdefault("agents", {})
    agents["count"] = persona_count + droid_count
    breakdown = agents.setdefault("breakdown", {})
    breakdown["personas"] = persona_count
    breakdown["droids"] = droid_count
    components.setdefault("skills", {})["count"] = skill_count
    return json.dumps(data, indent=2) + "\n"


def sync_component_counts(text: str, facts: dict[str, object]) -> str:
    command_count = int(facts["command_count"])
    skill_count = int(facts["skill_count"])
    persona_count = int(facts["persona_count"])
    updated, count = re.subn(
        r"\b\d+ (expert )?personas, \d+ commands, \d+ skills\b",
        lambda match: (
            f"{persona_count} "
            f"{'expert ' if match.group(1) else ''}"
            f"personas, {command_count} commands, {skill_count} skills"
        ),
        text,
    )
    if count != 1:
        raise ValueError("component count phrase is missing or duplicated")
    return updated


def main() -> int:
    args = parse_args()
    root = args.root.resolve()

    try:
        facts = derive_facts(root)
        transforms = {
            root / "README.md": sync_main_readme,
            root / ".claude-plugin/README.md": sync_plugin_readme,
            root / "PRODUCT.md": sync_product,
            root / "docs/AGENTS.md": sync_agent_catalog,
            root / "docs/COMMAND-REFERENCE.md": sync_command_reference,
            root / "docs/README.md": sync_docs_index,
            root / ".claude-plugin/plugin-manifest.json": sync_plugin_manifest,
            root / ".codex-plugin/plugin.json": sync_component_counts,
            root / ".factory-plugin/plugin.json": sync_component_counts,
            root / ".factory-plugin/marketplace.json": sync_component_counts,
        }
        drifted: list[Path] = []
        updates: dict[Path, str] = {}
        for path, transform in transforms.items():
            original = path.read_text()
            expected = transform(original, facts)
            if expected != original:
                drifted.append(path)
                updates[path] = expected
    except (FileNotFoundError, KeyError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: README sync failed: {exc}", file=sys.stderr)
        return 1

    if args.check:
        if drifted:
            for path in drifted:
                print(f"STALE: {path.relative_to(root)}", file=sys.stderr)
            print("Run ./scripts/sync-readme.py", file=sys.stderr)
            return 1
        print(
            "OK: README release facts are synchronized "
            f"(v{facts['version']}, {facts['capability_count']} capabilities through "
            f"v{facts['capability_ceiling']})"
        )
        return 0

    for path, expected in updates.items():
        path.write_text(expected)
        print(f"UPDATED: {path.relative_to(root)}")
    if not updates:
        print("OK: README release facts already synchronized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
