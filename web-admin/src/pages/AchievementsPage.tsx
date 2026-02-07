import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { apiFetch } from "../lib/api";
import { ENV } from "../lib/env";

type Achievement = {
  id: string;
  name: string;
  description?: string;
  category?: string;
  rarity?: string;
  xp_reward?: number;
  gems_reward?: number;
  is_hidden?: boolean;
};

type AdminResponse<T> = {
  success: boolean;
  message?: string;
  data?: T;
};

export const AchievementsPage = () => {
  const [items, setItems] = useState<Achievement[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setLoading(true);
    apiFetch<AdminResponse<Achievement[]>>(`${ENV.backendUrl}/admin/achievements`)
      .then((response) => setItems(response.data || []))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="panel">
      <SectionHeader title="Achievements" description="GET /api/v1/admin/achievements" />
      {loading ? (
        <div className="loading">Đang tải dữ liệu...</div>
      ) : items.length === 0 ? (
        <EmptyState title="Chưa có achievement" />
      ) : (
        <DataTable
          columns={[
            {
              header: "Achievement",
              render: (row) => (
                <div>
                  <div className="table-title">{row.name}</div>
                  <div className="table-sub">{row.description}</div>
                </div>
              )
            },
            {
              header: "Category",
              render: (row) => <span className="table-meta">{row.category}</span>
            },
            {
              header: "Rarity",
              render: (row) => <span className="table-meta">{row.rarity}</span>
            },
            {
              header: "Rewards",
              render: (row) => `${row.xp_reward || 0} XP • ${row.gems_reward || 0} gems`,
              align: "right"
            }
          ]}
          rows={items}
        />
      )}
    </div>
  );
};
