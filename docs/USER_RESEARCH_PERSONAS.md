# User Research: Personas & Journey Map
*Based on v4.2 Research Synthesis*

## 1. User Personas

### Persona A: Alex, the Senior Tech Lead (Primary)
**Archetype:** The Efficiency Maximizer & Governance-First
> *"I need automation to scale my output, but I need to drive the car, not just watch it from the sidewalk."*

*   **Background:** 10+ years exp. leads a team of 5. Responsible for architectural integrity and code quality.
*   **Goals:**
    *   Refactor legacy modules without introducing regressions.
    *   Review agent-generated code efficiently.
    *   Enforce team standards (linting, patterns) on generated code.
*   **Frustrations:**
    *   **"Black Box" Anxiety:** Hate staring at a spinner not knowing if the agent is hallucinating or working.
    *   **Lack of Governance:** Fears "runaway" agents making poor architectural decisions.
    *   **Non-Reprodubility:** "It worked yesterday, why is it failing now?"
*   **Key Behaviors:**
    *   Religiously uses **Human-in-the-Loop** reviews.
    *   Demands **Workflow Snapshots** to standardize team tools.
    *   Configures high-tier resource routing but monitors it closely.

### Persona B: Jordan, the Full-Stack Freelancer
**Archetype:** The Cost-Conscious Experimenter & Learner
> *"I want to use these AI agents, but I can't afford a surprise $500 bill or a broken dev environment."*

*   **Background:** 3 years exp. Works on multiple client projects. Pays for their own API keys.
*   **Goals:**
    *   Quickly fix bugs or scaffold features to save time.
    *   Learn best practices through the tool's suggestions.
    *   Keep operational costs predictable and low.
*   **Frustrations:**
    *   **Setup Friction:** Intimidated by complex manual configuration (keys, environments).
    *   **Cost Uncertainty:** "Usage paralysis" due to opaque pricing models.
    *   **Context Switching:** Gets lost when errors occur and the tool doesn't explain *why*.
*   **Key Behaviors:**
    *   Relies on **Smart Setup Wizard** (Intent-Based).
    *   Uses **Contextual Error Recovery** ("Fix this: ...") as a learning tool.
    *   Checks **Token-Aware Cost** estimates before every major command.

### Persona C: Sam, the Platform Engineer
**Archetype:** The Governance-First (Enterprise)
> *"If it's not auditable and reproducible, it doesn't go into our pipeline."*

*   **Background:** DevOps/SRE focus. Cares about security, compliance, and stability.
*   **Goals:**
    *   Integrate agent workflows into CI/CD pipelines.
    *   Ensure no secrets are leaked or unsafe code committed.
    *   Maintain audit trails of what the agent changed and why.
*   **Frustrations:**
    *   Lack of **Team Dashboards** or visibility into what devs are running.
    *   Inability to lock agent versions/behaviors (determinism).
*   **Key Behaviors:**
    *   Demands **Workflow Snapshots** and JSON logs.
    *   Sets strict cost/token limits globally.

---

## 2. Current-State Journey Map (Alex - Senior Tech Lead)

**Scenario:** Alex needs to refactor a complex authentication module using the CLI.

| Stage | Actions | Thinking / Feeling | Pain Points & Opportunities |
| :--- | :--- | :--- | :--- |
| **1. Setup & Config** | Runs `claude-octopus`. Selects "Refactoring" intent in **Smart Setup**. | *Thinking:* "I hope this doesn't mess up my existing config. Just give me the power tools." | **Pain:** Setup friction if manual steps are needed.<br>**High:** "Smart Setup" correctly guesses intent (Efficiency). |
| **2. Task Initiation** | Enters command: `refactor auth/login.ts to use OAuth2`. | *Feeling:* Cautious. Worried about token costs and time. | **Opportunity:** **Token-Aware Cost** estimate provides reassurance here. |
| **3. Execution (The Wait)** | The agent starts analyzing files. Logs stream by. | *Thinking:* "Is it stuck? What is it actually changing? Did it see the `auth-provider` file?" | **Pain (Critical):** **Operational "Blindness"**. Needs a TUI/Visual status bar.<br>**Gap:** Wants to see the "Plan" before execution. |
| **4. Moment of Truth** | Agent proposes changes. **Human-in-the-Loop** prompt appears. | *Feeling:* **Relief & Control.** "Okay, it waited for me. Let me check the diff." | **High (Critical):** Trust is built here. The ability to Approve/Reject is the #1 feature for Alex. |
| **5. Error Recovery** | Alex rejects a change; Agent retries but hits a linter error. | *Thinking:* "Ugh, now I have to fix it manually?" | **High:** **Contextual Error Recovery** kicks in: "Lint error detected. Auto-fixing..." -> *Delight.* |
| **6. Completion** | Task done. Tests pass. | *Feeling:* Satisfied but wary of the future. "How do I ensure the junior devs do it this way?" | **Gap:** **Predictable Reproducibility**. Alex wants to save this "Refactor Workflow" as a team template. |

---

## 3. Moments of Truth & Emotional Highs/Lows

1.  **The "Black Box" Anxiety (Low):**
    *   *Context:* During long-running tasks (Stage 3).
    *   *Emotion:* Uncertainty/Impatient.
    *   *Insight:* The user loses trust if the CLI is silent for too long.
    *   *Fix:* **Real-Time Progress Feedback** (TUI) is essential to convert this low into a high.

2.  **The Governance Gate (High):**
    *   *Context:* The Human-in-the-Loop review prompt (Stage 4).
    *   *Emotion:* Empowerment/Safety.
    *   *Insight:* This is the "Trust Anchor." Without it, Alex would not use the tool for complex tasks. It validates the "Transparency" insight.

3.  **The "Smart Rescue" (High):**
    *   *Context:* When a runtime error occurs and the tool offers a fix (Stage 5).
    *   *Emotion:* Gratitude/Delight.
    *   *Insight:* Transforms a potential drop-off point (error) into a demonstration of competence. This confirms the value of **Contextual Recovery**.

4.  **The Bill Shock Check (Neutral/High):**
    *   *Context:* Pre-run cost estimation.
    *   *Emotion:* Reassurance (or sticker shock).
    *   *Insight:* Even if the cost is high, *knowing* it beforehand builds trust (Transparency). Surprises destroy trust.
