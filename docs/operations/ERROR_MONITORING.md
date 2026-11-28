# Error monitoring and email reports

Request errors from backend-service, ai-service and the Celery worker are grouped, shown in the admin
Operations Center and mailed to a configurable list.

## What is captured

- Backend: every unhandled exception, every 5xx response (`kind=error`) and every 4xx response (`kind=client`).
  `/health*`, `/metrics` and `/ping` are skipped.
- Worker: every failed Celery task (`service=worker`, `method=TASK`, route = task name).
- ai-service: pushes batches to `POST /api/v1/internal/ops/errors:batch` (service token, same pair as
  entitlements). It reaches it through the private network, `LEARNER_STATE_API_URL + /ops/errors:batch`; nginx
  blocks `/api/v1/internal/` on purpose, so nothing here is exposed.

A group is `sha1(service | kind | method | route template | status | error type | location)`, where the route is
the template (`/lessons/{lesson_id}`, `<unmatched>` for scanners) and location is `file.py:function` of the last
traceback frame in `app/`. Client groups ignore error type and location. The message is not part of the key.

## What is stored, and what is not

Only a redacted sample message (emails, JWTs/bearer tokens, UUIDs and 6+ digit runs are replaced, 300 chars max),
the request id, and counts per group and hour (`ops_error_counts`, pruned after 30 days). Bodies, query strings and
headers are never read.

## Pipeline

1. The request path writes to Redis only (`ops:err:*`, ~300 ms cap, never raises). No database access, so a sick
   database does not make the error path worse.
2. `flush_error_buffer` (every minute) renames the buffer, upserts `ops_error_groups` / `ops_error_counts`, and
   sends one alert mail for: a new 5xx group, a regressed one, a 5xx group with `spike_threshold` errors in 5 min,
   or a 4xx group with `client_spike_threshold` in 5 min. One alert per group per `cooldown_minutes`.
3. `send_error_digest` (every 5 min) mails groups whose `total_count > reported_count` once
   `digest_interval_minutes` has passed since the last digest. 4xx groups only count past their threshold.
   Nothing is sent when nothing is new.
4. A `resolved` group that recurs reopens and is flagged `REGRESSED`. `muted` groups are never mailed.

## Settings

`GET/PUT /api/v1/admin/ops/error-report/settings` (read: `ops:read`, write: super admin, audited). Defaults:
enabled, recipients from env `OPS_ERROR_REPORT_RECIPIENTS` (`support@lexilingo.me`), digest every 60 min,
spike 20, client spike 200, cooldown 60. Intervals: 15, 30, 60, 180, 360, 720, 1440. 1 to 10 recipients; a
threshold of 0 turns that alert off. Needs `SMTP_*` configured.

## Operating it

- Mute or resolve a group: `PATCH /api/v1/admin/ops/errors/{fingerprint}` (super admin) or the Errors section.
- Send a test mail: `POST /api/v1/admin/ops/error-report/test`. It mails the current period and moves nothing; it
  answers 503 when `SMTP_HOST` is unset.
- Locally: run `python -m aiosmtpd -n -l localhost:1025`, point `SMTP_HOST`/`SMTP_PORT` at it (TLS off), trigger
  an error, then `flush_error_buffer_task()` and `send_error_digest_task()`.
- Tests: `pytest tests/test_ops_errors.py` (own `*_test` database).
