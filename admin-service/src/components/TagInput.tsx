import { useId, useState } from "react";
import { useI18n } from "../lib/i18n";

type Props = {
  label: string;
  value: string[];
  onChange: (tags: string[]) => void;
  placeholder?: string;
};

export const TagInput = ({ label, value, onChange, placeholder }: Props) => {
  const { t } = useI18n();
  const id = useId();
  const [draft, setDraft] = useState("");

  const add = (parts: string[]) => {
    const next = [...value];
    for (const part of parts) {
      const tag = part.trim();
      if (tag && !next.some((x) => x.toLowerCase() === tag.toLowerCase())) next.push(tag);
    }
    if (next.length !== value.length) onChange(next);
  };

  const commit = () => {
    add([draft]);
    setDraft("");
  };

  return (
    <div className="tag-input">
      <label htmlFor={id}>{label}</label>
      <div className="tag-input-box">
        {value.map((tag) => (
          <span className="tag-chip" key={tag}>
            {tag}
            <button
              type="button"
              aria-label={t.contentLab.tagRemove.replace("{tag}", tag)}
              onClick={() => onChange(value.filter((x) => x !== tag))}
            >
              ×
            </button>
          </span>
        ))}
        <input
          id={id}
          value={draft}
          placeholder={value.length === 0 ? placeholder : undefined}
          onChange={(e) => {
            const text = e.target.value;
            if (text.includes(",")) {
              add(text.split(","));
              setDraft("");
            } else setDraft(text);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              commit();
            } else if (e.key === "Backspace" && draft === "" && value.length > 0) {
              onChange(value.slice(0, -1));
            }
          }}
          onBlur={commit}
        />
      </div>
    </div>
  );
};
