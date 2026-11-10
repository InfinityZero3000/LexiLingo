/**
 * User Detail Modal
 * View and edit user information
 */
import { Dialog } from "../Dialog";
import { useConfirm } from "../ConfirmDialog";
import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { BookOpen, Gem, ShoppingBag, UserRound } from 'lucide-react';
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
import { usePermissions } from '../../lib/usePermissions';
import { getGemLimits } from '../../lib/gemLimitsApi';
import { UserWalletPanel } from './UserWalletPanel';
import { UserPremiumPanel } from './UserPremiumPanel';
import { useI18n } from '../../lib/i18n';

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
  const { t } = useI18n();
  const confirm = useConfirm();
  const { can } = usePermissions();
  const queryClient = useQueryClient();
  const [isEditing, setIsEditing] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'activity' | 'gift' | 'wallet' | 'premium'>('info');
  
  // Form state
  const [formData, setFormData] = useState<UserUpdateData>({});
  
  // Gifting Form states
  const [giftType, setGiftType] = useState<'gems' | 'course' | 'avatar' | 'shop_item'>('gems');
  const [selectedCourseId, setSelectedCourseId] = useState<string>('');
  const [selectedShopItemId, setSelectedShopItemId] = useState<string>('');
  const [amount, setAmount] = useState<number>(100);
  const [reason, setReason] = useState('');
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const GiftTypeIcon = {
    gems: Gem,
    course: BookOpen,
    avatar: UserRound,
    shop_item: ShoppingBag,
  }[giftType];

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
  
  const handleRoleChange = async (level: number) => {
    const ok = await confirm({
      message: t.userDetail.changeRoleConfirm.replace("{role}", getRoleLabel(level)),
      confirmLabel: t.userDetail.changeRoleAction,
    });
    if (ok) roleChangeMutation.mutate(level);
  };

  const { data: gemLimits } = useQuery({
    queryKey: ['gem-limits'],
    queryFn: getGemLimits,
    enabled: activeTab === 'gift',
  });

  const giftMutation = useMutation({
    mutationFn: (payload: GiftRequest) => giftToUser(userId, payload),
    onSuccess: (res) => {
      if (res.success) {
        setSuccessMessage(t.userDetail.giftSent.replace('{desc}', res.data?.gift_description || ''));
        setErrorMessage(null);
        queryClient.invalidateQueries({ queryKey: ['user-detail', userId] });
        queryClient.invalidateQueries({ queryKey: ['users'] });
        queryClient.invalidateQueries({ queryKey: ['gem-limits'] });
        queryClient.invalidateQueries({ queryKey: ['gem-grants'] });
        setReason('');
        setAmount(giftType === 'gems' ? 100 : 1);
        setSelectedCourseId('');
        setSelectedShopItemId('');
      } else {
        setErrorMessage(res.message || t.userDetail.giftFailed);
        setSuccessMessage(null);
      }
    },
    onError: (err: any) => {
      setErrorMessage(err?.message || t.userDetail.giftUnknownError);
      setSuccessMessage(null);
    }
  });

  const handleSendGift = (e: React.FormEvent) => {
    e.preventDefault();
    setSuccessMessage(null);
    setErrorMessage(null);

    if (reason.trim().length < 5) {
      setErrorMessage(t.userDetail.errGiftReason);
      return;
    }
    const payload: GiftRequest = {
      gift_type: giftType,
      reason: reason.trim(),
    };

    if (giftType === 'gems') {
      if (!amount || amount <= 0) {
        setErrorMessage(t.userDetail.errGemsPositive);
        return;
      }
      payload.amount = amount;
    } else if (giftType === 'course') {
      if (!selectedCourseId) {
        setErrorMessage(t.userDetail.errPickCourse);
        return;
      }
      payload.course_id = selectedCourseId;
    } else if (giftType === 'avatar') {
      if (!selectedShopItemId) {
        setErrorMessage(t.userDetail.errPickAvatar);
        return;
      }
      payload.shop_item_id = selectedShopItemId;
    } else if (giftType === 'shop_item') {
      if (!selectedShopItemId) {
        setErrorMessage(t.userDetail.errPickItem);
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

  const switchTab = (tab: typeof activeTab) => {
    setActiveTab(tab);
    setSuccessMessage(null);
    setErrorMessage(null);
  };

  if (isLoading) {
    return (
      <Dialog onClose={onClose} maxWidth={400} style={{ textAlign: 'center' }}>
        <div className="spinner ud-spinner" />
        <p className="ud-note">{t.userDetail.loading}</p>
      </Dialog>
    );
  }

  if (error || !user) {
    return (
      <Dialog onClose={onClose} maxWidth={400} style={{ textAlign: 'center' }}>
        <p className="ud-error-text">
          {error instanceof Error ? error.message : t.userDetail.loadFailed}
        </p>
        <div className="ud-actions-center">
          <button className="ghost-button" onClick={() => refetch()}>{t.userDetail.retry}</button>
          <button className="ghost-button" onClick={onClose}>{t.common.close}</button>
        </div>
      </Dialog>
    );
  }

  const tabs = [
    { id: 'info', label: t.userDetail.tabInfo },
    { id: 'activity', label: t.userDetail.tabActivity },
    ...(can('gifts:grant') ? [{ id: 'gift' as const, label: t.userDetail.tabGift }] : []),
    { id: 'wallet', label: t.support.tabWallet },
    { id: 'premium', label: t.support.tabPremium },
  ] as const;

  const roleStatusTone = user.role_level === 2 ? 'danger' : user.role_level === 1 ? 'warning' : 'info';
  const notSet = t.userDetail.notSet;

  return (
    <Dialog onClose={onClose} maxWidth={720}>
      <div className="ud-header">
        <div className="ud-identity">
          <div className="ud-avatar" aria-hidden="true">
            {(user.display_name || user.email)[0].toUpperCase()}
          </div>
          <div>
            <h3 className="ud-name">{user.display_name || user.email.split('@')[0]}</h3>
            <span className="table-sub">{user.email}</span>
          </div>
        </div>
        <button onClick={onClose} className="icon-button ud-close" aria-label={t.common.close}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </div>

      <div className="tab-row ud-tabs" role="tablist">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            role="tab"
            aria-selected={activeTab === tab.id}
            onClick={() => switchTab(tab.id)}
            className={`tab ${activeTab === tab.id ? 'active' : ''}`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="ud-body">
        {activeTab === 'info' && (
          <div className="stack">
            <div className="card-grid ud-stats">
              <div className="panel-inner ud-stat">
                <div className="stat-label">Total XP</div>
                <div className="ud-stat-value ud-stat-value--xp">{user.total_xp.toLocaleString()}</div>
              </div>
              <div className="panel-inner ud-stat">
                <div className="stat-label">Streak</div>
                <div className="ud-stat-value ud-stat-value--streak">—</div>
              </div>
              <div className="panel-inner ud-stat">
                <div className="stat-label">{t.userDetail.statCourses}</div>
                <div className="ud-stat-value ud-stat-value--courses">
                  {user.courses_completed}/{user.courses_enrolled}
                </div>
              </div>
              <div className="panel-inner ud-stat">
                <div className="stat-label">{t.userDetail.statLessons}</div>
                <div className="ud-stat-value ud-stat-value--lessons">{user.lessons_completed}</div>
              </div>
            </div>

            <div className="panel-inner">
              <div className="ud-section-head">
                <h4 className="ud-section-title">{t.userDetail.personalInfo}</h4>
                {!isEditing && (
                  <button onClick={handleEdit} className="ghost-button small">{t.userDetail.edit}</button>
                )}
              </div>

              {isEditing ? (
                <div className="form">
                  <label>
                    {t.userDetail.displayName}
                    <input
                      type="text"
                      value={formData.display_name || ''}
                      onChange={(e) => setFormData({ ...formData, display_name: e.target.value })}
                    />
                  </label>
                  <label>
                    {t.userDetail.bio}
                    <textarea
                      value={formData.bio || ''}
                      onChange={(e) => setFormData({ ...formData, bio: e.target.value })}
                      rows={3}
                    />
                  </label>
                  <div className="inline-actions inline-actions--end">
                    <button onClick={() => setIsEditing(false)} className="ghost-button small">{t.common.cancel}</button>
                    <button onClick={handleSave} disabled={updateMutation.isPending} className="primary-button small">
                      {updateMutation.isPending ? t.userDetail.saving : t.userDetail.saveChanges}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="mini-list">
                  <div className="pill-item">
                    <span className="table-sub">{t.userDetail.displayName}</span>
                    <span className="pill-title ud-value">{user.display_name || notSet}</span>
                  </div>
                  <div className="pill-item">
                    <span className="table-sub">{t.userDetail.bio}</span>
                    <span className="pill-title ud-value">{user.bio || notSet}</span>
                  </div>
                  <div className="pill-item">
                    <span className="table-sub">{t.userDetail.language}</span>
                    <span className="pill-title ud-value">{user.language_preference || notSet}</span>
                  </div>
                  <div className="pill-item">
                    <span className="table-sub">{t.userDetail.notifications}</span>
                    <span className={`status-pill ${user.notification_enabled ? 'success' : 'neutral'}`}>
                      {user.notification_enabled ? t.userDetail.on : t.userDetail.off}
                    </span>
                  </div>
                </div>
              )}
            </div>

            <div className="panel-inner">
              <h4 className="ud-section-title">{t.userDetail.roleAndStatus}</h4>
              <div className="mini-list">
                <div className="pill-item">
                  <span className="table-sub">{t.userDetail.role}</span>
                  <span className={`status-pill ${roleStatusTone}`}>{getRoleLabel(user.role_level)}</span>
                </div>
                <div className="pill-item">
                  <span className="table-sub">{t.userDetail.status}</span>
                  <span className={`status-pill ${user.is_active ? 'success' : 'neutral'}`}>
                    {user.is_active ? t.userDetail.statusActive : t.userDetail.statusPaused}
                  </span>
                </div>
                <div className="pill-item">
                  <span className="table-sub">{t.userDetail.joined}</span>
                  <span className="pill-title ud-value">{new Date(user.created_at).toLocaleDateString('vi-VN')}</span>
                </div>
                <div className="pill-item">
                  <span className="table-sub">{t.userDetail.lastLogin}</span>
                  <span className="pill-title ud-value">
                    {user.last_login ? new Date(user.last_login).toLocaleDateString('vi-VN') : t.userDetail.neverLoggedIn}
                  </span>
                </div>
              </div>

              <div className="ud-role-change">
                <p className="ud-role-label">{t.userDetail.changeRole}</p>
                <div className="action-group">
                  {([[0, 'User'], [1, 'Admin'], [2, 'Super Admin']] as const).map(([level, label]) => (
                    <button
                      key={level}
                      onClick={() => handleRoleChange(level)}
                      disabled={user.role_level === level || roleChangeMutation.isPending}
                      className="mini-btn"
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'wallet' && <UserWalletPanel userId={userId} />}
        {activeTab === 'premium' && <UserPremiumPanel userId={userId} />}

        {activeTab === 'activity' && (
          <div className="stack stack--flush">
            {activities && activities.length > 0 ? (
              activities.map((activity, index) => (
                <div key={index} className="ud-activity">
                  <div className="ud-activity-icon" aria-hidden="true">
                    {activity.activity_type === 'lesson_completed' ? 'L' : 'A'}
                  </div>
                  <div className="ud-activity-main">
                    <div className="table-title ud-value">{activity.description}</div>
                    <div className="ud-activity-meta">
                      <span>{new Date(activity.activity_date).toLocaleDateString('vi-VN')}</span>
                      {activity.xp_earned > 0 && (
                        <span className="ud-activity-xp">+{activity.xp_earned} XP</span>
                      )}
                    </div>
                  </div>
                </div>
              ))
            ) : (
              <div className="empty-state">
                <div className="empty-title">{t.userDetail.noActivity}</div>
                <div className="empty-description">{t.userDetail.noActivityDesc}</div>
              </div>
            )}
          </div>
        )}

        {activeTab === 'gift' && (
          <div className="stack">
            <div className="panel-inner">
              <h4 className="ud-section-title ud-section-title--spaced">{t.userDetail.giftTitle}</h4>

              {successMessage && <div className="form-success" role="status">{successMessage}</div>}
              {errorMessage && <div className="form-error" role="alert">{errorMessage}</div>}

              <form onSubmit={handleSendGift} className="form ud-gift-form">
                <label className="ud-field">
                  {t.userDetail.giftType}
                  <div className="gift-type-select">
                    <GiftTypeIcon size={18} aria-hidden="true" />
                    <select
                      value={giftType}
                      onChange={(e) => {
                        const val = e.target.value as typeof giftType;
                        setGiftType(val);
                        setAmount(val === 'gems' ? 100 : 1);
                        setSuccessMessage(null);
                        setErrorMessage(null);
                      }}
                    >
                      <option value="gems">{t.userDetail.giftGems}</option>
                      <option value="course">{t.userDetail.giftCourse}</option>
                      <option value="avatar">{t.userDetail.giftAvatar}</option>
                      <option value="shop_item">{t.userDetail.giftItem}</option>
                    </select>
                  </div>
                </label>

                {giftType === 'course' && (
                  <label className="ud-field">
                    {t.userDetail.pickCourse}
                    {isLoadingCourses ? (
                      <span className="ud-hint">{t.userDetail.loadingCourses}</span>
                    ) : (
                      <select value={selectedCourseId} onChange={(e) => setSelectedCourseId(e.target.value)} required>
                        <option value="">{t.userDetail.pickCoursePlaceholder}</option>
                        {coursesList.map((course: any) => (
                          <option key={course.id} value={course.id}>
                            [{course.level}] {course.title}
                          </option>
                        ))}
                      </select>
                    )}
                  </label>
                )}

                {giftType === 'avatar' && (
                  <label className="ud-field">
                    {t.userDetail.pickAvatar}
                    {isLoadingShopItems ? (
                      <span className="ud-hint">{t.userDetail.loadingAvatars}</span>
                    ) : (
                      <select value={selectedShopItemId} onChange={(e) => setSelectedShopItemId(e.target.value)} required>
                        <option value="">{t.userDetail.pickAvatarPlaceholder}</option>
                        {avatarsList.map((item: any) => (
                          <option key={item.id} value={item.id}>
                            {item.name} ({item.price_gems} Gems)
                          </option>
                        ))}
                      </select>
                    )}
                  </label>
                )}

                {giftType === 'shop_item' && (
                  <label className="ud-field">
                    {t.userDetail.pickItem}
                    {isLoadingShopItems ? (
                      <span className="ud-hint">{t.userDetail.loadingItems}</span>
                    ) : (
                      <select value={selectedShopItemId} onChange={(e) => setSelectedShopItemId(e.target.value)} required>
                        <option value="">{t.userDetail.pickItemPlaceholder}</option>
                        {consumablesList.map((item: any) => (
                          <option key={item.id} value={item.id}>
                            {item.name} ({item.item_type})
                          </option>
                        ))}
                      </select>
                    )}
                  </label>
                )}

                {(giftType === 'gems' || giftType === 'shop_item') && (
                  <label className="ud-field">
                    {giftType === 'gems' ? t.userDetail.amountGems : t.userDetail.amountItems}
                    <input
                      type="number"
                      min={1}
                      value={amount}
                      onChange={(e) => setAmount(Math.max(1, parseInt(e.target.value) || 1))}
                      required
                    />
                  </label>
                )}

                <label className="ud-field">
                  {t.userDetail.giftReason}
                  <input
                    type="text"
                    value={reason}
                    maxLength={300}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder={t.userDetail.giftReasonHint}
                    required
                  />
                </label>

                {gemLimits?.usage && (
                  <p className="text-muted" role="note">
                    {t.userDetail.giftLimits
                      .replace('{max}', gemLimits.usage.max_per_action.toLocaleString())
                      .replace('{left}', gemLimits.usage.remaining_today.toLocaleString())
                      .replace('{budget}', gemLimits.usage.daily_budget.toLocaleString())}
                  </p>
                )}

                <div className="ud-submit-row">
                  <button type="submit" className="primary-button" disabled={giftMutation.isPending}>
                    {giftMutation.isPending ? t.userDetail.sending : t.userDetail.sendGift}
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}
      </div>

      <div className="ud-footer">
        <button onClick={onClose} className="ghost-button small">{t.common.close}</button>
      </div>
    </Dialog>
  );
}
