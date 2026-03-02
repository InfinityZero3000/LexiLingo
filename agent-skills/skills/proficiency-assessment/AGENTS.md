# LexiLingo Team - Proficiency Assessment

**Version 1.0.0**  
LexiLingo Team  
February 2026

> **Note:**  
> This document is mainly for agents and LLMs to follow when maintaining,  
> generating, or refactoring code. Humans may also find it useful, but guidance  
> here is optimized for automation and consistency by AI-assisted workflows.

---

## Abstract

Patterns for AI-driven multi-dimensional proficiency assessment in language learning applications. Covers conversation-based scoring, skill dimension mapping, confidence thresholds, and the flow from AI analysis to persistent proficiency profiles.

---

## Table of Contents

1. [Score Pipeline](##1-score-pipeline)
2. [Dimension Mapping](##2-dimension-mapping)
3. [Confidence & Thresholds](##3-confidence-&-thresholds)
4. [Data Sync](##4-data-sync)

---

## 1. Score Pipeline

**Impact: CRITICAL**

The end-to-end flow for extracting proficiency scores from AI conversations and exercises. Covers per-turn scoring in GraphCAG, session aggregation, and EMA-based skill updates.

### 1.1 Untitled

**Impact: CRITICAL**



---

## 2. Dimension Mapping

**Impact: CRITICAL**

How to map the 6 backend skill types (vocabulary, grammar, reading, listening, speaking, writing) to the 5 display dimensions (Pronunciation, Vocabulary, Fluency, Grammar, Intonation) shown on the radar chart.

### 2.1 Untitled

**Impact: CRITICAL**



---

## 3. Confidence & Thresholds

**Impact: HIGH**

Managing score reliability through interaction counting, confidence decay, and per-skill confidence tracking. Prevents showing unreliable scores.

### 3.1 Untitled

**Impact: HIGH**



---

## 4. Data Sync

**Impact: HIGH**

Synchronizing proficiency data between the AI service (MongoDB) and backend service (PostgreSQL). Handles the known disconnection gap where both services maintain separate assessment data.

### 4.1 Untitled

**Impact: HIGH**



---

## References

1. [https://www.coe.int/en/web/common-european-framework-reference-languages](https://www.coe.int/en/web/common-european-framework-reference-languages)
2. [https://www.cambridgeenglish.org/exams-and-tests/](https://www.cambridgeenglish.org/exams-and-tests/)
3. [https://www.ets.org/toefl](https://www.ets.org/toefl)
4. [https://arxiv.org/abs/2303.08774](https://arxiv.org/abs/2303.08774)
