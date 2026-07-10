#!/usr/bin/env python3
import os
import sys
import time
import json
import shutil
import subprocess
import urllib.request
from datetime import datetime, timezone

# Load configuration
CONFIG_PATH = "/opt/lexilingo/scripts/sentinel-config.json"
default_config = {
    "check_interval_seconds": 30,
    "disk_threshold_percentage": 85,
    "nginx_security_log_path": "/opt/lexilingo/gateway/nginx/logs/security.log",
    "nginx_config_path": "/opt/lexilingo/gateway/nginx/templates/default.conf",
    "max_4xx_threshold": 150,
    "max_5xx_threshold": 40,
    "auto_restart_enabled": True,
    "auto_block_ips_enabled": True
}

if os.path.exists(CONFIG_PATH):
    try:
        with open(CONFIG_PATH, "r") as f:
            config = json.load(f)
    except Exception as e:
        print(f"[{datetime.now().isoformat()}] Failed to load config, using defaults: {e}")
        config = default_config
else:
    config = default_config

# Setup cooldowns to avoid restart loops (max 3 restarts per container every 15 minutes)
restart_history = {}  # container_name -> [timestamps]

def send_alert(message: str, severity: str = "warning"):
    emoji = "⚠️" if severity == "warning" else "🚨"
    formatted_msg = f"{emoji} *[LexiLingo Sentinel]* {message}\n_Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC_"

    # Telegram
    telegram_token = os.environ.get("TELEGRAM_BOT_TOKEN")
    telegram_chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    if telegram_token and telegram_chat_id:
        try:
            url = f"https://api.telegram.org/bot{telegram_token}/sendMessage"
            data = json.dumps({"chat_id": telegram_chat_id, "text": formatted_msg, "parse_mode": "Markdown"}).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=5) as response:
                response.read()
        except Exception as e:
            print(f"Failed to send Telegram alert: {e}")

    # Discord
    discord_webhook = os.environ.get("DISCORD_WEBHOOK_URL")
    if discord_webhook:
        try:
            data = json.dumps({"content": formatted_msg}).encode("utf-8")
            req = urllib.request.Request(discord_webhook, data=data, headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=5) as response:
                response.read()
        except Exception as e:
            print(f"Failed to send Discord alert: {e}")

    # Slack
    slack_webhook = os.environ.get("SLACK_WEBHOOK_URL")
    if slack_webhook:
        try:
            data = json.dumps({"text": formatted_msg}).encode("utf-8")
            req = urllib.request.Request(slack_webhook, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=5) as response:
                response.read()
        except Exception as e:
            print(f"Failed to send Slack alert: {e}")

    print(f"[{datetime.now().isoformat()}] ALERT [{severity.upper()}]: {message}")

def execute_cmd(cmd: list) -> tuple[int, str]:
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return res.returncode, res.stdout.strip() + "\n" + res.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "Timeout expired"
    except Exception as e:
        return -1, str(e)

def monitor_docker():
    if not config.get("auto_restart_enabled", True):
        return

    # Check docker states
    code, output = execute_cmd(["docker", "ps", "--all", "--format", "{{.Names}}|{{.State}}|{{.Status}}"])
    if code != 0:
        print(f"Error querying docker: {output}")
        return

    lines = [line.strip() for line in output.split("\n") if line.strip()]
    now = time.time()

    for line in lines:
        parts = line.split("|")
        if len(parts) < 3:
            continue
        name, state, status = parts[0], parts[1], parts[2]

        # We only monitor our project's core containers
        if not name.startswith("lexilingo-"):
            continue

        is_unhealthy = "(unhealthy)" in status
        is_exited = state != "running"

        if is_unhealthy or is_exited:
            # Check restart loop cooldowns
            history = restart_history.get(name, [])
            # Filter history to last 15 minutes (900 seconds)
            history = [t for t in history if now - t < 900]
            restart_history[name] = history

            if len(history) >= 3:
                # Cooldown triggered, do not restart to avoid infinite loop
                print(f"Skipping auto-restart for container {name} (cooldown triggered, restarted 3 times recently)")
                continue

            msg = f"Container `{name}` is down/unhealthy (State: `{state}`, Status: `{status}`). Attempting auto-healing restart..."
            send_alert(msg, severity="critical")

            # Perform restart
            restart_code, restart_out = execute_cmd(["docker", "restart", name])
            if restart_code == 0:
                restart_history[name].append(now)
                send_alert(f"Successfully restarted container `{name}`.", severity="warning")
            else:
                send_alert(f"Failed to restart container `{name}`: {restart_out}", severity="critical")

def monitor_databases():
    # 1. PostgreSQL Check
    pg_code, pg_out = execute_cmd(["docker", "exec", "lexilingo-postgres", "pg_isready", "-U", "lexilingo", "-d", "lexilingo"])
    if pg_code != 0:
        send_alert("PostgreSQL Database connection check failed! (pg_isready returned non-zero)", severity="critical")
        if config.get("auto_restart_enabled", True):
            execute_cmd(["docker", "restart", "lexilingo-postgres"])

    # 2. MongoDB Check
    mongo_code, mongo_out = execute_cmd(["docker", "exec", "lexilingo-mongodb", "mongosh", "--quiet", "--eval", "db.adminCommand('ping').ok"])
    if mongo_code != 0 or "1" not in mongo_out:
        send_alert(f"MongoDB health check failed! Output: {mongo_out}", severity="critical")
        if config.get("auto_restart_enabled", True):
            execute_cmd(["docker", "restart", "lexilingo-mongodb"])

def monitor_disk():
    total, used, free = shutil.disk_usage("/")
    used_percent = (used / total) * 100
    threshold = config.get("disk_threshold_percentage", 85)

    if used_percent > threshold:
        send_alert(f"Disk space usage is high: {used_percent:.2f}% (Threshold: {threshold}%). Triggering docker system prune...", severity="warning")
        
        # Clean build caches and unused containers/images
        prune_code, prune_out = execute_cmd(["docker", "system", "prune", "-af", "--volumes"])
        
        # Truncate large nginx logs
        execute_cmd(["sh", "-c", "truncate -s 0 /opt/lexilingo/gateway/nginx/logs/*.log"])
        
        # Recalculate
        new_total, new_used, new_free = shutil.disk_usage("/")
        new_used_percent = (new_used / new_total) * 100
        send_alert(f"Docker prune completed. Disk usage changed from {used_percent:.2f}% to {new_used_percent:.2f}%.", severity="warning")

def monitor_nginx_abuse():
    if not config.get("auto_block_ips_enabled", True):
        return

    sec_log_path = config.get("nginx_security_log_path", "/opt/lexilingo/gateway/nginx/logs/security.log")
    if not os.path.exists(sec_log_path):
        return

    try:
        # Tailing logs from the last check interval
        # We read the last 1000 lines of the security log to find flooding/scanner IPs
        with open(sec_log_path, "r") as f:
            lines = f.readlines()
        
        recent_lines = lines[-1000:] if len(lines) > 1000 else lines
        
        # Parse JSON logs to identify IP error rate spikes
        ip_errors = {}
        for line in recent_lines:
            try:
                data = json.loads(line.strip())
                status = int(data.get("status", 200))
                ip = data.get("remote_addr")
                if ip and (status >= 400 or status == 429):
                    ip_errors[ip] = ip_errors.get(ip, 0) + 1
            except Exception:
                continue

        # Check if any IP exceeded threshold
        threshold_4xx = config.get("max_4xx_threshold", 150)
        blocked_ips = []
        
        # Read Nginx config to check existing blocks
        nginx_conf_path = config.get("nginx_config_path", "/opt/lexilingo/gateway/nginx/templates/default.conf")
        if not os.path.exists(nginx_conf_path):
            return

        with open(nginx_conf_path, "r") as f:
            conf_content = f.read()

        for ip, err_count in ip_errors.items():
            if err_count > threshold_4xx:
                # Do not block localhost or local networks
                if ip in ["127.0.0.1", "localhost"] or ip.startswith("172.") or ip.startswith("10."):
                    continue
                
                # Check if already blocked in nginx config
                if ip in conf_content:
                    continue

                blocked_ips.append(ip)

        if blocked_ips:
            # Inject blocked IPs into default.conf geo $block_ip block
            # Target pattern: "geo $block_ip {"
            target_str = "geo $block_ip {"
            if target_str in conf_content:
                insert_lines = []
                for ip in blocked_ips:
                    insert_lines.append(f"    {ip}   1;   # Auto-blocked by Sentinel due to {ip_errors[ip]} errors")
                
                new_block_str = target_str + "\n" + "\n".join(insert_lines)
                conf_content = conf_content.replace(target_str, new_block_str)
                
                with open(nginx_conf_path, "w") as f:
                    f.write(conf_content)
                
                # Reload Nginx Gateway
                reload_code, reload_out = execute_cmd(["docker", "exec", "lexilingo-gateway", "nginx", "-s", "reload"])
                if reload_code == 0:
                    send_alert(f"Nginx Security Alert: Detected DDoS/Scanner pattern. Auto-blocked IPs: {blocked_ips}", severity="critical")
                else:
                    send_alert(f"Failed to reload Nginx configuration during auto-blocking: {reload_out}", severity="critical")
    except Exception as e:
        print(f"Error parsing nginx logs: {e}")

def main():
    print(f"[{datetime.now().isoformat()}] LexiLingo Sentinel Daemon started.")
    interval = config.get("check_interval_seconds", 30)

    while True:
        try:
            monitor_docker()
            monitor_databases()
            monitor_disk()
            monitor_nginx_abuse()
        except Exception as e:
            print(f"[{datetime.now().isoformat()}] Error in Sentinel loop: {e}")
        time.sleep(interval)

if __name__ == "__main__":
    main()
