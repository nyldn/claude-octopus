# Extraction Methodology

## Overview

This document details the technical approach for parsing JSONL transcript files and extracting meaningful conversation data for keyword analysis.

## Core Parsing Strategy

### Line-by-Line JSONL Processing

JSONL files must be read line-by-line (not loaded entirely into memory) to handle large transcript files efficiently.

#### Node.js Implementation

```javascript
const fs = require('fs');
const readline = require('readline');
const path = require('path');

async function parseTranscript(filePath) {
  const messages = [];
  const fileStream = fs.createReadStream(filePath);

  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    try {
      const message = JSON.parse(line);
      messages.push(message);
    } catch (error) {
      console.error(`Failed to parse line in ${filePath}:`, error.message);
      // Skip malformed lines
    }
  }

  return messages;
}
```

#### Python Implementation

```python
import json
from typing import List, Dict, Any
from pathlib import Path

def parse_transcript(file_path: Path) -> List[Dict[str, Any]]:
    """Parse a JSONL transcript file into a list of message objects."""
    messages = []

    with open(file_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue

            try:
                message = json.loads(line)
                messages.append(message)
            except json.JSONDecodeError as e:
                print(f"Error parsing line {line_num} in {file_path}: {e}")
                continue

    return messages
```

## Conversation Reconstruction

### Message Grouping

Group messages into conversation units based on:
1. **User Messages** - Starting points for conversation turns
2. **Tool Sequences** - Series of tool_use/tool_result pairs
3. **Assistant Responses** - Text responses (when present)

### Conversation Turn Structure

```typescript
interface ConversationTurn {
  sessionId: string;
  turnIndex: number;
  userMessage: string;
  timestamp: string;
  toolSequence: ToolExecution[];
  outcome: 'success' | 'error' | 'partial';
}

interface ToolExecution {
  toolName: string;
  toolInput: Record<string, any>;
  toolOutput: Record<string, any>;
  timestamp: string;
}
```

### Reconstruction Algorithm

```javascript
function reconstructConversations(messages) {
  const conversations = [];
  let currentTurn = null;
  let toolSequence = [];

  for (const message of messages) {
    switch (message.type) {
      case 'user':
        // Save previous turn if exists
        if (currentTurn) {
          currentTurn.toolSequence = toolSequence;
          conversations.push(currentTurn);
        }

        // Start new turn
        currentTurn = {
          userMessage: message.content,
          timestamp: message.timestamp,
          toolSequence: [],
          turnIndex: conversations.length
        };
        toolSequence = [];
        break;

      case 'tool_use':
        // Add to current tool sequence
        const tool = {
          toolName: message.tool_name,
          toolInput: message.tool_input,
          timestamp: message.timestamp
        };
        toolSequence.push(tool);
        break;

      case 'tool_result':
        // Find matching tool_use and attach result
        const matchingTool = toolSequence.find(
          t => t.toolName === message.tool_name && !t.output
        );
        if (matchingTool) {
          matchingTool.output = message.tool_output;
        }
        break;

      case 'assistant':
        // Assistant text responses (less common in tool-heavy conversations)
        if (currentTurn) {
          currentTurn.assistantResponse = message.content;
        }
        break;
    }
  }

  // Save final turn
  if (currentTurn) {
    currentTurn.toolSequence = toolSequence;
    conversations.push(currentTurn);
  }

  return conversations;
}
```

## Timestamp-Based Chronological Ordering

All messages include ISO 8601 timestamps. Use these for:

1. **Session Timeline Construction**
2. **Multi-turn Conversation Detection**
3. **Response Time Analysis**
4. **Tool Execution Ordering**

```javascript
function sortByTimestamp(messages) {
  return messages.sort((a, b) =>
    new Date(a.timestamp) - new Date(b.timestamp)
  );
}

function calculateResponseTime(userMessage, firstToolUse) {
  const userTime = new Date(userMessage.timestamp);
  const toolTime = new Date(firstToolUse.timestamp);
  return toolTime - userTime; // milliseconds
}
```

## Tool Context Preservation

### Tool Invocation Patterns

Track which tools are used in response to different user requests:

```javascript
function extractToolPatterns(conversations) {
  const patterns = {};

  for (const turn of conversations) {
    const userIntent = turn.userMessage;
    const tools = turn.toolSequence.map(t => t.toolName);
    const toolChain = tools.join(' → ');

    if (!patterns[toolChain]) {
      patterns[toolChain] = {
        count: 0,
        examples: []
      };
    }

    patterns[toolChain].count++;
    if (patterns[toolChain].examples.length < 5) {
      patterns[toolChain].examples.push(userIntent);
    }
  }

  return patterns;
}
```

### Tool Success Detection

Determine if tool executions were successful:

```javascript
function determineOutcome(toolSequence) {
  if (toolSequence.length === 0) {
    return 'no_tools';
  }

  // Check for bash command failures
  const bashCommands = toolSequence.filter(t => t.toolName === 'bash');
  const hasFailures = bashCommands.some(
    cmd => cmd.output && cmd.output.exit !== 0
  );

  if (hasFailures) {
    return 'error';
  }

  // Check if all tools have outputs
  const allComplete = toolSequence.every(t => t.output);
  return allComplete ? 'success' : 'partial';
}
```

## User Message Extraction

### Primary Extraction

Extract all user messages with metadata:

```javascript
function extractUserMessages(messages) {
  return messages
    .filter(m => m.type === 'user')
    .map(m => ({
      content: m.content,
      timestamp: m.timestamp,
      wordCount: m.content.split(/\s+/).length,
      hasCodeBlock: m.content.includes('```'),
      hasPath: /\/[a-zA-Z0-9_\-/.]+/.test(m.content)
    }));
}
```

### Filtering Criteria

Apply filters to focus on relevant messages:

```javascript
function filterRelevantMessages(userMessages) {
  return userMessages.filter(msg => {
    // Exclude single-word commands
    if (msg.wordCount < 2) return false;

    // Exclude purely navigational
    const navPattern = /^(ls|pwd|cd|cat|head|tail)\s/i;
    if (navPattern.test(msg.content)) return false;

    // Exclude pure questions without action
    const questionOnly = /^(what|where|how|why|when)\s/i;
    if (questionOnly.test(msg.content) && msg.wordCount < 5) return false;

    return true;
  });
}
```

## Text Normalization

### Preprocessing Pipeline

```javascript
function normalizeText(text) {
  return text
    // Convert to lowercase
    .toLowerCase()
    // Remove file paths
    .replace(/\/[a-zA-Z0-9_\-/.]+/g, '<PATH>')
    // Remove URLs
    .replace(/https?:\/\/[^\s]+/g, '<URL>')
    // Remove code blocks
    .replace(/```[\s\S]*?```/g, '<CODE>')
    // Normalize whitespace
    .replace(/\s+/g, ' ')
    .trim();
}
```

### Tokenization

```javascript
function tokenize(text) {
  return text
    .split(/\s+/)
    .filter(word => word.length > 1)
    .filter(word => !/^[0-9]+$/.test(word)); // Remove pure numbers
}
```

## Multi-Session Aggregation

### Batch Processing

Process all transcript files and aggregate results:

```javascript
const glob = require('glob');

async function processAllTranscripts(transcriptDir) {
  const files = glob.sync(`${transcriptDir}/*.jsonl`);
  const allConversations = [];

  for (const file of files) {
    try {
      const messages = await parseTranscript(file);
      const conversations = reconstructConversations(messages);

      conversations.forEach(conv => {
        conv.sessionId = path.basename(file, '.jsonl');
      });

      allConversations.push(...conversations);
    } catch (error) {
      console.error(`Error processing ${file}:`, error.message);
    }
  }

  return allConversations;
}
```

### Deduplication

Remove duplicate or near-duplicate user requests:

```javascript
function deduplicateMessages(messages) {
  const seen = new Set();
  const unique = [];

  for (const msg of messages) {
    const normalized = normalizeText(msg.content);
    if (!seen.has(normalized)) {
      seen.add(normalized);
      unique.push(msg);
    }
  }

  return unique;
}
```

## Output Format

### Structured JSON Export

```javascript
function exportConversations(conversations, outputPath) {
  const data = {
    metadata: {
      totalConversations: conversations.length,
      extractedAt: new Date().toISOString(),
      sourceDirectory: '/Users/chris/.claude/transcripts/'
    },
    conversations: conversations.map(conv => ({
      sessionId: conv.sessionId,
      turnIndex: conv.turnIndex,
      userMessage: conv.userMessage,
      timestamp: conv.timestamp,
      tools: conv.toolSequence.map(t => t.toolName),
      outcome: determineOutcome(conv.toolSequence)
    }))
  };

  fs.writeFileSync(outputPath, JSON.stringify(data, null, 2));
}
```

### CSV Export for Analysis

```javascript
function exportToCSV(conversations, outputPath) {
  const csv = [
    'session_id,turn_index,user_message,timestamp,tools,outcome'
  ];

  for (const conv of conversations) {
    const tools = conv.toolSequence.map(t => t.toolName).join(';');
    const message = conv.userMessage.replace(/"/g, '""'); // Escape quotes
    csv.push(
      `"${conv.sessionId}",${conv.turnIndex},"${message}","${conv.timestamp}","${tools}","${determineOutcome(conv.toolSequence)}"`
    );
  }

  fs.writeFileSync(outputPath, csv.join('\n'));
}
```

## Error Handling

### Robust Parsing

```javascript
async function safeParseTranscript(filePath) {
  try {
    const messages = await parseTranscript(filePath);

    // Validate message structure
    const valid = messages.every(m =>
      m.type && m.timestamp && (m.content || m.tool_name)
    );

    if (!valid) {
      console.warn(`Invalid messages in ${filePath}`);
    }

    return messages;
  } catch (error) {
    console.error(`Failed to parse ${filePath}:`, error);
    return [];
  }
}
```

### Progress Reporting

```javascript
async function processWithProgress(files) {
  const total = files.length;
  let processed = 0;

  for (const file of files) {
    await safeParseTranscript(file);
    processed++;

    if (processed % 10 === 0) {
      console.log(`Progress: ${processed}/${total} (${Math.round(processed/total*100)}%)`);
    }
  }
}
```

## Performance Optimization

### Streaming Processing

For very large datasets, use streaming to avoid memory issues:

```javascript
const { Transform } = require('stream');

class MessageProcessor extends Transform {
  constructor() {
    super({ objectMode: true });
    this.buffer = '';
  }

  _transform(chunk, encoding, callback) {
    this.buffer += chunk.toString();
    const lines = this.buffer.split('\n');
    this.buffer = lines.pop();

    for (const line of lines) {
      if (line.trim()) {
        try {
          const message = JSON.parse(line);
          this.push(message);
        } catch (e) {
          // Skip invalid JSON
        }
      }
    }

    callback();
  }
}
```

---

**Next Steps:** Proceed to `03-keyword-analysis-framework.md` to learn NLP techniques for extracting keywords from parsed conversations.
