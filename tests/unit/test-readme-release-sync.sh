#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "README Release Sync"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-readme.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-readme-sync-test.XXXXXX")"
CURRENT_VERSION="$(jq -r '.version' "$PROJECT_ROOT/.claude-plugin/plugin.json")"
CURRENT_COMMAND_COUNT="$(jq '.commands | length' "$PROJECT_ROOT/.claude-plugin/plugin.json")"
CURRENT_SKILL_COUNT="$(jq '.skills | length' "$PROJECT_ROOT/.claude-plugin/plugin.json")"
CURRENT_PERSONA_COUNT="$(find "$PROJECT_ROOT/agents/personas" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
CURRENT_DROID_COUNT="$(find "$PROJECT_ROOT/agents/droids" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
CURRENT_AGENT_COUNT="$((CURRENT_PERSONA_COUNT + CURRENT_DROID_COUNT))"
CURRENT_RELEASE_DATE="$(awk -v version="$CURRENT_VERSION" '
    $1 == "##" && $2 == "[" version "]" && $3 == "-" { print $4; exit }
' "$PROJECT_ROOT/CHANGELOG.md")"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

make_fixture() {
    local root="$1"

    mkdir -p \
        "$root/.claude-plugin" \
        "$root/.codex-plugin" \
        "$root/.factory-plugin" \
        "$root/docs" \
        "$root/agents/droids" \
        "$root/agents/personas" \
        "$root/scripts/lib" \
        "$root/tests/smoke" \
        "$root/tests/unit" \
        "$root/tests/integration"

    cp "$PROJECT_ROOT/README.md" "$root/README.md"
    cp "$PROJECT_ROOT/PRODUCT.md" "$root/PRODUCT.md"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$root/CHANGELOG.md"
    cp "$PROJECT_ROOT/.claude-plugin/plugin.json" "$root/.claude-plugin/plugin.json"
    cp "$PROJECT_ROOT/.claude-plugin/plugin-manifest.json" "$root/.claude-plugin/plugin-manifest.json"
    cp "$PROJECT_ROOT/.claude-plugin/README.md" "$root/.claude-plugin/README.md"
    cp "$PROJECT_ROOT/.codex-plugin/plugin.json" "$root/.codex-plugin/plugin.json"
    cp "$PROJECT_ROOT/.factory-plugin/plugin.json" "$root/.factory-plugin/plugin.json"
    cp "$PROJECT_ROOT/.factory-plugin/marketplace.json" "$root/.factory-plugin/marketplace.json"
    cp "$PROJECT_ROOT/docs/AGENTS.md" "$root/docs/AGENTS.md"
    cp "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md" "$root/docs/COMMAND-REFERENCE.md"
    cp "$PROJECT_ROOT/docs/README.md" "$root/docs/README.md"
    cp "$PROJECT_ROOT/scripts/orchestrate.sh" "$root/scripts/orchestrate.sh"
    cp "$PROJECT_ROOT/scripts/lib/model-resolver.sh" "$root/scripts/lib/model-resolver.sh"
    cp "$PROJECT_ROOT/scripts/lib/providers.sh" "$root/scripts/lib/providers.sh"
    cp "$PROJECT_ROOT/agents/personas/"*.md "$root/agents/personas/"
    cp "$PROJECT_ROOT/agents/droids/"*.md "$root/agents/droids/"
    local category test_file
    for category in smoke unit integration; do
        for test_file in "$PROJECT_ROOT/tests/$category"/test-*.sh; do
            : > "$root/tests/$category/$(basename "$test_file")"
        done
    done
}

if [[ -x "$SYNC_SCRIPT" ]]; then
    test_case "sync-readme.py exists and is executable"
    test_pass
else
    test_case "sync-readme.py exists and is executable"
    test_fail "missing executable README sync helper"
fi

test_case "tracked README surfaces are synchronized"
if "$SYNC_SCRIPT" --check >/tmp/octo-readme-sync-check.out 2>&1; then
    test_pass
else
    test_fail "README sync check failed: $(cat /tmp/octo-readme-sync-check.out 2>/dev/null)"
fi

fixture="$TMP_DIR/fixture"
make_fixture "$fixture"

python3 - "$fixture" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
readme = root / "README.md"
text = readme.read_text()
text = re.sub(r"Version-\d+\.\d+\.\d+-blue", "Version-0.0.0-blue", text)
text = re.sub(r"Version \d+\.\d+\.\d+", "Version 0.0.0", text)
text = text.replace(
    "supports twelve external provider integrations",
    "supports eight external provider integrations",
    1,
)
text = text.replace(
    "<!-- BEGIN CURRENT RELEASE -->",
    "<!-- BEGIN CURRENT RELEASE -->\n> stale release copy",
    1,
)
text = re.sub(
    r"current plugin tracks \d+ Claude Code capability flags through "
    r"\*\*Claude Code v\d+\.\d+\.\d+\*\*",
    "current plugin tracks feature flags through **Claude Code v2.1.157**",
    text,
)
readme.write_text(text)

plugin_readme = root / ".claude-plugin/README.md"
plugin_text = plugin_readme.read_text()
plugin_text = re.sub(
    r"^- Optional: .*$",
    "- Optional: Codex CLI and Gemini CLI",
    plugin_text,
    count=1,
    flags=re.MULTILINE,
)
plugin_readme.write_text(plugin_text)

product = root / "PRODUCT.md"
product_text = product.read_text()
product_text = product_text.replace(
    "up to 12 external AI integrations",
    "up to 8 AI CLIs",
)
# Any historical count line must normalise back to the stable phrase, so an
# existing checkout converges on sync instead of carrying a stale number.
product_text = re.sub(
    r"Local CI parity: .*",
    "Local CI parity: 3 smoke, 7 unit, and 2 integration suites",
    product_text,
)
product_text = re.sub(
    r"\*\*Traction \(as of [0-9-]+\):\*\*",
    "**Traction (as of 1999-01-01):**",
    product_text,
)
product_text = re.sub(
    r"\d+ slash commands, \d+ skills, and \d+ specialized personas",
    "999 slash commands, 999 skills, and 999 specialized personas",
    product_text,
)
product.write_text(product_text)

for relative_path in (
    "docs/AGENTS.md",
    "docs/COMMAND-REFERENCE.md",
    "docs/README.md",
    ".codex-plugin/plugin.json",
    ".factory-plugin/plugin.json",
    ".factory-plugin/marketplace.json",
):
    path = root / relative_path
    surface_text = path.read_text()
    surface_text = re.sub(
        r"\b\d+ (expert )?personas, \d+ commands, \d+ skills\b",
        lambda match: f"999 {'expert ' if match.group(1) else ''}personas, 999 commands, 999 skills",
        surface_text,
    )
    surface_text = re.sub(
        r"\b\d+ specialized personas\b",
        "999 specialized personas",
        surface_text,
        count=1,
    )
    surface_text = re.sub(
        r"Complete reference for all \d+ Claude Octopus slash commands",
        "Complete reference for all 999 Claude Octopus slash commands",
        surface_text,
        count=1,
    )
    surface_text = re.sub(
        r"All \d+ slash commands",
        "All 999 slash commands",
        surface_text,
        count=1,
    )
    surface_text = re.sub(
        r"\d+ persona agents and \d+ native agents",
        "999 persona agents and 999 native agents",
        surface_text,
        count=1,
    )
    path.write_text(surface_text)

manifest = root / ".claude-plugin/plugin-manifest.json"
manifest_text = manifest.read_text()
manifest_text = re.sub(r'("count": )\d+', r'\g<1>999', manifest_text)
manifest_text = re.sub(r'("personas": )\d+', r'\g<1>999', manifest_text)
manifest_text = re.sub(r'("droids": )\d+', r'\g<1>999', manifest_text)
manifest.write_text(manifest_text)

plugin_text = plugin_readme.read_text()
plugin_text = re.sub(
    r"\b\d+ specialized agents\b",
    "999 specialized agents",
    plugin_text,
)
plugin_readme.write_text(plugin_text)

readme_text = readme.read_text()
readme_text = re.sub(
    r"^### \d+ Specialist Personas$",
    "### 999 Specialist Personas",
    readme_text,
    flags=re.MULTILINE,
)
readme_text = re.sub(r"\ball \d+ personas\b", "all 999 personas", readme_text)
readme_text = re.sub(r"\bAll \d+ personas\b", "All 999 personas", readme_text)
readme.write_text(readme_text)
PY

test_case "--check rejects deliberately stale README facts"
if "$SYNC_SCRIPT" --root "$fixture" --check >/tmp/octo-readme-sync-stale.out 2>&1; then
    test_fail "stale fixture unexpectedly passed"
else
    test_pass
fi

test_case "sync rejects missing or duplicate PRODUCT traction headings"
traction_validation_ok=true
for variant in missing duplicate; do
    traction_fixture="$TMP_DIR/traction-$variant"
    make_fixture "$traction_fixture"
    python3 - "$traction_fixture/PRODUCT.md" "$variant" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
variant = sys.argv[2]
text = path.read_text()
pattern = r"^\*\*Traction \(as of [0-9-]+\):\*\*$"
match = re.search(pattern, text, flags=re.MULTILINE)
if match is None:
    raise SystemExit("fixture has no traction heading")
if variant == "missing":
    text = text[:match.start()] + text[match.end():]
else:
    text = text[:match.end()] + "\n" + match.group(0) + text[match.end():]
path.write_text(text)
PY
    traction_output="$TMP_DIR/traction-$variant.out"
    if "$SYNC_SCRIPT" --root "$traction_fixture" >"$traction_output" 2>&1 ||
       ! grep -qF 'PRODUCT traction evidence heading is missing or duplicated' "$traction_output"; then
        traction_validation_ok=false
    fi
done
if $traction_validation_ok; then
    test_pass
else
    test_fail "sync accepted a missing or duplicate PRODUCT traction heading"
fi

test_case "sync rejects duplicate singleton count surfaces"
duplicate_validation_ok=true
for variant in agent-catalog component-metadata; do
    duplicate_fixture="$TMP_DIR/duplicate-$variant"
    make_fixture "$duplicate_fixture"
    if [[ "$variant" == "agent-catalog" ]]; then
        line="$(grep -m1 'specialized personas' "$duplicate_fixture/docs/AGENTS.md")"
        printf '%s\n' "$line" >>"$duplicate_fixture/docs/AGENTS.md"
    else
        phrase="$(grep -oE '[0-9]+ personas, [0-9]+ commands, [0-9]+ skills' "$duplicate_fixture/.codex-plugin/plugin.json")"
        python3 - "$duplicate_fixture/.codex-plugin/plugin.json" "$phrase" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
phrase = sys.argv[2]
text = path.read_text()
path.write_text(text.replace(phrase, f"{phrase}; {phrase}", 1))
PY
    fi
    duplicate_output="$TMP_DIR/duplicate-$variant.out"
    if "$SYNC_SCRIPT" --root "$duplicate_fixture" >"$duplicate_output" 2>&1; then
        duplicate_validation_ok=false
    fi
done
if $duplicate_validation_ok; then
    test_pass
else
    test_fail "sync accepted a duplicated singleton count surface"
fi

test_case "sync repairs release, model, count, and capability facts"
if "$SYNC_SCRIPT" --root "$fixture" >/tmp/octo-readme-sync-update.out 2>&1 &&
   "$SYNC_SCRIPT" --root "$fixture" --check >/tmp/octo-readme-sync-recheck.out 2>&1 &&
   grep -q "Version-${CURRENT_VERSION}-blue" "$fixture/README.md" &&
   grep -q "v${CURRENT_VERSION}.*(new)" "$fixture/README.md" &&
   grep -q 'supports twelve external provider integrations.*Cursor CLI.*Kimi Code' "$fixture/README.md" &&
   grep -qF '| **v9** | Up to 10 external provider integrations (Codex, Antigravity CLI, Copilot, Qwen, Ollama, Perplexity, OpenRouter, OrcaRouter, OpenCode, and Grok)' "$fixture/README.md" &&
   grep -q 'OrcaRouter' "$fixture/README.md" &&
   grep -q 'GPT-5.6 Sol' "$fixture/README.md" &&
   grep -q 'Claude Opus 5' "$fixture/README.md" &&
   grep -q 'Claude Sonnet 5' "$fixture/README.md" &&
   grep -qE '[0-9]+ Claude Code capability flags through.*v[0-9]+\.[0-9]+\.[0-9]+' "$fixture/README.md" &&
   grep -q 'OpenCode CLI, Cursor CLI (`agent`), xAI API key (Grok), and Kimi Code CLI' "$fixture/.claude-plugin/README.md" &&
   grep -q 'OrcaRouter' "$fixture/.claude-plugin/README.md" &&
   grep -q "all ${CURRENT_COMMAND_COUNT} commands" "$fixture/.claude-plugin/README.md" &&
   grep -q "${CURRENT_PERSONA_COUNT} specialized agents" "$fixture/.claude-plugin/README.md" &&
   grep -q 'up to 12 external AI integrations' "$fixture/PRODUCT.md" &&
   grep -q "${CURRENT_COMMAND_COUNT} slash commands, ${CURRENT_SKILL_COUNT} skills, and ${CURRENT_PERSONA_COUNT} specialized personas" "$fixture/PRODUCT.md" &&
   grep -q "Complete reference for all ${CURRENT_COMMAND_COUNT} Claude Octopus slash commands" "$fixture/docs/COMMAND-REFERENCE.md" &&
   grep -q "All ${CURRENT_COMMAND_COUNT} slash commands" "$fixture/docs/README.md" &&
   grep -q "${CURRENT_PERSONA_COUNT} persona agents and ${CURRENT_DROID_COUNT} native agents" "$fixture/docs/README.md" &&
   grep -q "${CURRENT_PERSONA_COUNT} specialized personas" "$fixture/docs/AGENTS.md" &&
   grep -q "### ${CURRENT_PERSONA_COUNT} Specialist Personas" "$fixture/README.md" &&
   grep -q "all ${CURRENT_PERSONA_COUNT} personas" "$fixture/README.md" &&
   grep -q "All ${CURRENT_PERSONA_COUNT} personas" "$fixture/README.md" &&
   grep -q 'Categories span Software Engineering, Specialized Development, Documentation & Communication, Research & Strategy, Business & Compliance, and Creative & Design\.' "$fixture/README.md" &&
   ! grep -qE '^Categories: .*\([0-9]+\)' "$fixture/README.md" &&
   jq -e --argjson commands "$CURRENT_COMMAND_COUNT" \
      --argjson agents "$CURRENT_AGENT_COUNT" \
      --argjson personas "$CURRENT_PERSONA_COUNT" \
      --argjson droids "$CURRENT_DROID_COUNT" \
      --argjson skills "$CURRENT_SKILL_COUNT" \
      '.components.commands.count == $commands and
       .components.agents.count == $agents and
       .components.agents.breakdown.personas == $personas and
       .components.agents.breakdown.droids == $droids and
       .components.skills.count == $skills' \
      "$fixture/.claude-plugin/plugin-manifest.json" >/dev/null &&
   grep -q "${CURRENT_PERSONA_COUNT} personas, ${CURRENT_COMMAND_COUNT} commands, ${CURRENT_SKILL_COUNT} skills" "$fixture/.codex-plugin/plugin.json" &&
   grep -q "${CURRENT_PERSONA_COUNT} expert personas, ${CURRENT_COMMAND_COUNT} commands, ${CURRENT_SKILL_COUNT} skills" "$fixture/.factory-plugin/plugin.json" &&
   grep -q "${CURRENT_PERSONA_COUNT} personas, ${CURRENT_COMMAND_COUNT} commands, ${CURRENT_SKILL_COUNT} skills" "$fixture/.factory-plugin/marketplace.json" &&
   grep -qF "**Traction (as of ${CURRENT_RELEASE_DATE}):**" "$fixture/PRODUCT.md" &&
   grep -qF 'Local CI parity: `make ci-local` runs the same smoke, unit, and integration suites as CI' "$fixture/PRODUCT.md" &&
   ! grep -qE 'Local CI parity: [0-9]+ smoke' "$fixture/PRODUCT.md" &&
   ! grep -qE 'Version-0\.0\.0-blue|stale release copy|v2\.1\.157' "$fixture/README.md"; then
    test_pass
else
    test_fail "sync did not restore the expected README facts"
fi

test_case "release workflow regenerates and stages synchronized docs"
release_commit_block="$(sed -n '/^echo "2\/8 Committing\.\.\."/,/^git commit /p' "$PROJECT_ROOT/scripts/release.sh")"
changelog_line="$(grep -n '^octo_release_update_changelog ' "$PROJECT_ROOT/scripts/release.sh" | cut -d: -f1)"
sync_line="$(grep -n '^make sync$' "$PROJECT_ROOT/scripts/release.sh" | cut -d: -f1)"
if grep -q 'scripts/sync-readme.py' "$PROJECT_ROOT/Makefile" &&
   grep -q 'scripts/sync-readme.py --check' "$PROJECT_ROOT/Makefile" &&
   grep -q 'PRODUCT.md' <<<"$release_commit_block" &&
   grep -q 'README.md' <<<"$release_commit_block" &&
   grep -q 'docs/AGENTS.md' <<<"$release_commit_block" &&
   grep -q 'docs/COMMAND-REFERENCE.md' <<<"$release_commit_block" &&
   grep -q 'docs/README.md' <<<"$release_commit_block" &&
   grep -q '\.claude-plugin/README.md' <<<"$release_commit_block" &&
   grep -q '\.claude-plugin/plugin-manifest.json' <<<"$release_commit_block" &&
   grep -q '\.codex-plugin/plugin.json' <<<"$release_commit_block" &&
   grep -q '\.factory-plugin/plugin.json' <<<"$release_commit_block" &&
   grep -q '\.factory-plugin/marketplace.json' <<<"$release_commit_block" &&
   [[ -n "$changelog_line" && -n "$sync_line" && "$changelog_line" -lt "$sync_line" ]]; then
    test_pass
else
    test_fail "release workflow does not regenerate and stage every synchronized doc surface"
fi

test_case "release guide documents every synchronized count surface"
release_guide_ok=true
for surface in \
    README.md \
    .claude-plugin/README.md \
    PRODUCT.md \
    docs/AGENTS.md \
    docs/COMMAND-REFERENCE.md \
    docs/README.md \
    .claude-plugin/plugin-manifest.json \
    .codex-plugin/plugin.json \
    .factory-plugin/plugin.json \
    .factory-plugin/marketplace.json; do
    if ! grep -qF "$surface" "$PROJECT_ROOT/RELEASING.md"; then
        release_guide_ok=false
    fi
done
if $release_guide_ok &&
   ! grep -qE '"[0-9]+ personas, N commands, N skills"' "$PROJECT_ROOT/RELEASING.md"; then
    test_pass
else
    test_fail "RELEASING.md omits a synchronized surface or hard-codes a persona count"
fi

test_case "public agent guidance omits private handoff files"
if [[ ! -e "$PROJECT_ROOT/AI_AGENT_HANDOFF.md" &&
      ! -e "$PROJECT_ROOT/RTK.md" &&
      ! -e "$PROJECT_ROOT/GOALS.md" ]] &&
   grep -q 'scripts/sync-readme.py.*owns' "$PROJECT_ROOT/AGENTS.md" &&
   grep -q 'scripts/sync-readme.py' "$PROJECT_ROOT/CLAUDE.md" &&
   grep -Eq 'make[[:space:]]+sync([^[:alnum:]_-]|$)' "$PROJECT_ROOT/AGENTS.md" &&
   grep -Eq 'make[[:space:]]+sync([^[:alnum:]_-]|$)' "$PROJECT_ROOT/CLAUDE.md"; then
    test_pass
else
    test_fail "private handoff files remain or public agent guidance lost the README contract"
fi

test_case "current model configuration guidance uses the frontier roster"
if grep -q 'gpt-5.6-sol' "$PROJECT_ROOT/commands/model-config.md" &&
   grep -q 'gpt-5.6-terra' "$PROJECT_ROOT/commands/model-config.md" &&
   grep -q 'gpt-5.6-luna' "$PROJECT_ROOT/commands/model-config.md" &&
   ! grep -qE 'GPT-5\.4|gpt-5\.4' "$PROJECT_ROOT/commands/model-config.md"; then
    test_pass
else
    test_fail "model-config command still presents pre-GPT-5.6 defaults"
fi

test_case "public documentation names all twelve external integrations"
if grep -q 'twelve external provider integrations' "$PROJECT_ROOT/README.md" &&
   grep -q '| .*OrcaRouter' "$PROJECT_ROOT/README.md" &&
   grep -q '| .*Kimi Code' "$PROJECT_ROOT/README.md" &&
   grep -q '| .*Cursor CLI' "$PROJECT_ROOT/README.md" &&
   grep -q 'Up to twelve external AI integrations' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'OrcaRouter' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'Cursor CLI' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'Grok' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'Kimi Code' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'twelve external AI integrations' "$PROJECT_ROOT/docs/ARCHITECTURE.md" &&
   grep -q '| .*OrcaRouter' "$PROJECT_ROOT/docs/ARCHITECTURE.md" &&
   grep -q '| .*Cursor CLI' "$PROJECT_ROOT/docs/ARCHITECTURE.md" &&
   grep -q '| .*Kimi Code' "$PROJECT_ROOT/docs/ARCHITECTURE.md"; then
    test_pass
else
    test_fail "provider count/list differs across public documentation"
fi

test_summary
