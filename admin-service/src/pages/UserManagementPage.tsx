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
import UserDetailModal from '../components/user-management/UserDetailModal';
import UserFiltersPanel from '../components/user-management/UserFiltersPanel';

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
      <div className="p-8">
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <h3 className="text-red-800 font-semibold">Error Loading Users</h3>
          <p className="text-red-600">{error instanceof Error ? error.message : 'Unknown error'}</p>
        </div>
      </div>
    );
  }
  
  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">User Management</h1>
          <p className="text-gray-600 mt-1">Manage users, roles, and permissions</p>
        </div>
        
        {selectedUsers.size > 0 && (
          <div className="flex items-center gap-3">
            <span className="text-sm text-gray-600">{selectedUsers.size} selected</span>
            <button
              onClick={() => handleBulkAction('activate')}
              disabled={bulkActionMutation.isPending}
              className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50"
            >
              Activate
            </button>
            <button
              onClick={() => handleBulkAction('deactivate')}
              disabled={bulkActionMutation.isPending}
              className="px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-700 disabled:opacity-50"
            >
              Deactivate
            </button>
          </div>
        )}
      </div>
      
      {/* Filters */}
      <UserFiltersPanel filters={filters} onFilterChange={handleFilterChange} />
      
      {/* Stats */}
      {data && (
        <div className="bg-white rounded-lg shadow p-4 flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-600">Total Users</p>
            <p className="text-2xl font-bold text-gray-900">{data.total}</p>
          </div>
          <div>
            <p className="text-sm text-gray-600">Current Page</p>
            <p className="text-2xl font-bold text-gray-900">
              {data.page} / {data.total_pages}
            </p>
          </div>
        </div>
      )}
      
      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        {isLoading ? (
          <div className="p-12 text-center">
            <div className="inline-block animate-spin rounded-full h-12 w-12 border-4 border-blue-500 border-t-transparent"></div>
            <p className="mt-4 text-gray-600">Loading users...</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-4 py-3 text-left">
                    <input
                      type="checkbox"
                      checked={data?.users && selectedUsers.size === data.users.length}
                      onChange={handleSelectAll}
                      className="rounded"
                    />
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Role</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">XP</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Streak</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Joined</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {data?.users.map((user) => (
                  <tr key={user.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <input
                        type="checkbox"
                        checked={selectedUsers.has(user.id)}
                        onChange={() => handleToggleSelect(user.id)}
                        className="rounded"
                      />
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        {user.avatar_url ? (
                          <img src={user.avatar_url} alt="" className="w-8 h-8 rounded-full" />
                        ) : (
                          <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center">
                            <span className="text-gray-600 text-sm">{user.email[0].toUpperCase()}</span>
                          </div>
                        )}
                        <span className="text-sm text-gray-900">{user.email}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-900">
                      {user.display_name || <span className="text-gray-400">No name</span>}
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                          user.level === 2
                            ? 'bg-red-100 text-red-800'
                            : user.level === 1
                            ? 'bg-blue-100 text-blue-800'
                            : 'bg-gray-100 text-gray-800'
                        }`}
                      >
                        {getRoleLabel(user.level)}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                          user.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'
                        }`}
                      >
                        {user.is_active ? 'Active' : 'Inactive'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-900">{user.total_xp.toLocaleString()}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">
                      <span className="inline-flex items-center gap-1">
                        🔥 {user.streak_days}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {new Date(user.created_at).toLocaleDateString()}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => handleViewDetail(user.id)}
                          className="text-blue-600 hover:text-blue-800 text-sm font-medium"
                        >
                          View
                        </button>
                        <button
                          onClick={() => handleToggleStatus(user.id, user.is_active)}
                          disabled={statusMutation.isPending}
                          className="text-orange-600 hover:text-orange-800 text-sm font-medium disabled:opacity-50"
                        >
                          {user.is_active ? 'Deactivate' : 'Activate'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            
            {data?.users.length === 0 && (
              <div className="p-12 text-center">
                <p className="text-gray-500">No users found</p>
              </div>
            )}
          </div>
        )}
      </div>
      
      {/* Pagination */}
      {data && data.total_pages > 1 && (
        <div className="flex items-center justify-between bg-white rounded-lg shadow p-4">
          <button
            onClick={() => handlePageChange(filters.page! - 1)}
            disabled={filters.page === 1}
            className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Previous
          </button>
          
          <div className="flex items-center gap-2">
            {Array.from({ length: Math.min(5, data.total_pages) }, (_, i) => {
              const page = i + 1;
              return (
                <button
                  key={page}
                  onClick={() => handlePageChange(page)}
                  className={`px-3 py-1 rounded ${
                    filters.page === page
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                  }`}
                >
                  {page}
                </button>
              );
            })}
          </div>
          
          <button
            onClick={() => handlePageChange(filters.page! + 1)}
            disabled={filters.page === data.total_pages}
            className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Next
          </button>
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
