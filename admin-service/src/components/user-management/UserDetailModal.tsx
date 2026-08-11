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
  type UserUpdateData as ApiUserUpdateData,
  giftToUser,
  type GiftRequest,
} from '../../lib/userManagementApi';
import { listCoursesAdmin, listShopItems } from '../../lib/adminApi';

type UserUpdateData = ApiUserUpdateData & {
  bio?: string;
};

type UserDetailView = Awaited<ReturnType<typeof getUserDetail>> & {
  bio?: string | null;
  language_preference?: string | null;
  notification_enabled?: boolean;
};

interface UserDetailModalProps {
  userId: string;
  onClose: () => void;
}

export default function UserDetailModal({ userId, onClose }: UserDetailModalProps) {
  const queryClient = useQueryClient();
  const [isEditing, setIsEditing] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'activity' | 'gift'>('info');
  
  // Form state
  const [formData, setFormData] = useState<UserUpdateData>({});
  
  // Gifting Form states
  const [giftType, setGiftType] = useState<'gems' | 'course' | 'avatar' | 'shop_item'>('gems');
  const [selectedCourseId, setSelectedCourseId] = useState<string>('');
  const [selectedShopItemId, setSelectedShopItemId] = useState<string>('');
  const [amount, setAmount] = useState<number>(100);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Queries
  const { data: user, isLoading, error, refetch } = useQuery<UserDetailView>({
    queryKey: ['user-detail', userId],
    queryFn: () => getUserDetail(userId) as Promise<UserDetailView>,
  });
  
  const { data: activities } = useQuery({
    queryKey: ['user-activity', userId],
    queryFn: () => getUserActivity(userId, 30),
    enabled: activeTab === 'activity',
  });

  // Gifting Queries
  const { data: coursesData, isLoading: isLoadingCourses } = useQuery({
    queryKey: ['admin-courses-list'],
    queryFn: () => listCoursesAdmin({ page_size: 100 }),
    enabled: activeTab === 'gift',
  });

  const { data: shopItemsData, isLoading: isLoadingShopItems } = useQuery({
    queryKey: ['admin-shop-items-list'],
    queryFn: () => listShopItems(true),
    enabled: activeTab === 'gift',
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

  const giftMutation = useMutation({
    mutationFn: (payload: GiftRequest) => giftToUser(userId, payload),
    onSuccess: (res) => {
      if (res.success) {
        setSuccessMessage(`Đã gửi quà thành công: ${res.data?.gift_description || ''}`);
        setErrorMessage(null);
        queryClient.invalidateQueries({ queryKey: ['user-detail', userId] });
        queryClient.invalidateQueries({ queryKey: ['users'] });
        setAmount(giftType === 'gems' ? 100 : 1);
        setSelectedCourseId('');
        setSelectedShopItemId('');
      } else {
        setErrorMessage(res.message || 'Gửi quà thất bại');
        setSuccessMessage(null);
      }
    },
    onError: (err: any) => {
      setErrorMessage(err?.message || 'Lỗi không xác định khi gửi quà');
      setSuccessMessage(null);
    }
  });

  const handleSendGift = (e: React.FormEvent) => {
    e.preventDefault();
    setSuccessMessage(null);
    setErrorMessage(null);

    const payload: GiftRequest = {
      gift_type: giftType,
    };

    if (giftType === 'gems') {
      if (!amount || amount <= 0) {
        setErrorMessage('Số lượng Gems phải lớn hơn 0');
        return;
      }
      payload.amount = amount;
    } else if (giftType === 'course') {
      if (!selectedCourseId) {
        setErrorMessage('Vui lòng chọn khóa học');
        return;
      }
      payload.course_id = selectedCourseId;
    } else if (giftType === 'avatar') {
      if (!selectedShopItemId) {
        setErrorMessage('Vui lòng chọn Avatar');
        return;
      }
      payload.shop_item_id = selectedShopItemId;
    } else if (giftType === 'shop_item') {
      if (!selectedShopItemId) {
        setErrorMessage('Vui lòng chọn vật phẩm');
        return;
      }
      payload.shop_item_id = selectedShopItemId;
      payload.amount = amount;
    }

    giftMutation.mutate(payload);
  };

  const coursesList = coursesData?.data?.courses || [];
  const shopItemsList = shopItemsData?.data || [];
  const avatarsList = shopItemsList.filter(item => item.item_type === 'avatar');
  const consumablesList = shopItemsList.filter(item => item.item_type !== 'avatar');

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
  
  if (error || !user) {
    return (
      <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
        <div className="modal-content" style={{ maxWidth: 400, textAlign: 'center' }}>
          <p style={{ color: 'var(--danger, #e11d48)' }}>
            {error instanceof Error ? error.message : 'Không tải được thông tin người dùng.'}
          </p>
          <div style={{ display: 'flex', gap: 8, justifyContent: 'center', marginTop: 16 }}>
            <button className="btn-secondary" onClick={() => refetch()}>Thử lại</button>
            <button className="ghost-button" onClick={onClose}>Đóng</button>
          </div>
        </div>
      </div>
    );
  }
  
  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-content" style={{ maxWidth: 720 }}>
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'linear-gradient(135deg, var(--accent), #ff8c42)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700, fontSize: 22 }}>
              {(user.display_name || user.email)[0].toUpperCase()}
            </div>
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
            onClick={() => {
              setActiveTab('info');
              setSuccessMessage(null);
              setErrorMessage(null);
            }}
            className={`tab ${activeTab === 'info' ? 'active' : ''}`}
          >
            Thông tin
          </button>
          <button
            onClick={() => {
              setActiveTab('activity');
              setSuccessMessage(null);
              setErrorMessage(null);
            }}
            className={`tab ${activeTab === 'activity' ? 'active' : ''}`}
          >
            Hoạt động
          </button>
          <button
            onClick={() => {
              setActiveTab('gift');
              setSuccessMessage(null);
              setErrorMessage(null);
            }}
            className={`tab ${activeTab === 'gift' ? 'active' : ''}`}
          >
            Gửi Quà
          </button>
        </div>
        
        {/* Content */}
        <div style={{ maxHeight: '55vh', overflowY: 'auto' }}>
          {activeTab === 'info' && (
            <div className="stack">
              {/* Stats Grid */}
              <div className="card-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
                <div className="panel-inner" style={{ textAlign: 'center' }}>
                  <div className="stat-label">Total XP</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--accent)' }}>{user.total_xp.toLocaleString()}</div>
                </div>
                <div className="panel-inner" style={{ textAlign: 'center' }}>
                  <div className="stat-label">Streak</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--accent-2)' }}>—</div>
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
          )}

          {activeTab === 'activity' && (
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

          {activeTab === 'gift' && (
            <div className="stack">
              <div className="panel-inner">
                <h4 style={{ margin: '0 0 16px', fontSize: 15, fontWeight: 600 }}>Gửi Quà Tặng (Admin)</h4>
                
                {successMessage && (
                  <div className="form-success" style={{ marginBottom: 16, padding: '10px 14px', borderRadius: 8, background: 'rgba(34, 197, 94, 0.1)', color: '#16a34a', fontSize: 13, border: '1px solid rgba(34, 197, 94, 0.2)' }}>
                    {successMessage}
                  </div>
                )}
                
                {errorMessage && (
                  <div className="form-error" style={{ marginBottom: 16, padding: '10px 14px', borderRadius: 8, background: 'rgba(239, 68, 68, 0.1)', color: '#dc2626', fontSize: 13, border: '1px solid rgba(239, 68, 68, 0.2)' }}>
                    {errorMessage}
                  </div>
                )}

                <form onSubmit={handleSendGift} className="form" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                  <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    Loại quà tặng
                    <select 
                      value={giftType} 
                      onChange={(e) => {
                        const val = e.target.value as any;
                        setGiftType(val);
                        setAmount(val === 'gems' ? 100 : 1);
                        setSuccessMessage(null);
                        setErrorMessage(null);
                      }}
                      style={{ padding: '8px 12px', borderRadius: 8, border: '1px solid var(--line)', background: 'var(--panel-soft)', color: 'var(--text)' }}
                    >
                      <option value="gems">💎 Gems (Tiền ảo)</option>
                      <option value="course">📚 Khóa học (Course)</option>
                      <option value="avatar">👤 Ảnh đại diện (Avatar Shop)</option>
                      <option value="shop_item">🛍️ Vật phẩm hỗ trợ (Streak freeze, Heart refill, Double XP...)</option>
                    </select>
                  </label>

                  {/* Course Dropdown */}
                  {giftType === 'course' && (
                    <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      Chọn Khóa học
                      {isLoadingCourses ? (
                        <span style={{ fontSize: 12, color: 'var(--muted)' }}>Đang tải danh sách khóa học...</span>
                      ) : (
                        <select
                          value={selectedCourseId}
                          onChange={(e) => setSelectedCourseId(e.target.value)}
                          style={{ padding: '8px 12px', borderRadius: 8, border: '1px solid var(--line)', background: 'var(--panel-soft)', color: 'var(--text)' }}
                          required
                        >
                          <option value="">-- Chọn Khóa học --</option>
                          {coursesList.map((course: any) => (
                            <option key={course.id} value={course.id}>
                              [{course.level}] {course.title}
                            </option>
                          ))}
                        </select>
                      )}
                    </label>
                  )}

                  {/* Avatar Dropdown */}
                  {giftType === 'avatar' && (
                    <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      Chọn Avatar
                      {isLoadingShopItems ? (
                        <span style={{ fontSize: 12, color: 'var(--muted)' }}>Đang tải danh sách Avatar...</span>
                      ) : (
                        <select
                          value={selectedShopItemId}
                          onChange={(e) => setSelectedShopItemId(e.target.value)}
                          style={{ padding: '8px 12px', borderRadius: 8, border: '1px solid var(--line)', background: 'var(--panel-soft)', color: 'var(--text)' }}
                          required
                        >
                          <option value="">-- Chọn Avatar --</option>
                          {avatarsList.map((item: any) => (
                            <option key={item.id} value={item.id}>
                              {item.name} ({item.price_gems} Gems)
                            </option>
                          ))}
                        </select>
                      )}
                    </label>
                  )}

                  {/* Shop Item Dropdown */}
                  {giftType === 'shop_item' && (
                    <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      Chọn Vật phẩm Shop
                      {isLoadingShopItems ? (
                        <span style={{ fontSize: 12, color: 'var(--muted)' }}>Đang tải danh sách vật phẩm...</span>
                      ) : (
                        <select
                          value={selectedShopItemId}
                          onChange={(e) => setSelectedShopItemId(e.target.value)}
                          style={{ padding: '8px 12px', borderRadius: 8, border: '1px solid var(--line)', background: 'var(--panel-soft)', color: 'var(--text)' }}
                          required
                        >
                          <option value="">-- Chọn vật phẩm --</option>
                          {consumablesList.map((item: any) => (
                            <option key={item.id} value={item.id}>
                              {item.name} ({item.item_type})
                            </option>
                          ))}
                        </select>
                      )}
                    </label>
                  )}

                  {/* Amount / Quantity Input */}
                  {(giftType === 'gems' || giftType === 'shop_item') && (
                    <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {giftType === 'gems' ? 'Số lượng Gems' : 'Số lượng vật phẩm'}
                      <input
                        type="number"
                        min={1}
                        value={amount}
                        onChange={(e) => setAmount(Math.max(1, parseInt(e.target.value) || 1))}
                        style={{ padding: '8px 12px', borderRadius: 8, border: '1px solid var(--line)', background: 'var(--panel-soft)', color: 'var(--text)' }}
                        required
                      />
                    </label>
                  )}

                  <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 8 }}>
                    <button 
                      type="submit" 
                      className="primary-button" 
                      disabled={giftMutation.isPending}
                      style={{ padding: '10px 24px', borderRadius: 8, fontSize: 14, fontWeight: 600 }}
                    >
                      {giftMutation.isPending ? 'Đang gửi...' : 'Gửi Quà Tặng'}
                    </button>
                  </div>
                </form>
              </div>
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
