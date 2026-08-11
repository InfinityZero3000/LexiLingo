from fastapi import APIRouter, Depends, status
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.product_event import ProductEvent
from app.models.user import User
from app.schemas.product_event import ProductEventBatchCreate, ProductEventBatchResponse

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
    await db.execute(
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
    return ProductEventBatchResponse(accepted=len(request.events))
