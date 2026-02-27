# Sections

This file defines all sections, their ordering, impact levels, and descriptions.

---

## 1. Score Pipeline (pipeline)

**Impact:** CRITICAL  
**Description:** The end-to-end flow for extracting proficiency scores from AI conversations and exercises. Covers per-turn scoring in GraphCAG, session aggregation, and EMA-based skill updates.

## 2. Dimension Mapping (dimension)

**Impact:** CRITICAL  
**Description:** How to map the 6 backend skill types (vocabulary, grammar, reading, listening, speaking, writing) to the 5 display dimensions (Pronunciation, Vocabulary, Fluency, Grammar, Intonation) shown on the radar chart.

## 3. Confidence & Thresholds (confidence)

**Impact:** HIGH  
**Description:** Managing score reliability through interaction counting, confidence decay, and per-skill confidence tracking. Prevents showing unreliable scores.

## 4. Data Sync (sync)

**Impact:** HIGH  
**Description:** Synchronizing proficiency data between the AI service (MongoDB) and backend service (PostgreSQL). Handles the known disconnection gap where both services maintain separate assessment data.

## 5. Unlock & Display (display)

**Impact:** MEDIUM  
**Description:** UI patterns for displaying proficiency data including unlock thresholds, trend indicators, and actionable recommendations for skill improvement.
