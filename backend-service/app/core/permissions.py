"""Permission catalog: every resource an admin route guards, and the actions it distinguishes.

Slugs are "resource:action". `resource:manage` is a wildcard for the resource.
Money, premium, partner keys, quota reset, role changes and permanent deletes are
not here on purpose: they stay super-admin only and cannot be delegated.
"""

CRUD = ["create", "read", "update", "delete"]

PERMISSION_CATALOG: dict[str, list[str]] = {
    "courses": CRUD + ["manage"],
    "content": CRUD,
    "achievements": CRUD,
    "shop": CRUD,
    "ielts": CRUD,
    "banners": CRUD,
    "categories": CRUD,
    "topics": CRUD,
    "notifications": CRUD,
    "ranking": CRUD,
    "content_agent": CRUD,
    "users": ["read", "update", "delete", "manage"],
    "gifts": ["read", "grant"],
    "analytics": ["read"],
    "ops": ["read"],
    "rbac": ["read", "manage"],
}

ACTION_BY_METHOD = {
    "GET": "read",
    "HEAD": "read",
    "POST": "create",
    "PUT": "update",
    "PATCH": "update",
    "DELETE": "delete",
}


def all_slugs() -> list[str]:
    return [f"{resource}:{action}" for resource, actions in PERMISSION_CATALOG.items() for action in actions]
