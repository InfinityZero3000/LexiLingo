#!/usr/bin/env python3
"""
env-switch.py — LexiLingo Environment Switch
═══════════════════════════════════════════════════════════════════════
Chuyển đổi toàn bộ services giữa development (local) và production.

Usage:
    python3 env-switch.py          # menu tương tác
    python3 env-switch.py dev      # chuyển sang development
    python3 env-switch.py prod     # chuyển sang production
    python3 env-switch.py --check  # xem trạng thái hiện tại

Cấu trúc template files:
    {service}/.env.development  ← URLs local là primary
    {service}/.env.production   ← URLs production là primary
    {service}/.env              ← file active (được ghi đè bởi script này)

Fallback pattern (cả dev lẫn prod):
    Mỗi service có PRIMARY_URL + FALLBACK_URL trong config.
    Code sẽ thử PRIMARY trước, nếu không kết nối được → thử FALLBACK.
    Nếu cả 2 đều fail → throw exception rõ ràng.
"""

import sys
import shutil
import os
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────

ROOT = Path(__file__).parent

SERVICES = {
    "backend": {
        "path":  ROOT / "backend-service",
        "label": "Backend (FastAPI)",
        "health": "http://localhost:8000/health",
    },
    "admin": {
        "path":  ROOT / "admin-service",
        "label": "Admin Dashboard (Vite/React)",
        "health": None,  # Vite dev server (not always running)
    },
    "flutter": {
        "path":  ROOT / "flutter-app",
        "label": "Flutter App",
        "health": None,  # mobile app
    },
    "ai": {
        "path":  ROOT / "ai-service",
        "label": "AI Service (FastAPI)",
        "health": "http://localhost:8001/health",
    },
}

# URLs để hiển thị summary sau khi switch
URL_SUMMARY = {
    "development": {
        "backend_primary":  "http://localhost:8000/api/v1",
        "backend_fallback": "https://api.lexilingo.me/api/v1",
        "ai_primary":       "http://localhost:8001/api/v1",
        "ai_fallback":      "https://api.lexilingo.me/api/v1",
    },
    "production": {
        "backend_primary":  "https://api.lexilingo.me/api/v1",
        "backend_fallback": "(none — prod only)",
        "ai_primary":       "https://api.lexilingo.me/api/v1",
        "ai_fallback":      "(none — prod only)",
    },
}

# ─────────────────────────────────────────────
# Terminal colors
# ─────────────────────────────────────────────

RESET  = "\033[0m"
BOLD   = "\033[1m"
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
BLUE   = "\033[94m"
CYAN   = "\033[96m"
DIM    = "\033[2m"


def colored(text: str, color: str) -> str:
    return f"{color}{text}{RESET}"


def bold(text: str) -> str:
    return f"{BOLD}{text}{RESET}"


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

def get_current_env(service_path: Path) -> str | None:
    """Đọc APP_ENV / VITE_ENV / ENVIRONMENT từ .env hiện tại."""
    env_file = service_path / ".env"
    if not env_file.exists():
        return None
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key in ("APP_ENV", "VITE_ENV", "ENVIRONMENT"):
            return val
    return None


def get_primary_url(service_path: Path) -> str | None:
    """Đọc URL chính từ .env hiện tại."""
    env_file = service_path / ".env"
    if not env_file.exists():
        return None
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key in ("API_BASE_URL", "VITE_BACKEND_URL", "DATABASE_URL") and val:
            return val
    return None


def check_reachable(url: str, timeout: int = 3) -> bool:
    """Kiểm tra URL có respond không (health check)."""
    try:
        urllib.request.urlopen(url, timeout=timeout)
        return True
    except Exception:
        return False


def switch_env(service_name: str, env_type: str) -> bool:
    """Copy .env.{env_type} → .env cho một service. Trả về True nếu thành công."""
    svc = SERVICES[service_name]
    service_path = svc["path"]
    template = service_path / f".env.{env_type}"
    target   = service_path / ".env"

    if not template.exists():
        print(f"  {colored('✗', RED)} Template không tồn tại: {colored(str(template.relative_to(ROOT)), YELLOW)}")
        return False

    # Backup .env hiện tại
    if target.exists():
        backup = service_path / f".env.backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        shutil.copy2(target, backup)

    shutil.copy2(template, target)

    # Optional: overlay secrets file into active .env (gitignored)
    secrets_template = service_path / f".env.{env_type}.secrets"
    if secrets_template.exists():
        base_content = target.read_text()
        secrets_content = secrets_template.read_text()
        merged = (
            base_content.rstrip()
            + "\n\n# ===== Loaded from .env.{env}.secrets =====\n".replace("{env}", env_type)
            + secrets_content.strip()
            + "\n"
        )
        target.write_text(merged)

    return True


# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────

def cmd_check():
    """Hiển thị trạng thái môi trường hiện tại của tất cả services."""
    print(f"\n{bold('═══ LexiLingo — Trạng thái Environment ═══')}\n")

    for name, svc in SERVICES.items():
        path     = svc["path"]
        env_val  = get_current_env(path)
        pri_url  = get_primary_url(path)
        env_file = path / ".env"

        if not env_file.exists():
            status = colored("✗ Không có .env", RED)
        elif env_val:
            if env_val in ("development", "dev"):
                status = colored(f"● DEV", GREEN)
            elif env_val in ("production", "prod"):
                status = colored(f"● PROD", RED)
            else:
                status = colored(f"● {env_val}", YELLOW)
        else:
            status = colored("● (APP_ENV không set)", DIM)

        # Health check
        health_url = svc.get("health")
        if health_url:
            alive = check_reachable(health_url)
            health_str = colored("online", GREEN) if alive else colored("offline", DIM)
            health_str = f"  [{health_str}]"
        else:
            health_str = ""

        url_str = f"\n    URL: {colored(pri_url, CYAN)}" if pri_url else ""
        print(f"  {bold(svc['label'])} — {status}{health_str}{url_str}\n")

    # Template availability
    print(f"{bold('Templates:')}\n")
    for name, svc in SERVICES.items():
        path = svc["path"]
        dev_ok = "✓" if (path / ".env.development").exists() else "✗"
        prod_ok = "✓" if (path / ".env.production").exists() else "✗"
        prod_secret_ok = "✓" if (path / ".env.production.secrets").exists() else "✗"
        dev_c = GREEN if dev_ok == "✓" else RED
        prod_c = GREEN if prod_ok == "✓" else RED
        prod_secret_c = GREEN if prod_secret_ok == "✓" else DIM
        print(
            f"  {svc['label']:35s}  "
            f".env.development {colored(dev_ok, dev_c)}   "
            f".env.production {colored(prod_ok, prod_c)}   "
            f".env.production.secrets {colored(prod_secret_ok, prod_secret_c)}"
        )
    print()


def cmd_switch(env_type: str):
    """Chuyển đổi tất cả services sang env_type (development / production)."""
    env_display = "DEVELOPMENT" if env_type == "development" else "PRODUCTION"
    env_color   = GREEN if env_type == "development" else RED

    print(f"\n{bold('═══ LexiLingo — Chuyển sang')} {colored(bold(env_display), env_color)} {bold('═══')}\n")

    success_count = 0
    for name, svc in SERVICES.items():
        label   = svc["label"]
        result  = switch_env(name, env_type)
        if result:
            print(f"  {colored('✓', GREEN)} {label}")
            success_count += 1
        else:
            print(f"  {colored('✗', RED)} {label} — bỏ qua (thiếu template)")

    # Summary URLs
    urls = URL_SUMMARY[env_type]
    print(f"\n{bold('URLs đang active:')}")
    print(f"  Backend  : {colored(urls['backend_primary'], CYAN)}")
    print(f"  Fallback : {colored(urls['backend_fallback'], DIM)}")
    print(f"  AI       : {colored(urls['ai_primary'], CYAN)}")
    print(f"  Fallback : {colored(urls['ai_fallback'], DIM)}")

    # Health check
    print(f"\n{bold('Health checks:')}")
    for name, svc in SERVICES.items():
        health_url = svc.get("health")
        if not health_url:
            continue
        alive = check_reachable(health_url)
        status = colored("online ✓", GREEN) if alive else colored("offline (chưa start?)", DIM)
        print(f"  {svc['label']:30s} {status}")

    # Warnings
    print()
    if env_type == "production":
        print(colored(
            "  ⚠  Production mode — mọi request sẽ đến server thật!\n"
            "     Nhớ chuyển lại dev khi test xong: python3 env-switch.py dev",
            YELLOW
        ))
    else:
        print(colored(
            "  ℹ  Development mode — backend + AI service phải đang chạy local.\n"
            "     Nếu local down, fallback sẽ tự dùng production URL.",
            CYAN
        ))
    print()

    if success_count == len(SERVICES):
        print(colored(f"  ✓ Tất cả {success_count} services đã chuyển sang {env_display}.\n", GREEN))
    else:
        print(colored(
            f"  ⚠ {success_count}/{len(SERVICES)} services đã chuyển.\n"
            "    Kiểm tra các template còn thiếu bằng: python3 env-switch.py --check\n",
            YELLOW
        ))


def cmd_menu():
    """Menu tương tác."""
    print(f"\n{bold('═══ LexiLingo — Environment Switch ═══')}")
    print(f"\n  Chọn môi trường:\n")
    print(f"  {colored('[1]', CYAN)} Development  {DIM}(local URLs, fallback → production){RESET}")
    print(f"  {colored('[2]', RED )} Production   {DIM}(production URLs, không có fallback){RESET}")
    print(f"  {colored('[3]', DIM )} Xem trạng thái hiện tại{RESET}")
    print(f"  {colored('[0]', DIM )} Thoát{RESET}\n")

    choice = input("  Lựa chọn [1/2/3/0]: ").strip()
    if choice == "1":
        cmd_switch("development")
    elif choice == "2":
        confirm = input(
            f"\n  {colored('⚠ Chuyển sang PRODUCTION?', YELLOW)} (y/N): "
        ).strip().lower()
        if confirm == "y":
            cmd_switch("production")
        else:
            print("  Đã hủy.\n")
    elif choice == "3":
        cmd_check()
    else:
        print("  Thoát.\n")


# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args:
        cmd_menu()
        return

    arg = args[0].lower()

    if arg in ("--check", "-c", "check", "status"):
        cmd_check()
    elif arg in ("dev", "development", "local"):
        cmd_switch("development")
    elif arg in ("prod", "production"):
        # Safety: ask confirm unless --force
        if "--force" not in args:
            confirm = input(
                f"\n  {colored('⚠ Chuyển sang PRODUCTION?', YELLOW)} "
                f"(y/N, hoặc thêm --force để bỏ qua): "
            ).strip().lower()
            if confirm != "y":
                print("  Đã hủy.\n")
                return
        cmd_switch("production")
    else:
        print(f"\n  Dùng: python3 env-switch.py [dev|prod|--check]\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
