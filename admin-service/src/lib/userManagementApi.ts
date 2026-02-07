/**
 * User Management API Client
 * Phase 2 - Admin Panel User Management
 */
import { apiFetch } from './api';

// ============================================================================
// Types
// ============================================================================

export interface UserListItem {
  id: string;
  email: string;
  display_name: string | null;
  avatar_url: string | null;
  level: number;
  is_active: boolean;
  created_at: string;
  last_sign_in: string | null;
  total_xp: number;
  streak_days: number;
}

export interface UserDetail extends UserListItem {
  bio: string | null;
  language_preference: string | null;
  notification_enabled: boolean;
  courses_enrolled: number;
  courses_completed: number;
  lessons_completed: number;
  daily_activities: number;
}

export interface PaginatedUsers {
  users: UserListItem[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export interface UserActivity {
  activity_date: string;
  activity_type: string;
  description: string;
  xp_earned: number;
}

export interface UserFilters {
  page?: number;
  page_size?: number;
  search?: string;
  role?: number;
  is_active?: boolean;
  sort_by?: 'created_at' | 'last_sign_in' | 'email' | 'level' | 'total_xp';
  order?: 'asc' | 'desc';
}

export interface UserUpdateData {
  display_name?: string;
  bio?: string;
  level?: number;
  is_active?: boolean;
}

export interface RoleUpdateData {
  level: number;
}

export interface StatusUpdateData {
  is_active: boolean;
}

export interface BulkActionData {
  user_ids: string[];
  action: 'activate' | 'deactivate' | 'delete';
}

// ============================================================================
// API Functions
// ============================================================================

/**
 * Get paginated list of users with filters
 */
export async function getUsers(filters: UserFilters = {}): Promise<PaginatedUsers> {
  const params = new URLSearchParams();
  
  if (filters.page) params.append('page', filters.page.toString());
  if (filters.page_size) params.append('page_size', filters.page_size.toString());
  if (filters.search) params.append('search', filters.search);
  if (filters.role !== undefined) params.append('role', filters.role.toString());
  if (filters.is_active !== undefined) params.append('is_active', filters.is_active.toString());
  if (filters.sort_by) params.append('sort_by', filters.sort_by);
  if (filters.order) params.append('order', filters.order);
  
  const queryString = params.toString();
  const url = queryString ? `/admin/users?${queryString}` : '/admin/users';
  
  return apiFetch<PaginatedUsers>(url);
}

/**
 * Get detailed information about a specific user
 */
export async function getUserDetail(userId: string): Promise<UserDetail> {
  return apiFetch<UserDetail>(`/admin/users/${userId}`);
}

/**
 * Update user information
 */
export async function updateUser(userId: string, data: UserUpdateData): Promise<UserDetail> {
  return apiFetch<UserDetail>(`/admin/users/${userId}`, {
    method: 'PUT',
    body: JSON.stringify(data),
  });
}

/**
 * Update user role (super admin only)
 */
export async function updateUserRole(userId: string, data: RoleUpdateData): Promise<{ message: string; user_id: string; new_level: number }> {
  return apiFetch(`/admin/users/${userId}/role`, {
    method: 'PUT',
    body: JSON.stringify(data),
  });
}

/**
 * Update user status (activate/deactivate)
 */
export async function updateUserStatus(userId: string, data: StatusUpdateData): Promise<{ message: string; user_id: string; is_active: boolean }> {
  return apiFetch(`/admin/users/${userId}/status`, {
    method: 'PUT',
    body: JSON.stringify(data),
  });
}

/**
 * Get user activity timeline
 */
export async function getUserActivity(userId: string, days: number = 30): Promise<UserActivity[]> {
  return apiFetch<UserActivity[]>(`/admin/users/${userId}/activity?days=${days}`);
}

/**
 * Perform bulk action on multiple users
 */
export async function bulkUserAction(data: BulkActionData): Promise<{ message: string; updated_count: number; requested_count: number }> {
  return apiFetch('/admin/users/bulk-action', {
    method: 'POST',
    body: JSON.stringify(data),
  });
}

/**
 * Get role label from level number
 */
export function getRoleLabel(level: number): string {
  switch (level) {
    case 0:
      return 'User';
    case 1:
      return 'Admin';
    case 2:
      return 'Super Admin';
    default:
      return 'Unknown';
  }
}

/**
 * Get role color for badges
 */
export function getRoleColor(level: number): string {
  switch (level) {
    case 0:
      return 'default';
    case 1:
      return 'blue';
    case 2:
      return 'red';
    default:
      return 'default';
  }
}
