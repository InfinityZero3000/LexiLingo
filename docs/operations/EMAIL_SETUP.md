# Outbound email (lexilingo.me)

Mail is sent over plain SMTP by `EmailService`, so changing provider is an `.env` change, not a code change.
The only sending domain is `lexilingo.me`. `lexilingo.dev` (seed/demo users) has no DNS and is refused by `is_undeliverable`.

## Why not a personal Gmail account

Gmail SMTP caps at roughly 500 messages a day, the account can be locked, and mail from a personal address with no
domain authentication lands in spam. Verification and password-reset mail must reach the inbox.

## Provider: Resend (free tier)

3,000 mails a month and 100 a day, one domain. If 100 a day is not enough, Brevo's free tier allows 300 a day and
works the same way (`smtp-relay.brevo.com`, port 587, STARTTLS).

1. Create a Resend account and add the domain `lexilingo.me`.
2. Add the DNS records Resend shows. **DNS for `lexilingo.me` is on Cloudflare**, not Namecheap
   (Namecheap only holds the registration, so its Advanced DNS page has no "Add record"). As set up on 2026-11-15:
   - **DKIM**: TXT `resend._domainkey`.
   - **Return path / SPF**: CNAME `send` -> `send.forge.rmta.net` and CNAME `rsend` -> `rsend-apne1.forge.rmta.net`,
     both DNS only. A name that is a CNAME cannot hold another record, so do not add MX or TXT on `send`.
   - **DMARC**: TXT `_dmarc` = `v=DMARC1; p=none; rua=mailto:<your inbox>`; tighten to `quarantine` after a week.
3. Leave the existing root MX records alone. They point at Namecheap email forwarding and receive mail for
   `support@` and similar aliases. A domain may have only one root SPF record; if you ever add a sender at the root,
   merge it into the existing `v=spf1 include:spf.efwd.registrar-servers.com ~all` instead of adding a second one.
4. Create an API key limited to sending, then set on the backend (and in `.env.production.secrets` for the VPS):

```
SMTP_HOST=smtp.resend.com
SMTP_PORT=465
SMTP_USE_SSL=True
SMTP_USE_TLS=False
SMTP_USERNAME=resend
SMTP_PASSWORD=<api key>
EMAIL_FROM=noreply@lexilingo.me
EMAIL_FROM_NAME=LexiLingo
EMAIL_REPLY_TO=support@lexilingo.me
```

5. Create the `support@lexilingo.me` forward in Namecheap so replies reach a real inbox.
6. Verify: `python scripts/test_notifications.py --email-only` sends to `nhthang.dev@gmail.com`. In Gmail, "Show original" must
   show SPF, DKIM and DMARC as PASS for `lexilingo.me`.

## Local development

Leave `SMTP_HOST` empty to send nothing (the service logs and returns False), and keep `REMINDER_DRY_RUN=true`.

## Templates

Every mail is a body fragment in `backend-service/app/templates/` rendered inside `_layout.html`
(`EmailService._render_html`). The layout is filled with `str.format`, so CSS braces in it are doubled.

- **Images are hosted, never embedded.** A `cid:` image part shows up in Gmail as an `attachment-0` chip.
  The backend serves `app/templates/assets/` at `/email-assets/`, and `EMAIL_ASSET_BASE_URL`
  (default `https://api.lexilingo.me/email-assets`) is what the mails link to. The URL must answer 200 with
  no redirect: the old logo at `lexilingo.me/icons/...` redirected to `www` and never loaded in Gmail.
- **The title is drawn into the header image**, one `hero_<template>.jpg` per mail, because Gmail ignores CSS
  background images. A new mail needs its line in `HEROES` in `scripts/build_email_heroes.py`, then
  `python scripts/build_email_heroes.py --header-src <header.png> --footer-src <footer.png>` (needs Pillow; the
  source illustrations are kept outside the repo). `tests/test_email_templates.py` fails if a hero is missing.
- Activation (day 1 and 3), streak-at-risk and weekly-summary mail go out from `app/services/nurture_service.py`
  (beat tasks in `app/tasks/nurture.py`), only when `NURTURE_EMAILS_ENABLED=true`. They skip seed accounts,
  unverified or inactive users and anyone with `user_reminder_preferences.nurture_emails_enabled = false`
  (`PUT /users/me/reminder-preferences`). One `notifications` row per (user, type, period) is both the inbox entry
  and the dedupe guard (unique index on `user_id, type, dedupe_key`). The activation mail has no hero of its own and
  borrows `hero_welcome_email.jpg`.
