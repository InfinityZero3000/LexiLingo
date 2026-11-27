import { useRemoveFromForm } from "../lib/useRemoveFromForm";
import { useI18n } from "../lib/i18n";
import type { ChoiceProblem } from "../lib/questionForm";

type Props = {
  label: string;
  options: string[];
  onOptionsChange: (options: string[]) => void;
  // undefined hides the radios (types whose answer is typed in separately)
  correct: number | null | undefined;
  onCorrectChange?: (index: number | null) => void;
  problems?: ChoiceProblem[];
  warning?: string | null;
};

export const ChoiceEditor = ({ label, options, onOptionsChange, correct, onCorrectChange, problems = [], warning }: Props) => {
  const { t } = useI18n();
  const c = t.contentLab;
  const showRadios = correct !== undefined;
  const name = `${label}-correct`;
  const messages: Record<ChoiceProblem, string> = {
    tooFew: c.errTooFew,
    duplicate: c.errDuplicate,
    noCorrect: c.errNoCorrect
  };

  const removeFromForm = useRemoveFromForm();
  const remove = (index: number) => {
    onOptionsChange(options.filter((_, i) => i !== index));
    if (!onCorrectChange || correct === null || correct === undefined) return;
    if (correct === index) onCorrectChange(null);
    else if (correct > index) onCorrectChange(correct - 1);
  };

  return (
    <fieldset className="choice-editor">
      <legend>{label}</legend>
      {showRadios && <p className="form-hint">{c.correctHint}</p>}
      {options.map((text, index) => {
        const isSelected = showRadios && correct === index;
        return (
          <div
            className={isSelected ? "choice-row is-selected" : "choice-row"}
            key={index}
            style={{
              padding: "8px 12px",
              borderRadius: 14,
              border: `1px solid ${isSelected ? "var(--accent-2, #FF7A00)" : "var(--line, #E2E8F0)"}`,
              background: isSelected ? "rgba(255, 77, 0, 0.08)" : "var(--panel-soft-2, #F8FAFC)",
              transition: "background 0.15s ease, border-color 0.15s ease",
            }}
          >
            {showRadios && (
              <input
                type="radio"
                name={name}
                checked={isSelected}
                onChange={() => onCorrectChange?.(index)}
                aria-label={c.correctOption.replace("{n}", String(index + 1))}
                style={{ accentColor: "var(--accent-2, #FF7A00)" }}
              />
            )}
            <input
              type="text"
              value={text}
              aria-label={c.optionLabel.replace("{n}", String(index + 1))}
              onChange={(e) => onOptionsChange(options.map((o, i) => (i === index ? e.target.value : o)))}
            />
            <button
              type="button"
              className="ghost-button small"
              style={{ borderRadius: 999 }}
              aria-label={c.removeOption.replace("{n}", String(index + 1))}
              onClick={() => void removeFromForm(text, () => remove(index))}
            >
              ×
            </button>
          </div>
        );
      })}
      <div>
        <button
          type="button"
          className="ghost-button small"
          style={{ borderRadius: 999 }}
          onClick={() => onOptionsChange([...options, ""])}
        >
          {c.addOption}
        </button>
      </div>
      {warning && <div className="form-error" role="alert">{warning}</div>}
      {problems.map((p) => (
        <div className="form-error" role="alert" key={p}>{messages[p]}</div>
      ))}
    </fieldset>
  );
};
