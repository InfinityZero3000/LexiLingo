"""
RBAC Management Routes
Super admin endpoints for managing roles, permissions, users, and audit logs.
"""

import csv
import io
from datetime import datetime
from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_

from app.core.database import get_db
from app.core.dependencies import get_current_admin, get_current_super_admin, require_permission
from app.models.user import User
from app.services.admin_audit import record_admin_action
from app.models.rbac import Role, Permission, RolePermission, AuditLog
from app.schemas.rbac import (
    RoleResponse,
    RoleWithPermissions,
    PermissionResponse,
)

router = APIRouter(prefix="/admin/rbac", tags=["RBAC Management"])


# ============================================================================
# Roles (admin can read, super_admin can modify)
# ============================================================================

@router.get("/roles", response_model=List[RoleResponse])
async def list_roles(
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """List all system roles."""
    result = await db.execute(select(Role).order_by(Role.level))
    return result.scalars().all()


@router.get("/roles/{role_slug}", response_model=RoleWithPermissions)
async def get_role_with_permissions(
    role_slug: str,
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """Get a role with its permissions."""
    result = await db.execute(select(Role).where(Role.slug == role_slug))
    role = result.scalar_one_or_none()
    if not role:
        raise HTTPException(status_code=404, detail=f"Role '{role_slug}' not found")

    # Get permissions for this role
    result = await db.execute(
        select(Permission)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .where(RolePermission.role_id == role.id)
        .order_by(Permission.resource, Permission.action)
    )
    perms = result.scalars().all()

    return RoleWithPermissions(
        id=role.id,
        name=role.name,
        slug=role.slug,
        description=role.description,
        level=role.level,
        is_system=role.is_system,
        is_active=role.is_active,
        created_at=role.created_at,
        permissions=[PermissionResponse.model_validate(p) for p in perms],
    )


# ============================================================================
# Permissions (admin can read)
# ============================================================================

@router.get("/permissions", response_model=List[PermissionResponse])
async def list_permissions(
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """List all permissions."""
    result = await db.execute(
        select(Permission).order_by(Permission.resource, Permission.action)
    )
    return result.scalars().all()


class RolePermissionsUpdate(BaseModel):
    permission_slugs: List[str]


@router.put("/roles/{role_slug}/permissions", response_model=RoleWithPermissions)
async def set_role_permissions(
    role_slug: str,
    data: RolePermissionsUpdate,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """Replace the permissions of an admin-level role. Super admin is never editable."""
    role = (await db.execute(select(Role).where(Role.slug == role_slug))).scalar_one_or_none()
    if not role:
        raise HTTPException(status_code=404, detail=f"Role '{role_slug}' not found")
    if role.level != 1:
        raise HTTPException(status_code=400, detail="Only admin-level roles can be edited")

    wanted = set(data.permission_slugs)
    known = {
        p.slug: p
        for p in (await db.execute(select(Permission).where(Permission.slug.in_(wanted)))).scalars().all()
    }
    unknown = sorted(wanted - known.keys())
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown permissions: {', '.join(unknown)}")

    current_rows = (
        await db.execute(
            select(RolePermission, Permission.slug)
            .join(Permission, Permission.id == RolePermission.permission_id)
            .where(RolePermission.role_id == role.id)
        )
    ).all()
    current = {slug: row for row, slug in current_rows}
    removed = sorted(current.keys() - wanted)
    added = sorted(wanted - current.keys())
    for slug in removed:
        await db.delete(current[slug])
    for slug in added:
        db.add(RolePermission(role_id=role.id, permission_id=known[slug].id))
    if added or removed:
        record_admin_action(
            db, admin, "role_permissions_update", "role", role.slug, {"added": added, "removed": removed}, request
        )
    await db.commit()
    return await get_role_with_permissions(role_slug, admin, db)


@router.get("/me/permissions")
async def my_permissions(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """What the caller may do, so the UI can hide what the server would refuse."""
    if admin.role_level >= 2:
        return {"all": True, "permissions": []}
    rows = await db.execute(
        select(Permission.slug)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .where(RolePermission.role_id == admin.role_id)
    )
    return {"all": False, "permissions": sorted(rows.scalars().all())}


# ============================================================================
# User Role Assignment (super_admin only)
# ============================================================================


# ============================================================================
# Audit Logs (admin can read)
# ============================================================================

def _audit_filters(
    action: Optional[str],
    resource_type: Optional[str],
    resource_id: Optional[str],
    user_id: Optional[UUID],
    date_from: Optional[datetime],
    date_to: Optional[datetime],
    q: Optional[str],
):
    conditions = []
    if action:
        conditions.append(AuditLog.action == action)
    if resource_type:
        conditions.append(AuditLog.resource_type == resource_type)
    if resource_id:
        conditions.append(AuditLog.resource_id == resource_id)
    if user_id:
        conditions.append(AuditLog.user_id == user_id)
    if date_from:
        conditions.append(AuditLog.created_at >= date_from)
    if date_to:
        conditions.append(AuditLog.created_at <= date_to)
    if q:
        like = f"%{q}%"
        conditions.append(
            or_(
                AuditLog.details.ilike(like),
                AuditLog.resource_id.ilike(like),
                User.username.ilike(like),
                User.email.ilike(like),
            )
        )
    return conditions


def _audit_select(conditions):
    return (
        select(AuditLog, User.username, User.email)
        .outerjoin(User, User.id == AuditLog.user_id)
        .where(*conditions)
    )


@router.get("/audit-logs", response_model=dict)
async def list_audit_logs(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    action: Optional[str] = Query(None),
    resource_type: Optional[str] = Query(None),
    resource_id: Optional[str] = Query(None),
    user_id: Optional[UUID] = Query(None),
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
    q: Optional[str] = Query(None, max_length=100),
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """List audit logs with filtering and pagination."""
    conditions = _audit_filters(action, resource_type, resource_id, user_id, date_from, date_to, q)

    count_query = select(func.count()).select_from(_audit_select(conditions).subquery())
    total = (await db.execute(count_query)).scalar()

    query = (
        _audit_select(conditions)
        .order_by(AuditLog.created_at.desc())
        .offset((page - 1) * per_page)
        .limit(per_page)
    )
    rows = (await db.execute(query)).all()

    return {
        "logs": [
            {
                "id": str(log.id),
                "user_id": str(log.user_id) if log.user_id else None,
                "actor": {"username": username, "email": email} if username or email else None,
                "action": log.action,
                "resource_type": log.resource_type,
                "resource_id": log.resource_id,
                "details": log.details,
                "ip_address": log.ip_address,
                "user_agent": log.user_agent,
                "created_at": log.created_at.isoformat(),
            }
            for log, username, email in rows
        ],
        "total": total,
        "page": page,
        "per_page": per_page,
    }


@router.get("/audit-logs/facets", response_model=dict)
async def audit_log_facets(
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """Values that actually occur, so filter dropdowns never drift from the data."""
    actions = (await db.execute(select(AuditLog.action).distinct().order_by(AuditLog.action))).scalars().all()
    resource_types = (
        await db.execute(select(AuditLog.resource_type).distinct().order_by(AuditLog.resource_type))
    ).scalars().all()
    return {"actions": list(actions), "resource_types": list(resource_types)}


_CSV_MAX_ROWS = 10_000


def _csv_cell(value) -> str:
    text = "" if value is None else str(value)
    # Spreadsheets run cells that start with these as formulas.
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text


@router.get("/audit-logs/export")
async def export_audit_logs(
    action: Optional[str] = Query(None),
    resource_type: Optional[str] = Query(None),
    resource_id: Optional[str] = Query(None),
    user_id: Optional[UUID] = Query(None),
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
    q: Optional[str] = Query(None, max_length=100),
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """CSV of the same filtered view, newest first, capped at 10,000 rows."""
    conditions = _audit_filters(action, resource_type, resource_id, user_id, date_from, date_to, q)
    query = (
        _audit_select(conditions).order_by(AuditLog.created_at.desc()).limit(_CSV_MAX_ROWS)
    )
    rows = (await db.execute(query)).all()

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        ["created_at", "actor", "actor_email", "action", "resource_type", "resource_id", "ip_address", "details"]
    )
    for log, username, email in rows:
        writer.writerow(
            [
                _csv_cell(log.created_at.isoformat()),
                _csv_cell(username),
                _csv_cell(email),
                _csv_cell(log.action),
                _csv_cell(log.resource_type),
                _csv_cell(log.resource_id),
                _csv_cell(log.ip_address),
                _csv_cell(log.details),
            ]
        )
    return Response(
        content="\ufeff" + buffer.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="audit-logs.csv"'},
    )


# ============================================================================
# Dashboard Stats (admin can read)
# ============================================================================

@router.get("/dashboard", response_model=dict)
async def admin_dashboard(
    admin: User = Depends(require_permission("rbac:read")),
    db: AsyncSession = Depends(get_db),
):
    """Admin dashboard with key metrics."""
    stats = {}

    # Total users
    r = await db.execute(select(func.count(User.id)))
    stats["total_users"] = r.scalar()

    # Active users
    r = await db.execute(select(func.count(User.id)).where(User.is_active == True))
    stats["active_users"] = r.scalar()

    # Users by role
    r = await db.execute(
        select(Role.slug, func.count(User.id))
        .outerjoin(User, User.role_id == Role.id)
        .group_by(Role.slug)
    )
    stats["users_by_role"] = {row[0]: row[1] for row in r.fetchall()}

    # Total achievements
    from app.models.gamification import Achievement, UserAchievement
    r = await db.execute(select(func.count(Achievement.id)))
    stats["total_achievements"] = r.scalar()

    # Total unlocked achievements
    r = await db.execute(select(func.count(UserAchievement.id)))
    stats["total_unlocks"] = r.scalar()

    # Recent audit actions (last 10)
    r = await db.execute(
        select(AuditLog).order_by(AuditLog.created_at.desc()).limit(10)
    )
    stats["recent_actions"] = [
        {
            "action": log.action,
            "resource_type": log.resource_type,
            "created_at": log.created_at.isoformat(),
        }
        for log in r.scalars().all()
    ]

    return {"dashboard": stats}
