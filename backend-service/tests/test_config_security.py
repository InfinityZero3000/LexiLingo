import pytest

from app.core.config import Settings

BASE_PROD_KWARGS = dict(
    APP_ENV="production",
    DATABASE_URL="postgresql+asyncpg://u:p@localhost/db",
    SECRET_KEY="a-real-random-secret-key-value",
    DEBUG=False,
    ENABLE_APP_CORS=True,
    # Settings.model_config reads a local .env file (pydantic-settings
    # env_file), so any field not pinned here falls back to whatever a
    # developer's machine-local, gitignored .env happens to contain —
    # e.g. a local ALLOWED_ORIGINS with http://localhost:5959 for dev.
    # Pin every field validate_production_security() inspects so this
    # test's outcome never depends on ambient local config.
    ALLOWED_ORIGINS="https://lexilingo.me,https://www.lexilingo.me,https://admin.lexilingo.me",
    CONTENT_AGENT_ENABLED=False,
    LEARNER_STATE_ENABLED=False,
    GOOGLE_CLIENT_ID="client-id",
    GOOGLE_ADMIN_CLIENT_ID="admin-client-id",
    FIREBASE_CREDENTIALS_FILE=None,
)


def test_devtunnels_regex_escaped_dot_is_rejected():
    """CORS_ALLOW_ORIGIN_REGEX values are regexes, so a real dev-tunnel
    domain shows up as "devtunnels\\.ms", not the literal "devtunnels.ms" —
    the check must still catch it."""
    with pytest.raises(ValueError, match="development tunnel"):
        Settings(
            **BASE_PROD_KWARGS,
            CORS_ALLOW_ORIGIN_REGEX=r"https?://.*\.devtunnels\.ms(:\d+)?",
        )


def test_github_dev_regex_escaped_dot_is_rejected():
    with pytest.raises(ValueError, match="development tunnel"):
        Settings(
            **BASE_PROD_KWARGS,
            CORS_ALLOW_ORIGIN_REGEX=r"https?://.*\.github\.dev(:\d+)?",
        )


def test_clean_production_cors_regex_is_accepted():
    settings = Settings(
        **BASE_PROD_KWARGS,
        CORS_ALLOW_ORIGIN_REGEX=r"https?://([a-zA-Z0-9-]+\.)*lexilingo\.me(:\d+)?",
    )
    assert settings.is_production


_CLEAN_CORS_REGEX = r"https?://([a-zA-Z0-9-]+\.)*lexilingo\.me(:\d+)?"


def test_firebase_credentials_file_inside_repo_is_rejected():
    kwargs = {
        **BASE_PROD_KWARGS,
        "CORS_ALLOW_ORIGIN_REGEX": _CLEAN_CORS_REGEX,
        "FIREBASE_CREDENTIALS_FILE": "./firebase-service-account.json",
    }
    with pytest.raises(ValueError, match="FIREBASE_CREDENTIALS_FILE"):
        Settings(**kwargs)


def test_firebase_credentials_file_outside_repo_is_accepted():
    kwargs = {
        **BASE_PROD_KWARGS,
        "CORS_ALLOW_ORIGIN_REGEX": _CLEAN_CORS_REGEX,
        "FIREBASE_CREDENTIALS_FILE": "/run/secrets/firebase.json",
    }
    settings = Settings(**kwargs)
    assert settings.is_production
