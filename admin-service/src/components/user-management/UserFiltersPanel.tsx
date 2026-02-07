/**
 * User Filters Panel
 * Filter and search controls for user list
 */
import React, { useState } from 'react';
import type { UserFilters } from '../../lib/userManagementApi';

interface UserFiltersPanelProps {
  filters: UserFilters;
  onFilterChange: (filters: Partial<UserFilters>) => void;
}

export default function UserFiltersPanel({ filters, onFilterChange }: UserFiltersPanelProps) {
  const [searchInput, setSearchInput] = useState(filters.search || '');
  
  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onFilterChange({ search: searchInput || undefined });
  };
  
  const handleClearFilters = () => {
    setSearchInput('');
    onFilterChange({
      search: undefined,
      role: undefined,
      is_active: undefined,
      sort_by: 'created_at',
      order: 'desc',
    });
  };
  
  const hasActiveFilters = filters.search || filters.role !== undefined || filters.is_active !== undefined;
  
  return (
    <div className="bg-white rounded-lg shadow p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">Filters</h2>
        {hasActiveFilters && (
          <button
            onClick={handleClearFilters}
            className="text-sm text-blue-600 hover:text-blue-800"
          >
            Clear all
          </button>
        )}
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {/* Search */}
        <form onSubmit={handleSearchSubmit} className="md:col-span-2">
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Search
          </label>
          <div className="flex gap-2">
            <input
              type="text"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Search by name or email..."
              className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <button
              type="submit"
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
            >
              Search
            </button>
          </div>
        </form>
        
        {/* Role Filter */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Role
          </label>
          <select
            value={filters.role !== undefined ? filters.role : ''}
            onChange={(e) => onFilterChange({ role: e.target.value ? Number(e.target.value) : undefined })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="">All Roles</option>
            <option value="0">User</option>
            <option value="1">Admin</option>
            <option value="2">Super Admin</option>
          </select>
        </div>
        
        {/* Status Filter */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Status
          </label>
          <select
            value={filters.is_active !== undefined ? (filters.is_active ? 'true' : 'false') : ''}
            onChange={(e) => onFilterChange({ is_active: e.target.value ? e.target.value === 'true' : undefined })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="">All Status</option>
            <option value="true">Active</option>
            <option value="false">Inactive</option>
          </select>
        </div>
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2 border-t">
        {/* Sort By */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Sort By
          </label>
          <select
            value={filters.sort_by || 'created_at'}
            onChange={(e) => onFilterChange({ sort_by: e.target.value as any })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="created_at">Join Date</option>
            <option value="last_sign_in">Last Sign In</option>
            <option value="email">Email</option>
            <option value="level">Role</option>
            <option value="total_xp">Total XP</option>
          </select>
        </div>
        
        {/* Order */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Order
          </label>
          <select
            value={filters.order || 'desc'}
            onChange={(e) => onFilterChange({ order: e.target.value as 'asc' | 'desc' })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="asc">Ascending</option>
            <option value="desc">Descending</option>
          </select>
        </div>
      </div>
    </div>
  );
}
