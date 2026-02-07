import React, { useEffect, useState } from "react";
import { DataTable } from "../components/DataTable";
import { SectionHeader } from "../components/SectionHeader";
import { EmptyState } from "../components/EmptyState";
import { apiFetch } from "../lib/api";
import { ENV } from "../lib/env";

type VocabItem = {
  id: string;
  word: string;
  translation?: string | { vi?: string };
  part_of_speech?: string;
  difficulty_level?: string;
  status?: string;
};

type AdminResponse<T> = {
  success: boolean;
  message?: string;
  data?: T;
};

export const VocabularyPage = () => {
  const [items, setItems] = useState<VocabItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    apiFetch<AdminResponse<VocabItem[]>>(`${ENV.backendUrl}/admin/vocabulary?limit=50&offset=0`)
      .then((response) => setItems(response.data || []))
      .catch((err) => setError(err?.message || "Không lấy được dữ liệu"))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="panel">
      <SectionHeader title="Từ vựng" description="GET /api/v1/admin/vocabulary" />
      {error && <div className="form-error">{error}</div>}
      {loading ? (
        <div className="loading">Đang tải dữ liệu...</div>
      ) : items.length === 0 ? (
        <EmptyState title="Chưa có từ vựng" description="Thêm dữ liệu bằng API admin." />
      ) : (
        <DataTable
          columns={[
            {
              header: "Từ",
              render: (row) => (
                <div>
                  <div className="table-title">{row.word}</div>
                  <div className="table-sub">{row.part_of_speech || "--"}</div>
                </div>
              )
            },
            {
              header: "Dịch nghĩa",
              render: (row) => {
                if (!row.translation) return "--";
                if (typeof row.translation === "string") return row.translation;
                return row.translation.vi || "--";
              }
            },
            {
              header: "Level",
              render: (row) => <span className="table-meta">{row.difficulty_level || "A1"}</span>,
              align: "center"
            }
          ]}
          rows={items}
        />
      )}
    </div>
  );
};
