#!/usr/bin/env bash
# SubagentStop Gate — Quality scoring, provider attribution, cost logging, and
# council verdict pre-screening before a subagent's summary reaches the lead.
#
# Runs AFTER subagent-result-capture.sh in the SubagentStop chain (v9.50.0).
# Responsibilities:
#   1. Provider attribution — map agent_type to an Octopus provider name
#   2. Quality score — cheap 0-100 heuristic (length + error markers)
#   3. Cost logging — append a JSONL usage record for /octo:usage aggregation
#   4. Council verdict pre-screen — flag malformed verdict blocks before they
#      reach the lead; blocks only when OCTOPUS_SUBAGENT_GATE_STRICT=true
#
# Hook event: SubagentStop
# Env knobs:
#   OCTOPUS_SUBAGENT_GATE_STRICT   (default false) — block on gate failures
#   OCTOPUS_SUBAGENT_MIN_QUALITY   (default 0)     — quality floor, 0 disables
# Returns: exit 0 with no output (allow), or {"decision":"block","reason":...}

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}"
USAGE_DIR="${WORKSPACE_DIR}/usage"

# Guard: python3 required for JSON parsing
if ! command -v python3 &>/dev/null; then
    exit 0
fi

# Read hook input from stdin
if [ -t 0 ]; then exit 0; fi
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && exit 0

# Single python pass: parse payload, score, attribute, log, and pre-screen.
# Emits either nothing (allow) or a block-decision JSON on stdout.
_OCTOPUS_INPUT="$INPUT" \
_OCTOPUS_USAGE_DIR="$USAGE_DIR" \
_OCTOPUS_GATE_STRICT="${OCTOPUS_SUBAGENT_GATE_STRICT:-false}" \
_OCTOPUS_MIN_QUALITY="${OCTOPUS_SUBAGENT_MIN_QUALITY:-0}" \
_OCTOPUS_PHASE="${OCTOPUS_WORKFLOW_PHASE:-}" \
_OCTOPUS_SKILL="${OCTOPUS_ACTIVE_SKILL:-}" \
python3 - <<'PYEOF' 2>/dev/null || exit 0
import json, os, re, sys, time

try:
    d = json.loads(os.environ.get("_OCTOPUS_INPUT", "") or "{}")
except Exception:
    sys.exit(0)

msg = d.get("last_assistant_message", "") or ""
agent_id = d.get("agent_id", "") or ""
agent_type = (d.get("agent_type", "") or "").lower()

# --- 1. Provider attribution ---------------------------------------------
PROVIDER_PREFIXES = [
    ("codex", "codex"), ("gemini", "gemini"), ("agy", "agy"),
    ("antigravity", "agy"), ("claude-sdk", "claude-sdk"),
    ("claude", "claude"), ("openrouter", "openrouter"),
    ("atlascloud", "atlascloud"), ("openai-", "openai-compatible-agent"),
    ("perplexity", "perplexity"), ("qwen", "qwen"),
    ("cursor-agent", "cursor-agent"), ("grok", "grok"),
    ("opencode", "opencode"), ("ollama", "ollama"),
    ("copilot", "copilot"), ("vibe", "vibe"),
]
provider = "claude"  # native subagents default to Claude
for prefix, name in PROVIDER_PREFIXES:
    if agent_type.startswith(prefix):
        provider = name
        break

# --- 2. Quality score (0-100 heuristic) ----------------------------------
# Length component: 0 chars -> 0, 400+ chars -> 60. Error markers subtract.
score = min(60, len(msg) // 7 if msg else 0)
if re.search(r"^#+\s|\n[-*]\s|```", msg):
    score += 20  # structured output (headings, lists, code blocks)
if re.search(r"\b(SUCCESS|PASS|complete[d]?|verified)\b", msg, re.I):
    score += 20
for marker in ("Traceback", "command not found", "Permission denied",
               "FATAL", "rate limit", "ETIMEDOUT"):
    if marker in msg:
        score -= 25
score = max(0, min(100, score))

# --- 3. Cost logging (JSONL for /octo:usage) ------------------------------
est_tokens = max(1, len(msg) // 4) if msg else 0
record = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "source": "subagent-stop-gate",
    "agent_id": agent_id,
    "agent_type": agent_type,
    "provider": provider,
    "skill": os.environ.get("_OCTOPUS_SKILL", ""),
    "phase": os.environ.get("_OCTOPUS_PHASE", ""),
    "chars_out": len(msg),
    "est_tokens_out": est_tokens,
    "quality": score,
}
usage_dir = os.environ.get("_OCTOPUS_USAGE_DIR", "")
if usage_dir:
    try:
        os.makedirs(usage_dir, exist_ok=True)
        with open(os.path.join(usage_dir, "subagent-usage.jsonl"), "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass

# --- 4. Council verdict pre-screen + quality floor ------------------------
strict = os.environ.get("_OCTOPUS_GATE_STRICT", "false") == "true"
try:
    min_quality = int(os.environ.get("_OCTOPUS_MIN_QUALITY", "0"))
except ValueError:
    min_quality = 0

reasons = []
has_verdict_block = bool(re.search(r"(^|\n)#{0,3}\s*Verdict\b|VERDICT\s*:", msg, re.I))
if has_verdict_block:
    valid = re.search(
        r"\b(APPROVE[D]?|REJECT[ED]?|ABSTAIN|REVISE|BLOCK|PASS|FAIL)\b", msg)
    if not valid:
        reasons.append(
            "council verdict block present but no recognizable verdict token "
            "(APPROVE/REJECT/ABSTAIN/REVISE/BLOCK/PASS/FAIL)")
if min_quality > 0 and score < min_quality:
    reasons.append(f"quality score {score} below floor {min_quality}")

if reasons and strict:
    print(json.dumps({
        "decision": "block",
        "reason": "subagent-stop-gate [{}]: {}".format(provider, "; ".join(reasons)),
    }))
PYEOF

exit 0
