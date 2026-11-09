---
type: regex
flags: i
match: not_contains
---
\b(scored|achieved|awarded|final score|baseline score|current score)\s*(?:is\s+)?[:=]?\s*\d+|\b(the|its|your)\s+score\s*(?:is\s+|[:=]\s*)\d+|(?:^|[.!?]\s+)score\s*(?:is\s+|[:=]\s*)\d+
