#!/usr/bin/env bash
# Unit tests for progressive feature disclosure (manifest + consent ledger).

set -euo pipefail

# features.sh resolves paths with `cd -P && pwd` (physical, symlinks resolved).
# Matching that here, not `cd && pwd` (logical), avoids a false mismatch on a
# symlinked checkout (e.g. macOS /tmp -> /private/tmp).
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Feature disclosure"

FEATURES_LIB="$PROJECT_ROOT/scripts/lib/features.sh"
MANIFEST="$PROJECT_ROOT/config/features.json"

# Isolate the ledger. Without this every assertion below reads the developer's
# real ~/.claude-octopus/state.json and the suite passes or fails according to
# which features they happen to have enabled.
export OCTOPUS_STATE_DIR="$TEST_TMP_DIR/feature-state"
mkdir -p "$OCTOPUS_STATE_DIR"

# Provider CLIs the manifest prereqs probe. The runner has neither claude nor
# codex, so without stubs every feature is prereq-blocked, actionable_count is 0,
# and the advisory emits no directive at all — which passed locally and failed on
# CI. Stub them for the whole suite so offers exist regardless of host. The one
# case that asserts prereq-blocking sets its own PATH and so is unaffected.
PREREQ_BIN="$TEST_TMP_DIR/prereq-bin"
mkdir -p "$PREREQ_BIN"
for _cli in claude codex agy; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$PREREQ_BIN/$_cli"
    chmod +x "$PREREQ_BIN/$_cli"
done
export PATH="$PREREQ_BIN:$PATH"

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

test_case "every manifest entry declares the common required fields"
missing=$(jq -r '
    .features[]
    | select((.id? | not) or (.added_in? | not) or (.key? | not)
             or (.title? | not) or (.prereq? | not) or (.decision? | not))
    | .id // "<no id>"' "$MANIFEST")
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "manifest entries missing common fields: $missing"
fi

# The two shapes are not interchangeable. A decision=required entry with no
# choices would raise a question the picker cannot answer; a decision=none entry
# with no description is undocumented.
test_case "decision=required entries carry a question and at least two choices"
bad=$(jq -r '
    .features[] | select(.decision == "required")
    | select((.question? | not) or ((.choices // []) | length) < 2)
    | .id' "$MANIFEST")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "decision=required entries lacking question/choices: $bad"
fi

test_case "decision=none entries carry a description and never a question"
bad=$(jq -r '
    .features[] | select(.decision == "none")
    | select((.description? | not) or (.question? != null))
    | .id' "$MANIFEST")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "decision=none entries malformed: $bad"
fi

test_case "decision is one of required or none"
bad=$(jq -r '.features[] | select(.decision != "required" and .decision != "none") | .id' "$MANIFEST")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "unknown decision value on: $bad"
fi

# Every choice must be reachable: AskUserQuestion allows at most 4 options.
test_case "no feature declares more than four choices"
bad=$(jq -r '.features[] | select(((.choices // []) | length) > 4) | .id' "$MANIFEST")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "AskUserQuestion caps options at 4; over-long: $bad"
fi

test_case "each feature default is one of its own declared choices"
bad=$(jq -r '
    .features[] | select(((.choices // []) | length) > 0)
    | . as $f
    | select(([$f.choices[].value] | index($f.default)) == null)
    | .id' "$MANIFEST")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "default not among choices for: $bad"
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

# Tested against a synthetic manifest rather than a real feature id. Pinning this
# to a shipped feature made the test rot the moment that feature's backfill or
# decision classification changed, and it then failed for a reason unrelated to
# the watermark gate it exists to protect.
test_case "a pre-watermark feature is never offered"
reset_ledger '{"last_seen_version":"9.55.0"}'
watermark_fixture="$TEST_TMP_DIR/watermark-manifest.json"
cat > "$watermark_fixture" <<'FIXTURE'
{
  "schema": "features_v1",
  "features": [
    {
      "id": "below-watermark-probe",
      "added_in": "9.52.0",
      "backfill": false,
      "decision": "required",
      "title": "Below the watermark",
      "question": "Should this ever be asked?",
      "key": "OCTOPUS_BELOW_WATERMARK_PROBE",
      "default": "0",
      "prereq": "none",
      "choices": [
        { "value": "1", "label": "Yes", "description": "enabled" },
        { "value": "0", "label": "No", "description": "disabled" }
      ]
    },
    {
      "id": "above-watermark-probe",
      "added_in": "9.56.0",
      "backfill": false,
      "decision": "required",
      "title": "Above the watermark",
      "question": "Should this be asked?",
      "key": "OCTOPUS_ABOVE_WATERMARK_PROBE",
      "default": "0",
      "prereq": "none",
      "choices": [
        { "value": "1", "label": "Yes", "description": "enabled" },
        { "value": "0", "label": "No", "description": "disabled" }
      ]
    }
  ]
}
FIXTURE
ids=$(OCTOPUS_FEATURES_MANIFEST="$watermark_fixture" bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_offerable_ids")
# The above-watermark twin proves the gate discriminates rather than suppressing
# everything, which a bare "not offered" assertion would not catch.
if ! grep -qx "below-watermark-probe" <<< "$ids" && grep -qx "above-watermark-probe" <<< "$ids"; then
    test_pass
else
    test_fail "watermark gate wrong: a non-backfill feature added at 9.52.0 must not be offered at watermark 9.55.0, and one added at 9.56.0 must be; got [$ids]"
fi

test_case "a recorded choice is sticky across repeated sessions"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record fable5-routing off 9.57.0
    for _ in 1 2 3; do octo_features_offerable_ids; done
")
if ! grep -qx "fable5-routing" <<< "$out"; then
    test_pass
else
    test_fail "choosing a policy, including the default, must stop the question"
fi

# Choosing "off" is a real answer, not an absence of one. If it did not stick,
# every upgrade would re-ask the user who already said no.
test_case "choosing the default value still records and still sticks"
if [[ "$(bash -c "source '$FEATURES_LIB'; octo_features_decision fable5-routing")" == "off" ]]; then
    test_pass
else
    test_fail "the default choice must be recorded like any other"
fi

test_case "a recorded policy reads back through octo_features_choice"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_record fable5-routing escalate-reviews 9.57.0
    octo_features_choice fable5-routing
")
if [[ "$out" == "escalate-reviews" ]]; then
    test_pass
else
    test_fail "expected escalate-reviews, got '$out'"
fi

test_case "an unanswered feature resolves to its manifest default"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "source '$FEATURES_LIB'; octo_features_choice fable5-routing")
if [[ "$out" == "off" ]]; then
    test_pass
else
    test_fail "expected the manifest default 'off', got '$out'"
fi

# Derived from the manifest rather than naming ids, so reclassifying a feature
# cannot silently narrow what this covers.
test_case "silent features are never raised however new they are"
reset_ledger '{"last_seen_version":"9.0.0"}'
out=$(bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_offerable_ids")
silent_ids=$(jq -r '.features[] | select(.decision == "none") | .id' "$MANIFEST")
if [[ -z "$silent_ids" ]]; then
    test_fail "manifest has no decision=none feature, so this invariant is untested — add one or delete this case"
else
    leaked=""
    while IFS= read -r sid; do
        [[ -n "$sid" ]] || continue
        grep -qx "$sid" <<< "$out" && leaked="$leaked $sid"
    done <<< "$silent_ids"
    if [[ -z "$leaked" ]]; then
        test_pass
    else
        test_fail "decision=none features must never be prompted, but these were:$leaked"
    fi
fi

test_case "only decision=required features are ever offered"
required=$(jq -r '.features[] | select(.decision == "required") | .id' "$MANIFEST" | sort)
offered=$(bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_offerable_ids" | sort)
if [[ "$offered" == "$required" ]]; then
    test_pass
else
    test_fail "offered [$offered] should equal the decision=required set [$required]"
fi

test_case "env key overrides a recorded policy"
reset_ledger '{"last_seen_version":"9.55.0"}'
out=$(bash -c "
    source '$FEATURES_LIB'
    octo_features_record fable5-routing off 9.57.0
    OCTOPUS_FABLE5_ROUTING=escalate octo_features_choice fable5-routing
")
if [[ "$out" == "escalate" ]]; then
    test_pass
else
    test_fail "env override should win, got '$out'"
fi

test_case "an invalid env value falls back to the recorded policy"
out=$(bash -c "
    source '$FEATURES_LIB'
    OCTOPUS_FABLE5_ROUTING=nonsense octo_features_choice fable5-routing
")
if [[ "$out" == "off" ]]; then
    test_pass
else
    test_fail "a bogus env value must not become the policy, got '$out'"
fi

test_case "recording a value outside the declared choices is rejected"
reset_ledger '{"last_seen_version":"9.55.0"}'
if bash -c "source '$FEATURES_LIB'; octo_features_record fable5-routing maybe 9.57.0" 2>/dev/null; then
    test_fail "record must validate against the feature's own choices"
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

test_case "reoffer_at above the chosen version re-opens the question"
reset_ledger '{"last_seen_version":"9.55.0"}'
tmp_manifest="$TEST_TMP_DIR/reoffer-manifest.json"
jq '(.features[] | select(.id == "fable5-routing")) |= (. + {reoffer_at: "9.60.0"})' \
    "$MANIFEST" > "$tmp_manifest"
out=$(OCTOPUS_FEATURES_MANIFEST="$tmp_manifest" bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record fable5-routing off 9.57.0
    octo_features_offerable_ids
")
if grep -qx "fable5-routing" <<< "$out"; then
    test_pass
else
    test_fail "reoffer_at 9.60.0 above a 9.57.0 choice should re-open the question"
fi

test_case "reoffer_at at or below the chosen version stays suppressed"
reset_ledger '{"last_seen_version":"9.55.0"}'
tmp_manifest2="$TEST_TMP_DIR/reoffer-equal-manifest.json"
jq '(.features[] | select(.id == "fable5-routing")) |= (. + {reoffer_at: "9.57.0"})' \
    "$MANIFEST" > "$tmp_manifest2"
out=$(OCTOPUS_FEATURES_MANIFEST="$tmp_manifest2" bash -c "
    source '$FEATURES_LIB'
    octo_features_seed_watermark
    octo_features_record fable5-routing off 9.57.0
    octo_features_offerable_ids
")
if ! grep -qx "fable5-routing" <<< "$out"; then
    test_pass
else
    test_fail "reoffer_at equal to the chosen version must not re-ask"
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

# ── Non-invasive SessionStart disclosure ─────────────────────────────────────
# Upgrade and first-run notices are user-visible system messages. They must not
# inject model context, call AskUserQuestion, or take over an unrelated prompt.

ADVISORY_HOOK="$PROJECT_ROOT/hooks/version-advisory.sh"
MEMORY_HOOK="$PROJECT_ROOT/hooks/session-start-memory.sh"

# Run the advisory hook against an isolated state dir that looks like an upgrade.
advisory() {
    local state="$1"; shift
    # Reset only last_seen_version so the hook sees an upgrade again. Overwriting
    # the whole file would also wipe features_prompt_attempts, and the budget
    # cases below would then never accumulate a count.
    if [[ -f "$state/state.json" ]]; then
        jq '.last_seen_version = "9.55.0"' "$state/state.json" > "$state/state.tmp" \
            && mv "$state/state.tmp" "$state/state.json"
    else
        printf '{"last_seen_version":"9.55.0"}\n' > "$state/state.json"
    fi
    touch "$state/.setup-complete"
    env "$@" OCTOPUS_STATE_DIR="$state" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
        bash "$ADVISORY_HOOK" 2>/dev/null | jq -r '.systemMessage // .hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

test_case "upgrade advisory is a user-visible system message"
adv_state="$TEST_TMP_DIR/adv-a"; mkdir -p "$adv_state"
printf '{"last_seen_version":"9.55.0"}\n' > "$adv_state/state.json"
touch "$adv_state/.setup-complete"
raw=$(env -u CI -u OCTOPUS_NON_INTERACTIVE -u CLAUDE_CODE_REMOTE \
    OCTOPUS_STATE_DIR="$adv_state" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    bash "$ADVISORY_HOOK" 2>/dev/null)
out=$(jq -r '.systemMessage // empty' <<<"$raw")
if grep -q "Claude Octopus updated" <<<"$out" && jq -e 'has("systemMessage") and (has("hookSpecificOutput") | not)' <<<"$raw" >/dev/null; then
    test_pass
else
    test_fail "expected a systemMessage-only advisory, got: $(head -5 <<<"$raw")"
fi

test_case "upgrade advisory never directs the model to act"
if ! grep -qE "AskUserQuestion|Before doing anything else|OCTOPUS-NEW-FEATURES" <<<"$out" \
   && grep -q "/octo:whats-new" <<<"$out"; then
    test_pass
else
    test_fail "advisory should be a passive explicit-command pointer: $(head -5 <<<"$out")"
fi

test_case "upgrade advisory records the version after one notice"
if jq -e --arg v "$(jq -r .version "$PROJECT_ROOT/.claude-plugin/plugin.json")" '.last_seen_version == $v' "$adv_state/state.json" >/dev/null; then
    test_pass
else
    test_fail "last_seen_version was not advanced"
fi

test_case "second SessionStart is silent after the upgrade notice"
second=$(env OCTOPUS_STATE_DIR="$adv_state" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$ADVISORY_HOOK" 2>/dev/null)
if [[ -z "$second" ]]; then
    test_pass
else
    test_fail "upgrade advisory repeated: $second"
fi

test_case "non-interactive upgrades also avoid model directives"
adv_state="$TEST_TMP_DIR/adv-ci"; mkdir -p "$adv_state"
out=$(advisory "$adv_state" CI=1)
if ! grep -qE "AskUserQuestion|OCTOPUS-NEW-FEATURES" <<<"$out"; then
    test_pass
else
    test_fail "CI run received a model directive: $(head -5 <<<"$out")"
fi

test_case "remote upgrades also avoid model directives"
adv_state="$TEST_TMP_DIR/adv-remote"; mkdir -p "$adv_state"
out=$(advisory "$adv_state" -u CI CLAUDE_CODE_REMOTE=true)
if ! grep -qE "AskUserQuestion|OCTOPUS-NEW-FEATURES" <<<"$out"; then
    test_pass
else
    test_fail "remote run received a model directive"
fi

test_case "a newer plugin version resets the prompt budget"
reset_ledger '{"features_prompt_version":"9.0.0","features_prompt_attempts":99}'
if bash -c "source '$FEATURES_LIB'; octo_features_prompt_allowed 9.57.0"; then
    test_pass
else
    test_fail "a version bump should hand out a fresh budget"
fi

test_case "the budget is not reset by the same version"
reset_ledger '{"features_prompt_version":"9.57.0","features_prompt_attempts":99}'
if ! bash -c "source '$FEATURES_LIB'; octo_features_prompt_allowed 9.57.0"; then
    test_pass
else
    test_fail "an exhausted budget must stay exhausted within a version"
fi

test_case "prompt manifest is tab-separated id/title/description"
reset_ledger '{"last_seen_version":"9.55.0"}'
# sed -n 1p rather than head -1: head closes the pipe after one line, which
# SIGPIPEs the producer and, under pipefail, aborts the suite with 141.
line=$(bash -c "source '$FEATURES_LIB'; octo_features_seed_watermark; octo_features_prompt_manifest" | sed -n 1p)
if [[ "$(awk -F'\t' '{print NF}' <<<"$line")" == "3" ]]; then
    test_pass
else
    test_fail "expected 3 tab-separated fields, got: $line"
fi

# The first-run welcome claimed to trigger setup via additionalContext while only
# echoing bare text, which SessionStart does not accept as context.
test_case "first-run welcome is a user-visible system message"
fr_home="$TEST_TMP_DIR/firstrun-home"
rm -rf "$fr_home"; mkdir -p "$fr_home"
out=$(env HOME="$fr_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$MEMORY_HOOK" 2>/dev/null)
if printf '%s' "$out" | jq -e 'has("systemMessage") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1; then
    test_pass
else
    test_fail "first-run must emit systemMessage only, got: $(printf '%s' "$out" | head -2)"
fi

test_case "first-run offers setup without directing model action"
message=$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)
if grep -qi "octo:setup" <<<"$message" && ! grep -qiE "invoke|before doing anything|auto-run" <<<"$message"; then
    test_pass
else
    test_fail "the welcome must passively offer setup: $message"
fi

test_case "first-run stays silent on the second session"
out2=$(env HOME="$fr_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$MEMORY_HOOK" 2>/dev/null)
if ! grep -qi "Welcome to Claude Octopus" <<<"$out2"; then
    test_pass
else
    test_fail "the welcome must not repeat once the setup marker exists"
fi

test_summary
