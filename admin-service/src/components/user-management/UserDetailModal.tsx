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
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <div className="bg-white rounded-lg p-8">
          <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-500 border-t-transparent mx-auto"></div>
          <p className="mt-4 text-gray-600">Loading user details...</p>
        </div>
      </div>
    );
  }
  
  if (!user) {
    return null;
  }
  
  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b flex items-center justify-between">
          <div className="flex items-center gap-4">
            {user.avatar_url ? (
              <img src={user.avatar_url} alt="" className="w-16 h-16 rounded-full" />
            ) : (
              <div className="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center">
                <span className="text-gray-600 text-2xl">{user.email[0].toUpperCase()}</span>
              </div>
            )}
            <div>
              <h2 className="text-2xl font-bold text-gray-900">
                {user.display_name || 'No Name'}
              </h2>
              <p className="text-gray-600">{user.email}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 text-2xl"
          >
            ×
          </button>
        </div>
        
        {/* Tabs */}
        <div className="flex border-b px-6">
          <button
            onClick={() => setActiveTab('info')}
            className={`px-4 py-2 font-medium ${
              activeTab === 'info'
                ? 'text-blue-600 border-b-2 border-blue-600'
                : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            Information
          </button>
          <button
            onClick={() => setActiveTab('activity')}
            className={`px-4 py-2 font-medium ${
              activeTab === 'activity'
                ? 'text-blue-600 border-b-2 border-blue-600'
                : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            Activity
          </button>
        </div>
        
        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {activeTab === 'info' ? (
            <div className="space-y-6">
              {/* Stats Grid */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="bg-blue-50 rounded-lg p-4">
                  <p className="text-sm text-blue-600 font-medium">Total XP</p>
                  <p className="text-2xl font-bold text-blue-900">{user.total_xp.toLocaleString()}</p>
                </div>
                <div className="bg-green-50 rounded-lg p-4">
                  <p className="text-sm text-green-600 font-medium">Streak</p>
                  <p className="text-2xl font-bold text-green-900">🔥 {user.streak_days}</p>
                </div>
                <div className="bg-purple-50 rounded-lg p-4">
                  <p className="text-sm text-purple-600 font-medium">Courses</p>
                  <p className="text-2xl font-bold text-purple-900">
                    {user.courses_completed}/{user.courses_enrolled}
                  </p>
                </div>
                <div className="bg-orange-50 rounded-lg p-4">
                  <p className="text-sm text-orange-600 font-medium">Lessons</p>
                  <p className="text-2xl font-bold text-orange-900">{user.lessons_completed}</p>
                </div>
              </div>
              
              {/* User Info */}
              <div className="bg-gray-50 rounded-lg p-4 space-y-3">
                <h3 className="font-semibold text-gray-900">User Information</h3>
                
                {isEditing ? (
                  <div className="space-y-3">
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Display Name
                      </label>
                      <input
                        type="text"
                        value={formData.display_name || ''}
                        onChange={(e) => setFormData({ ...formData, display_name: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Bio
                      </label>
                      <textarea
                        value={formData.bio || ''}
                        onChange={(e) => setFormData({ ...formData, bio: e.target.value })}
                        rows={3}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                      />
                    </div>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Display Name:</span>
                      <span className="font-medium">{user.display_name || 'Not set'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Bio:</span>
                      <span className="font-medium">{user.bio || 'Not set'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Language:</span>
                      <span className="font-medium">{user.language_preference || 'Not set'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Notifications:</span>
                      <span className="font-medium">{user.notification_enabled ? 'Enabled' : 'Disabled'}</span>
                    </div>
                  </div>
                )}
              </div>
              
              {/* Role Management */}
              <div className="bg-gray-50 rounded-lg p-4 space-y-3">
                <h3 className="font-semibold text-gray-900">Role & Status</h3>
                <div className="space-y-2">
                  <div className="flex justify-between items-center">
                    <span className="text-gray-600">Current Role:</span>
                    <span
                      className={`inline-flex px-3 py-1 text-sm font-semibold rounded-full ${
                        user.level === 2
                          ? 'bg-red-100 text-red-800'
                          : user.level === 1
                          ? 'bg-blue-100 text-blue-800'
                          : 'bg-gray-100 text-gray-800'
                      }`}
                    >
                      {getRoleLabel(user.level)}
                    </span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-gray-600">Status:</span>
                    <span
                      className={`inline-flex px-3 py-1 text-sm font-semibold rounded-full ${
                        user.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'
                      }`}
                    >
                      {user.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-gray-600">Joined:</span>
                    <span className="font-medium">{new Date(user.created_at).toLocaleDateString()}</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-gray-600">Last Sign In:</span>
                    <span className="font-medium">
                      {user.last_sign_in ? new Date(user.last_sign_in).toLocaleDateString() : 'Never'}
                    </span>
                  </div>
                </div>
                
                {/* Role Change Buttons (Super Admin only) */}
                <div className="pt-3 border-t">
                  <p className="text-sm text-gray-600 mb-2">Change Role (Super Admin only):</p>
                  <div className="flex gap-2">
                    <button
                      onClick={() => handleRoleChange(0)}
                      disabled={user.level === 0 || roleChangeMutation.isPending}
                      className="px-3 py-1 bg-gray-100 text-gray-800 rounded hover:bg-gray-200 disabled:opacity-50 text-sm"
                    >
                      User
                    </button>
                    <button
                      onClick={() => handleRoleChange(1)}
                      disabled={user.level === 1 || roleChangeMutation.isPending}
                      className="px-3 py-1 bg-blue-100 text-blue-800 rounded hover:bg-blue-200 disabled:opacity-50 text-sm"
                    >
                      Admin
                    </button>
                    <button
                      onClick={() => handleRoleChange(2)}
                      disabled={user.level === 2 || roleChangeMutation.isPending}
                      className="px-3 py-1 bg-red-100 text-red-800 rounded hover:bg-red-200 disabled:opacity-50 text-sm"
                    >
                      Super Admin
                    </button>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            // Activity Timeline
            <div className="space-y-4">
              {activities && activities.length > 0 ? (
                activities.map((activity, index) => (
                  <div key={index} className="flex gap-4 pb-4 border-b last:border-0">
                    <div className="flex-shrink-0">
                      <div className="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center">
                        <span className="text-blue-600 text-sm">
                          {activity.activity_type === 'lesson_completed' ? '📚' : '✨'}
                        </span>
                      </div>
                    </div>
                    <div className="flex-1">
                      <p className="font-medium text-gray-900">{activity.description}</p>
                      <div className="flex items-center gap-4 mt-1 text-sm text-gray-600">
                        <span>{new Date(activity.activity_date).toLocaleDateString()}</span>
                        {activity.xp_earned > 0 && (
                          <span className="text-blue-600 font-medium">+{activity.xp_earned} XP</span>
                        )}
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-12 text-gray-500">
                  No activity recorded
                </div>
              )}
            </div>
          )}
        </div>
        
        {/* Footer */}
        {activeTab === 'info' && (
          <div className="px-6 py-4 border-t flex justify-end gap-3">
            <button
              onClick={onClose}
              className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200"
            >
              Close
            </button>
            {isEditing ? (
              <>
                <button
                  onClick={() => setIsEditing(false)}
                  className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200"
                >
                  Cancel
                </button>
                <button
                  onClick={handleSave}
                  disabled={updateMutation.isPending}
                  className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                  {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
                </button>
              </>
            ) : (
              <button
                onClick={handleEdit}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
              >
                Edit User
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
