"""
RBAC Management Routes
Super admin endpoints for managing roles, permissions, users, and audit logs.
"""

from typing import Optional, List
from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.core.database import get_db
from app.core.dependencies import get_current_admin, get_current_super_admin
from app.models.user import User
from app.models.rbac import Role, Permission, RolePermission, AuditLog
from app.schemas.rbac import (
    RoleResponse,
    RoleWithPermissions,
    PermissionResponse,
    AuditLogResponse,
    AssignRoleRequest,
)
from app.schemas.user import UserResponse

router = APIRouter(prefix="/admin/rbac", tags=["RBAC Management"])


# ── Helper: log admin actions ─────────────────────────────

async def _audit(
    db: AsyncSession,
    user_id: UUID,
    action: str,
    resource_type: str,
    resource_id: str = None,
    details: str = None,
):
    """Write an audit log entry."""
    log = AuditLog(
        user_id=user_id,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        details=details,
    )
    db.add(log)


# ============================================================================
# Roles (admin can read, super_admin can modify)
# ============================================================================

@router.get("/roles", response_model=List[RoleResponse])
async def list_roles(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List all system roles."""
    result = await db.execute(select(Role).order_by(Role.level))
    return result.scalars().all()


@router.get("/roles/{role_slug}", response_model=RoleWithPermissions)
async def get_role_with_permissions(
    role_slug: str,
    admin: User = Depends(get_current_admin),
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
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List all permissions."""
    result = await db.execute(
        select(Permission).order_by(Permission.resource, Permission.action)
    )
    return result.scalars().all()


# ============================================================================
# User Role Assignment (super_admin only)
# ============================================================================

@router.get("/users", response_model=dict)
async def list_users_with_roles(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    role_slug: Optional[str] = Query(None, description="Filter by role slug"),
    search: Optional[str] = Query(None, description="Search by username or email"),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List users with their roles. Admin and super_admin can access this."""
    query = select(User).order_by(User.created_at.desc())

    if role_slug:
        query = query.join(Role, User.role_id == Role.id).where(Role.slug == role_slug)

    if search:
        query = query.where(
            (User.username.ilike(f"%{search}%")) | (User.email.ilike(f"%{search}%"))
        )

    # Count total
    count_query = select(func.count()).select_from(query.subquery())
    total = (await db.execute(count_query)).scalar()

    # Paginate
    query = query.offset((page - 1) * per_page).limit(per_page)
    result = await db.execute(query)
    users = result.scalars().all()

    return {
        "users": [
            {
                "id": str(u.id),
                "username": u.username,
                "email": u.email,
                "display_name": u.display_name,
                "role": u.role_slug,
                "is_active": u.is_active,
                "is_verified": u.is_verified,
                "numeric_level": u.numeric_level,
                "total_xp": u.total_xp,
                "created_at": u.created_at.isoformat(),
            }
            for u in users
        ],
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page if total else 0,
    }


@router.post("/users/assign-role", response_model=dict)
async def assign_role_to_user(
    request: AssignRoleRequest,
    super_admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Assign a role to a user. Super admin only.
    Cannot demote yourself or another super_admin.
    """
    # Find target user
    result = await db.execute(select(User).where(User.id == request.user_id))
    target_user = result.scalar_one_or_none()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    # Find role
    result = await db.execute(select(Role).where(Role.slug == request.role_slug))
    role = result.scalar_one_or_none()
    if not role:
        raise HTTPException(status_code=404, detail=f"Role '{request.role_slug}' not found")

    # Prevent self-demotion
    if target_user.id == super_admin.id and role.level < super_admin.role_level:
        raise HTTPException(
            status_code=400,
            detail="Cannot demote yourself",
        )

    # Prevent demoting another super_admin (only higher or equal level can modify)
    if target_user.role_level >= super_admin.role_level and target_user.id != super_admin.id:
        raise HTTPException(
            status_code=403,
            detail="Cannot modify a user with equal or higher role level",
        )

    old_role = target_user.role_slug
    target_user.role_id = role.id

    await _audit(
        db,
        user_id=super_admin.id,
        action="assign_role",
        resource_type="user",
        resource_id=str(target_user.id),
        details=f"Role changed from '{old_role}' to '{role.slug}'",
    )

    await db.commit()
    await db.refresh(target_user)

    return {
        "message": f"Role '{role.slug}' assigned to user '{target_user.username}'",
        "user_id": str(target_user.id),
        "username": target_user.username,
        "old_role": old_role,
        "new_role": role.slug,
    }


@router.post("/users/{user_id}/deactivate", response_model=dict)
async def deactivate_user(
    user_id: UUID,
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Deactivate (soft-ban) a user. Admin can deactivate regular users, super_admin can deactivate anyone."""
    result = await db.execute(select(User).where(User.id == user_id))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    # Admin can't deactivate other admins
    if target.role_level >= admin.role_level and target.id != admin.id:
        raise HTTPException(status_code=403, detail="Cannot deactivate a user with equal or higher role")

    # Can't deactivate yourself
    if target.id == admin.id:
        raise HTTPException(status_code=400, detail="Cannot deactivate yourself")

    target.is_active = False

    await _audit(db, admin.id, "deactivate", "user", str(target.id),
                 f"User {target.username} deactivated by {admin.username}")
    await db.commit()

    return {"message": f"User '{target.username}' has been deactivated", "user_id": str(target.id)}


@router.post("/users/{user_id}/activate", response_model=dict)
async def activate_user(
    user_id: UUID,
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Re-activate a deactivated user."""
    result = await db.execute(select(User).where(User.id == user_id))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    target.is_active = True

    await _audit(db, admin.id, "activate", "user", str(target.id),
                 f"User {target.username} reactivated by {admin.username}")
    await db.commit()

    return {"message": f"User '{target.username}' has been activated", "user_id": str(target.id)}


# ============================================================================
# Audit Logs (admin can read)
# ============================================================================

@router.get("/audit-logs", response_model=dict)
async def list_audit_logs(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    action: Optional[str] = Query(None),
    resource_type: Optional[str] = Query(None),
    user_id: Optional[UUID] = Query(None),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List audit logs with filtering and pagination."""
    query = select(AuditLog).order_by(AuditLog.created_at.desc())

    if action:
        query = query.where(AuditLog.action == action)
    if resource_type:
        query = query.where(AuditLog.resource_type == resource_type)
    if user_id:
        query = query.where(AuditLog.user_id == user_id)

    # Count
    count_query = select(func.count()).select_from(query.subquery())
    total = (await db.execute(count_query)).scalar()

    # Paginate
    query = query.offset((page - 1) * per_page).limit(per_page)
    result = await db.execute(query)
    logs = result.scalars().all()

    return {
        "logs": [
            {
                "id": str(log.id),
                "user_id": str(log.user_id) if log.user_id else None,
                "action": log.action,
                "resource_type": log.resource_type,
                "resource_id": log.resource_id,
                "details": log.details,
                "ip_address": log.ip_address,
                "created_at": log.created_at.isoformat(),
            }
            for log in logs
        ],
        "total": total,
        "page": page,
        "per_page": per_page,
    }


# ============================================================================
# Dashboard Stats (admin can read)
# ============================================================================

@router.get("/dashboard", response_model=dict)
async def admin_dashboard(
    admin: User = Depends(get_current_admin),
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
