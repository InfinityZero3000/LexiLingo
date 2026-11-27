/**
 * User Filters Panel
 * Filter and search controls for user list
 */
import React, { useState } from 'react';
import { Search } from 'lucide-react';
import type { UserFilters } from '../../lib/userManagementApi';
import { useI18n } from '../../lib/i18n';

interface UserFiltersPanelProps {
  filters: UserFilters;
  onFilterChange: (filters: Partial<UserFilters>) => void;
}

export default function UserFiltersPanel({ filters, onFilterChange }: UserFiltersPanelProps) {
  const { t } = useI18n();
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
    <div className="panel filter-panel user-filter-panel">
      <div className="filter-bar">
        {/* Search */}
        <form onSubmit={handleSearchSubmit} className="filter-search-form">
          <input
            className="search-input"
            type="search"
            aria-label={t.users.searchAria}
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder={t.users.searchByNameEmail}
          />
          <button
            type="submit"
            className="icon-button filter-search-button"
            aria-label={t.common.search}
            title={t.common.search}
          >
            <Search size={16} aria-hidden="true" />
          </button>
        </form>
        
        <label className="filter-field">
          <span>{t.users.role}</span>
          <select
            className="filter-select"
            value={filters.role !== undefined ? filters.role : ''}
            onChange={(e) => onFilterChange({ role: e.target.value ? Number(e.target.value) : undefined })}
          >
            <option value="">{t.users.allRoles}</option>
            <option value="0">{t.users.roleUser}</option>
            <option value="1">{t.users.roleAdmin}</option>
            <option value="2">{t.users.roleSuperAdmin}</option>
          </select>
        </label>
        
        {/* Status Filter */}
        <label className="filter-field">
          <span>{t.users.statusLabel}</span>
          <select
            className="filter-select"
            value={filters.is_active !== undefined ? (filters.is_active ? 'true' : 'false') : ''}
            onChange={(e) => onFilterChange({ is_active: e.target.value ? e.target.value === 'true' : undefined })}
          >
            <option value="">{t.common.all}</option>
            <option value="true">{t.users.statusActive}</option>
            <option value="false">{t.users.statusPaused}</option>
          </select>
        </label>

        {hasActiveFilters && (
          <button
            type="button"
            onClick={handleClearFilters}
            className="ghost-button small"
            style={{ borderRadius: '9999px', marginLeft: 'auto' }}
          >
            {t.users.resetFilters}
          </button>
        )}
      </div>
    </div>
  );
}
