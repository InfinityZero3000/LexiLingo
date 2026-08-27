import logging
import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.core.redis import get_redis
from app.models.product_event import ProductEvent
from app.models.user import User
from app.schemas.product_event import ProductEventBatchCreate, ProductEventBatchResponse
from app.services.feature_processor import STREAM_KEY
from app.services.recommendation_service import INTERACTION_EPOCH_PREFIX

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/analytics", tags=["Product Analytics"])


@router.post(
    "/events",
    response_model=ProductEventBatchResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def ingest_product_events(
    request: ProductEventBatchCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProductEventBatchResponse:
    result = await db.execute(
        pg_insert(ProductEvent)
        .values(
            [
                {
                    "event_id": event.event_id,
                    "user_id": current_user.id,
                    "event_name": event.event_name,
                    "properties": event.properties,
                    "source": event.source,
                    "client_timestamp": event.client_timestamp,
                }
                for event in request.events
            ]
        )
        .on_conflict_do_nothing(
            index_elements=["user_id", "event_id"],
        )
    )
    await db.commit()

    # rowcount excludes rows skipped by on_conflict_do_nothing, so a resent
    # (already-seen) batch doesn't bump the epoch and thrash the rec cache.
    if result.rowcount and any(
        event.event_name == "content_interaction" for event in request.events
    ):
        await _signal_content_interaction(current_user.id)

    return ProductEventBatchResponse(accepted=len(request.events))


async def _signal_content_interaction(user_id: uuid.UUID) -> None:
    """Two signals for one trigger: bump the cache-freshness epoch (cheap,
    read synchronously on the next request), and XADD to the Event Worker's
    stream so it recomputes this user's insights off the request path — see
    app.tasks.event_worker. content_interaction doesn't bump the
    learner-state epoch (that would also invalidate TraceCAG's chat cache on
    every browse action), so it needs its own."""
    try:
        client = await get_redis()
        if client is None:
            return
        await client.incr(f"{INTERACTION_EPOCH_PREFIX}{user_id}")
        # Bounded so a stalled/dead worker can't grow this stream forever.
        await client.xadd(
            STREAM_KEY, {"user_id": str(user_id)}, maxlen=100_000, approximate=True
        )
    except Exception as exc:
        logger.warning("content_interaction signal failed: %s", exc)
