/**
 * Debate Integration
 * Multi-AI debate for design token validation and improvement
 */

import { Token, DebateResult, DebateConsensus, TokenChange } from './types';
import {
  generateDebatePrompts,
  parseDebateResponse,
  DebatePromptContext,
} from './debate/debate-prompts';

export interface DebateOptions {
  rounds?: number;
  consensusThreshold?: number;
  providers?: string[];
  autoApply?: boolean;
  minConfidence?: number;
}

const DEFAULT_DEBATE_OPTIONS: Required<DebateOptions> = {
  rounds: 2,
  consensusThreshold: 0.67,
  providers: ['claude', 'codex', 'gemini'],
  autoApply: false,
  minConfidence: 0.75,
};

/**
 * Run multi-AI debate on extracted tokens
 */
export async function runDebateOnTokens(
  tokens: Token[],
  options: DebateOptions = {}
): Promise<DebateResult> {
  const opts = { ...DEFAULT_DEBATE_OPTIONS, ...options };

  console.log('Starting multi-AI debate on tokens...');
  console.log(`  Rounds: ${opts.rounds}`);
  console.log(`  Consensus threshold: ${opts.consensusThreshold}`);
  console.log(`  Providers: ${opts.providers.join(', ')}`);
  console.log('');

  const allConsensus: DebateConsensus[] = [];
  const allImprovements: TokenChange[] = [];
  const auditTrail: string[] = [];

  // Run debate rounds
  for (let round = 1; round <= opts.rounds; round++) {
    console.log(`Debate Round ${round}/${opts.rounds}...`);

    const roundResult = await runDebateRound(tokens, round, opts);

    allConsensus.push(...roundResult.consensus);
    allImprovements.push(...roundResult.improvements);
    auditTrail.push(`\n## Round ${round}\n${roundResult.auditEntry}`);

    console.log(`  Consensus items: ${roundResult.consensus.length}`);
    console.log(`  Improvements proposed: ${roundResult.improvements.length}`);
    console.log('');
  }

  // Build final result
  const result: DebateResult = {
    rounds: opts.rounds,
    consensus: allConsensus,
    improvements: allImprovements,
    auditTrail: auditTrail.join('\n'),
    timestamp: new Date().toISOString(),
  };

  console.log('Debate complete!');
  console.log(`  Total consensus items: ${allConsensus.length}`);
  console.log(`  Total improvements: ${allImprovements.length}`);
  console.log('');

  return result;
}

/**
 * Run a single debate round
 */
async function runDebateRound(
  tokens: Token[],
  round: number,
  options: Required<DebateOptions>
): Promise<{
  consensus: DebateConsensus[];
  improvements: TokenChange[];
  auditEntry: string;
}> {
  const context: DebatePromptContext = {
    tokens: tokens.map(t => ({
      name: t.name,
      value: t.value,
      type: t.type,
      path: t.path,
      source: t.source,
    })),
    extractionSource: 'token-extraction-pipeline',
    projectName: 'extracted-tokens',
    round,
  };

  const prompts = generateDebatePrompts(context);

  // Step 1: Proposer analyzes tokens
  const proposerResponse = await callAIProvider(
    'proposer',
    prompts.proposer,
    'claude'
  );
  const proposerAnalysis = parseDebateResponse(proposerResponse);

  // Step 2: Critic challenges the proposer
  const criticResponse = await callAIProvider(
    'critic',
    prompts.critic(proposerResponse),
    'gemini'
  );
  const criticAnalysis = parseDebateResponse(criticResponse);

  // Step 3: Synthesizer produces final recommendations
  const synthesisResponse = await callAIProvider(
    'synthesizer',
    prompts.synthesis(proposerResponse, criticResponse),
    'claude'
  );
  const synthesis = parseDebateResponse(synthesisResponse);

  // Extract consensus and improvements
  const consensus = extractConsensus(synthesis, options.consensusThreshold);
  const improvements = extractImprovements(synthesis, tokens, options.minConfidence);

  // Generate audit trail entry
  const auditEntry = generateAuditEntry(
    round,
    proposerAnalysis,
    criticAnalysis,
    synthesis
  );

  return { consensus, improvements, auditEntry };
}

/**
 * Call an AI provider (mock implementation)
 * In real implementation, this would call orchestrate.sh or AI CLI tools
 */
async function callAIProvider(
  role: string,
  prompt: string,
  provider: string
): Promise<string> {
  console.log(`  Calling ${provider} as ${role}...`);

  // Mock implementation - returns structured response
  // Real implementation would call:
  // - orchestrate.sh grapple_debate
  // - codex CLI
  // - gemini CLI

  const mockResponses: Record<string, any> = {
    proposer: {
      issues: [
        {
          tokenPath: 'colors.primary.500',
          severity: 'medium',
          issue: 'Color value might not meet WCAG AA contrast requirements',
          suggestion: 'Verify contrast ratio against background colors',
        },
      ],
      improvements: [
        {
          category: 'naming',
          description: 'Consider using semantic naming over descriptive',
          examples: ['Use "brand-primary" instead of "blue-500"'],
        },
      ],
      overallAssessment: 'Tokens are well-structured but could benefit from semantic naming and accessibility validation.',
    },
    critic: {
      agreements: [
        {
          proposerIssue: 'WCAG contrast concern',
          reasoning: 'Accessibility is critical and should be validated',
        },
      ],
      disagreements: [
        {
          proposerIssue: 'Semantic naming suggestion',
          reasoning: 'Current naming is clear and follows industry standards',
          alternative: 'Keep current naming but add semantic aliases',
        },
      ],
      additionalConcerns: [],
      overallAssessment: 'Proposer raised valid accessibility concerns but naming suggestions may be overly prescriptive.',
    },
    synthesizer: {
      consensus: [
        {
          issue: 'WCAG contrast validation needed',
          recommendation: 'Run accessibility audit on all color tokens',
          confidence: 0.9,
          priority: 'high',
        },
      ],
      resolvedConflicts: [
        {
          conflictArea: 'Naming convention',
          resolution: 'Keep current naming, add semantic aliases as alternative',
          reasoning: 'Preserves existing clarity while enabling semantic usage',
          confidence: 0.8,
        },
      ],
      finalRecommendations: [
        {
          action: 'Add accessibility metadata to color tokens',
          affectedTokens: ['colors.*'],
          expectedImpact: 'Enable automatic WCAG validation',
          confidence: 0.85,
          autoApplicable: true,
        },
      ],
      summary: {
        totalIssues: 1,
        criticalIssues: 0,
        confidenceLevel: 0.85,
        recommendApply: true,
        reasoning: 'High-confidence improvements with clear benefits',
      },
    },
  };

  // Simulate AI processing delay
  await new Promise(resolve => setTimeout(resolve, 100));

  return JSON.stringify(mockResponses[role] || {}, null, 2);
}

/**
 * Extract consensus items from synthesis
 */
function extractConsensus(
  synthesis: any,
  threshold: number
): DebateConsensus[] {
  if (!synthesis.consensus) return [];

  return synthesis.consensus
    .filter((item: any) => item.confidence >= threshold)
    .map((item: any) => ({
      topic: item.issue || item.recommendation,
      agreement: item.confidence,
      recommendation: item.recommendation,
      providers: ['proposer', 'critic', 'synthesizer'],
    }));
}

/**
 * Extract improvement suggestions
 */
function extractImprovements(
  synthesis: any,
  tokens: Token[],
  minConfidence: number
): TokenChange[] {
  if (!synthesis.finalRecommendations) return [];

  const improvements: TokenChange[] = [];

  for (const rec of synthesis.finalRecommendations) {
    if (rec.confidence >= minConfidence && rec.autoApplicable) {
      // Find affected tokens
      const affectedTokens = findAffectedTokens(tokens, rec.affectedTokens);

      for (const token of affectedTokens) {
        improvements.push({
          tokenName: token.name,
          path: token.path,
          oldValue: token.value,
          newValue: token.value, // In real implementation, would apply the change
          reason: rec.action,
          confidence: rec.confidence,
          approvedBy: ['synthesizer'],
        });
      }
    }
  }

  return improvements;
}

/**
 * Find tokens matching patterns
 */
function findAffectedTokens(tokens: Token[], patterns: string[]): Token[] {
  const affected: Token[] = [];

  for (const pattern of patterns) {
    const regex = new RegExp(pattern.replace('*', '.*'));
    for (const token of tokens) {
      const tokenPath = token.path.join('.');
      if (regex.test(tokenPath)) {
        affected.push(token);
      }
    }
  }

  return affected;
}

/**
 * Generate audit trail entry for a round
 */
function generateAuditEntry(
  round: number,
  proposer: any,
  critic: any,
  synthesis: any
): string {
  return `
### Proposer Analysis
Issues found: ${proposer.issues?.length || 0}
Improvements suggested: ${proposer.improvements?.length || 0}
Assessment: ${proposer.overallAssessment}

### Critic Response
Agreements: ${critic.agreements?.length || 0}
Disagreements: ${critic.disagreements?.length || 0}
Additional concerns: ${critic.additionalConcerns?.length || 0}
Assessment: ${critic.overallAssessment}

### Synthesis
Consensus items: ${synthesis.consensus?.length || 0}
Conflicts resolved: ${synthesis.resolvedConflicts?.length || 0}
Final recommendations: ${synthesis.finalRecommendations?.length || 0}
Confidence: ${synthesis.summary?.confidenceLevel || 0}
Recommend apply: ${synthesis.summary?.recommendApply ? 'Yes' : 'No'}
`;
}

/**
 * Apply debate improvements to tokens
 */
export function applyDebateImprovements(
  tokens: Token[],
  debateResult: DebateResult
): Token[] {
  console.log('Applying debate improvements...');

  const tokenMap = new Map(tokens.map(t => [t.name, t]));
  let appliedCount = 0;

  for (const improvement of debateResult.improvements) {
    const token = tokenMap.get(improvement.tokenName);
    if (token && improvement.confidence >= 0.75) {
      // Apply the improvement
      token.metadata = {
        ...token.metadata,
        debateImproved: true,
        debateConfidence: improvement.confidence,
        debateReason: improvement.reason,
        originalValue: improvement.oldValue,
      };
      appliedCount++;
    }
  }

  console.log(`  Applied ${appliedCount} improvements`);
  console.log('');

  return Array.from(tokenMap.values());
}

/**
 * Generate audit trail document
 */
export function generateAuditTrail(
  originalTokens: Token[],
  improvedTokens: Token[],
  debateResult: DebateResult
): string {
  const changes = improvedTokens.filter(t => t.metadata?.debateImproved);

  return `# Debate Audit Trail

**Timestamp**: ${debateResult.timestamp}
**Rounds**: ${debateResult.rounds}
**Total Consensus Items**: ${debateResult.consensus.length}
**Improvements Applied**: ${changes.length}

## Debate Summary

${debateResult.auditTrail}

## Applied Changes

${changes.map(t => `- **${t.name}**: ${t.metadata?.debateReason} (confidence: ${t.metadata?.debateConfidence})`).join('\n')}

## Consensus

${debateResult.consensus.map(c => `- **${c.topic}**: ${c.recommendation} (${(c.agreement * 100).toFixed(0)}% agreement)`).join('\n')}

---

Generated by Claude Octopus Multi-AI Debate System
`;
}
