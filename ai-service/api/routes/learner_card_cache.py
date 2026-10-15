"""Internal endpoint backend-service calls when a learner card goes stale.

The card is cached here for its TTL so ordinary turns cost one Redis GET.
That TTL is a floor on how wrong the card can be, not a policy: a learner who
just got promoted, or who just enrolled from one of Lexi's own course cards,
will ask about it in the next breath. Backend owns those writes, so backend
tells us to drop the entry.

Best-effort by design — the TTL is still the safety net if this call is lost.
"""

from fastapi import APIRouter, Security
from pydantic import BaseModel

from api.core.auth import verify_internal_admin_key
from api.services.learner_card import invalidate

router = APIRouter(prefix="/api/v1/internal/learner-card")


class InvalidateRequest(BaseModel):
    user_id: str


@router.post("/invalidate", dependencies=[Security(verify_internal_admin_key)])
async def invalidate_learner_card(body: InvalidateRequest) -> dict[str, bool]:
    await invalidate(body.user_id)
    return {"success": True}
