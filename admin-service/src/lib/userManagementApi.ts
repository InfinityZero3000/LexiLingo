/**
 * User Management API Client
 * Phase 2 - Admin Panel User Management
 */
import { apiFetch } from './api';
import { ENV } from './env';

// ============================================================================
// Types
// ============================================================================

export interface UserListItem {
  id: string;
  email: string;
  username: string;
  display_name: string | null;
  is_active: boolean;
  is_verified: boolean;
  role_slug: string; // "user", "admin", "super_admin"
  role_level: number; // 0, 1, 2
  created_at: string;
  last_login: string | null;
  avatar_url?: string | null;
  total_xp?: number;
  streak_days?: number;
}

export interface UserDetail extends UserListItem {
  avatar_url: string | null;
  provider: string[]; // ["local"], ["google"]
  total_xp: number;
  courses_enrolled: number;
  courses_completed: number;
  lessons_completed: number;
  daily_activities: number;
  bio?: string | null;
  language_preference?: string | null;
  notification_enabled?: boolean;
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
  role?: number; // Filter by role level: 0=user, 1=admin, 2=super_admin
  is_active?: boolean;
  sort_by?: 'created_at' | 'last_login' | 'email' | 'role' | 'total_xp';
  order?: 'asc' | 'desc';
}

export interface UserUpdateData {
  display_name?: string;
  is_active?: boolean;
  bio?: string;
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
  const url = queryString 
    ? `${ENV.backendUrl}/admin/users?${queryString}` 
    : `${ENV.backendUrl}/admin/users`;
  
  const response = await apiFetch<{ success: boolean; data: PaginatedUsers }>(url);
  if (!response.data) {
    throw new Error('Invalid response format from server');
  }
  return response.data;
}

/**
 * Get detailed information about a specific user
 */
export async function getUserDetail(userId: string): Promise<UserDetail> {
  const response = await apiFetch<{ success: boolean; data: UserDetail }>(
    `${ENV.backendUrl}/admin/users/${userId}`
  );
  return response.data;
}

/**
 * Update user information
 */
export async function updateUser(userId: string, data: UserUpdateData): Promise<UserDetail> {
  const response = await apiFetch<{ success: boolean; data: UserDetail }>(
    `${ENV.backendUrl}/admin/users/${userId}`,
    {
      method: 'PUT',
      body: JSON.stringify(data),
    }
  );
  return response.data;
}

/**
 * Update user role (super admin only)
 */
export async function updateUserRole(userId: string, data: RoleUpdateData): Promise<{ message: string; user_id: string; new_level: number }> {
  const response = await apiFetch<{ success: boolean; data: { message: string; user_id: string; new_level: number } }>(
    `${ENV.backendUrl}/admin/users/${userId}/role`,
    {
      method: 'PUT',
      body: JSON.stringify(data),
    }
  );
  return response.data;
}

/**
 * Update user status (activate/deactivate)
 */
export async function updateUserStatus(userId: string, data: StatusUpdateData): Promise<{ message: string; user_id: string; is_active: boolean }> {
  const response = await apiFetch<{ success: boolean; data: { message: string; user_id: string; is_active: boolean } }>(
    `${ENV.backendUrl}/admin/users/${userId}/status`,
    {
      method: 'PUT',
      body: JSON.stringify(data),
    }
  );
  return response.data;
}

/**
 * Get user activity timeline
 */
export async function getUserActivity(userId: string, days: number = 30): Promise<UserActivity[]> {
  const response = await apiFetch<{ success: boolean; data: UserActivity[] }>(
    `${ENV.backendUrl}/admin/users/${userId}/activity?days=${days}`
  );
  return response.data;
}

/**
 * Perform bulk action on multiple users
 */
export async function bulkUserAction(data: BulkActionData): Promise<{ message: string; updated_count: number; requested_count: number }> {
  const response = await apiFetch<{ success: boolean; data: { message: string; updated_count: number; requested_count: number } }>(
    `${ENV.backendUrl}/admin/users/bulk-action`,
    {
      method: 'POST',
      body: JSON.stringify(data),
    }
  );
  return response.data;
}

/**
 * Permanently delete a user account and all of their data (super admin only)
 */
export async function permanentlyDeleteUser(userId: string): Promise<{ message: string; user_id: string }> {
  const response = await apiFetch<{ success: boolean; data: { message: string; user_id: string } }>(
    `${ENV.backendUrl}/admin/users/${userId}/permanent`,
    {
      method: 'DELETE',
    }
  );
  return response.data;
}

/**
 * Get role label from level number
 */
export function getRoleLabel(role_level: number): string {
  switch (role_level) {
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
export function getRoleColor(role_level: number): string {
  switch (role_level) {
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

// ============================================================================
// Admin Gifting API
// ============================================================================

export interface GiftRequest {
  gift_type: 'course' | 'avatar' | 'shop_item' | 'gems';
  course_id?: string;
  shop_item_id?: string;
  amount?: number;
}

export async function giftToUser(
  userId: string,
  data: GiftRequest
): Promise<{ success: boolean; message: string; data: { gift_description: string } }> {
  return apiFetch<{ success: boolean; message: string; data: { gift_description: string } }>(
    `${ENV.backendUrl}/admin/users/${userId}/gift`,
    {
      method: 'POST',
      body: JSON.stringify(data),
    }
  );
}

