# Learner-state load validation

Start the development stack from the repository root:

```bash
docker compose -f docker-compose.dev.yml up -d --build
```

Install load-only dependencies into a separate environment:

```bash
pip install -r ai-service/tests/load/requirements.txt
```

Run smoke and peak profiles:

```bash
cd ai-service
LEXILINGO_LOAD_TOKENS_FILE=/secure/path/load-identities.jsonl locust -f tests/load/locustfile_tracecag_learner_state.py --headless --host http://localhost:8001 -u 100 -r 10 -t 5m --csv reports/learner-state-smoke
LEXILINGO_LOAD_TOKENS_FILE=/secure/path/load-identities.jsonl locust -f tests/load/locustfile_tracecag_learner_state.py --headless --host http://localhost:8001 -u 1000 -r 50 -t 15m --csv reports/learner-state-peak
```

The identity file is newline-delimited JSON with one short-lived access token per
simulated user: `{"user_id":"<jwt-sub>","token":"<access-token>"}`. Keep it
outside the repository with mode `0600`; the run aborts when the pool has fewer
identities than requested users. A single-user probe may instead pass both
`--token` and `--user-id`.

Run dependency-injection stages separately: Redis unavailable, backend learner-state timeout, and Mongo spool latency/saturation. Record p50/p95/p99, error/degraded rates, cache decisions, queue depth/drops, PostgreSQL connections, duplicate events and state divergence.

Fail the rollout for any cross-user state leakage, duplicate application, unbounded queue/connection growth, normal-peak observation loss, p95 batch read ≥40 ms, or injected-failure observation loss ≥0.01%.
