# ICTA Mathematical Strengthening Implementation Plan

> **For agentic workers:** Execute these minimal steps in order; do not change benchmark artifacts.

**Goal:** Strengthen the three requested technical claims while preserving a professional, exactly eight-page ICTA DOCM.

**Architecture:** Extend the existing single-file paper builder with bordered equation paragraphs and Word bookmark hyperlinks. Replace existing prose so pagination remains stable.

**Tech Stack:** Python, python-docx XML helpers, Microsoft Word pagination.

---

### Task 1: Word primitives

**Files:**
- Modify: `model-development/scripts/build_icta_paper.py`

- [x] Add a reusable paragraph-border helper.
- [x] Keep citations as ordinary text without internal bookmarks.
- [x] Validate that `word/document.xml` contains no citation hyperlinks or bookmarks.

### Task 2: Strengthen the paper

**Files:**
- Modify: `model-development/scripts/build_icta_paper.py`

- [x] Replace the correctness prose with a compact proposition, equation, and proof sketch.
- [x] Expand Selective IRCoT trigger, bridge retrieval, and contract validation.
- [x] Distinguish benchmark SCAR features from production SCAR features.
- [x] Border the routing algorithm and central equations.

### Task 3: Build and verify

**Files:**
- Generate: `model-development/pdf/TRACE-CAG_ICTA_2026_camera_ready_8pages_v5.docm`

- [x] Build the DOCM and verify the ZIP plus VBA payload.
- [x] Verify all citation anchors resolve.
- [x] Open in Microsoft Word and confirm exactly eight pages.
- [x] Inspect document structure for table/image widths and bordered equations.
