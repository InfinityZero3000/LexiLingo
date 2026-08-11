import React from "react";
import { ArrowRight, Check, Plus, Trash2 } from "lucide-react";
import {
  type Exercise,
  type ExerciseOption,
  type UiType,
  UI_TYPE_TO_TYPE,
} from "../lib/adminApi";

interface Props {
  uiType: UiType;
  value: Exercise;
  onChange: (updated: Exercise) => void;
}

// ─── helpers ────────────────────────────────────────────────────────────────

const newOption = (idx: number, isCorrect = false): ExerciseOption => ({
  id: String(idx),
  text: "",
  is_correct: isCorrect,
});

const inputCls = "exercise-form-input";
const labelCls = "exercise-form-label";
const fieldCls = "exercise-form-field";

// ─── sub-sections ────────────────────────────────────────────────────────────

/** Common fields present in every exercise */
const CommonFields = ({
  value,
  onChange,
}: {
  value: Exercise;
  onChange: (u: Exercise) => void;
}) => (
  <>
    <div className={fieldCls}>
      <label className={labelCls}>Explanation (optional)</label>
      <textarea
        className={inputCls}
        rows={2}
        value={value.explanation ?? ""}
        placeholder="Giải thích đáp án đúng..."
        onChange={(e) => onChange({ ...value, explanation: e.target.value || null })}
      />
    </div>
    <div className="exercise-form-grid">
      <div className={fieldCls}>
        <label className={labelCls}>Hint (optional)</label>
        <input
          className={inputCls}
          value={value.hint ?? ""}
          placeholder="Gợi ý..."
          onChange={(e) => onChange({ ...value, hint: e.target.value || null })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Points</label>
        <input
          type="number"
          className={inputCls}
          min={0}
          value={value.points}
          onChange={(e) => onChange({ ...value, points: Number(e.target.value) })}
        />
      </div>
    </div>
  </>
);

/** MCQ options editor — used by many types */
const OptionsEditor = ({
  options,
  onlyOneCorrect = true,
  onChange,
}: {
  options: ExerciseOption[];
  onlyOneCorrect?: boolean;
  onChange: (opts: ExerciseOption[]) => void;
}) => {
  const setOption = (idx: number, patch: Partial<ExerciseOption>) => {
    const next = options.map((o, i) => (i === idx ? { ...o, ...patch } : o));
    onChange(next);
  };

  const markCorrect = (idx: number) => {
    if (onlyOneCorrect) {
      onChange(options.map((o, i) => ({ ...o, is_correct: i === idx })));
    } else {
      setOption(idx, { is_correct: !options[idx].is_correct });
    }
  };

  const addOption = () => onChange([...options, newOption(options.length)]);
  const removeOption = (idx: number) =>
    onChange(options.filter((_, i) => i !== idx).map((o, i) => ({ ...o, id: String(i) })));

  return (
    <div className={fieldCls}>
      <label className={labelCls}>Options</label>
      <div className="exercise-form-list">
        {options.map((opt, idx) => (
          <div key={opt.id} className="exercise-form-row">
            <button
              type="button"
              title={opt.is_correct ? "Đáp án đúng" : "Nhấn để đánh dấu đúng"}
              aria-label={opt.is_correct ? "Đáp án đúng" : "Đánh dấu là đáp án đúng"}
              className={`exercise-option-toggle${opt.is_correct ? " is-correct" : ""}`}
              onClick={() => markCorrect(idx)}
            >
              {opt.is_correct && <Check size={14} aria-hidden="true" />}
            </button>
            <input
              className={inputCls}
              value={opt.text}
              placeholder={`Option ${idx + 1}`}
              onChange={(e) => setOption(idx, { text: e.target.value })}
            />
            <button
              type="button"
              className="icon-button exercise-remove-button"
              aria-label={`Xóa option ${idx + 1}`}
              onClick={() => removeOption(idx)}
            >
              <Trash2 size={15} aria-hidden="true" />
            </button>
          </div>
        ))}
        <button
          type="button"
          className="ghost-button small exercise-add-button"
          onClick={addOption}
        >
          <Plus size={15} aria-hidden="true" /> Thêm option
        </button>
      </div>
    </div>
  );
};

/** Word-pair editor for match/categorization types */
const PairsEditor = ({
  pairs,
  leftLabel,
  rightLabel,
  onChange,
}: {
  pairs: [string, string][];
  leftLabel: string;
  rightLabel: string;
  onChange: (pairs: [string, string][]) => void;
}) => {
  const set = (idx: number, side: 0 | 1, val: string) => {
    const next: [string, string][] = pairs.map((p, i) =>
      i === idx ? (side === 0 ? [val, p[1]] : [p[0], val]) : p
    );
    onChange(next);
  };
  const add = () => onChange([...pairs, ["", ""]]);
  const remove = (idx: number) => onChange(pairs.filter((_, i) => i !== idx));

  // Derive options array: first half = left, second half = right
  const toOptions = (ps: [string, string][]): ExerciseOption[] => [
    ...ps.map((p, i) => ({ id: String(i), text: p[0], is_correct: false })),
    ...ps.map((p, i) => ({ id: String(ps.length + i), text: p[1], is_correct: true })),
  ];

  return (
    <div className={fieldCls}>
      <label className={labelCls}>
        Pairs ({leftLabel} → {rightLabel})
      </label>
      <div className="exercise-form-list">
        {pairs.map(([l, r], idx) => (
          <div key={idx} className="exercise-form-row">
            <input
              className={inputCls}
              placeholder={leftLabel}
              value={l}
              onChange={(e) => set(idx, 0, e.target.value)}
            />
            <ArrowRight className="exercise-pair-arrow" size={16} aria-hidden="true" />
            <input
              className={inputCls}
              placeholder={rightLabel}
              value={r}
              onChange={(e) => set(idx, 1, e.target.value)}
            />
            <button
              type="button"
              className="icon-button exercise-remove-button"
              aria-label={`Xóa cặp ${idx + 1}`}
              onClick={() => remove(idx)}
            >
              <Trash2 size={15} aria-hidden="true" />
            </button>
          </div>
        ))}
        <button
          type="button"
          className="ghost-button small exercise-add-button"
          onClick={add}
        >
          <Plus size={15} aria-hidden="true" /> Thêm cặp
        </button>
      </div>
      {/* hidden helper so caller can read toOptions */}
      <input type="hidden" data-pairs={JSON.stringify(toOptions(pairs))} />
    </div>
  );
};

// ─── parse helpers for pairs ─────────────────────────────────────────────────

const optionsToPairs = (options: ExerciseOption[] | null | undefined): [string, string][] => {
  if (!options || options.length === 0) return [["", ""]];
  const half = Math.floor(options.length / 2);
  const left = options.slice(0, half);
  const right = options.slice(half);
  return left.map((l, i) => [l.text, right[i]?.text ?? ""]);
};

const pairsToOptions = (pairs: [string, string][]): ExerciseOption[] => [
  ...pairs.map((p, i) => ({ id: String(i), text: p[0], is_correct: false })),
  ...pairs.map((p, i) => ({ id: String(pairs.length + i), text: p[1], is_correct: true })),
];

// ─── form sections per pattern ────────────────────────────────────────────────

/** MCQ: question + options list (mark correct) + correct_answer auto-derived */
const McqForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [newOption(0, true), newOption(1), newOption(2), newOption(3)];

  const handleOptionsChange = (opts: ExerciseOption[]) => {
    const correct = opts.find((o) => o.is_correct)?.text ?? "";
    onChange({ ...value, options: opts, correct_answer: correct });
  };

  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Question / Prompt</label>
        <textarea
          className={inputCls}
          rows={3}
          value={value.question}
          placeholder="Nhập câu hỏi..."
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <OptionsEditor options={options} onlyOneCorrect onChange={handleOptionsChange} />
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** True/False — only 2 fixed options */
const TrueFalseForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const correct = value.correct_answer === "True" ? "True" : "False";
  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Statement</label>
        <textarea
          className={inputCls}
          rows={3}
          value={value.question}
          placeholder="Nhập câu phát biểu..."
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Correct Answer</label>
        <div className="exercise-answer-options">
          {(["True", "False"] as const).map((v) => (
            <button
              key={v}
              type="button"
              className={`exercise-answer-button${correct === v ? " is-active" : ""}`}
              onClick={() =>
                onChange({
                  ...value,
                  correct_answer: v,
                  options: [
                    { id: "0", text: "True", is_correct: v === "True" },
                    { id: "1", text: "False", is_correct: v === "False" },
                  ],
                })
              }
            >
              {v}
            </button>
          ))}
        </div>
      </div>
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Fill blank: sentence with {blank} placeholder + correct answer */
const FillBlankForm = ({
  value,
  onChange,
  showOptions = false,
}: {
  value: Exercise;
  onChange: (u: Exercise) => void;
  showOptions?: boolean;
}) => {
  const options = value.options ?? [];
  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>
          Sentence (use <code className="exercise-inline-code">{"{blank}"}</code> for the gap)
        </label>
        <textarea
          className={inputCls}
          rows={3}
          value={value.question}
          placeholder="We {blank} to school every day."
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Correct Answer</label>
        <input
          className={inputCls}
          value={value.correct_answer}
          placeholder="go"
          onChange={(e) => onChange({ ...value, correct_answer: e.target.value })}
        />
      </div>
      {showOptions && (
        <OptionsEditor
          options={options.length ? options : [newOption(0, true), newOption(1)]}
          onlyOneCorrect
          onChange={(opts) =>
            onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? value.correct_answer })
          }
        />
      )}
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Dialogue completion: A/B chat + blank + optional options */
const DialogueForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [];
  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>
          Dialogue (use <code className="exercise-inline-code">{"{blank}"}</code> for the gap)
        </label>
        <textarea
          className={inputCls}
          rows={4}
          value={value.question}
          placeholder={"A: Do you speak English?\nB: Yes, I {blank}."}
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
        <p className="exercise-form-help">Format: "A: ... B: ... {`{blank}`}"</p>
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Correct Answer</label>
        <input
          className={inputCls}
          value={value.correct_answer}
          placeholder="do"
          onChange={(e) => onChange({ ...value, correct_answer: e.target.value })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Options (leave empty for text input mode)</label>
        <OptionsEditor
          options={options}
          onlyOneCorrect
          onChange={(opts) =>
            onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? value.correct_answer })
          }
        />
      </div>
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Arrange the sentence: instruction + word array + correct sentence */
const ArrangeForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [];
  const wordsText = options.map((o) => o.text).join(" / ");

  const handleWordsChange = (raw: string) => {
    const words = raw.split("/").map((w) => w.trim()).filter(Boolean);
    const opts: ExerciseOption[] = words.map((w, i) => ({ id: String(i), text: w, is_correct: false }));
    onChange({ ...value, options: opts });
  };

  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Instruction</label>
        <input
          className={inputCls}
          value={value.question}
          placeholder="Arrange: 'day / every / study / they'"
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Words (separated by /)</label>
        <input
          className={inputCls}
          value={wordsText}
          placeholder="they / study / every / day"
          onChange={(e) => handleWordsChange(e.target.value)}
        />
        <p className="exercise-form-help">Nhập các từ cần sắp xếp, phân cách bằng /</p>
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Correct Sentence</label>
        <input
          className={inputCls}
          value={value.correct_answer}
          placeholder="they study every day"
          onChange={(e) => onChange({ ...value, correct_answer: e.target.value })}
        />
      </div>
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Match/Pairs: word ↔ meaning, word ↔ category */
const PairsForm = ({
  value,
  onChange,
  leftLabel = "Word",
  rightLabel = "Meaning",
}: {
  value: Exercise;
  onChange: (u: Exercise) => void;
  leftLabel?: string;
  rightLabel?: string;
}) => {
  const pairs = optionsToPairs(value.options);

  const handlePairsChange = (newPairs: [string, string][]) => {
    const opts = pairsToOptions(newPairs);
    const correctStr = newPairs.map(([l, r]) => `${l}:${r}`).join("|");
    onChange({ ...value, options: opts, correct_answer: correctStr });
  };

  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Instruction / Prompt</label>
        <input
          className={inputCls}
          value={value.question}
          placeholder="Match each word with its meaning."
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <PairsEditor
        pairs={pairs}
        leftLabel={leftLabel}
        rightLabel={rightLabel}
        onChange={handlePairsChange}
      />
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Speaking/Audio: sentence + translation */
const SpeakingForm = ({
  value,
  onChange,
  showAudioUrl = false,
}: {
  value: Exercise;
  onChange: (u: Exercise) => void;
  showAudioUrl?: boolean;
}) => (
  <>
    <div className={fieldCls}>
      <label className={labelCls}>Sentence to Repeat / Pronounce</label>
      <textarea
        className={inputCls}
        rows={2}
        value={value.question}
        placeholder="I listen to music every evening."
        onChange={(e) => onChange({ ...value, question: e.target.value })}
      />
    </div>
    <div className={fieldCls}>
      <label className={labelCls}>Correct Answer (same as sentence)</label>
      <input
        className={inputCls}
        value={value.correct_answer}
        placeholder="I listen to music every evening"
        onChange={(e) => onChange({ ...value, correct_answer: e.target.value })}
      />
    </div>
    {showAudioUrl && (
      <div className={fieldCls}>
        <label className={labelCls}>Audio URL (optional)</label>
        <input
          className={inputCls}
          value={value.audio_url ?? ""}
          placeholder="https://..."
          onChange={(e) => onChange({ ...value, audio_url: e.target.value || null })}
        />
      </div>
    )}
    <CommonFields value={value} onChange={onChange} />
  </>
);

/** Translation choice: source sentence + translation MCQ */
const TranslationForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [newOption(0, true), newOption(1), newOption(2)];
  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Source Sentence (e.g. Vietnamese)</label>
        <textarea
          className={inputCls}
          rows={2}
          value={value.question}
          placeholder="Choose the translation for: 'Chúng tôi muốn học.'"
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <OptionsEditor
        options={options}
        onlyOneCorrect
        onChange={(opts) =>
          onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? "" })
        }
      />
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Vocabulary flashcard: word + definition + optional MCQ */
const FlashcardForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const hasOptions = (value.options?.length ?? 0) > 1;
  const options = value.options ?? [{ id: "0", text: "Got it!", is_correct: true }];

  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Word / Phrase (wrap in quotes: &apos;Word&apos;)</label>
        <input
          className={inputCls}
          value={value.question}
          placeholder="Learn the card: 'Adventure'"
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Definition / Explanation</label>
        <textarea
          className={inputCls}
          rows={2}
          value={value.explanation ?? ""}
          placeholder="An unusual, exciting, and daring experience."
          onChange={(e) => onChange({ ...value, explanation: e.target.value || null })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Image URL (optional)</label>
        <input
          className={inputCls}
          value={value.image_url ?? ""}
          placeholder="https://..."
          onChange={(e) => onChange({ ...value, image_url: e.target.value || null })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Mode</label>
        <div className="exercise-mode-options">
          <label className="exercise-radio-label">
            <input
              type="radio"
              checked={!hasOptions}
              onChange={() =>
                onChange({ ...value, options: [{ id: "0", text: "Got it!", is_correct: true }], correct_answer: "Got it!" })
              }
            />
            Simple flashcard ("Got it!")
          </label>
          <label className="exercise-radio-label">
            <input
              type="radio"
              checked={hasOptions}
              onChange={() =>
                onChange({
                  ...value,
                  options: [newOption(0, true), newOption(1), newOption(2), newOption(3)],
                })
              }
            />
            Flashcard + MCQ
          </label>
        </div>
      </div>
      {hasOptions && (
        <OptionsEditor
          options={options}
          onlyOneCorrect
          onChange={(opts) =>
            onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? "" })
          }
        />
      )}
    </>
  );
};

/** Reading comprehension: long passage + question + MCQ */
const ReadingForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [newOption(0, true), newOption(1), newOption(2), newOption(3)];
  // question field = passage + "\n" + question sentence
  const lines = value.question.split("\n");
  const passage = lines.slice(0, -1).join("\n");
  const questionLine = lines[lines.length - 1];

  const update = (newPassage: string, newQuestion: string) => {
    onChange({ ...value, question: `${newPassage}\n${newQuestion}` });
  };

  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Passage / Reading Text</label>
        <textarea
          className={inputCls}
          rows={6}
          value={passage}
          placeholder="The Amazon rainforest is the world's largest tropical rainforest..."
          onChange={(e) => update(e.target.value, questionLine)}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Question (last line of passage field)</label>
        <input
          className={inputCls}
          value={questionLine}
          placeholder="What is the Amazon rainforest known for?"
          onChange={(e) => update(passage, e.target.value)}
        />
      </div>
      <OptionsEditor
        options={options}
        onlyOneCorrect
        onChange={(opts) =>
          onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? "" })
        }
      />
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Image-based choice */
const ImageChoiceForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [newOption(0, true), newOption(1), newOption(2), newOption(3)];
  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Image URL</label>
        <input
          className={inputCls}
          value={value.image_url ?? ""}
          placeholder="https://..."
          onChange={(e) => onChange({ ...value, image_url: e.target.value || null })}
        />
      </div>
      {value.image_url && (
        <img
          src={value.image_url}
          alt="preview"
          className="exercise-image-preview"
          onError={(e) => ((e.target as HTMLImageElement).style.display = "none")}
        />
      )}
      <div className={fieldCls}>
        <label className={labelCls}>Question</label>
        <input
          className={inputCls}
          value={value.question}
          placeholder="What is in the image?"
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <OptionsEditor
        options={options}
        onlyOneCorrect
        onChange={(opts) =>
          onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? "" })
        }
      />
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Listen and choose: audio URL + MCQ */
const ListenChooseForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => {
  const options = value.options ?? [newOption(0, true), newOption(1), newOption(2), newOption(3)];
  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Audio URL (TTS or file URL)</label>
        <input
          className={inputCls}
          value={value.audio_url ?? ""}
          placeholder="https://..."
          onChange={(e) => onChange({ ...value, audio_url: e.target.value || null })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Question / Instruction</label>
        <input
          className={inputCls}
          value={value.question}
          placeholder="Listen and choose the word you hear."
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <OptionsEditor
        options={options}
        onlyOneCorrect
        onChange={(opts) =>
          onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? "" })
        }
      />
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

/** Short writing: prompt + sample answer */
const ShortWritingForm = ({ value, onChange }: { value: Exercise; onChange: (u: Exercise) => void }) => (
  <>
    <div className={fieldCls}>
      <label className={labelCls}>Writing Prompt</label>
      <textarea
        className={inputCls}
        rows={3}
        value={value.question}
        placeholder="Write a sentence using the word 'persevere'."
        onChange={(e) => onChange({ ...value, question: e.target.value })}
      />
    </div>
    <div className={fieldCls}>
      <label className={labelCls}>Sample / Model Answer</label>
      <textarea
        className={inputCls}
        rows={2}
        value={value.correct_answer}
        placeholder="She persevered despite all the challenges."
        onChange={(e) => onChange({ ...value, correct_answer: e.target.value })}
      />
    </div>
    <CommonFields value={value} onChange={onChange} />
  </>
);

/** Grammar correction */
const GrammarCorrectionForm = ({
  value,
  onChange,
}: {
  value: Exercise;
  onChange: (u: Exercise) => void;
}) => {
  const hasOptions = (value.options?.length ?? 0) > 0;
  const options = value.options ?? [];

  return (
    <>
      <div className={fieldCls}>
        <label className={labelCls}>Incorrect Sentence</label>
        <textarea
          className={inputCls}
          rows={2}
          value={value.question}
          placeholder="Correct this sentence: 'She go to school every day.'"
          onChange={(e) => onChange({ ...value, question: e.target.value })}
        />
      </div>
      <div className={fieldCls}>
        <label className={labelCls}>Mode</label>
        <div className="exercise-mode-options">
          <label className="exercise-radio-label">
            <input
              type="radio"
              checked={!hasOptions}
              onChange={() => onChange({ ...value, options: [] })}
            />
            Free text input
          </label>
          <label className="exercise-radio-label">
            <input
              type="radio"
              checked={hasOptions}
              onChange={() =>
                onChange({ ...value, options: [newOption(0, true), newOption(1), newOption(2)] })
              }
            />
            Multiple choice
          </label>
        </div>
      </div>
      {hasOptions && (
        <OptionsEditor
          options={options}
          onlyOneCorrect
          onChange={(opts) =>
            onChange({ ...value, options: opts, correct_answer: opts.find((o) => o.is_correct)?.text ?? value.correct_answer })
          }
        />
      )}
      <div className={fieldCls}>
        <label className={labelCls}>Correct Answer</label>
        <input
          className={inputCls}
          value={value.correct_answer}
          placeholder="She goes to school every day."
          onChange={(e) => onChange({ ...value, correct_answer: e.target.value })}
        />
      </div>
      <CommonFields value={value} onChange={onChange} />
    </>
  );
};

// ─── main export ─────────────────────────────────────────────────────────────

export const ExerciseTypeForm: React.FC<Props> = ({ uiType, value, onChange }) => {
  // Sync type field whenever ui_type changes
  const withType = (e: Exercise): Exercise => ({
    ...e,
    type: UI_TYPE_TO_TYPE[uiType as UiType] ?? "multiple_choice",
    ui_type: uiType,
  });

  const handle = (updated: Exercise) => onChange(withType(updated));

  switch (uiType) {
    case "multiple_choice":
    case "collocation_choice":
      return <McqForm value={value} onChange={handle} />;

    case "true_or_false":
      return <TrueFalseForm value={value} onChange={handle} />;

    case "fill_in_the_blank":
    case "dictation":
      return <FillBlankForm value={value} onChange={handle} />;

    case "short_writing_answer":
      return <ShortWritingForm value={value} onChange={handle} />;

    case "dialogue_completion":
      return <DialogueForm value={value} onChange={handle} />;

    case "arrange_the_sentence":
      return <ArrangeForm value={value} onChange={handle} />;

    case "match_word_to_meaning":
    case "cognitive_fluidity":
      return <PairsForm value={value} onChange={handle} leftLabel="Word" rightLabel="Meaning" />;

    case "categorization":
      return <PairsForm value={value} onChange={handle} leftLabel="Word" rightLabel="Category" />;

    case "speaking_repeat":
    case "pronunciation_practice":
      return <SpeakingForm value={value} onChange={handle} showAudioUrl />;

    case "translation_choice":
      return <TranslationForm value={value} onChange={handle} />;

    case "vocabulary_flashcard":
      return <FlashcardForm value={value} onChange={handle} />;

    case "reading_comprehension":
      return <ReadingForm value={value} onChange={handle} />;

    case "image_based_choice":
      return <ImageChoiceForm value={value} onChange={handle} />;

    case "listen_and_choose":
      return <ListenChooseForm value={value} onChange={handle} />;

    case "grammar_correction":
      return <GrammarCorrectionForm value={value} onChange={handle} />;

    default:
      return <McqForm value={value} onChange={handle} />;
  }
};
