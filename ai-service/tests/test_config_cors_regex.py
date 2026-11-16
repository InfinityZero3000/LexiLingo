import pytest

from api.core.config import Settings

BASE_PROD = dict(
    _env_file=None,
    ENVIRONMENT="production",
    DEBUG=False,
    SECRET_KEY="x" * 32,
)


@pytest.mark.parametrize(
    "regex",
    [
        r"https?://.*\.devtunnels\.ms(:\d+)?",
        r"https?://.*\.github\.dev(:\d+)?",
        "https://x.devtunnels.ms",
    ],
)
def test_dev_tunnel_regex_is_rejected_in_production(regex: str) -> None:
    with pytest.raises(ValueError, match="development tunnel"):
        Settings(**BASE_PROD, CORS_ALLOW_ORIGIN_REGEX=regex)


def test_clean_regex_is_accepted_in_production() -> None:
    s = Settings(**BASE_PROD, CORS_ALLOW_ORIGIN_REGEX=r"https?://([a-zA-Z0-9-]+\.)*lexilingo\.me(:\d+)?")
    assert s.ENVIRONMENT == "production"


def test_exact_vercel_alias_in_regex_is_accepted_and_scoped() -> None:
    import re

    regex = r"https?://([a-zA-Z0-9-]+\.)*lexilingo\.me(:\d+)?|https://lexilingo\.vercel\.app"
    s = Settings(**BASE_PROD, CORS_ALLOW_ORIGIN_REGEX=regex)
    assert re.fullmatch(s.CORS_ALLOW_ORIGIN_REGEX, "https://lexilingo.vercel.app")
    assert not re.fullmatch(s.CORS_ALLOW_ORIGIN_REGEX, "https://evil.vercel.app")
    assert not re.fullmatch(s.CORS_ALLOW_ORIGIN_REGEX, "https://lexilingo.vercel.app.evil.com")
