"""Which accounts are real people, shared by analytics and outbound mail."""

from sqlalchemy import and_

from app.models.user import User

SEED_EMAIL_DOMAINS = ("lexilingo.test", "lexilingo.dev")


def real_user_clause():
    return and_(*(~User.email.ilike(f"%@{d}") for d in SEED_EMAIL_DOMAINS))
