import { useEffect, useRef, useState } from "react";
import { useI18n } from "../lib/i18n";
import { listQuestions, type QuestionItem } from "../lib/adminApi";
import { pickRandom } from "../lib/questionForm";

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];
const DEBOUNCE_MS = 300;

type Props = {
  examLevel: string;
  selected: string[];
  onChange: (ids: string[]) => void;
  known?: QuestionItem[];
  random?: () => number;
};

export const QuestionPicker = ({ examLevel, selected, onChange, known = [], random }: Props) => {
  const { t } = useI18n();
  const c = t.contentLab;
  const [level, setLevel] = useState(examLevel);
  const [keyword, setKeyword] = useState("");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<QuestionItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [count, setCount] = useState(5);
  const [notice, setNotice] = useState<string | null>(null);
  const seen = useRef(new Map<string, QuestionItem>());

  useEffect(() => setLevel(examLevel), [examLevel]);

  useEffect(() => {
    const timer = setTimeout(() => setQuery(keyword.trim()), DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [keyword]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    listQuestions({ level: level || undefined, q: query || undefined, limit: 200 })
      .then((res) => {
        if (cancelled) return;
        const rows = res.data || [];
        rows.forEach((r) => seen.current.set(r.id, r));
        setResults(rows);
      })
      .catch((err: any) => !cancelled && setError(err?.message || c.pickerError))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [level, query]);

  const lookup = (id: string) => seen.current.get(id) ?? known.find((q) => q.id === id);
  const toggle = (id: string) => onChange(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]);

  const handleRandom = () => {
    const pool = results.filter((q) => !selected.includes(q.id));
    const picked = pickRandom(pool, count, random).map((q) => q.id);
    onChange([...selected, ...picked]);
    setNotice(
      picked.length === 0
        ? c.randomNone
        : picked.length < count
          ? c.randomPartial.replace("{added}", String(picked.length)).replace("{requested}", String(count))
          : null
    );
  };

  return (
    <fieldset className="choice-editor">
      <legend>{c.pickerTitle}</legend>
      <div className="form-row">
        <label>
          {c.pickerLevel}
          <select value={level} onChange={(e) => setLevel(e.target.value)}>
            <option value="">{c.pickerAllLevels}</option>
            {LEVELS.map((lvl) => (
              <option key={lvl} value={lvl}>{lvl}</option>
            ))}
          </select>
        </label>
        <label>
          {c.pickerSearch}
          <input type="search" value={keyword} onChange={(e) => setKeyword(e.target.value)} />
        </label>
      </div>

      {error && <div className="form-error" role="alert">{error}</div>}
      <div className="picker-list" aria-busy={loading}>
        {loading && results.length === 0 && <div className="loading">{c.pickerLoading}</div>}
        {!loading && !error && results.length === 0 && <div className="loading">{c.pickerEmpty}</div>}
        {results.map((q) => (
          <label className="picker-item" key={q.id}>
            <input type="checkbox" checked={selected.includes(q.id)} onChange={() => toggle(q.id)} />
            <span className="picker-item-text">{q.prompt}</span>
            <span className="table-meta">{q.difficulty_level} · {q.question_type}</span>
          </label>
        ))}
      </div>

      <div className="form-row">
        <label>
          {c.randomCount}
          <input
            type="number"
            min={1}
            value={count}
            onChange={(e) => setCount(Math.max(1, Math.floor(Number(e.target.value)) || 1))}
          />
        </label>
        <div className="picker-random">
          <button type="button" className="ghost-button" onClick={handleRandom} disabled={loading}>
            {c.randomPick.replace("{count}", String(count))}
          </button>
        </div>
      </div>
      {notice && <div className="form-hint" role="status">{notice}</div>}

      <strong>{c.selectedCount.replace("{count}", String(selected.length))}</strong>
      {selected.length === 0 ? (
        <div className="form-hint">{c.selectedEmpty}</div>
      ) : (
        <ol className="picker-selected">
          {selected.map((id, index) => (
            <li key={id}>
              <span className="picker-item-text">{lookup(id)?.prompt ?? id.slice(0, 8)}</span>
              <button
                type="button"
                className="ghost-button small"
                aria-label={c.removeQuestion.replace("{n}", String(index + 1))}
                onClick={() => toggle(id)}
              >
                ×
              </button>
            </li>
          ))}
        </ol>
      )}
    </fieldset>
  );
};
