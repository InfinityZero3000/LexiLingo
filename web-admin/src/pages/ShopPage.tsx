import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { apiFetch } from "../lib/api";
import { ENV } from "../lib/env";

type ShopItem = {
  id: string;
  name: string;
  description?: string;
  item_type?: string;
  price_gems?: number;
  is_available?: boolean;
  stock_quantity?: number | null;
};

type AdminResponse<T> = {
  success: boolean;
  message?: string;
  data?: T;
};

export const ShopPage = () => {
  const [items, setItems] = useState<ShopItem[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setLoading(true);
    apiFetch<AdminResponse<ShopItem[]>>(`${ENV.backendUrl}/admin/shop?include_unavailable=true`)
      .then((response) => setItems(response.data || []))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="panel">
      <SectionHeader title="Shop Items" description="GET /api/v1/admin/shop" />
      {loading ? (
        <div className="loading">Đang tải dữ liệu...</div>
      ) : items.length === 0 ? (
        <EmptyState title="Chưa có item" />
      ) : (
        <DataTable
          columns={[
            {
              header: "Item",
              render: (row) => (
                <div>
                  <div className="table-title">{row.name}</div>
                  <div className="table-sub">{row.description}</div>
                </div>
              )
            },
            {
              header: "Loại",
              render: (row) => <span className="table-meta">{row.item_type}</span>
            },
            {
              header: "Giá",
              render: (row) => `${row.price_gems || 0} gems`,
              align: "right"
            }
          ]}
          rows={items}
        />
      )}
    </div>
  );
};
