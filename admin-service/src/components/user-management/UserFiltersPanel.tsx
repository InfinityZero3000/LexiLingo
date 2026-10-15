/**
 * User Filters Panel
 * Filter and search controls for user list
 */
import React, { useState } from 'react';
import { Search } from 'lucide-react';
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
    <div className="panel user-filter-panel">
      <div className="filter-panel-header">
        <h3>Bộ lọc</h3>
        {hasActiveFilters && (
          <button onClick={handleClearFilters} className="ghost-button small">Xóa bộ lọc</button>
        )}
      </div>
      
      <div className="filter-bar">
        {/* Search */}
        <form onSubmit={handleSearchSubmit} className="filter-search-form">
          <input
            className="search-input"
            type="search"
            aria-label="Tìm kiếm người dùng"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Tìm theo tên hoặc email..."
          />
          <button type="submit" className="icon-button filter-search-button" aria-label="Tìm kiếm" title="Tìm kiếm">
            <Search size={18} aria-hidden="true" />
          </button>
        </form>
        
          <label className="filter-field">
            Vai trò
            <select
              className="filter-select"
              value={filters.role !== undefined ? filters.role : ''}
              onChange={(e) => onFilterChange({ role: e.target.value ? Number(e.target.value) : undefined })}
            >
              <option value="">Tất cả vai trò</option>
              <option value="0">User</option>
              <option value="1">Admin</option>
              <option value="2">Super Admin</option>
            </select>
          </label>
          
          {/* Status Filter */}
          <label className="filter-field">
            Trạng thái
            <select
              className="filter-select"
              value={filters.is_active !== undefined ? (filters.is_active ? 'true' : 'false') : ''}
              onChange={(e) => onFilterChange({ is_active: e.target.value ? e.target.value === 'true' : undefined })}
            >
              <option value="">Tất cả</option>
              <option value="true">Hoạt động</option>
              <option value="false">Tạm dừng</option>
            </select>
          </label>
          
          {/* Sort By */}
          <label className="filter-field">
            Sắp xếp theo
            <select
              className="filter-select"
              value={filters.sort_by || 'created_at'}
              onChange={(e) => onFilterChange({ sort_by: e.target.value as any })}
            >
              <option value="created_at">Ngày tham gia</option>
              <option value="last_sign_in">Đăng nhập cuối</option>
              <option value="email">Email</option>
              <option value="level">Vai trò</option>
              <option value="total_xp">Tổng XP</option>
            </select>
          </label>
          
          {/* Order */}
          <label className="filter-field">
            Thứ tự
            <select
              className="filter-select"
              value={filters.order || 'desc'}
              onChange={(e) => onFilterChange({ order: e.target.value as 'asc' | 'desc' })}
            >
              <option value="asc">Tăng dần</option>
              <option value="desc">Giảm dần</option>
            </select>
          </label>
      </div>
    </div>
  );
}
