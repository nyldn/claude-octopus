#!/usr/bin/env bash
# Unit tests for progressive feature disclosure (manifest + consent ledger).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Feature disclosure"

FEATURES_LIB="$PROJECT_ROOT/scripts/lib/features.sh"
MANIFEST="$PROJECT_ROOT/config/features.json"

# Isolate the ledger. Without this every assertion below reads the developer's
# real ~/.claude-octopus/state.json and the suite passes or fails according to
# which features they happen to have enabled.
export OCTOPUS_STATE_DIR="$TEST_TMP_DIR/feature-state"
mkdir -p "$OCTOPUS_STATE_DIR"

reset_ledger() {
    rm -rf "$OCTOPUS_STATE_DIR"
    mkdir -p "$OCTOPUS_STATE_DIR"
    printf '%s\n' "${1:-\{\}}" > "$OCTOPUS_STATE_DIR/state.json"
}

test_case "features.sh has valid bash syntax"
if bash -n "$FEATURES_LIB"; then
    test_pass
else
    test_fail "features.sh has syntax errors"
fi

test_case "manifest is valid JSON with a features array"
if jq -e '.features | type == "array" and length > 0' "$MANIFEST" >/dev/null; then
    test_pass
else
    test_fail "config/features.json is not a non-empty features array"
fi

test_case "every manifest entry declares the required fields"
missing=$(jq -r '
    .features[]
    | select((.id? | not) or (.added_in? | not) or (.key? | not)
             or (.title? | not) or (.description? | not) or (.prereq? | not))
    | .id // "<no id>"' "$MANIFEST")
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "manifest entries missing required fields: $missing"
fi

# Manifest/reality drift guard: a feature whose env key was renamed would
# silently set a variable nothing reads. Every declared key must appear in the
# codebase outside the manifest itself.
test_case "every manifest env key appears in the codebase"
orphans=""
while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if ! grep -rq --include="*.sh" --include="*.md" -- "$key" \
        "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/hooks" "$PROJECT_ROOT/commands" 2>/dev/null; then
        orphans="$orphans $key"
    fi
done < <(jq -r '.features[].key' "$MANIFEST")
if [[ -z "$orphans" ]]; then
    test_pass
else
    test_fail "manifest keys not referenced anywhere:$orphans"
fi

test_case "every manifest prereq resolves to a real check"
bad=""
while IFS= read -r prereq; do
    [[ -n "$prereq" ]] || continue
    if ! bash -c "source '$FEATURES_LIB'; octo_features_prereq_ok '$prereq'" >/dev/null 2>&1; then
        # A prereq can legitimately fail (CLI absent). Distinguish "unknown
        # check" from "check ran and said no" by probing the case arm directly.
        if ! grep -q "^        ${prereq})" "$FEATURES_LIB" \
           && ! grep -q "^        [a-z|-]*${prereq}[a-z|-]*)" "$FEATURES_LIB"; then
            bad="$bad $prereq"
        fi
    fi
done < <(jq -r '.features[].prereq' "$MANIFEST")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "manifest prereqs with no matching check:$bad"
fi

test_case "unknown prereq fails closed"
if bash -c "source '$FEATURES_LIB'; octo_features_prereq_ok 'no-such-check'" 2>/dev/null; then
    test_fail "unknown prereq should fail closed, not open"
else
    test_pass
fi

test_case "manifest resolves when sourced from an unrelated cwd"
resolved=$(cd / && bash -c "source '$FEATURES_LIB'; octo_features_manifest")
if [[ "$resolved" == "$MANIFEST" ]]; then
    test_pass
else
    test_fail "expected $MANIFEST, resolved $resolved"
fi

# CLAUDE_PLUGIN_ROOT frequently points at a stale plugin cache directory for an
# uninstalled version. Disclosure must fall back rather than go silently dead.
test_case "stale CLAUDE_PLUGIN_ROOT falls back to the repo manifest"
resolved=$(CLAUDE_PLUGIN_ROOT="$TEST_TMP_DIR/does-not-exist-9.0.0" \
    bash -c "source '$FEATURES_LIB'; octo_features_manifest")
if [[ "$resolved" == "$MANIFEST" ]]; then
    test_pass
else
    test_fail "stale plugin root should fall back; got $resolved"
fi

test_case "watermark seeds from the pre-existing last_seen_version"
reset_ledger '{"last_seen_version":"9.55.0","model_defaults_v2":"accepted"}'
w=$(bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_watermark")
if [[ "$w" == "9.55.0" ]]; then
    test_pass
else
    test_fail "expected watermark 9.55.0, got '$w'"
fi

test_case "seeding preserves the model_defaults_v2 consent record"
if jq -e '.model_defaults_v2 == "accepted"' "$OCTOPUS_STATE_DIR/state.json" >/dev/null; then
    test_pass
else
    test_fail "seeding the watermark must not disturb existing consent records"
fi

# Backfill bounds the launch offer. Features that predate the watermark must not
# be offered, or every upgrading user is handed the entire history at once.
test_case "only backfill entries and post-watermark features are offered"
reset_ledger '{"last_seen_version":"9.55.0"}'
ids=$(bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_offerable_ids" | sort | tr '\n' ' ')
expected=$(jq -r '.features[] | select(.backfill == true) | .id' "$MANIFEST" | sort | tr '\n' ' ')
if [[ "$ids" == "$expected" ]]; then
    test_pass
else
    test_fail "offered [$ids], expected backfill set [$expected]"
fi

test_case "a pre-watermark feature is never offered"
reset_ledger '{"last_seen_version":"9.55.0"}'
ids=$(bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_offerable_ids")
if ! grep -qx "gemini-via-agy" <<< "$ids"; then
    test_pass
else
    test_fail "gemini-via-agy (added 9.52.0) is below the 9.55.0 watermark and must not be offered"
fi

test_case "declined is sticky across repeated sessions"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record fable5-escalation declined 9.57.0
    for _ in 1 2 3; do octo_features_offerable_ids; done
")
if ! grep -qx "fable5-escalation" <<< "$out"; then
    test_pass
else
    test_fail "a declined feature must never be re-offered"
fi

test_case "enabled feature drops off the offer list and reads back enabled"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record codex-reviewer-flip enabled 9.57.0
    octo_features_offerable_ids
    octo_features_enabled codex-reviewer-flip && echo ENABLED
")
if grep -qx "ENABLED" <<< "$out" && ! grep -qx "codex-reviewer-flip" <<< "$out"; then
    test_pass
else
    test_fail "enabling must record consent and stop the offer"
fi

test_case "disabled is distinct from declined and also suppresses offers"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record codex-reviewer-flip disabled 9.57.0
    octo_features_offerable_ids
    echo \"DECISION=\$(octo_features_decision codex-reviewer-flip)\"
")
if grep -qx "DECISION=disabled" <<< "$out" && ! grep -qx "codex-reviewer-flip" <<< "$out"; then
    test_pass
else
    test_fail "disabled must be recorded distinctly and suppress offers"
fi

test_case "env var overrides the ledger in both directions"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_record fable5-escalation declined 9.57.0
    OCTOPUS_FABLE5_ESCALATE=1 octo_features_enabled fable5-escalation && echo ENV_ON
    octo_features_record fable5-escalation enabled 9.57.0
    OCTOPUS_FABLE5_ESCALATE=0 octo_features_enabled fable5-escalation || echo ENV_OFF
")
if grep -qx "ENV_ON" <<< "$out" && grep -qx "ENV_OFF" <<< "$out"; then
    test_pass
else
    test_fail "env var must win over the recorded decision both ways"
fi

test_case "invalid decision values are rejected"
reset_ledger '{"last_seen_version":"9.55.0"}'
if bash -c "source '$FEATURES_LIB'; octo_features_record fable5-escalation maybe 9.57.0" 2>/dev/null; then
    test_fail "record should reject a decision outside enabled/declined/disabled"
else
    test_pass
fi

# Anti-nagware: a corrupt or unwritable ledger must make disclosure go quiet,
# never loop. A ledger read failure that returned "nothing decided" while writes
# also failed would re-offer every feature every session forever.
test_case "corrupt ledger yields zero actionable features rather than looping"
reset_ledger 'NOT VALID JSON {'
n=$(bash -c "source '$FEATURES_LIB'; octo_features_actionable_count")
if [[ "$n" == "0" ]]; then
    test_pass
else
    test_fail "corrupt ledger should report 0 actionable, got '$n'"
fi

test_case "missing jq reports unavailable instead of erroring"
fake_bin="$TEST_TMP_DIR/nojq"
mkdir -p "$fake_bin"
if PATH="$fake_bin" bash -c "source '$FEATURES_LIB'; octo_features_available" 2>/dev/null; then
    test_fail "without jq the library must report unavailable"
else
    test_pass
fi

test_case "reoffer_at above the declined version re-opens the offer"
reset_ledger '{"last_seen_version":"9.55.0"}'
tmp_manifest="$TEST_TMP_DIR/reoffer-manifest.json"
jq '(.features[] | select(.id == "fable5-escalation")) |= (. + {reoffer_at: "9.60.0"})' \
    "$MANIFEST" > "$tmp_manifest"
out=$(OCTOPUS_FEATURES_MANIFEST="$tmp_manifest" bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record fable5-escalation declined 9.57.0
    octo_features_offerable_ids
")
if grep -qx "fable5-escalation" <<< "$out"; then
    test_pass
else
    test_fail "reoffer_at 9.60.0 above a 9.57.0 decline should re-open the offer"
fi

test_case "reoffer_at at or below the declined version stays suppressed"
reset_ledger '{"last_seen_version":"9.55.0"}'
tmp_manifest2="$TEST_TMP_DIR/reoffer-equal-manifest.json"
jq '(.features[] | select(.id == "fable5-escalation")) |= (. + {reoffer_at: "9.57.0"})' \
    "$MANIFEST" > "$tmp_manifest2"
out=$(OCTOPUS_FEATURES_MANIFEST="$tmp_manifest2" bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record fable5-escalation declined 9.57.0
    octo_features_offerable_ids
")
if ! grep -qx "fable5-escalation" <<< "$out"; then
    test_pass
else
    test_fail "reoffer_at equal to the declined version must not re-offer"
fi

test_case "actionable count excludes features whose prereq is missing"
reset_ledger '{"last_seen_version":"9.55.0"}'
empty_bin="$TEST_TMP_DIR/empty-bin"
mkdir -p "$empty_bin"
# Keep bash, jq and the coreutils the library calls reachable while hiding the
# provider CLIs the manifest prereqs look for. Those live in package-manager
# prefixes (/opt/homebrew/bin, ~/.local/bin), never in /bin or /usr/bin, so the
# system paths can stay on PATH without defeating the test.
jq_dir="$(dirname "$(command -v jq)")"
n=$(PATH="$empty_bin:/bin:/usr/bin:$jq_dir" bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_actionable_count")
total=$(bash -c "source '$FEATURES_LIB'; octo_features_offerable_ids" | grep -c . || true)
if [[ "$n" -lt "$total" ]]; then
    test_pass
else
    test_fail "with provider CLIs hidden, actionable ($n) should be below offerable ($total)"
fi

test_summary
