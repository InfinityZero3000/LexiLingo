/**
 * User Management Page
 * Phase 2 - Admin Panel
 */
import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getUsers,
  updateUserStatus,
  bulkUserAction,
  getUserDetail,
  getRoleLabel,
  getRoleColor,
  type UserFilters,
  type UserListItem,
} from '../lib/userManagementApi';
import UserDetailModal from '../components/user-management/UserDetailModal';import { SectionHeader } from "../components/SectionHeader";import UserFiltersPanel from '../components/user-management/UserFiltersPanel';

export default function UserManagementPage() {
  const queryClient = useQueryClient();
  
  // State
  const [filters, setFilters] = useState<UserFilters>({
    page: 1,
    page_size: 20,
    sort_by: 'created_at',
    order: 'desc',
  });
  
  const [selectedUsers, setSelectedUsers] = useState<Set<string>>(new Set());
  const [detailModalUserId, setDetailModalUserId] = useState<string | null>(null);
  
  // Queries
  const { data, isLoading, error } = useQuery({
    queryKey: ['users', filters],
    queryFn: () => getUsers(filters),
    staleTime: 30000, // 30 seconds
  });
  
  // Mutations
  const statusMutation = useMutation({
    mutationFn: ({ userId, isActive }: { userId: string; isActive: boolean }) =>
      updateUserStatus(userId, { is_active: isActive }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });
  
  const bulkActionMutation = useMutation({
    mutationFn: bulkUserAction,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      setSelectedUsers(new Set());
    },
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
  
  const handleBulkAction = (action: 'activate' | 'deactivate') => {
    if (selectedUsers.size === 0) return;
    
    if (confirm(`Are you sure you want to ${action} ${selectedUsers.size} user(s)?`)) {
      bulkActionMutation.mutate({
        user_ids: Array.from(selectedUsers),
        action,
      });
    }
  };
  
  const handleToggleStatus = (userId: string, currentStatus: boolean) => {
    if (confirm(`Are you sure you want to ${currentStatus ? 'deactivate' : 'activate'} this user?`)) {
      statusMutation.mutate({ userId, isActive: !currentStatus });
    }
  };
  
  const handleViewDetail = (userId: string) => {
    setDetailModalUserId(userId);
  };
  
  // Render
  if (error) {
    return (
      <div className="stack" style={{ padding: 32 }}>
        <div className="form-error" style={{ padding: 20 }}>
          <h3 style={{ margin: '0 0 8px', fontWeight: 600 }}>Lỗi tải dữ liệu</h3>
          <p style={{ margin: 0, fontSize: 14 }}>{error instanceof Error ? error.message : 'Lỗi không xác định'}</p>
        </div>
      </div>
    );
  }
  
  // Calculate stats
  const activeUsers = data?.users.filter(u => u.is_active).length || 0;
  const inactiveUsers = data?.users.filter(u => !u.is_active).length || 0;
  const totalXP = data?.users.reduce((sum, u) => sum + (u.total_xp || 0), 0) || 0;
  const avgXP = data?.users.length ? Math.round(totalXP / data.users.length) : 0;

  return (
    <div className="stack">
      {/* Header */}
      <div className="cluster" style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <SectionHeader title="Quản lý Người dùng" description="Quản lý người dùng, vai trò và quyền hạn" />
        
        {selectedUsers.size > 0 && (
          <div className="cluster" style={{ gap: 12, alignItems: 'center', padding: '12px 16px', background: 'var(--panel)', borderRadius: 12, border: '1px solid var(--line)' }}>
            <span style={{ fontSize: 14, color: 'var(--text)', fontWeight: 600 }}>{selectedUsers.size} đã chọn</span>
            <button
              onClick={() => handleBulkAction('activate')}
              disabled={bulkActionMutation.isPending}
              className="btn-secondary"
              style={{ minWidth: 100 }}
            >
              Kích hoạt
            </button>
            <button
              onClick={() => handleBulkAction('deactivate')}
              disabled={bulkActionMutation.isPending}
              className="ghost-button"
              style={{ minWidth: 100 }}
            >
              Hủy kích hoạt
            </button>
          </div>
        )}
      </div>
      
      {/* Stats Cards */}
      {data && (
        <div className="card-grid">
          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
                <circle cx="9" cy="7" r="4"/>
                <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
                <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">Tổng người dùng</div>
              <div className="stat-value">{data.total.toLocaleString()}</div>
            </div>
          </div>
          
          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                <polyline points="22 4 12 14.01 9 11.01"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">Đang hoạt động</div>
              <div className="stat-value">{activeUsers}</div>
              <div className="stat-meta">{data.total > 0 ? Math.round((activeUsers / data.total) * 100) : 0}% tổng số</div>
            </div>
          </div>
          
          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="10"/>
                <line x1="12" y1="8" x2="12" y2="12"/>
                <line x1="12" y1="16" x2="12.01" y2="16"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">Ngừng hoạt động</div>
              <div className="stat-value">{inactiveUsers}</div>
              <div className="stat-meta">{data.total > 0 ? Math.round((inactiveUsers / data.total) * 100) : 0}% tổng số</div>
            </div>
          </div>
          
          <div className="stat-card">
            <div className="stat-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
              </svg>
            </div>
            <div>
              <div className="stat-label">Trung bình XP</div>
              <div className="stat-value">{avgXP.toLocaleString()}</div>
              <div className="stat-meta">Tổng: {totalXP.toLocaleString()} XP</div>
            </div>
          </div>
        </div>
      )}
      
      {/* Filters */}
      <UserFiltersPanel filters={filters} onFilterChange={handleFilterChange} />
      
      {/* Table */}
      <div className="panel" style={{ padding: 0, overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ padding: '64px 32px', textAlign: 'center' }}>
            <div className="spinner" style={{ width: 48, height: 48, margin: '0 auto' }}></div>
            <p style={{ marginTop: 16, color: 'var(--muted)' }}>Đang tải người dùng...</p>
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ background: 'var(--panel-soft)', borderBottom: '1px solid var(--line)' }}>
                  <th style={{ padding: '12px 16px', textAlign: 'left', width: 40 }}>
                    <input
                      type="checkbox"
                      checked={data?.users && selectedUsers.size === data.users.length}
                      onChange={handleSelectAll}
                      style={{ cursor: 'pointer' }}
                    />
                  </th>
                  <th className="table-header">Người dùng</th>
                  <th className="table-header">Role</th>
                  <th className="table-header">Tiến trình</th>
                  <th className="table-header">Trạng thái</th>
                  <th className="table-header">Tham gia</th>
                  <th className="table-header" style={{ textAlign: 'right', paddingRight: 16 }}>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {data?.users.map((user) => (
                  <tr key={user.id} style={{ borderBottom: '1px solid var(--line)', transition: 'background 0.15s', cursor: 'pointer' }} onMouseEnter={(e) => e.currentTarget.style.background = 'var(--panel-soft)'} onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}>
                    <td style={{ padding: '16px', width: 40 }}>
                      <input
                        type="checkbox"
                        checked={selectedUsers.has(user.id)}
                        onChange={() => handleToggleSelect(user.id)}
                        style={{ cursor: 'pointer' }}
                      />
                    </td>
                    <td style={{ padding: '16px' }}>
                      <div className="cluster" style={{ gap: 12, alignItems: 'center' }}>
                        {user.avatar_url ? (
                          <img src={user.avatar_url} alt="" style={{ width: 44, height: 44, borderRadius: '50%', objectFit: 'cover', border: '2px solid var(--line)' }} />
                        ) : (
                          <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'linear-gradient(135deg, var(--accent), #ff8c42)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 600, fontSize: 16 }}>
                            {user.email[0].toUpperCase()}
                          </div>
                        )}
                        <div>
                          <div className="table-title">{user.display_name || user.email.split('@')[0]}</div>
                          <div className="table-sub">{user.email}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ padding: '16px' }}>
                      <span className="badge" style={{ 
                        background: user.role_level === 2 ? 'rgba(239, 68, 68, 0.1)' : user.role_level === 1 ? 'rgba(255, 77, 0, 0.1)' : 'var(--panel-soft)',
                        color: user.role_level === 2 ? '#dc2626' : user.role_level === 1 ? 'var(--accent)' : 'var(--muted)'
                      }}>
                        {getRoleLabel(user.role_level)}
                      </span>
                    </td>
                    <td style={{ padding: '16px' }}>
                      <div className="stack" style={{ gap: 6 }}>
                        <div className="cluster" style={{ gap: 8, alignItems: 'center' }}>
                          <div style={{ flex: 1, height: 6, background: 'var(--panel-soft)', borderRadius: 3, overflow: 'hidden' }}>
                            <div style={{ width: `${Math.min(100, (user.total_xp || 0) / 100)}%`, height: '100%', background: 'linear-gradient(90deg, var(--accent), #fbbf24)', borderRadius: 3, transition: 'width 0.3s' }}></div>
                          </div>
                          <span className="table-meta" style={{ minWidth: 60 }}>{(user.total_xp || 0).toLocaleString()} XP</span>
                        </div>
                        <span className="table-meta">
                          Streak: {user.streak_days || 0} days
                        </span>
                      </div>
                    </td>
                    <td style={{ padding: '16px' }}>
                      <span className="badge" style={{ 
                        background: user.is_active ? 'rgba(34, 197, 94, 0.1)' : 'rgba(156, 163, 175, 0.1)',
                        color: user.is_active ? '#16a34a' : '#6b7280'
                      }}>
                        {user.is_active ? 'Hoạt động' : 'Tạm dừng'}
                      </span>
                    </td>
                    <td style={{ padding: '16px' }}>
                      <div className="stack" style={{ gap: 4 }}>
                        <div className="table-meta">{new Date(user.created_at).toLocaleDateString('vi-VN')}</div>
                        <div className="table-sub" style={{ fontSize: 11 }}>
                          {user.last_login ? `Đăng nhập: ${new Date(user.last_login).toLocaleDateString('vi-VN')}` : 'Chưa đăng nhập'}
                        </div>
                      </div>
                    </td>
                    <td style={{ padding: '16px', textAlign: 'right' }}>
                      <div className="cluster" style={{ gap: 6, justifyContent: 'flex-end' }}>
                        <button
                          onClick={() => handleViewDetail(user.id)}
                          className="icon-button"
                          title="Xem chi tiết"
                          style={{ width: 32, height: 32 }}
                        >
                          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                            <circle cx="12" cy="12" r="3"/>
                          </svg>
                        </button>
                        <button
                          onClick={() => handleToggleStatus(user.id, user.is_active)}
                          disabled={statusMutation.isPending}
                          className="icon-button"
                          title={user.is_active ? 'Hủy kích hoạt' : 'Kích hoạt'}
                          style={{ width: 32, height: 32, opacity: statusMutation.isPending ? 0.5 : 1 }}
                        >
                          {user.is_active ? (
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                              <circle cx="12" cy="12" r="10"/>
                              <line x1="15" y1="9" x2="9" y2="15"/>
                              <line x1="9" y1="9" x2="15" y2="15"/>
                            </svg>
                          ) : (
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                              <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                              <polyline points="22 4 12 14.01 9 11.01"/>
                            </svg>
                          )}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            
            {data?.users.length === 0 && (
              <div className="empty-state" style={{ margin: 32, border: 'none' }}>
                <div className="empty-title">Không tìm thấy người dùng</div>
                <div className="empty-description">Thử thay đổi bộ lọc của bạn</div>
              </div>
            )}
          </div>
        )}
      </div>
      
      {/* Pagination */}
      {data && data.total_pages > 1 && (
        <div className="panel" style={{ padding: 16 }}>
          <div className="cluster" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
            <button
              onClick={() => handlePageChange(filters.page! - 1)}
              disabled={filters.page === 1}
              className="btn-secondary"
              style={{ minWidth: 100, opacity: filters.page === 1 ? 0.4 : 1 }}
            >
              ← Trước
            </button>
            
            <div className="cluster" style={{ gap: 6 }}>
              {Array.from({ length: data.total_pages }, (_, i) => {
                const page = i + 1;
                const isCurrentPage = filters.page === page;
                const showPage = page === 1 || page === data.total_pages || Math.abs(page - (filters.page || 1)) <= 2;
                const showEllipsis = (page === 2 && (filters.page || 1) > 4) || (page === data.total_pages - 1 && (filters.page || 1) < data.total_pages - 3);
                
                if (showEllipsis) {
                  return <span key={page} style={{ padding: '0 4px', color: 'var(--muted)' }}>...</span>;
                }
                
                if (!showPage) return null;
                
                return (
                  <button
                    key={page}
                    onClick={() => handlePageChange(page)}
                    style={{
                      minWidth: 36,
                      height: 36,
                      padding: '0 12px',
                      borderRadius: 8,
                      border: 'none',
                      background: isCurrentPage ? 'var(--accent)' : 'var(--panel-soft)',
                      color: isCurrentPage ? 'white' : 'var(--text)',
                      fontWeight: isCurrentPage ? 600 : 500,
                      fontSize: 14,
                      cursor: 'pointer',
                      transition: 'all 0.2s'
                    }}
                    onMouseEnter={(e) => !isCurrentPage && (e.currentTarget.style.background = 'var(--line)')}
                    onMouseLeave={(e) => !isCurrentPage && (e.currentTarget.style.background = 'var(--panel-soft)')}
                  >
                    {page}
                  </button>
                );
              })}
            </div>
            
            <button
              onClick={() => handlePageChange(filters.page! + 1)}
              disabled={filters.page === data.total_pages}
              className="btn-secondary"
              style={{ minWidth: 100, opacity: filters.page === data.total_pages ? 0.4 : 1 }}
            >
              Sau →
            </button>
          </div>
          <div style={{ marginTop: 12, textAlign: 'center' }}>
            <span className="table-meta">Trang {filters.page} / {data.total_pages} • Tổng {data.total} người dùng</span>
          </div>
        </div>
      )}
      
      {/* Detail Modal */}
      {detailModalUserId && (
        <UserDetailModal
          userId={detailModalUserId}
          onClose={() => setDetailModalUserId(null)}
        />
      )}
    </div>
  );
}
