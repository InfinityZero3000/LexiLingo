# Unified JWT Secret Key Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use `SECRET_KEY` as the single environment variable for signing backend JWTs and verifying them in the AI service.

**Architecture:** The backend remains the JWT issuer and continues reading `SECRET_KEY`. The AI service becomes a strict JWT verifier that reads the same `SECRET_KEY` without accepting legacy aliases, so deployment drift is detected instead of silently selecting another key.

**Tech Stack:** Python, FastAPI, python-jose, pytest, dotenv/Docker environment variables

---

## Chunk 1: Runtime Contract

### Task 1: Make AI JWT verification strict

**Files:**
- Modify: `ai-service/api/core/auth.py`
- Test: `ai-service/tests/test_auth_module.py`

- [x] Add a test proving `JWT_SECRET_KEY` is not accepted when `SECRET_KEY` is absent.
- [x] Change the AI JWT secret resolver to read only `SECRET_KEY`.
- [x] Run `pytest tests/test_auth_module.py -q` from `ai-service`.

## Chunk 2: Deployment Configuration

### Task 2: Normalize environment variable names

**Files:**
- Modify: `ai-service/.env.example`
- Modify locally: `ai-service/.env.production`
- Modify locally: `ai-service/.env.production.secrets`
- Modify locally: `backend-service/.env.production.secrets`

- [x] Rename `JWT_SECRET_KEY` entries to `SECRET_KEY` without changing values.
- [x] Confirm active code and deploy configuration contain no `JWT_SECRET_KEY` or `AI_JWT_SECRET_KEY`.
- [x] Confirm each deployment path supplies one shared `SECRET_KEY` to both services.
