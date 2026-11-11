"""Point the debug build at the local stack or at production.

main.dart loads assets/env/dev_config in debug and assets/env/prod_config in release,
so only dev_config is touched here. The raw .env files are never copied into assets:
they can hold server secrets that must not be bundled into Flutter web.
"""
import os
import re
import sys

TARGETS = {
    "dev": {
        "API_BASE_URL": "http://localhost:8000/api/v1",
        "AI_SERVICE_URL": "http://localhost:8001/api/v1",
    },
    "prod": {
        "API_BASE_URL": "https://api.lexilingo.me/api/v1",
        "AI_SERVICE_URL": "https://api.lexilingo.me/api/v1",
    },
}
ALIASES = {"development": "dev", "production": "prod"}
CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "env", "dev_config")


def current() -> str:
    with open(CONFIG, encoding="utf-8") as f:
        text = f.read()
    for name, target in TARGETS.items():
        if all(re.search(rf"^{k}={re.escape(v)}$", text, flags=re.M) for k, v in target.items()):
            return name
    return "custom"


def switch(name: str) -> None:
    target = TARGETS.get(ALIASES.get(name, name))
    if target is None:
        sys.exit("Invalid environment type! Use 'dev' or 'prod'.")
    with open(CONFIG, encoding="utf-8") as f:
        text = f.read()
    for key, value in target.items():
        text, n = re.subn(rf"^{key}=.*$", f"{key}={value}", text, flags=re.M)
        if n != 1:
            sys.exit(f"Expected exactly one {key}= line in {CONFIG}, found {n}.")
    with open(CONFIG, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"dev_config now points at: {current()}")
    print("Hot restart the app: assets are read at startup, hot reload will not pick this up.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: python3 env-switch.py [dev|prod|status]")
    if sys.argv[1] == "status":
        print(f"dev_config points at: {current()}")
    else:
        switch(sys.argv[1])
