/**
 * User Detail Modal
 * View and edit user information
 */
import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getUserDetail,
  updateUser,
  updateUserRole,
  getUserActivity,
  getRoleLabel,
  type UserUpdateData,
} from '../../lib/userManagementApi';

interface UserDetailModalProps {
  userId: string;
  onClose: () => void;
}

export default function UserDetailModal({ userId, onClose }: UserDetailModalProps) {
  const queryClient = useQueryClient();
  const [isEditing, setIsEditing] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'activity'>('info');
  
  // Form state
  const [formData, setFormData] = useState<UserUpdateData>({});
  
  // Queries
  const { data: user, isLoading } = useQuery({
    queryKey: ['user-detail', userId],
    queryFn: () => getUserDetail(userId),
  });
  
  const { data: activities } = useQuery({
    queryKey: ['user-activity', userId],
    queryFn: () => getUserActivity(userId, 30),
    enabled: activeTab === 'activity',
  });
  
  // Mutations
  const updateMutation = useMutation({
    mutationFn: (data: UserUpdateData) => updateUser(userId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-detail', userId] });
      queryClient.invalidateQueries({ queryKey: ['users'] });
      setIsEditing(false);
    },
  });
  
  const roleChangeMutation = useMutation({
    mutationFn: (level: number) => updateUserRole(userId, { level }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-detail', userId] });
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });
  
  // Handlers
  const handleEdit = () => {
    if (user) {
      setFormData({
        display_name: user.display_name || '',
        bio: user.bio || '',
      });
      setIsEditing(true);
    }
  };
  
  const handleSave = () => {
    updateMutation.mutate(formData);
  };
  
  const handleRoleChange = (level: number) => {
    if (confirm(`Are you sure you want to change this user's role to ${getRoleLabel(level)}?`)) {
      roleChangeMutation.mutate(level);
    }
  };
  
  if (isLoading) {
    return (
      <div className="modal-overlay">
        <div className="modal-content" style={{ maxWidth: 400, textAlign: 'center' }}>
          <div className="spinner" style={{ width: 44, height: 44, margin: '0 auto' }}></div>
          <p style={{ marginTop: 16, color: 'var(--muted)' }}>Đang tải thông tin...</p>
        </div>
      </div>
    );
  }
  
  if (!user) {
    return null;
  }
  
  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-content" style={{ maxWidth: 720 }}>
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            {user.avatar_url ? (
              <img src={user.avatar_url} alt="" style={{ width: 56, height: 56, borderRadius: '50%', objectFit: 'cover', border: '2px solid var(--line)' }} />
            ) : (
              <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'linear-gradient(135deg, var(--accent), #ff8c42)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700, fontSize: 22 }}>
                {user.email[0].toUpperCase()}
              </div>
            )}
            <div>
              <h3 style={{ margin: '0 0 4px', fontSize: 20, fontWeight: 700 }}>
                {user.display_name || user.email.split('@')[0]}
              </h3>
              <span className="table-sub">{user.email}</span>
            </div>
          </div>
          <button onClick={onClose} className="icon-button" style={{ width: 36, height: 36 }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>
        
        {/* Tabs */}
        <div className="tab-row" style={{ marginBottom: 20 }}>
          <button
            onClick={() => setActiveTab('info')}
            className={`tab ${activeTab === 'info' ? 'active' : ''}`}
          >
            Thông tin
          </button>
          <button
            onClick={() => setActiveTab('activity')}
            className={`tab ${activeTab === 'activity' ? 'active' : ''}`}
          >
            Hoạt động
          </button>
        </div>
        
        {/* Content */}
        <div style={{ maxHeight: '55vh', overflowY: 'auto' }}>
          {activeTab === 'info' ? (
            <div className="stack">
              {/* Stats Grid */}
              <div className="card-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
                <div className="panel-inner" style={{ textAlign: 'center' }}>
                  <div className="stat-label">Total XP</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--accent)' }}>{user.total_xp.toLocaleString()}</div>
                </div>
                <div className="panel-inner" style={{ textAlign: 'center' }}>
                  <div className="stat-label">Streak</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--accent-2)' }}>0 days</div>
                  <div className="table-sub" style={{ fontSize: 10 }}>Coming soon</div>
                </div>
                <div className="panel-inner" style={{ textAlign: 'center' }}>
                  <div className="stat-label">Khóa học</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--accent-3)' }}>
                    {user.courses_completed}/{user.courses_enrolled}
                  </div>
                </div>
                <div className="panel-inner" style={{ textAlign: 'center' }}>
                  <div className="stat-label">Bài học</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--accent-4)' }}>{user.lessons_completed}</div>
                </div>
              </div>
              
              {/* User Info */}
              <div className="panel-inner">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <h4 style={{ margin: 0, fontSize: 15, fontWeight: 600 }}>Thông tin cá nhân</h4>
                  {!isEditing && (
                    <button onClick={handleEdit} className="ghost-button small">Chỉnh sửa</button>
                  )}
                </div>
                
                {isEditing ? (
                  <div className="form">
                    <label>
                      Tên hiển thị
                      <input
                        type="text"
                        value={formData.display_name || ''}
                        onChange={(e) => setFormData({ ...formData, display_name: e.target.value })}
                      />
                    </label>
                    <label>
                      Giới thiệu
                      <textarea
                        value={formData.bio || ''}
                        onChange={(e) => setFormData({ ...formData, bio: e.target.value })}
                        rows={3}
                      />
                    </label>
                    <div className="inline-actions" style={{ justifyContent: 'flex-end' }}>
                      <button onClick={() => setIsEditing(false)} className="ghost-button small">Hủy</button>
                      <button onClick={handleSave} disabled={updateMutation.isPending} className="primary-button" style={{ fontSize: 13, padding: '8px 16px', minHeight: 34 }}>
                        {updateMutation.isPending ? 'Đang lưu...' : 'Lưu thay đổi'}
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="mini-list">
                    <div className="pill-item">
                      <span className="table-sub">Tên hiển thị</span>
                      <span className="pill-title" style={{ fontSize: 13 }}>{user.display_name || 'Chưa đặt'}</span>
                    </div>
                    <div className="pill-item">
                      <span className="table-sub">Giới thiệu</span>
                      <span className="pill-title" style={{ fontSize: 13 }}>{user.bio || 'Chưa đặt'}</span>
                    </div>
                    <div className="pill-item">
                      <span className="table-sub">Ngôn ngữ</span>
                      <span className="pill-title" style={{ fontSize: 13 }}>{user.language_preference || 'Chưa đặt'}</span>
                    </div>
                    <div className="pill-item">
                      <span className="table-sub">Thông báo</span>
                      <span className={`status-pill ${user.notification_enabled ? 'success' : 'neutral'}`}>
                        {user.notification_enabled ? 'Bật' : 'Tắt'}
                      </span>
                    </div>
                  </div>
                )}
              </div>
              
              {/* Role Management */}
              <div className="panel-inner">
                <h4 style={{ margin: 0, fontSize: 15, fontWeight: 600 }}>Vai trò & Trạng thái</h4>
                <div className="mini-list">
                  <div className="pill-item">
                    <span className="table-sub">Vai trò</span>
                    <span className={`status-pill ${user.role_level === 2 ? 'danger' : user.role_level === 1 ? 'warning' : 'info'}`}>
                      {getRoleLabel(user.role_level)}
                    </span>
                  </div>
                  <div className="pill-item">
                    <span className="table-sub">Trạng thái</span>
                    <span className={`status-pill ${user.is_active ? 'success' : 'neutral'}`}>
                      {user.is_active ? 'Hoạt động' : 'Tạm dừng'}
                    </span>
                  </div>
                  <div className="pill-item">
                    <span className="table-sub">Ngày tham gia</span>
                    <span className="pill-title" style={{ fontSize: 13 }}>{new Date(user.created_at).toLocaleDateString('vi-VN')}</span>
                  </div>
                  <div className="pill-item">
                    <span className="table-sub">Đăng nhập cuối</span>
                    <span className="pill-title" style={{ fontSize: 13 }}>
                      {user.last_login ? new Date(user.last_login).toLocaleDateString('vi-VN') : 'Chưa đăng nhập'}
                    </span>
                  </div>
                </div>
                
                {/* Role Change */}
                <div style={{ paddingTop: 12, borderTop: '1px solid var(--line)' }}>
                  <p style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 8 }}>Thay đổi vai trò:</p>
                  <div className="action-group">
                    <button
                      onClick={() => handleRoleChange(0)}
                      disabled={user.role_level === 0 || roleChangeMutation.isPending}
                      className="mini-btn"
                      style={{ opacity: user.role_level === 0 ? 0.4 : 1 }}
                    >
                      User
                    </button>
                    <button
                      onClick={() => handleRoleChange(1)}
                      disabled={user.role_level === 1 || roleChangeMutation.isPending}
                      className="mini-btn"
                      style={{ opacity: user.role_level === 1 ? 0.4 : 1 }}
                    >
                      Admin
                    </button>
                    <button
                      onClick={() => handleRoleChange(2)}
                      disabled={user.role_level === 2 || roleChangeMutation.isPending}
                      className="mini-btn"
                      style={{ opacity: user.role_level === 2 ? 0.4 : 1 }}
                    >
                      Super Admin
                    </button>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            // Activity Timeline
            <div className="stack" style={{ gap: 0 }}>
              {activities && activities.length > 0 ? (
                activities.map((activity, index) => (
                  <div key={index} style={{ display: 'flex', gap: 14, padding: '14px 0', borderBottom: index < activities.length - 1 ? '1px solid var(--line)' : 'none' }}>
                    <div style={{ width: 38, height: 38, borderRadius: '50%', background: 'var(--panel-soft)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, border: '1px solid var(--line)' }}>
                      <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--accent)' }}>
                        {activity.activity_type === 'lesson_completed' ? 'L' : 'A'}
                      </span>
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="table-title" style={{ fontSize: 13 }}>{activity.description}</div>
                      <div style={{ display: 'flex', gap: 12, marginTop: 4, fontSize: 12, color: 'var(--muted)' }}>
                        <span>{new Date(activity.activity_date).toLocaleDateString('vi-VN')}</span>
                        {activity.xp_earned > 0 && (
                          <span style={{ color: 'var(--accent)', fontWeight: 600 }}>+{activity.xp_earned} XP</span>
                        )}
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="empty-state">
                  <div className="empty-title">Chưa có hoạt động</div>
                  <div className="empty-description">Người dùng chưa có hoạt động nào được ghi nhận</div>
                </div>
              )}
            </div>
          )}
        </div>
        
        {/* Footer */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 20, paddingTop: 16, borderTop: '1px solid var(--line)' }}>
          <button onClick={onClose} className="ghost-button small">Đóng</button>
        </div>
      </div>
    </div>
  );
}
