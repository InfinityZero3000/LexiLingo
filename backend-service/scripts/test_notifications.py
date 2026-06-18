"""
Notification diagnostic & live-fire test script.

Usage (from backend-service/):
    venv/bin/python3 scripts/test_notifications.py                # email + push + reminder pipeline
    venv/bin/python3 scripts/test_notifications.py --email-only
    venv/bin/python3 scripts/test_notifications.py --push-only
    venv/bin/python3 scripts/test_notifications.py --reminder-only
    venv/bin/python3 scripts/test_notifications.py --config-check  # chỉ kiểm tra cấu hình

The script overrides REMINDER_DRY_RUN and REMINDERS_ENABLED for the duration
of its run — your .env is not modified.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
import os
from pathlib import Path

# ── make sure the package root is on sys.path ──────────────────────────────
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

os.chdir(ROOT)

# ── import settings first so we can patch before any service imports ────────
from app.core.config import settings  # noqa: E402

# ── colour helpers ──────────────────────────────────────────────────────────
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg: str)    -> None: print(f"{GREEN}  ✓ {msg}{RESET}")
def warn(msg: str)  -> None: print(f"{YELLOW}  ⚠ {msg}{RESET}")
def fail(msg: str)  -> None: print(f"{RED}  ✗ {msg}{RESET}")
def info(msg: str)  -> None: print(f"{CYAN}  → {msg}{RESET}")
def header(msg: str)-> None: print(f"\n{BOLD}{msg}{RESET}")


# ═══════════════════════════════════════════════════════════════════════════
# 1.  CONFIG CHECK
# ═══════════════════════════════════════════════════════════════════════════

def check_config() -> dict[str, bool]:
    header("═══  CONFIG CHECK  ═══")

    results: dict[str, bool] = {}

    # SMTP
    smtp_ok = bool(settings.SMTP_HOST and settings.SMTP_USERNAME and settings.SMTP_PASSWORD)
    results["smtp"] = smtp_ok
    if smtp_ok:
        ok(f"SMTP  : {settings.SMTP_HOST}:{settings.SMTP_PORT}  user={settings.SMTP_USERNAME}")
    else:
        fail("SMTP  : SMTP_HOST / SMTP_USERNAME / SMTP_PASSWORD chưa cấu hình")

    # Firebase
    fb_file  = Path(settings.FIREBASE_CREDENTIALS_FILE or "").resolve() if settings.FIREBASE_CREDENTIALS_FILE else None
    fb_json  = bool(settings.FIREBASE_CREDENTIALS_JSON)
    fb_ok    = (fb_file and fb_file.exists()) or fb_json
    results["firebase"] = bool(fb_ok)
    if fb_ok:
        src = str(fb_file) if fb_file and fb_file.exists() else "JSON env var"
        ok(f"Firebase: project={settings.FIREBASE_PROJECT_ID}  creds={src}")
    else:
        fail("Firebase: FIREBASE_CREDENTIALS_FILE không tồn tại và FIREBASE_CREDENTIALS_JSON rỗng")

    # Reminder flags
    results["reminders_enabled"] = settings.REMINDERS_ENABLED
    results["dry_run"] = settings.REMINDER_DRY_RUN
    if settings.REMINDERS_ENABLED:
        ok("REMINDERS_ENABLED = True")
    else:
        fail("REMINDERS_ENABLED = False  ← Celery task sẽ không chạy!  Thêm vào .env: REMINDERS_ENABLED=True")

    if settings.REMINDER_DRY_RUN:
        warn("REMINDER_DRY_RUN = True  ← chỉ log, không gửi thật.  Thêm vào .env: REMINDER_DRY_RUN=False")
    else:
        ok("REMINDER_DRY_RUN = False  (live mode)")

    return results


# ═══════════════════════════════════════════════════════════════════════════
# 2.  EMAIL TEST
# ═══════════════════════════════════════════════════════════════════════════

async def test_email(to_email: str) -> bool:
    header("═══  EMAIL TEST  ═══")
    from app.services.email_service import EmailService

    info(f"Gửi vocabulary review reminder đến {to_email} …")
    try:
        sent = await EmailService.send_vocabulary_review_reminder_email(
            to_email=to_email,
            display_name="Test User",
            due_count=5,
        )
    except Exception as exc:
        fail(f"Ngoại lệ khi gửi email: {exc}")
        return False

    if sent:
        ok(f"Email đã gửi thành công → {to_email}")
    else:
        fail(
            "Email không gửi được. Kiểm tra:\n"
            "    • SMTP_HOST / SMTP_USERNAME / SMTP_PASSWORD trong .env\n"
            "    • Nếu dùng Gmail: bật 2FA + tạo App Password tại myaccount.google.com\n"
            "    • SMTP_USE_SSL=True  SMTP_PORT=465  (hoặc TLS 587)"
        )
    return sent


# ═══════════════════════════════════════════════════════════════════════════
# 3.  PUSH NOTIFICATION TEST
# ═══════════════════════════════════════════════════════════════════════════

async def test_push(fcm_token: str | None) -> bool:
    header("═══  PUSH NOTIFICATION TEST  ═══")
    from app.services.push_notification_service import PushNotificationService

    if not fcm_token:
        # Pull the first active FCM token from the DB
        info("Không có --fcm-token, đang lấy token từ DB …")
        fcm_token = await _get_first_fcm_token_from_db()
        if not fcm_token:
            warn(
                "Không tìm thấy FCM token nào trong bảng user_devices.\n"
                "    Chạy lại với:  --fcm-token <token>  hoặc đảm bảo app đã đăng nhập và gửi token."
            )
            return False
        info(f"Dùng FCM token: {fcm_token[:30]}…")

    try:
        sent = await PushNotificationService().send_review_reminder(
            tokens=[fcm_token],
            due_count=7,
            title="[TEST] Vocabulary review is ready",
            body="Đây là thông báo test — bạn có 7 từ cần ôn.",
            data={"source": "test_script"},
        )
    except Exception as exc:
        fail(f"Ngoại lệ FCM: {exc}")
        return False

    if sent:
        ok("Push notification gửi thành công qua FCM!")
    else:
        fail(
            "Push notification thất bại. Kiểm tra:\n"
            "    • FIREBASE_CREDENTIALS_FILE (hoặc JSON) trong .env\n"
            "    • Firebase project ID có đúng không\n"
            "    • FCM token có còn valid không (app phải đang cài trên device)\n"
            "    • Firebase Cloud Messaging API có được bật trong Google Cloud Console không"
        )
    return sent


async def _get_first_fcm_token_from_db() -> str | None:
    try:
        from sqlalchemy import select, text
        from app.core.database import AsyncSessionLocal
        from app.models.user import UserDevice

        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(UserDevice.fcm_token)
                .where(UserDevice.fcm_token.is_not(None))
                .limit(1)
            )
            return result.scalar_one_or_none()
    except Exception as exc:
        warn(f"Không thể kết nối DB để lấy FCM token: {exc}")
        return None


# ═══════════════════════════════════════════════════════════════════════════
# 4.  REMINDER PIPELINE TEST (end-to-end, dry_run overridden)
# ═══════════════════════════════════════════════════════════════════════════

async def test_reminder_pipeline() -> None:
    header("═══  REMINDER PIPELINE TEST  ═══")

    # Force both flags on for this run
    settings.REMINDERS_ENABLED = True  # type: ignore[attr-defined]
    settings.REMINDER_DRY_RUN = False  # type: ignore[attr-defined]
    info("Overriding REMINDERS_ENABLED=True, REMINDER_DRY_RUN=False for this run")

    try:
        from datetime import datetime, timezone
        from app.core.database import AsyncSessionLocal
        from app.services.reminder_service import ReminderService

        async with AsyncSessionLocal() as db:
            svc = ReminderService()
            result = await svc.scan_due_preferences(
                db,
                now_utc=datetime.now(timezone.utc),
            )
            await db.commit()

        print()
        print(f"  {'processed':12}: {result.get('processed', 0)}")
        print(f"  {'sent':12}: {result.get('sent', 0)}")
        print(f"  {'skipped':12}: {result.get('skipped', 0)}")
        print(f"  {'failed':12}: {result.get('failed', 0)}")
        print(f"  {'dry_run':12}: {result.get('dry_run', 0)}")
        print(f"  {'reason':12}: {result.get('reason', '-')}")

        if result.get("sent", 0) > 0:
            ok("Ít nhất một reminder đã gửi thành công!")
        elif result.get("processed", 0) == 0:
            warn(
                "Không có preference nào đến hạn (next_check_at > now).\n"
                "    Thử đổi giờ nhắc nhở trong app hoặc chờ đến đúng giờ đã cài."
            )
        else:
            warn("Reminder scan chạy nhưng không gửi được (xem log phía trên để biết lý do).")

    except Exception as exc:
        fail(f"Reminder pipeline lỗi: {exc}")
        import traceback
        traceback.print_exc()


# ═══════════════════════════════════════════════════════════════════════════
# 5.  MANUAL TRIGGER — force reminder cho một user cụ thể
# ═══════════════════════════════════════════════════════════════════════════

async def force_reminder_for_user(email: str) -> None:
    header(f"═══  FORCE REMINDER cho {email}  ═══")
    settings.REMINDERS_ENABLED = True  # type: ignore[attr-defined]
    settings.REMINDER_DRY_RUN = False  # type: ignore[attr-defined]

    try:
        from datetime import datetime, timezone, timedelta
        from sqlalchemy import select
        from app.core.database import AsyncSessionLocal
        from app.models.user import User
        from app.models.reminder import UserReminderPreference
        from app.services.reminder_service import ReminderService

        async with AsyncSessionLocal() as db:
            user_result = await db.execute(select(User).where(User.email == email))
            user = user_result.scalar_one_or_none()
            if not user:
                fail(f"Không tìm thấy user với email: {email}")
                return

            pref_result = await db.execute(
                select(UserReminderPreference).where(UserReminderPreference.user_id == user.id)
            )
            pref = pref_result.scalar_one_or_none()
            if not pref:
                warn(f"User {email} chưa có reminder preference — tạo mặc định")
                pref = UserReminderPreference(user_id=user.id)
                db.add(pref)
                await db.flush()

            # Force next_check_at vào quá khứ để scan nhận ra là đến hạn
            pref.enabled = True
            pref.next_check_at = datetime.now(timezone.utc) - timedelta(minutes=1)
            await db.flush()

            svc = ReminderService()
            now = datetime.now(timezone.utc)
            partial = await svc.process_preference(db, preference=pref, now_utc=now)
            await db.commit()

        info(f"Kết quả: processed={partial.processed} sent={partial.sent} "
             f"skipped={partial.skipped} failed={partial.failed}")
        if partial.sent > 0:
            ok("Reminder gửi thành công!")
        else:
            warn("Reminder không gửi — xem log ở trên để biết chi tiết.")

    except Exception as exc:
        fail(f"Force reminder lỗi: {exc}")
        import traceback
        traceback.print_exc()


# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

async def main(args: argparse.Namespace) -> None:
    print(f"\n{BOLD}{'═'*55}")
    print("  LexiLingo — Notification Diagnostic Script")
    print(f"{'═'*55}{RESET}\n")

    cfg = check_config()

    if args.config_check:
        return

    email_ok = push_ok = True

    if not args.push_only and not args.reminder_only:
        to = args.to_email or settings.EMAIL_FROM
        if not to:
            print("Error: provide --to-email or set EMAIL_FROM in config")
            return
        email_ok = await test_email(to)

    if not args.email_only and not args.reminder_only:
        push_ok = await test_push(args.fcm_token)

    if not args.email_only and not args.push_only:
        if args.force_user:
            await force_reminder_for_user(args.force_user)
        else:
            await test_reminder_pipeline()

    header("═══  TÓM TẮT  ═══")

    if not cfg["reminders_enabled"]:
        fail(
            "REMINDERS_ENABLED=False trong .env → thêm dòng này để Celery task hoạt động:\n"
            "    REMINDERS_ENABLED=True\n"
            "    REMINDER_DRY_RUN=False"
        )
    if cfg["dry_run"]:
        warn(
            "REMINDER_DRY_RUN=True → thêm vào .env:\n"
            "    REMINDER_DRY_RUN=False"
        )
    if not cfg["firebase"]:
        fail("Firebase chưa cấu hình → push notification sẽ không hoạt động")
    if not cfg["smtp"]:
        fail("SMTP chưa cấu hình → email sẽ không hoạt động")

    if cfg["reminders_enabled"] and not cfg["dry_run"] and cfg["smtp"] and cfg["firebase"]:
        ok("Cấu hình OK — reminder sẽ gửi tự động qua Celery khi đến giờ")

    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test LexiLingo notifications")
    parser.add_argument("--email-only",    action="store_true", help="Chỉ test email")
    parser.add_argument("--push-only",     action="store_true", help="Chỉ test push notification")
    parser.add_argument("--reminder-only", action="store_true", help="Chỉ test reminder pipeline")
    parser.add_argument("--config-check",  action="store_true", help="Chỉ kiểm tra cấu hình")
    parser.add_argument("--to-email",      default=None,        help="Địa chỉ email nhận test (mặc định: EMAIL_FROM)")
    parser.add_argument("--fcm-token",     default=None,        help="FCM token cụ thể để test push")
    parser.add_argument("--force-user",    default=None,        help="Email user để force gửi reminder ngay")

    args = parser.parse_args()
    asyncio.run(main(args))
