import pytest

from app.core.config import Settings

BASE_PROD_KWARGS = dict(
    APP_ENV="production",
    DATABASE_URL="postgresql+asyncpg://u:p@localhost/db",
    SECRET_KEY="a-real-random-secret-key-value",
    DEBUG=False,
    ENABLE_APP_CORS=True,
    GOOGLE_CLIENT_ID="client-id",
    GOOGLE_ADMIN_CLIENT_ID="admin-client-id",
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
