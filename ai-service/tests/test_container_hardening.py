from pathlib import Path
import re
import yaml


ROOT = Path(__file__).resolve().parents[1]
PINNED_PYTHON_IMAGE = (
    "python:3.11.13-slim-bookworm"
    "@sha256:86adf8dbadc3d6e82ee5dd2c74bec2e1c2467cdad47886280501df722372d2e1"
)


def _read(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def test_production_image_uses_pinned_multi_stage_runtime():
    dockerfile = _read("Dockerfile.prod")

    assert dockerfile.count(f"FROM {PINNED_PYTHON_IMAGE}") == 2
    assert f"FROM {PINNED_PYTHON_IMAGE} AS builder" in dockerfile
    runtime = dockerfile.split(f"FROM {PINNED_PYTHON_IMAGE}", maxsplit=2)[-1]

    assert "gcc" not in runtime
    assert "g++" not in runtime
    assert "cmake" not in runtime
    assert "USER appuser" in runtime
    assert "HEALTHCHECK" in runtime
    assert "ENV SECRET_KEY=" not in dockerfile
    assert "SECRET_KEY=build-time-import-check-not-a-runtime-secret" in dockerfile


def test_images_install_the_locked_ai_stack():
    for name in ("Dockerfile", "Dockerfile.prod"):
        dockerfile = _read(name)

        assert "COPY requirements.txt constraints-ai.txt" in dockerfile
        assert "pip install --no-cache-dir -c constraints-ai.txt -r requirements.txt" in dockerfile
        assert "pip install --no-cache-dir torch==" not in dockerfile


def test_production_build_context_excludes_research_and_reports():
    dockerignore = _read(".dockerignore")
    assert "model-development/" in dockerignore
    assert "reports/" in dockerignore


def test_local_compose_avoids_latest_and_hardens_service_runtime():
    compose = _read("docker-compose.yml")

    assert not re.search(r"^\s*image:\s*\S+:latest\s*$", compose, re.MULTILINE)
    assert (
        "mongo-express:1.0.2"
        "@sha256:1b23d7976f0210dbec74045c209e52fbb26d29b2e873d6c6fa3d3f0ae32c2a64"
        in compose
    )
    ai_service = compose.split("  ai-service:", maxsplit=1)[1].split(
        "\n  mongodb:", maxsplit=1
    )[0]

    assert "init: true" in ai_service
    assert "security_opt:" in ai_service
    assert "no-new-privileges:true" in ai_service


def test_e2e_compose_matches_production_security_boundary():
    compose = yaml.safe_load(_read("docker-compose.yml"))
    services = compose["services"]
    ai = services["ai-service"]

    assert ai["build"]["dockerfile"] == "Dockerfile.prod"
    assert ai["environment"]["ENVIRONMENT"] == "production"
    assert ai["environment"]["GROQ_API_KEYS"]
    assert ai["environment"]["GROQ_SLOT_TELEMETRY"]
    assert ai["ports"] == ["127.0.0.1:${AI_E2E_PORT:-18001}:8001"]
    assert ai["environment"]["ALLOWED_ORIGINS"] == "${AI_E2E_ALLOWED_ORIGINS:-https://e2e.invalid}"
    assert ai["environment"]["GROQ_MODEL"] == "${GROQ_MODEL:-groq/compound-mini}"
    assert ai["environment"]["GEMINI_API_KEY"] == "${AI_E2E_GEMINI_API_KEY:-}"
    assert ai["environment"]["TRACECAG_ENABLE_JIT_MINIGRAPH"].endswith(":-false}")
    assert ai["environment"]["V3_ENABLE_GRAPH_ANALYTICS"].endswith(":-false}")
    assert ai["environment"]["V3_FORCE_HASH_EMBEDDINGS"].endswith(":-true}")
    assert ai["environment"]["CORS_ALLOW_ORIGIN_REGEX"] == ""
    assert ai["environment"]["CORS_ALLOW_PRIVATE_NETWORK"] == "false"
    assert ai["environment"]["AI_USER_TPM_LIMIT"].endswith(":-1000000}")
    assert ai["environment"]["REDIS_MAX_CONNECTIONS"].endswith(":-64}")
    assert ai["environment"]["TRACECAG_GROQ_RPM"].endswith(":-28}")
    assert not ai.get("volumes")
    assert "--reload" not in ai.get("command", "")
    assert "container_name" not in ai

    mongodb = services["mongodb"]
    assert "@sha256:" in mongodb["image"]
    assert not mongodb.get("ports")
    assert "container_name" not in mongodb

    redis = services["redis"]
    assert "@sha256:" in redis["image"]
    assert redis["ports"] == ["127.0.0.1:${AI_E2E_REDIS_PORT:-16379}:6379"]
    assert "--requirepass" in redis["command"]
    assert "REDIS_PASSWORD" in redis["environment"]
    assert "REDIS_PASSWORD" in str(redis["healthcheck"]["test"])
    assert "redis-cli -a" not in str(redis["healthcheck"]["test"])
    assert "container_name" not in redis

    admin = services["mongo-express"]
    assert admin["profiles"] == ["admin"]
    assert admin["ports"] == ["127.0.0.1:8081:8081"]
    assert "MONGO_EXPRESS_PASSWORD" in admin["command"]
    assert "container_name" not in admin
