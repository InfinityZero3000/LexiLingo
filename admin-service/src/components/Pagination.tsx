import { useI18n } from "../lib/i18n";

type PaginationProps = {
  page: number;
  pages: number;
  total?: number;
  onChange: (page: number) => void;
};

/** Windowed page buttons with first/last pinned and gaps marked. */
export const Pagination = ({ page, pages, total, onChange }: PaginationProps) => {
  const { t } = useI18n();
  if (pages <= 1) return null;

  return (
    <nav className="panel pagination" aria-label={t.common.page}>
      <div className="cluster cluster--between">
        <button onClick={() => onChange(page - 1)} disabled={page === 1} className="ghost-button">
          {t.common.prev}
        </button>

        <div className="cluster">
          {Array.from({ length: pages }, (_, i) => {
            const n = i + 1;
            const showPage = n === 1 || n === pages || Math.abs(n - page) <= 2;
            const showGap = (n === 2 && page > 4) || (n === pages - 1 && page < pages - 3);

            if (showGap) return <span key={n} className="pagination__gap">…</span>;
            if (!showPage) return null;

            return (
              <button
                key={n}
                onClick={() => onChange(n)}
                className={n === page ? "page-button active" : "page-button"}
                aria-current={n === page ? "page" : undefined}
              >
                {n}
              </button>
            );
          })}
        </div>

        <button onClick={() => onChange(page + 1)} disabled={page === pages} className="ghost-button">
          {t.common.next}
        </button>
      </div>
      <div className="pagination__info table-meta">
        {t.common.page} {page} / {pages}
        {total !== undefined ? ` · ${total}` : ""}
      </div>
    </nav>
  );
};
