# Data Sources Documentation

## Primary Data Source: Claude Code Transcripts

### Location
```
/Users/chris/.claude/transcripts/
```

### Statistics
- **Total Files:** 282 session files
- **Total Size:** 154 MB
- **Format:** JSONL (JSON Lines)
- **Date Range:** January 2026
- **File Naming:** `ses_[session_id].jsonl`
- **Average File Size:** ~546 KB per session

### File Format: JSONL (JSON Lines)

Each transcript file contains one JSON object per line, representing individual messages, tool invocations, and results in chronological order.

#### Message Types

1. **`user`** - User input messages
2. **`assistant`** - Claude's text responses (not including tool calls)
3. **`tool_use`** - Claude invoking a tool
4. **`tool_result`** - Output returned from tool execution

### JSON Schema

#### User Message
```json
{
  "type": "user",
  "timestamp": "2026-01-18T02:37:16.717Z",
  "content": "uninstall finder.md"
}
```

**Fields:**
- `type`: Always `"user"`
- `timestamp`: ISO 8601 timestamp
- `content`: Raw user input text

#### Tool Use Message
```json
{
  "type": "tool_use",
  "timestamp": "2026-01-18T02:37:20.181Z",
  "tool_name": "glob",
  "tool_input": {
    "pattern": "**/finder.md"
  }
}
```

**Fields:**
- `type`: Always `"tool_use"`
- `timestamp`: ISO 8601 timestamp
- `tool_name`: Name of tool being invoked (e.g., `bash`, `glob`, `grep`, `read`, `write`, `edit`)
- `tool_input`: Object containing tool-specific parameters

#### Tool Result Message
```json
{
  "type": "tool_result",
  "timestamp": "2026-01-18T02:38:20.200Z",
  "tool_name": "glob",
  "tool_input": {},
  "tool_output": {
    "truncated": false
  }
}
```

**Fields:**
- `type`: Always `"tool_result"`
- `timestamp`: ISO 8601 timestamp
- `tool_name`: Name of tool that was executed
- `tool_input`: Echo of the input parameters (may include environment variables)
- `tool_output`: Object containing execution results
  - `output`: stdout text (for bash commands)
  - `exit`: Exit code (for bash commands)
  - `description`: Human-readable description
  - `truncated`: Boolean indicating if output was cut off

### Sample Conversation Flow

This example shows a typical interaction sequence from an actual transcript:

```jsonl
{"type":"user","timestamp":"2026-01-18T02:37:16.717Z","content":"uninstall finder.md"}
{"type":"tool_use","timestamp":"2026-01-18T02:37:20.181Z","tool_name":"glob","tool_input":{"pattern":"**/finder.md"}}
{"type":"tool_result","timestamp":"2026-01-18T02:38:20.200Z","tool_name":"glob","tool_input":{},"tool_output":{"truncated":false}}
{"type":"tool_use","timestamp":"2026-01-18T02:38:24.645Z","tool_name":"bash","tool_input":{"command":"find ~ -maxdepth 3 -name \"finder.md\" 2>/dev/null","description":"Find finder.md in home directory","timeout":10000}}
{"type":"tool_result","timestamp":"2026-01-18T02:38:25.263Z","tool_name":"bash","tool_input":{"command":"find ~ -maxdepth 3 -name \"finder.md\" 2>/dev/null","description":"Find finder.md in home directory","timeout":10000},"tool_output":{"output":"/Users/chris/git/finder.md\n","exit":0,"description":"Find finder.md in home directory","truncated":false}}
```

**Conversation Reconstruction:**

1. **User Request:** "uninstall finder.md" (2026-01-18 02:37:16)
2. **Tool Action:** Glob search for `**/finder.md` (2026-01-18 02:37:20)
3. **Tool Result:** No matches found (2026-01-18 02:38:20)
4. **Tool Action:** Bash find command in home directory (2026-01-18 02:38:24)
5. **Tool Result:** Found at `/Users/chris/git/finder.md` (2026-01-18 02:38:25)

### Key Patterns to Extract

#### 1. User Intent Phrases
Extract from `type: "user"` messages:
- Initial request phrasing
- Command keywords
- Action verbs
- Target nouns
- Modifiers and qualifiers

**Example Keywords:**
- "uninstall" (action verb)
- "finder.md" (target)
- "finder extension" (qualified target)

#### 2. Tool Selection Patterns
Analyze `type: "tool_use"` sequences to understand:
- Which tools Claude uses for different request types
- Common tool combinations
- Tool parameter patterns

**Example Pattern:**
- File location requests → `glob` → `bash find` → `bash rm`

#### 3. Multi-turn Conversations
Identify conversations spanning multiple user messages to understand:
- Complex workflow requests
- Clarification patterns
- Iteration and refinement

### Secondary Data Sources

#### AI Project References

These projects may contain additional context about workflow types:

**1. ai_amac-builder**
- **Location:** `/Users/chris/git/ai_amac-builder/`
- **Type:** React/TypeScript application development
- **Relevance:** Frontend architecture, component development, testing workflows

**2. ai_harvard_gazette**
- **Location:** `/Users/chris/git/ai_harvard_gazette/`
- **Type:** Content research and analysis project
- **Relevance:** Research synthesis, documentation, content workflows

### Data Extraction Strategy

#### Phase 1: Conversation Parsing
1. Read JSONL files line-by-line
2. Parse JSON objects
3. Group by session and timestamp
4. Reconstruct conversation flows

#### Phase 2: User Message Analysis
1. Extract all `type: "user"` messages
2. Filter out single-word commands
3. Focus on 2+ word phrases
4. Normalize and tokenize text

#### Phase 3: Context Enrichment
1. Associate user messages with subsequent tool_use patterns
2. Track conversation outcomes (success/failure)
3. Identify multi-turn conversations vs. one-shot requests

#### Phase 4: Anonymization
1. Remove file paths containing sensitive information
2. Redact user-specific identifiers
3. Generalize project names
4. Preserve semantic content

### File Access Methods

#### Bash (Fastest for Statistics)
```bash
# Count total files
ls -1 /Users/chris/.claude/transcripts/*.jsonl | wc -l

# Get total size
du -sh /Users/chris/.claude/transcripts/

# Sample random files
ls -1 /Users/chris/.claude/transcripts/*.jsonl | shuf -n 10

# Count total conversations
cat /Users/chris/.claude/transcripts/*.jsonl | grep '"type":"user"' | wc -l
```

#### Node.js (Best for JSONL Processing)
```javascript
const fs = require('fs');
const readline = require('readline');

async function parseTranscript(filePath) {
  const fileStream = fs.createReadStream(filePath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    const message = JSON.parse(line);
    // Process message
  }
}
```

#### Python (Best for NLP Analysis)
```python
import json

def parse_transcript(file_path):
    with open(file_path, 'r') as f:
        for line in f:
            message = json.loads(line.strip())
            # Process message
```

### Data Quality Considerations

#### Completeness
- All sessions from January 2026 are present
- Some sessions may be incomplete (interrupted/crashed)
- Tool results may be truncated for large outputs

#### Noise Reduction
- Filter out system/test conversations
- Exclude debugging sessions
- Focus on productive user interactions
- Remove repetitive error-retry loops

#### Privacy & Anonymization
- Redact absolute file paths in documentation
- Remove user-specific configuration details
- Generalize project names
- Preserve semantic patterns without exposing sensitive data

### Expected Volume

Based on 282 files at ~546 KB average:

- **Total Lines:** ~1-2 million JSON objects
- **User Messages:** ~50,000-100,000 user requests
- **Unique Sessions:** 282 distinct conversations
- **Tool Invocations:** ~200,000-400,000 tool uses
- **Date Span:** ~18 days (January 2026)

### Access Verification

To verify access and validate data sources:

```bash
# Check directory exists and is readable
ls -la /Users/chris/.claude/transcripts/ | head -10

# Verify JSONL format
head -5 /Users/chris/.claude/transcripts/*.jsonl | head -1 | python -m json.tool

# Sample random user messages
cat /Users/chris/.claude/transcripts/*.jsonl | \
  grep '"type":"user"' | \
  shuf -n 20 | \
  python -c "import sys,json; [print(json.loads(l)['content']) for l in sys.stdin]"
```

---

**Next Steps:** Proceed to `02-extraction-methodology.md` to learn how to parse and extract conversations from these transcripts.
