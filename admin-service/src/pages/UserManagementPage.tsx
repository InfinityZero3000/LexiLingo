/**
 * User Management Page
 * Phase 2 - Admin Panel
 */
import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import {
  getUsers,
  updateUserStatus,
  bulkUserAction,
  permanentlyDeleteUser,
  getUserDetail,
  getRoleLabel,
  type UserFilters,
  type UserListItem as ApiUserListItem,
} from '../lib/userManagementApi';
import { getDashboardStats } from '../lib/rbacApi';
import { SectionHeader } from '../components/SectionHeader';
import UserDetailModal from '../components/user-management/UserDetailModal';
import UserFiltersPanel from '../components/user-management/UserFiltersPanel';
import { useAuth } from '../components/AuthProvider';
import { useI18n } from '../lib/i18n';
import { useConfirm } from '../components/ConfirmDialog';
import { DataTable, type Column } from '../components/DataTable';

type UserListItem = ApiUserListItem & {
  avatar_url: string | null;
  total_xp: number;
  streak_days: number;
};

export default function UserManagementPage() {
  const queryClient = useQueryClient();
  const { user: currentAdmin, role } = useAuth();
  const { t, locale } = useI18n();
  const confirm = useConfirm();
  const fill = (text: string, vars: Record<string, string | number>) =>
    Object.entries(vars).reduce((out, [k, v]) => out.replace(`{${k}}`, String(v)), text);
  const dateLocale = locale === 'vi' ? 'vi-VN' : 'en-US';

  // State
  const [filters, setFilters] = useState<UserFilters>({
    page: 1,
    page_size: 20,
    sort_by: 'created_at',
    order: 'desc',
  });
  
  const [selectedUsers, setSelectedUsers] = useState<Set<string>>(new Set());
  const [detailModalUserId, setDetailModalUserId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const reportFailure = (err: unknown) =>
    setActionError(err instanceof Error && err.message ? err.message : t.userList.actionFailed);
  
  // Queries
  const { data, isLoading, error } = useQuery({
    queryKey: ['users', filters],
    queryFn: () => getUsers(filters),
    staleTime: 30000, // 30 seconds
    placeholderData: keepPreviousData, // keep the table on screen while a new sort/page loads
  });

  const { data: dashboardStats } = useQuery({
    queryKey: ['users-dashboard-stats'],
    queryFn: getDashboardStats,
    staleTime: 30000,
  });
  
  // Mutations
  const statusMutation = useMutation({
    mutationFn: ({ userId, isActive }: { userId: string; isActive: boolean }) =>
      updateUserStatus(userId, { is_active: isActive }),
    onMutate: () => setActionError(null),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
    onError: reportFailure,
  });
  
  const bulkActionMutation = useMutation({
    mutationFn: bulkUserAction,
    onMutate: () => setActionError(null),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      setSelectedUsers(new Set());
    },
    onError: reportFailure,
  });

  const deleteMutation = useMutation({
    mutationFn: permanentlyDeleteUser,
    onMutate: () => setActionError(null),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
    onError: reportFailure,
  });

  // Handlers
  const handleFilterChange = (newFilters: Partial<UserFilters>) => {
    setFilters((prev) => ({ ...prev, ...newFilters, page: 1 }));
  };
  
  const handlePageChange = (page: number) => {
    setFilters((prev) => ({ ...prev, page }));
  };
  
  const handleToggleSelect = (userId: string) => {
    setSelectedUsers((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) {
        next.delete(userId);
      } else {
        next.add(userId);
      }
      return next;
    });
  };
  
  const handleSelectAll = () => {
    if (!data?.users) return;
    
    if (selectedUsers.size === data.users.length) {
      setSelectedUsers(new Set());
    } else {
      setSelectedUsers(new Set(data.users.map((u) => u.id)));
    }
  };
  
  const handleBulkAction = async (action: 'activate' | 'deactivate') => {
    if (selectedUsers.size === 0) return;
    const label = action === 'activate' ? t.userList.activate : t.userList.deactivate;
    const ok = await confirm({ message: fill(t.userList.bulkConfirm, { action: label, n: selectedUsers.size }), confirmLabel: label });
    if (ok) bulkActionMutation.mutate({ user_ids: Array.from(selectedUsers), action });
  };

  const handleToggleStatus = async (userId: string, currentStatus: boolean) => {
    const label = currentStatus ? t.userList.deactivate : t.userList.activate;
    const ok = await confirm({ message: fill(t.userList.toggleConfirm, { action: label }), confirmLabel: label });
    if (ok) statusMutation.mutate({ userId, isActive: !currentStatus });
  };

  const handleSort = (key: string) => {
    const sort_by = key as UserFilters['sort_by'];
    const order = filters.sort_by === sort_by ? (filters.order === 'asc' ? 'desc' : 'asc') : (sort_by === 'email' || sort_by === 'role' ? 'asc' : 'desc');
    setFilters((prev) => ({ ...prev, sort_by, order, page: 1 }));
  };

  const handleViewDetail = (userId: string) => {
    setDetailModalUserId(userId);
  };

  const handlePermanentDelete = async (userId: string, email: string) => {
    const ok = await confirm({
      message: fill(t.userList.deleteConfirm, { email }),
      confirmLabel: t.userList.deletePermanent,
      danger: true,
      requireText: email,
    });
    if (ok) deleteMutation.mutate(userId);
  };

  // Render
  if (error) {
    return (
      <div className="stack">
        <div className="form-error">
          <h3 className="state-title">{t.userList.loadErrorTitle}</h3>
          <p className="state-text">{error instanceof Error ? error.message : t.userList.loadErrorUnknown}</p>
        </div>
      </div>
    );
  }

  // Calculate stats
  const users = (data?.users ?? []) as UserListItem[];
  // Active/inactive counts come from the global dashboard endpoint, not the
  // current page of `users` — a per-page count would misreport the % of total.
  const globalTotal = dashboardStats?.dashboard.total_users ?? data?.total ?? 0;
  const activeUsers = dashboardStats?.dashboard.active_users ?? 0;
  const inactiveUsers = Math.max(globalTotal - activeUsers, 0);
  // XP totals are page-local by necessity (no global XP aggregate endpoint exists yet).
  const pageTotalXP = users.reduce((sum, u) => sum + (u.total_xp || 0), 0);
  const pageAvgXP = users.length ? Math.round(pageTotalXP / users.length) : 0;
  const pct = (n: number) => fill(t.userList.ofTotal, { p: globalTotal > 0 ? Math.round((n / globalTotal) * 100) : 0 });
  const allSelected = users.length > 0 && selectedUsers.size === users.length;
  const canDelete = (u: UserListItem) => role === 'super_admin' && u.id !== currentAdmin?.id && u.role_level < 2;
  const roleTone = (level: number) => (level === 2 ? 'badge--danger' : level === 1 ? 'badge--warn' : 'badge--muted');
  const sort = filters.sort_by ? { key: filters.sort_by, dir: filters.order ?? 'desc' } : undefined;

  const columns: Column<UserListItem>[] = [
    {
      header: (
        <input
          type="checkbox"
          checked={allSelected}
          onChange={handleSelectAll}
          aria-label={t.userList.selectAll}
        />
      ),
      render: (user) => (
        <input
          type="checkbox"
          checked={selectedUsers.has(user.id)}
          onChange={() => handleToggleSelect(user.id)}
          aria-label={fill(t.userList.selectOne, { name: user.display_name || user.email })}
        />
      ),
    },
    {
      header: t.userList.colUser,
      sortKey: 'email',
      render: (user) => (
        <div className="user-cell">
          <div className="user-cell__avatar" aria-hidden="true">{(user.display_name || user.email)[0].toUpperCase()}</div>
          <div>
            <button type="button" className="link-button table-title" onClick={() => handleViewDetail(user.id)}>
              {user.display_name || user.email.split('@')[0]}
            </button>
            <div className="table-sub">{user.email}</div>
          </div>
        </div>
      ),
    },
    {
      header: t.userList.colRole,
      sortKey: 'role',
      render: (user) => <span className={`badge ${roleTone(user.role_level)}`}>{getRoleLabel(user.role_level)}</span>,
    },
    {
      header: t.userList.colProgress,
      sortKey: 'total_xp',
      render: (user) => (
        <div className="stack stack--tight">
          <div className="xp-row">
            <div className="xp-meter"><span style={{ width: `${Math.min(100, (user.total_xp || 0) / 100)}%` }} /></div>
            <span className="table-meta xp-row__value">{(user.total_xp || 0).toLocaleString()} XP</span>
          </div>
          <span className="table-meta">{fill(t.userList.streak, { n: user.streak_days || 0 })}</span>
        </div>
      ),
    },
    {
      header: t.userList.colStatus,
      render: (user) => (
        <span className={`badge ${user.is_active ? 'badge--ok' : 'badge--muted'}`}>
          {user.is_active ? t.userList.statusActive : t.userList.statusPaused}
        </span>
      ),
    },
    {
      header: t.userList.colJoined,
      sortKey: 'created_at',
      render: (user) => (
        <div className="stack stack--tight">
          <div className="table-meta">{new Date(user.created_at).toLocaleDateString(dateLocale)}</div>
          <div className="table-sub">
            {user.last_login
              ? fill(t.userList.lastLogin, { d: new Date(user.last_login).toLocaleDateString(dateLocale) })
              : t.userList.neverLoggedIn}
          </div>
        </div>
      ),
    },
    {
      header: t.userList.colActions,
      align: 'right',
      render: (user) => {
        const toggleLabel = user.is_active ? t.userList.deactivate : t.userList.activate;
        return (
          <div className="table-actions">
            <button type="button" onClick={() => handleViewDetail(user.id)} className="icon-button" title={t.userList.view} aria-label={t.userList.view}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                <circle cx="12" cy="12" r="3"/>
              </svg>
            </button>
            <button
              type="button"
              onClick={() => handleToggleStatus(user.id, user.is_active)}
              disabled={statusMutation.isPending}
              className="icon-button"
              title={toggleLabel}
              aria-label={toggleLabel}
            >
              {user.is_active ? (
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                  <circle cx="12" cy="12" r="10"/>
                  <line x1="15" y1="9" x2="9" y2="15"/>
                  <line x1="9" y1="9" x2="15" y2="15"/>
                </svg>
              ) : (
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                  <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                  <polyline points="22 4 12 14.01 9 11.01"/>
                </svg>
              )}
            </button>
            {canDelete(user) && (
              <button
                type="button"
                onClick={() => handlePermanentDelete(user.id, user.email)}
                disabled={deleteMutation.isPending}
                className="icon-button icon-button--danger"
                title={t.userList.deletePermanent}
                aria-label={t.userList.deletePermanent}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                  <polyline points="3 6 5 6 21 6"/>
                  <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6m5 0V4a2 2 0 0 1 2-2h0a2 2 0 0 1 2 2v2"/>
                  <line x1="10" y1="11" x2="10" y2="17"/>
                  <line x1="14" y1="11" x2="14" y2="17"/>
                </svg>
              </button>
            )}
          </div>
        );
      },
    },
  ];

  const page = filters.page || 1;

  return (
    <div className="stack">
      {actionError && <div className="form-error" role="alert">{actionError}</div>}
      <div className="cluster cluster--between">
        <SectionHeader title={t.userList.title} description={t.userList.description} />

        {selectedUsers.size > 0 && (
          <div className="bulk-bar" role="region" aria-live="polite">
            <span className="bulk-bar__count">{fill(t.userList.selected, { n: selectedUsers.size })}</span>
            <button onClick={() => handleBulkAction('activate')} disabled={bulkActionMutation.isPending} className="ghost-button">
              {t.userList.activate}
            </button>
            <button onClick={() => handleBulkAction('deactivate')} disabled={bulkActionMutation.isPending} className="ghost-button">
              {t.userList.deactivate}
            </button>
          </div>
        )}
      </div>

      {data && (
        <div className="card-grid">
          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
                <circle cx="9" cy="7" r="4"/>
                <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
                <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">{t.userList.statTotal}</div>
              <div className="stat-value">{data.total.toLocaleString()}</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                <polyline points="22 4 12 14.01 9 11.01"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">{t.userList.statActive}</div>
              <div className="stat-value">{activeUsers}</div>
              <div className="stat-meta">{pct(activeUsers)}</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <circle cx="12" cy="12" r="10"/>
                <line x1="12" y1="8" x2="12" y2="12"/>
                <line x1="12" y1="16" x2="12.01" y2="16"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">{t.userList.statInactive}</div>
              <div className="stat-value">{inactiveUsers}</div>
              <div className="stat-meta">{pct(inactiveUsers)}</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">{t.userList.avgXp}</div>
              <div className="stat-value">{pageAvgXP.toLocaleString()}</div>
              <div className="stat-meta">{fill(t.userList.pageXp, { n: pageTotalXP.toLocaleString() })}</div>
            </div>
          </div>
        </div>
      )}

      <UserFiltersPanel filters={filters} onFilterChange={handleFilterChange} />

      {isLoading ? (
        <div className="panel center-state" role="status">
          <div className="spinner" />
          <p>{t.userList.loading}</p>
        </div>
      ) : users.length === 0 ? (
        <div className="empty-state">
          <div className="empty-title">{t.userList.emptyTitle}</div>
          <div className="empty-description">{t.userList.emptyDescription}</div>
        </div>
      ) : (
        <DataTable columns={columns} rows={users} sort={sort} onSort={handleSort} rowKey={(u) => u.id} />
      )}

      {data && data.total_pages > 1 && (
        <nav className="panel pagination" aria-label={t.userList.colUser}>
          <div className="cluster cluster--between">
            <button onClick={() => handlePageChange(page - 1)} disabled={page === 1} className="ghost-button">
              {t.userList.prev}
            </button>

            <div className="cluster">
              {Array.from({ length: data.total_pages }, (_, i) => {
                const n = i + 1;
                const showPage = n === 1 || n === data.total_pages || Math.abs(n - page) <= 2;
                const showEllipsis = (n === 2 && page > 4) || (n === data.total_pages - 1 && page < data.total_pages - 3);

                if (showEllipsis) return <span key={n} className="pagination__gap">...</span>;
                if (!showPage) return null;

                return (
                  <button
                    key={n}
                    onClick={() => handlePageChange(n)}
                    className={n === page ? 'page-button active' : 'page-button'}
                    aria-current={n === page ? 'page' : undefined}
                  >
                    {n}
                  </button>
                );
              })}
            </div>

            <button onClick={() => handlePageChange(page + 1)} disabled={page === data.total_pages} className="ghost-button">
              {t.userList.next}
            </button>
          </div>
          <div className="pagination__info table-meta">
            {fill(t.userList.pageInfo, { page, pages: data.total_pages, total: data.total })}
          </div>
        </nav>
      )}

      {detailModalUserId && (
        <UserDetailModal
          userId={detailModalUserId}
          onClose={() => setDetailModalUserId(null)}
        />
      )}
    </div>
  );
}
