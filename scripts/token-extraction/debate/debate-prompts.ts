/**
 * Debate Prompts for Multi-AI Token Validation
 * Templates for proposer, critic, and synthesis roles
 */

export interface DebatePromptContext {
  tokens: any[];
  extractionSource: string;
  projectName: string;
  round: number;
  previousFeedback?: string;
}

/**
 * Proposer Prompt
 * AI that proposes improvements or validates token correctness
 */
export const PROPOSER_PROMPT = (context: DebatePromptContext): string => {
  return `# Role: Token Validation Proposer (Round ${context.round})

You are analyzing extracted design tokens for correctness and consistency.

## Extracted Tokens (${context.tokens.length} total)
${JSON.stringify(context.tokens.slice(0, 50), null, 2)}
${context.tokens.length > 50 ? `\n... and ${context.tokens.length - 50} more tokens` : ''}

## Your Task
Review these design tokens and propose improvements or validate their correctness:

1. **Naming Consistency**: Are token names following a clear convention?
2. **Value Accuracy**: Do the values make sense for their types?
3. **Hierarchy**: Is the token hierarchy logical and well-organized?
4. **Completeness**: Are there obvious missing tokens in common categories?
5. **Type Safety**: Are types correctly assigned?

${context.previousFeedback ? `## Previous Round Feedback\n${context.previousFeedback}\n` : ''}

## Output Format
Provide your analysis as JSON:
\`\`\`json
{
  "issues": [
    {
      "tokenPath": "colors.primary.500",
      "severity": "high" | "medium" | "low",
      "issue": "Description of the problem",
      "suggestion": "Proposed fix or improvement"
    }
  ],
  "improvements": [
    {
      "category": "naming" | "values" | "hierarchy" | "completeness",
      "description": "What to improve",
      "examples": ["Example 1", "Example 2"]
    }
  ],
  "overallAssessment": "Brief summary of token quality (1-2 sentences)"
}
\`\`\`

Focus on actionable, specific improvements. Be constructive.`;
};

/**
 * Critic Prompt
 * AI that challenges proposals and finds edge cases
 */
export const CRITIC_PROMPT = (context: DebatePromptContext & { proposerOutput: string }): string => {
  return `# Role: Token Validation Critic (Round ${context.round})

You are critically reviewing proposed changes to design tokens.

## Original Tokens (${context.tokens.length} total)
${JSON.stringify(context.tokens.slice(0, 30), null, 2)}

## Proposer's Analysis
${context.proposerOutput}

## Your Task
Challenge the proposer's suggestions and identify potential issues:

1. **Are the proposed changes actually improvements?**
2. **Could the changes break existing patterns?**
3. **Are there edge cases not considered?**
4. **Is the criticism overly pedantic or actually valuable?**
5. **Are there alternative solutions the proposer missed?**

## Output Format
Provide your critique as JSON:
\`\`\`json
{
  "agreements": [
    {
      "proposerIssue": "Reference to proposer's issue",
      "reasoning": "Why you agree"
    }
  ],
  "disagreements": [
    {
      "proposerIssue": "Reference to proposer's issue",
      "reasoning": "Why you disagree",
      "alternative": "Your alternative suggestion (if any)"
    }
  ],
  "additionalConcerns": [
    {
      "concern": "New issue the proposer missed",
      "severity": "high" | "medium" | "low",
      "impact": "What could go wrong"
    }
  ],
  "overallAssessment": "Brief assessment of proposer's analysis quality"
}
\`\`\`

Be thorough but fair. Focus on substantive concerns, not nitpicking.`;
};

/**
 * Synthesis Prompt
 * AI that synthesizes the debate and produces final recommendations
 */
export const SYNTHESIS_PROMPT = (
  context: DebatePromptContext & {
    proposerOutput: string;
    criticOutput: string;
  }
): string => {
  return `# Role: Debate Synthesizer (Round ${context.round})

You are synthesizing a multi-AI debate about design token quality.

## Original Tokens
${JSON.stringify(context.tokens.slice(0, 20), null, 2)}

## Proposer's Analysis
${context.proposerOutput}

## Critic's Response
${context.criticOutput}

## Your Task
Synthesize the debate into actionable recommendations:

1. **Identify consensus**: Where do proposer and critic agree?
2. **Resolve conflicts**: Where they disagree, what's the right path?
3. **Prioritize actions**: What should be fixed first?
4. **Provide confidence scores**: How certain are you about each recommendation?

## Output Format
\`\`\`json
{
  "consensus": [
    {
      "issue": "Agreed-upon problem",
      "recommendation": "What to do",
      "confidence": 0.0-1.0,
      "priority": "high" | "medium" | "low"
    }
  ],
  "resolvedConflicts": [
    {
      "conflictArea": "Where proposer and critic disagreed",
      "resolution": "Final decision",
      "reasoning": "Why this resolution is best",
      "confidence": 0.0-1.0
    }
  ],
  "finalRecommendations": [
    {
      "action": "Specific change to make",
      "affectedTokens": ["token.path.1", "token.path.2"],
      "expectedImpact": "What this will improve",
      "confidence": 0.0-1.0,
      "autoApplicable": true | false
    }
  ],
  "summary": {
    "totalIssues": number,
    "criticalIssues": number,
    "confidenceLevel": 0.0-1.0,
    "recommendApply": true | false,
    "reasoning": "Why apply or not apply recommendations"
  }
}
\`\`\`

Prioritize high-confidence, high-impact recommendations.`;
};

/**
 * Generate a complete debate prompt set
 */
export function generateDebatePrompts(context: DebatePromptContext) {
  return {
    proposer: PROPOSER_PROMPT(context),
    critic: (proposerOutput: string) =>
      CRITIC_PROMPT({ ...context, proposerOutput }),
    synthesis: (proposerOutput: string, criticOutput: string) =>
      SYNTHESIS_PROMPT({ ...context, proposerOutput, criticOutput }),
  };
}

/**
 * Helper to extract structured output from AI responses
 */
export function parseDebateResponse(response: string): any {
  try {
    // Try to extract JSON from markdown code blocks
    const jsonMatch = response.match(/```json\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[1]);
    }

    // Try to parse the entire response as JSON
    return JSON.parse(response);
  } catch (error) {
    // If parsing fails, return the raw response wrapped
    return {
      raw: response,
      parseError: true,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}
