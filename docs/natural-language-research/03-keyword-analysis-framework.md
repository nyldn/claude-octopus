# Keyword Analysis Framework

## Overview

This document outlines Natural Language Processing (NLP) techniques for extracting meaningful keyword phrases from Claude Code conversation transcripts.

## N-gram Extraction

### Definition

N-grams are contiguous sequences of N words from text. For workflow trigger detection, we focus on:

- **Bigrams (2-grams):** Two-word phrases (e.g., "review code", "optimize performance")
- **Trigrams (3-grams):** Three-word phrases (e.g., "analyze security vulnerabilities", "generate API documentation")
- **4-grams:** Four-word phrases (e.g., "implement real-time data sync")
- **5-grams:** Five-word phrases (e.g., "build a scalable microservices architecture")

### Python Implementation

```python
from collections import Counter
from typing import List, Tuple
import re

def extract_ngrams(text: str, n: int) -> List[Tuple[str, ...]]:
    """Extract n-grams from text."""
    # Tokenize
    words = re.findall(r'\b\w+\b', text.lower())

    # Filter stopwords for better results
    stopwords = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for'}
    words = [w for w in words if w not in stopwords]

    # Generate n-grams
    ngrams = []
    for i in range(len(words) - n + 1):
        ngrams.append(tuple(words[i:i+n]))

    return ngrams

def extract_all_ngrams(text: str, min_n: int = 2, max_n: int = 5) -> List[Tuple[str, ...]]:
    """Extract all n-grams from min_n to max_n."""
    all_ngrams = []
    for n in range(min_n, max_n + 1):
        all_ngrams.extend(extract_ngrams(text, n))
    return all_ngrams
```

### Example Output

**Input:** "review this code for security vulnerabilities and performance issues"

**Bigrams:**
- ("review", "code")
- ("code", "security")
- ("security", "vulnerabilities")
- ("performance", "issues")

**Trigrams:**
- ("review", "code", "security")
- ("code", "security", "vulnerabilities")
- ("security", "vulnerabilities", "performance")

**4-grams:**
- ("review", "code", "security", "vulnerabilities")

## TF-IDF Scoring

### Term Frequency-Inverse Document Frequency

TF-IDF identifies phrases that are distinctive to certain types of requests.

**Formula:**
```
TF-IDF(phrase, document, corpus) = TF(phrase, document) × IDF(phrase, corpus)

TF(phrase, doc) = (count of phrase in doc) / (total phrases in doc)
IDF(phrase, corpus) = log(total documents / documents containing phrase)
```

### Python Implementation

```python
from sklearn.feature_extraction.text import TfidfVectorizer
import numpy as np

def compute_tfidf_keywords(conversations: List[str], top_n: int = 100):
    """
    Extract top keywords using TF-IDF.

    Args:
        conversations: List of user message strings
        top_n: Number of top keywords to extract

    Returns:
        List of (phrase, score) tuples
    """
    # Configure vectorizer for 2-5 word phrases
    vectorizer = TfidfVectorizer(
        ngram_range=(2, 5),
        max_features=1000,
        stop_words='english',
        min_df=2,  # Phrase must appear in at least 2 documents
        max_df=0.5  # Phrase must appear in less than 50% of documents
    )

    # Fit and transform
    tfidf_matrix = vectorizer.fit_transform(conversations)

    # Get feature names (phrases)
    feature_names = vectorizer.get_feature_names_out()

    # Calculate mean TF-IDF score for each phrase
    mean_scores = np.asarray(tfidf_matrix.mean(axis=0)).flatten()

    # Sort by score
    top_indices = mean_scores.argsort()[-top_n:][::-1]

    # Return top phrases with scores
    return [(feature_names[i], mean_scores[i]) for i in top_indices]
```

### Example Output

```python
[
    ("review code", 0.342),
    ("optimize performance", 0.298),
    ("security vulnerabilities", 0.287),
    ("generate documentation", 0.265),
    ("implement authentication", 0.251),
    ("analyze database schema", 0.243),
    ("write unit tests", 0.231),
    ("refactor architecture", 0.224),
    ("deploy production", 0.218),
    ("investigate error", 0.207)
]
```

## Collocation Detection

### Point-wise Mutual Information (PMI)

PMI identifies word pairs that occur together more often than chance.

```python
from math import log2
from collections import defaultdict

def calculate_pmi(bigrams, word_freq, bigram_freq, total_words):
    """Calculate PMI scores for bigrams."""
    pmi_scores = {}

    for bigram in bigrams:
        w1, w2 = bigram

        # P(w1, w2)
        p_bigram = bigram_freq[bigram] / total_words

        # P(w1) * P(w2)
        p_w1 = word_freq[w1] / total_words
        p_w2 = word_freq[w2] / total_words
        p_independent = p_w1 * p_w2

        # PMI = log2(P(w1,w2) / (P(w1) * P(w2)))
        if p_independent > 0:
            pmi = log2(p_bigram / p_independent)
            pmi_scores[bigram] = pmi

    return pmi_scores
```

### spaCy Collocation Detection

```python
import spacy
from collections import Counter

def extract_collocations(texts: List[str], min_freq: int = 5):
    """Extract meaningful collocations using spaCy."""
    nlp = spacy.load("en_core_web_sm")

    collocations = []

    for text in texts:
        doc = nlp(text)

        # Extract verb + noun patterns
        for i in range(len(doc) - 1):
            if doc[i].pos_ == "VERB" and doc[i+1].pos_ == "NOUN":
                collocations.append((doc[i].lemma_, doc[i+1].lemma_))

        # Extract adjective + noun patterns
        for i in range(len(doc) - 1):
            if doc[i].pos_ == "ADJ" and doc[i+1].pos_ == "NOUN":
                collocations.append((doc[i].lemma_, doc[i+1].lemma_))

    # Count and filter
    colloc_counts = Counter(collocations)
    return [(bigram, count) for bigram, count in colloc_counts.most_common()
            if count >= min_freq]
```

## Intent Classification

### Pattern Categories

Classify user messages into intent categories:

```python
import re
from typing import Dict, List

class IntentClassifier:
    def __init__(self):
        self.patterns = {
            'architecture_design': [
                r'\b(design|architect|structure|organize)\b.*\b(system|api|service|microservice)',
                r'\b(implement|build|create)\b.*\b(architecture|pattern|framework)'
            ],
            'code_review': [
                r'\b(review|check|analyze|audit)\b.*\b(code|implementation|pull request|pr)',
                r'\b(find|identify)\b.*\b(issues|problems|bugs|vulnerabilities)'
            ],
            'performance': [
                r'\b(optimize|improve|speed up|faster)\b.*\b(performance|speed|latency)',
                r'\b(profile|benchmark|measure)\b.*\b(performance|speed)'
            ],
            'security': [
                r'\b(audit|check|scan|analyze)\b.*\b(security|vulnerabilities)',
                r'\b(secure|protect|harden)\b.*\b(api|endpoint|authentication)'
            ],
            'testing': [
                r'\b(write|create|generate)\b.*\b(tests|test suite|unit tests)',
                r'\b(automate|set up)\b.*\b(testing|test|qa)'
            ],
            'documentation': [
                r'\b(write|create|generate|document)\b.*\b(docs|documentation|readme)',
                r'\b(explain|describe|document)\b.*\b(architecture|system|api)'
            ],
            'research': [
                r'\b(research|investigate|explore|analyze)\b.*\b(approach|solution|options)',
                r'\b(compare|evaluate)\b.*\b(libraries|frameworks|tools)'
            ],
            'deployment': [
                r'\b(deploy|release|publish)\b.*\b(production|staging|server)',
                r'\b(set up|configure)\b.*\b(ci|cd|pipeline|deployment)'
            ]
        }

    def classify(self, text: str) -> List[str]:
        """Classify text into intent categories."""
        text_lower = text.lower()
        matched_intents = []

        for intent, patterns in self.patterns.items():
            for pattern in patterns:
                if re.search(pattern, text_lower):
                    matched_intents.append(intent)
                    break

        return matched_intents
```

### Example Classification

```python
classifier = IntentClassifier()

examples = [
    "review this code for security issues",
    "optimize the database query performance",
    "design a microservices architecture for the API",
    "write unit tests for the authentication module",
    "generate documentation for the REST endpoints"
]

for example in examples:
    intents = classifier.classify(example)
    print(f"{example} → {intents}")
```

**Output:**
```
review this code for security issues → ['code_review', 'security']
optimize the database query performance → ['performance']
design a microservices architecture for the API → ['architecture_design']
write unit tests for the authentication module → ['testing']
generate documentation for the REST endpoints → ['documentation']
```

## Keyword Clustering

### Semantic Similarity

Group similar keywords using embeddings:

```python
from sentence_transformers import SentenceTransformer
from sklearn.cluster import KMeans
import numpy as np

def cluster_keywords(keywords: List[str], n_clusters: int = 10):
    """Cluster keywords by semantic similarity."""
    # Load pre-trained model
    model = SentenceTransformer('all-MiniLM-L6-v2')

    # Generate embeddings
    embeddings = model.encode(keywords)

    # Cluster
    kmeans = KMeans(n_clusters=n_clusters, random_state=42)
    clusters = kmeans.fit_predict(embeddings)

    # Group by cluster
    clustered = defaultdict(list)
    for keyword, cluster_id in zip(keywords, clusters):
        clustered[cluster_id].append(keyword)

    return dict(clustered)
```

## Action Verb Extraction

### Identify Command Verbs

Extract action verbs that indicate workflow intent:

```python
def extract_action_verbs(texts: List[str]) -> Counter:
    """Extract and count action verbs from texts."""
    nlp = spacy.load("en_core_web_sm")

    action_verbs = []

    for text in texts:
        doc = nlp(text)

        for token in doc:
            # Look for imperative verbs (often at start of sentence)
            if token.pos_ == "VERB" and token.dep_ in ["ROOT", "ccomp"]:
                action_verbs.append(token.lemma_)

    return Counter(action_verbs)
```

### Common Action Verbs by Category

| Category | Action Verbs |
|----------|--------------|
| **Code Review** | review, check, analyze, audit, inspect, examine |
| **Architecture** | design, architect, structure, organize, refactor |
| **Performance** | optimize, improve, speed up, profile, benchmark |
| **Security** | secure, protect, audit, scan, harden, validate |
| **Testing** | test, validate, verify, check, assert |
| **Documentation** | document, explain, describe, generate, write |
| **Deployment** | deploy, release, publish, ship, launch |
| **Research** | investigate, research, explore, analyze, compare |

## Phrase Scoring Algorithm

### Composite Scoring

Combine multiple signals to score keyword phrases:

```python
def score_phrase(phrase: str, phrase_data: Dict) -> float:
    """
    Calculate composite score for a phrase.

    Factors:
    - TF-IDF score (0-1)
    - Frequency (normalized)
    - Length bonus (2-4 words preferred)
    - Specificity (has domain terms)
    - Action verb presence
    """
    score = 0.0

    # TF-IDF component (40%)
    score += phrase_data.get('tfidf', 0) * 0.4

    # Frequency component (20%)
    max_freq = phrase_data.get('max_freq', 1)
    freq = phrase_data.get('frequency', 0)
    score += (freq / max_freq) * 0.2

    # Length bonus (20%)
    word_count = len(phrase.split())
    if 2 <= word_count <= 4:
        score += 0.2
    elif word_count == 5:
        score += 0.15

    # Specificity bonus (10%)
    domain_terms = ['api', 'database', 'security', 'performance', 'test',
                    'deploy', 'architecture', 'code', 'review', 'optimize']
    if any(term in phrase.lower() for term in domain_terms):
        score += 0.1

    # Action verb bonus (10%)
    action_verbs = ['review', 'optimize', 'design', 'implement', 'analyze',
                   'generate', 'create', 'build', 'deploy', 'test']
    if any(verb in phrase.lower() for verb in action_verbs):
        score += 0.1

    return min(score, 1.0)  # Cap at 1.0
```

## Pattern Categories

### Workflow Intent Patterns

| Pattern | Intent Category | Example Phrases |
|---------|----------------|-----------------|
| **Architecture/Design** | System design requests | "design API", "architect microservices", "structure codebase" |
| **Code Review** | Quality assessment | "review code", "check implementation", "audit pull request" |
| **Performance** | Optimization requests | "optimize query", "improve performance", "reduce latency" |
| **Security** | Security auditing | "security scan", "check vulnerabilities", "audit authentication" |
| **Testing** | Test automation | "write tests", "automate testing", "generate test cases" |
| **Documentation** | Doc generation | "generate docs", "document API", "write README" |
| **Research** | Investigation | "research approaches", "compare libraries", "analyze options" |
| **Deployment** | CI/CD workflows | "deploy to production", "setup pipeline", "configure deployment" |

## Output Format

### Keyword Extraction Results

```json
{
  "keywords": [
    {
      "phrase": "review code security",
      "frequency": 42,
      "tfidf_score": 0.342,
      "composite_score": 0.78,
      "intent_categories": ["code_review", "security"],
      "example_contexts": [
        "please review this code for security issues",
        "can you review the code and check for security vulnerabilities"
      ]
    }
  ],
  "statistics": {
    "total_phrases": 1547,
    "unique_phrases": 892,
    "top_categories": {
      "code_review": 234,
      "performance": 187,
      "security": 156
    }
  }
}
```

---

**Next Steps:** Proceed to `04-workflow-categorization.md` to map extracted keywords to specific claude-octopus personas.
