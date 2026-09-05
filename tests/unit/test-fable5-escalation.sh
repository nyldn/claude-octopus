#!/usr/bin/env bash
# Unit tests for selective Fable 5 escalation and the authorship-aware
# reviewer flip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Fable 5 escalation"

FABLE_LIB="$PROJECT_ROOT/scripts/lib/fable5.sh"
FEATURES_LIB="$PROJECT_ROOT/scripts/lib/features.sh"
AGENT_UTILS="$PROJECT_ROOT/scripts/lib/agent-utils.sh"

# Isolate the ledger and the quota-dead marker. Without this these assertions
# read the developer's real consent state and provider health.
export OCTOPUS_STATE_DIR="$TEST_TMP_DIR/escalation-state"
export WORKSPACE_DIR="$TEST_TMP_DIR/escalation-workspace"
mkdir -p "$OCTOPUS_STATE_DIR" "$WORKSPACE_DIR/state"
echo '{}' > "$OCTOPUS_STATE_DIR/state.json"

# Escalation must never be reachable through an inherited pin during these runs.
unset OCTOPUS_OPUS_MODEL OCTOPUS_CLAUDE_SDK_MODEL OCTOPUS_FABLE5_ROUTING 2>/dev/null || true

# escalate <role> [extra env assignments...] — resolve one dispatch decision in a
# clean subshell so the per-run cap marker never leaks between cases.
escalate() {
    local role="$1"; shift
    env "$@" \
        OCTOPUS_STATE_DIR="$OCTOPUS_STATE_DIR" \
        WORKSPACE_DIR="$WORKSPACE_DIR" \
        bash -c "
            source '$FEATURES_LIB'
            source '$PROJECT_ROOT/scripts/lib/quota-watcher.sh'
            source '$FABLE_LIB'
            fable5_maybe_escalate 'claude-opus-5' '$role' 'claude-opus' 'grasp'
        "
}

test_case "escalation library functions have valid bash syntax"
if bash -n "$FABLE_LIB"; then
    test_pass
else
    test_fail "fable5.sh has syntax errors"
fi

test_case "the default policy (off) escalates nothing"
got=$(escalate architect)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "without consent the model must stay claude-opus-5, got '$got'"
fi

# Choose the planning-and-PRDs policy for the remaining cases.
bash -c "source '$FEATURES_LIB'; octo_features_record fable5-routing escalate 9.57.0"

test_case "architect escalates under the escalate policy"
got=$(escalate architect)
if [[ "$got" == "claude-fable-5-1" ]]; then
    test_pass
else
    test_fail "architect should escalate, got '$got'"
fi

test_case "strategist escalates to Fable 5"
got=$(escalate strategist)
if [[ "$got" == "claude-fable-5-1" ]]; then
    test_pass
else
    test_fail "strategist should escalate, got '$got'"
fi

# The echo problem: Fable reviewing Opus-authored work is same-family agreement,
# not an independent check. Under the default escalate policy, review stays off
# Fable; the user can opt into it, but it is not what "escalate" buys.
test_case "code-reviewer does not escalate under the escalate policy"
got=$(escalate code-reviewer)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "code-reviewer must not escalate under 'escalate', got '$got'"
fi

test_case "code-reviewer DOES escalate under the escalate-reviews policy"
got=$(escalate code-reviewer OCTOPUS_FABLE5_ROUTING=escalate-reviews)
if [[ "$got" == "claude-fable-5-1" ]]; then
    test_pass
else
    test_fail "the user opted into Fable reviews; expected fable, got '$got'"
fi

test_case "the on-demand policy escalates nothing automatically"
got=$(escalate architect OCTOPUS_FABLE5_ROUTING=on-demand)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "on-demand must never auto-escalate, got '$got'"
fi

test_case "security-reviewer never escalates under any policy"
got=$(escalate security-reviewer OCTOPUS_FABLE5_ROUTING=escalate-reviews)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "security roles must never reach Fable 5, got '$got'"
fi

test_case "implementer-heavy never escalates"
got=$(escalate implementer-heavy)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "implementation is not judgment work, got '$got'"
fi

# Resolution precedence: an explicit pin is Tier 1 and outranks a release default.
test_case "an explicit OCTOPUS_OPUS_MODEL pin suppresses escalation"
got=$(escalate architect OCTOPUS_OPUS_MODEL=claude-opus-5)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "user pin must beat escalation, got '$got'"
fi

test_case "session env override can stand escalation down without touching the record"
got=$(escalate architect OCTOPUS_FABLE5_ROUTING=off)
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "OCTOPUS_FABLE5_ROUTING=off should stand down, got '$got'"
fi

test_case "a non-Opus model is passed through untouched"
got=$(env OCTOPUS_STATE_DIR="$OCTOPUS_STATE_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$FEATURES_LIB'; source '$FABLE_LIB'
    fable5_maybe_escalate 'claude-sonnet-5' 'architect' 'claude' 'grasp'")
if [[ "$got" == "claude-sonnet-5" ]]; then
    test_pass
else
    test_fail "only the default Opus seat may be upgraded, got '$got'"
fi

# Headroom is reactive: no endpoint reports remaining Fable 5 usage, so a
# rate-limited dispatch marks the model dead and escalation stands down.
test_case "a quota-dead Fable 5 seat stands down to Opus 5"
printf 'claude-fable-5-1\n' > "$WORKSPACE_DIR/state/.provider-quota-dead"
got=$(escalate architect)
rm -f "$WORKSPACE_DIR/state/.provider-quota-dead"
if [[ "$got" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "a dead Fable seat must fall back, got '$got'"
fi

# Cost containment: councils, debates and review fleets dispatch many seats.
# Escalating each one is the spend the one-owner rule exists to prevent.
test_case "only one escalation per run; the second judgment seat stays on Opus"
out=$(env OCTOPUS_STATE_DIR="$OCTOPUS_STATE_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$FEATURES_LIB'
    source '$PROJECT_ROOT/scripts/lib/quota-watcher.sh'
    source '$FABLE_LIB'
    fable5_maybe_escalate 'claude-opus-5' 'architect'   'claude-opus' 'grasp'
    fable5_maybe_escalate 'claude-opus-5' 'strategist'  'claude-opus' 'grasp'
")
first=$(echo "$out" | sed -n 1p)
second=$(echo "$out" | sed -n 2p)
if [[ "$first" == "claude-fable-5-1" && "$second" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "expected fable then opus, got '$first' then '$second'"
fi

test_case "separate runs sharing one session do not inherit the Fable claim"
shared_session="shared-session-fixture"
run_one=$(OCTOPUS_SESSION_ID="$shared_session" OCTOPUS_STATE_DIR="$OCTOPUS_STATE_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$FEATURES_LIB'; source '$PROJECT_ROOT/scripts/lib/run-contract.sh'; source '$FABLE_LIB'
    fable5_maybe_escalate 'claude-opus-5' 'architect' 'claude-opus' 'grasp'")
run_two=$(OCTOPUS_SESSION_ID="$shared_session" OCTOPUS_STATE_DIR="$OCTOPUS_STATE_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" bash -c "
    source '$FEATURES_LIB'; source '$PROJECT_ROOT/scripts/lib/run-contract.sh'; source '$FABLE_LIB'
    fable5_maybe_escalate 'claude-opus-5' 'architect' 'claude-opus' 'grasp'")
if [[ "$run_one" == "claude-fable-5-1" && "$run_two" == "claude-fable-5-1" ]]; then
    test_pass
else
    test_fail "shared session leaked a prior claim: first=$run_one second=$run_two"
fi

# Fable 5 effort applies per tool call, so xhigh widens each step's scope at 2x
# cost rather than extending the run.
test_case "effort clamps xhigh to high for a Fable 5 dispatch"
got=$(bash -c "source '$FABLE_LIB'; fable5_clamp_effort_for_model xhigh claude-fable-5")
if [[ "$got" == "high" ]]; then
    test_pass
else
    test_fail "expected high, got '$got'"
fi

test_case "Fable 5.1 effort defaults to the high cap"
got=$(bash -c "source '$FABLE_LIB'; fable5_clamp_effort_for_model max claude-fable-5-1")
if [[ "$got" == "high" ]]; then
    test_pass
else
    test_fail "expected high, got '$got'"
fi

test_case "an explicit Fable effort cap permits xhigh without disabling guards"
got=$(OCTOPUS_FABLE5_MAX_EFFORT=xhigh bash -c "source '$FABLE_LIB'; fable5_clamp_effort_for_model xhigh claude-fable-5-1")
if [[ "$got" == "xhigh" ]]; then
    test_pass
else
    test_fail "expected xhigh, got '$got'"
fi

# The clamp must not over-reach onto unrelated Opus work in the same run.
test_case "effort is untouched for a non-Fable dispatch"
got=$(bash -c "source '$FABLE_LIB'; fable5_clamp_effort_for_model xhigh claude-opus-5")
if [[ "$got" == "xhigh" ]]; then
    test_pass
else
    test_fail "Opus 5 xhigh must survive the clamp, got '$got'"
fi

test_case "escalation is wired into the dispatch path, not the model resolver"
# The resolver caches on provider/agent/phase/role/config-cksum with no liveness
# component, so an escalation applied there would keep serving a cached Fable
# model after the seat was marked dead.
if grep -q "fable5_maybe_escalate" "$PROJECT_ROOT/scripts/lib/dispatch.sh" \
   && ! grep -q "fable5_maybe_escalate" "$PROJECT_ROOT/scripts/lib/model-resolver.sh"; then
    test_pass
else
    test_fail "escalation must be called from dispatch.sh and not model-resolver.sh"
fi

test_case "escalation runs before the security reroute in dispatch"
esc_line=$(grep -n "fable5_maybe_escalate" "$PROJECT_ROOT/scripts/lib/dispatch.sh" | head -1 | cut -d: -f1)
rer_line=$(grep -n "fable5_maybe_reroute" "$PROJECT_ROOT/scripts/lib/dispatch.sh" | head -1 | cut -d: -f1)
if [[ -n "$esc_line" && -n "$rer_line" ]] && (( esc_line < rer_line )); then
    test_pass
else
    test_fail "reroute must run after escalation (escalate=$esc_line reroute=$rer_line)"
fi

# ── Each gate pinned on its own ──────────────────────────────────────────────
# fable5_maybe_escalate consults two gates that both reject a non-escalating
# policy: fable5_escalation_consented and fable5_escalation_role_eligible. That
# redundancy is deliberate, but it means an end-to-end assertion cannot fail from
# a single-gate regression — mutating either one alone is masked by the other.
# These cases exercise the gates directly so each is genuinely covered.

gate() {
    env OCTOPUS_STATE_DIR="$OCTOPUS_STATE_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" \
        OCTOPUS_FABLE5_ROUTING="$1" bash -c "
            source '$FEATURES_LIB'; source '$FABLE_LIB'
            $2 && echo YES || echo NO"
}

test_case "consent gate: only escalate and escalate-reviews consent"
res=""
for pol in off on-demand escalate escalate-reviews; do
    res="${res}$(gate "$pol" 'fable5_escalation_consented')|"
done
if [[ "$res" == "NO|NO|YES|YES|" ]]; then
    test_pass
else
    test_fail "expected NO|NO|YES|YES| for off,on-demand,escalate,escalate-reviews; got $res"
fi

test_case "role gate: escalate covers judgment authoring only"
res="$(gate escalate 'fable5_escalation_role_eligible architect')|$(gate escalate 'fable5_escalation_role_eligible strategist')|$(gate escalate 'fable5_escalation_role_eligible code-reviewer')"
if [[ "$res" == "YES|YES|NO" ]]; then
    test_pass
else
    test_fail "expected YES|YES|NO for architect,strategist,code-reviewer; got $res"
fi

test_case "role gate: escalate-reviews adds review, still not security"
res="$(gate escalate-reviews 'fable5_escalation_role_eligible code-reviewer')|$(gate escalate-reviews 'fable5_escalation_role_eligible security-reviewer')"
if [[ "$res" == "YES|NO" ]]; then
    test_pass
else
    test_fail "expected YES|NO for code-reviewer,security-reviewer; got $res"
fi

test_case "role gate: off and on-demand make every role ineligible"
res=""
for pol in off on-demand; do
    for role in architect strategist code-reviewer; do
        res="${res}$(gate "$pol" "fable5_escalation_role_eligible $role")"
    done
done
if [[ "$res" == "NONONONONONO" ]]; then
    test_pass
else
    test_fail "no role may be eligible under off/on-demand; got $res"
fi

# ── Authorship-aware reviewer flip ───────────────────────────────────────────

# The flip only fires when the Codex CLI is present, so these cases must supply a
# mock rather than depend on whether the host happens to have codex installed.
# Reading the real PATH made this suite pass locally and fail on CI, where codex
# is absent and the flip correctly stayed inert.
flip_bin="$TEST_TMP_DIR/flip-mock-bin"
mkdir -p "$flip_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$flip_bin/codex"
chmod +x "$flip_bin/codex"

test_case "reviewer flip is off by default"
got=$(PATH="$flip_bin:$PATH" bash -c "source '$FEATURES_LIB' 2>/dev/null; source '$AGENT_UTILS' 2>/dev/null; get_role_mapping code-reviewer")
if [[ "$got" == codex-review:* ]]; then
    test_pass
else
    test_fail "default review seat should be Codex, got '$got'"
fi

test_case "reviewer flip moves review off the implementing vendor"
got=$(PATH="$flip_bin:$PATH" OCTOPUS_REVIEWER_FLIP=claude bash -c "source '$FEATURES_LIB' 2>/dev/null; source '$AGENT_UTILS' 2>/dev/null; get_role_mapping code-reviewer")
if [[ "$got" == claude-opus:* ]]; then
    test_pass
else
    test_fail "flip should send review to the Claude opus seat, got '$got'"
fi

test_case "reviewer flip leaves the implementer seat on Codex"
got=$(PATH="$flip_bin:$PATH" OCTOPUS_REVIEWER_FLIP=1 bash -c "source '$FEATURES_LIB' 2>/dev/null; source '$AGENT_UTILS' 2>/dev/null; get_role_mapping implementer")
if [[ "$got" == codex:* ]]; then
    test_pass
else
    test_fail "flip must not move implementation, got '$got'"
fi

# Without Codex the implementer already falls back off Codex, so flipping review
# away from it would remove vendor diversity rather than create it.
test_case "reviewer flip stays inert when the Codex CLI is absent"
empty_bin="$TEST_TMP_DIR/flip-empty-bin"
mkdir -p "$empty_bin"
got=$(PATH="$empty_bin:/bin:/usr/bin" OCTOPUS_REVIEWER_FLIP=claude \
    bash -c "source '$FEATURES_LIB' 2>/dev/null; source '$AGENT_UTILS' 2>/dev/null; get_role_mapping code-reviewer")
if [[ "$got" == codex-review:* ]]; then
    test_pass
else
    test_fail "with no codex CLI the flip must not fire, got '$got'"
fi

test_summary
