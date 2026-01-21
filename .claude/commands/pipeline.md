---
command: octo:pipeline
description: "Run content analysis pipeline on URL(s) to extract patterns and create anatomy guides"
---

# /octo:pipeline

Analyze content from URLs to extract patterns, psychological techniques, and structural elements.

**Usage:**
```
/octo:pipeline <url>
/octo:pipeline <url1> <url2> <url3>
```

**What it does:**
1. Validates and fetches content from URLs
2. Deconstructs patterns (structure, psychology, mechanics)
3. Synthesizes findings into an anatomy guide
4. Generates interview questions for content recreation

**See:** skill-content-pipeline for full documentation.

---

**Example:**
```
/octo:pipeline https://example.com/great-article

→ Fetching content...
→ Analyzing structure, psychology, mechanics...
→ Generating anatomy guide...
→ Creating interview questions...

✓ Analysis complete! See results below.
```
