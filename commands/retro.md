---
command: retro
description: "[advanced] Generate engineering retrospectives from git history with trends and team analysis"
allowed-tools: Bash, Read, Glob, Grep, Write
---

# Retro — Engineering Retrospective from Git History

**Your first output line MUST be:** `🐙 Octopus Retrospective`

Generate data-driven engineering retrospectives by mining git history. Surfaces commit patterns, contributor breakdown, hotspots, session analysis, and AI-assisted commit tracking.

## Usage

```
/octo:retro              # Last 7 days (default)
/octo:retro 24h          # Last 24 hours
/octo:retro 14d          # Last 14 days
/octo:retro 30d          # Last 30 days
```

## Instructions

When the user invokes `/octo:retro`, you MUST follow these steps exactly.

### 1. Parse Time Window

Accept an optional argument for the time window. Default to `7d` if none provided.

Supported formats:
- `24h` — last 24 hours (`--since='24 hours ago'`)
- `7d` — last 7 days (`--since='7 days ago'`)
- `14d` — last 14 days (`--since='14 days ago'`)
- `30d` — last 30 days (`--since='30 days ago'`)

Map the argument to a git `--since` value. If the argument does not match a supported format, warn the user and fall back to `7d`.

### 2. Gather Git Data

Run the following git commands to collect raw data. Each command MUST be executed — do NOT skip any.

**Commit list:**
```bash
git log --oneline --since='<window>' --no-merges
```

**LOC changes (lines added/removed per file):**
```bash
git log --numstat --since='<window>' --no-merges --format=''
```

**Contributor leaderboard:**
```bash
git shortlog -sn --since='<window>' --no-merges
```

**Hotspot analysis (files modified most often):**
```bash
git log --format='' --name-only --since='<window>' --no-merges | sort | uniq -c | sort -rn | head -20
```

**PR merge count (merge commits):**
```bash
git log --oneline --since='<window>' --merges | wc -l
```

**Commit timestamps for session detection:**
```bash
git log --format='%at %H %s' --since='<window>' --no-merges
```

**AI-assisted commit detection:**
```bash
git log --since='<window>' --no-merges --format='%b' | grep -ci 'Co-Authored-By:'
```

**Current user identification:**
```bash
git config user.name
```

### 3. Compute and Display Results

Present the retrospective in this structured format:

#### Summary Table

| Metric | Value |
|--------|-------|
| Time window | `<window>` |
| Total commits | N |
| Lines added | +N |
| Lines removed | -N |
| Net change | +/-N |
| PRs merged | N |
| Contributors | N |
| AI-assisted commits | N (X%) |

#### Per-Contributor Breakdown

For each contributor from `git shortlog`, show:
- Commit count
- Lines added / removed
- Label the current user (from `git config user.name`) as **"You"**

Format as a table sorted by commit count descending.

#### Commit Type Breakdown

Parse commit messages for conventional commit prefixes. Count each type:
- `feat:` / `feature:` — Features
- `fix:` — Bug fixes
- `refactor:` — Refactoring
- `test:` — Tests
- `chore:` — Chores
- `docs:` — Documentation
- `perf:` — Performance
- `ci:` — CI/CD
- Other — anything that does not match

Calculate the **test ratio**: test commits / total commits.

Display as a table with counts and percentages.

#### Hotspot Analysis

Show the top 10 most-changed files from the hotspot data. These are files modified across the most commits (not by LOC). Flag any file appearing in more than 30% of commits as a potential refactoring candidate.

#### Session Detection

Analyze commit timestamps to detect work sessions. A gap of 45 minutes or more between consecutive commits marks a new session.

For each detected session, show:
- Session number
- Start time — end time
- Duration
- Commit count in session

Show total session count and average session length.

### 4. Save JSON Snapshot

Save a structured JSON snapshot to `.claude-octopus/retros/<date>.json` (where `<date>` is today in YYYY-MM-DD format).

```bash
mkdir -p .claude-octopus/retros
```

The JSON MUST include these fields:
```json
{
  "date": "YYYY-MM-DD",
  "window": "<window>",
  "total_commits": N,
  "lines_added": N,
  "lines_removed": N,
  "prs_merged": N,
  "contributors": N,
  "ai_assisted_commits": N,
  "test_ratio": 0.XX,
  "top_hotspots": ["file1", "file2", ...],
  "sessions": N,
  "avg_session_minutes": N,
  "commit_types": {
    "feat": N,
    "fix": N,
    "refactor": N,
    "test": N,
    "chore": N,
    "docs": N,
    "other": N
  }
}
```

### 5. Compare with Prior Snapshot

After saving, check if a prior snapshot exists in `.claude-octopus/retros/`. If one is found:

- Load the most recent prior JSON
- Compare key metrics: commits, LOC, test ratio, sessions, AI-assisted %
- Show a delta table with arrows indicating direction of change

Example:
```
Compared to <prior-date>:
  Commits:     42 → 58 (+38%)  ↑
  Test ratio:  0.12 → 0.18     ↑
  Sessions:    8 → 11          ↑
  AI-assisted: 24% → 31%       ↑
```

If no prior snapshot exists, note that this is the first retrospective and future runs will include comparisons.

## What You Get

- Data-driven view of engineering activity
- Contributor visibility (with privacy — current user labeled as "You")
- Commit hygiene metrics (conventional commit adherence, test ratio)
- Hotspot warnings for over-touched files
- Work pattern analysis via session detection
- AI adoption tracking via Co-Authored-By detection
- Trend comparison across retrospectives

## Cost

Retro uses only local git commands and Claude (included with Claude Code). No external provider costs.
