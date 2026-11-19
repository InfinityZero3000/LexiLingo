import React, { useEffect, useRef, useState } from "react";
import { Loader2, Plus, Sparkles, Trash2 } from "lucide-react";
import { useI18n } from "../../lib/i18n";
import { useConfirm } from "../ConfirmDialog";
import {
  createTopicStoryAdmin,
  draftTopicStoryAdmin,
  suggestTopicMetaAdmin,
  type TopicDifficulty,
  type TopicMeta,
} from "../../lib/adminApi";
import {
  CATEGORIES,
  DIFFICULTIES,
  applyDraft,
  checkForm,
  emptyGrammar,
  emptyVocabulary,
  hasAuthoredContent,
  payloadFromForm,
  topicIdFromTitle,
  type TopicFormState,
} from "../../lib/topicForm";
import { TOPIC_ICONS, iconFor, iconLabel } from "./topicIcons";

export type TopicFormMode = "create" | "edit" | "clone";

const META_DEBOUNCE_MS = 350;

export const TopicForm = ({
  mode,
  initial,
  onSaved,
  onCancel,
}: {
  mode: TopicFormMode;
  initial: TopicFormState;
  onSaved: () => void;
  onCancel: () => void;
}) => {
  const { t } = useI18n();
  const confirm = useConfirm();
  const [form, setForm] = useState(initial);
  // A new topic follows its title; a clone or an edit keeps what the admin already chose.
  const [categoryTouched, setCategoryTouched] = useState(mode !== "create");
  const [iconTouched, setIconTouched] = useState(mode !== "create");
  const [meta, setMeta] = useState<TopicMeta | null>(null);
  const [notes, setNotes] = useState("");
  const [drafting, setDrafting] = useState(false);
  const [fromDraft, setFromDraft] = useState(false);
  const [draftWarnings, setDraftWarnings] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const metaSeq = useRef(0);

  const patch = (changes: Partial<TopicFormState>) => setForm((f) => ({ ...f, ...changes }));

  useEffect(() => {
    if (mode !== "create" || (categoryTouched && iconTouched)) return;
    const title = form.title_en.trim();
    if (title.length < 3) {
      setMeta(null);
      return;
    }
    const seq = ++metaSeq.current;
    const timer = setTimeout(async () => {
      try {
        const res = await suggestTopicMetaAdmin(title);
        const suggestion = res.data;
        if (seq !== metaSeq.current || !suggestion) return;
        setMeta(suggestion);
        setForm((f) => ({
          ...f,
          ...(categoryTouched ? {} : { category: suggestion.category }),
          ...(iconTouched ? {} : { icon_key: suggestion.icon_key }),
        }));
      } catch {
        // The picker still works by hand; a failed hint is not worth an error banner.
      }
    }, META_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [form.title_en, mode, categoryTouched, iconTouched]);

  const onDraft = async () => {
    if (form.title_en.trim().length < 3) {
      setError("Give the topic an English title first.");
      return;
    }
    if (
      hasAuthoredContent(form) &&
      !(await confirm({
        message: "The AI draft replaces the character, scenario, vocabulary and grammar you have entered. Continue?",
        confirmLabel: "Replace",
      }))
    ) {
      return;
    }
    setDrafting(true);
    setError(null);
    try {
      const res = await draftTopicStoryAdmin({
        title_en: form.title_en.trim(),
        difficulty_level: form.difficulty_level,
        category: categoryTouched ? form.category : "",
        notes: notes.trim(),
      });
      if (!res.data) throw new Error("The AI returned nothing. Try again.");
      const { draft, warnings } = res.data;
      setForm((f) => applyDraft(f, draft));
      setDraftWarnings(warnings);
      setFromDraft(true);
    } catch (err: any) {
      setError(err?.message || "The AI draft failed. Try again.");
    } finally {
      setDrafting(false);
    }
  };

  const check = checkForm(form);

  const onSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (check.errors.length) {
      setError(check.errors[0]);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await createTopicStoryAdmin(payloadFromForm(form));
      onSaved();
    } catch (err: any) {
      setError(err?.message || t.adminPages.topicSaveFailed);
    } finally {
      setSaving(false);
    }
  };

  const Icon = iconFor(form.icon_key, form.category);
  const idHint = mode === "edit" ? form.story_id : topicIdFromTitle(form.title_en);
  const title =
    mode === "edit" ? t.adminPages.topicsEditing.replace("{title}", initial.title_en)
    : mode === "clone" ? "Clone topic"
    : t.adminPages.topicsNew;

  return (
    <form className="panel form" onSubmit={onSubmit} style={{ padding: 16 }}>
      <h4 style={{ margin: 0, fontSize: 15, fontWeight: 600 }}>{title}</h4>
      {mode === "clone" && (
        <p className="form-hint">
          A copy you can edit. The original stays as it is; give the copy its own title so it gets its own id.
        </p>
      )}
      {error && <div className="form-error" role="alert">{error}</div>}

      <div className="form-row">
        <label>
          English title
          <input required value={form.title_en} onChange={(e) => patch({ title_en: e.target.value })} />
        </label>
        <label>
          Vietnamese title
          <input value={form.title_vi} onChange={(e) => patch({ title_vi: e.target.value })} />
        </label>
        <label>
          Level
          <select
            value={form.difficulty_level}
            onChange={(e) => patch({ difficulty_level: e.target.value as TopicDifficulty })}
          >
            {DIFFICULTIES.map((level) => <option key={level} value={level}>{level}</option>)}
          </select>
        </label>
        <label>
          Minutes
          <input
            type="number"
            min={5}
            max={60}
            value={form.estimated_minutes}
            onChange={(e) => patch({ estimated_minutes: Number(e.target.value) })}
          />
        </label>
      </div>

      <div className="form-row">
        <label>
          Category
          <select
            value={form.category}
            onChange={(e) => { setCategoryTouched(true); patch({ category: e.target.value }); }}
          >
            {CATEGORIES.map((category) => <option key={category} value={category}>{category}</option>)}
          </select>
        </label>
        <label>
          Topic ID
          <input
            readOnly={mode === "edit"}
            placeholder={idHint}
            value={form.story_id}
            onChange={(e) => patch({ story_id: e.target.value })}
          />
        </label>
      </div>
      {mode !== "edit" && <p className="form-hint">Leave the ID empty to use <code>{idHint}</code>.</p>}

      <div className="panel-inner">
        <div className="table-title">Draft with AI</div>
        <p className="form-hint" style={{ margin: 0 }}>
          Fills the character, scenario, opening line, prompts, vocabulary and grammar from the title and level.
          Takes 10 to 40 seconds. Nothing is saved until you press Save.
        </p>
        <label>
          Notes for the AI (optional)
          <input
            placeholder="e.g. the learner is calling to complain; keep it polite"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </label>
        <div className="inline-actions">
          <button className="primary-button" type="button" onClick={onDraft} disabled={drafting}>
            {drafting ? <Loader2 size={16} style={{ animation: "spin 1s linear infinite" }} aria-hidden="true" /> : <Sparkles size={16} aria-hidden="true" />}
            {" "}{drafting ? "Drafting…" : "Draft with AI"}
          </button>
        </div>
        {fromDraft && (
          <div className="form-hint" role="status">
            Draft ready: read it through and edit it before saving.
            {draftWarnings.map((w) => <div key={w}>{w}</div>)}
          </div>
        )}
      </div>

      <div>
        <div className="table-title" style={{ marginBottom: 8 }}>
          Icon{" "}
          {mode === "create" && !iconTouched && meta && (
            <span className="table-meta">
              {meta.confidence === "high"
                ? `chosen from the title (${iconLabel(meta.icon_key)})`
                : "not sure: please check it"}
            </span>
          )}
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }} role="group" aria-label="Icon">
          {TOPIC_ICONS.map((item) => {
            const ItemIcon = item.icon;
            const selected = form.icon_key === item.key;
            return (
              <button
                key={item.key}
                type="button"
                className={selected ? "primary-button" : "ghost-button"}
                aria-pressed={selected}
                onClick={() => { setIconTouched(true); patch({ icon_key: item.key }); }}
                style={{ display: "inline-flex", alignItems: "center", gap: 6 }}
              >
                <ItemIcon size={16} aria-hidden="true" />
                {item.label}
              </button>
            );
          })}
        </div>
      </div>

      <div className="panel-inner" style={{ flexDirection: "row", alignItems: "center" }} aria-label="Preview in the app">
        <span className="stat-icon" style={{ width: 40, height: 40 }}><Icon size={20} aria-hidden="true" /></span>
        <div>
          <div className="table-title">{form.title_en.trim() || "Topic title"}</div>
          <div className="table-sub">{form.difficulty_level} · {form.estimated_minutes} min · {form.category}</div>
        </div>
        <span className="table-meta" style={{ marginLeft: "auto" }}>how it looks in the app</span>
      </div>

      <details open>
        <summary className="table-title">Conversation</summary>
        <div className="form" style={{ marginTop: 8 }}>
          <label>
            Opening line (what the character says first)
            <textarea rows={2} value={form.opening_prompt} onChange={(e) => patch({ opening_prompt: e.target.value })} />
          </label>
          <label>
            Suggested prompts (one per line: the chips learners tap)
            <textarea
              rows={4}
              value={form.suggested_prompts.join("\n")}
              onChange={(e) => patch({ suggested_prompts: e.target.value.split("\n") })}
            />
          </label>
          <label>
            Tags (comma separated)
            <input value={form.tags} onChange={(e) => patch({ tags: e.target.value })} />
          </label>
        </div>
      </details>

      <details open={Boolean(form.persona.name || form.scenario)}>
        <summary className="table-title">Character and scenario</summary>
        <div className="form" style={{ marginTop: 8 }}>
          <div className="form-row">
            {(
              [
                ["name", "Name"],
                ["role", "Role"],
                ["personality", "Personality"],
                ["speaking_style", "Speaking style"],
              ] as const
            ).map(([key, label]) => (
              <label key={key}>
                {label}
                <input
                  value={form.persona[key]}
                  onChange={(e) => patch({ persona: { ...form.persona, [key]: e.target.value } })}
                />
              </label>
            ))}
          </div>
          <label>
            Background
            <textarea
              rows={2}
              value={form.persona.background}
              onChange={(e) => patch({ persona: { ...form.persona, background: e.target.value } })}
            />
          </label>
          <label>
            Setting
            <input value={form.setting} onChange={(e) => patch({ setting: e.target.value })} />
          </label>
          <label>
            Scenario
            <textarea rows={3} value={form.scenario} onChange={(e) => patch({ scenario: e.target.value })} />
          </label>
          <label>
            Objectives (one per line)
            <textarea
              rows={3}
              value={form.objectives.join("\n")}
              onChange={(e) => patch({ objectives: e.target.value.split("\n") })}
            />
          </label>
        </div>
      </details>

      <details open={form.vocabulary.length > 0}>
        <summary className="table-title">Vocabulary ({form.vocabulary.filter((v) => v.term.trim()).length})</summary>
        <div className="form" style={{ marginTop: 8 }}>
          {form.vocabulary.map((item, index) => (
            <div className="form-row" key={index} style={{ alignItems: "start" }}>
              <input
                aria-label={`Term ${index + 1}`}
                placeholder="term"
                value={item.term}
                onChange={(e) => patch({ vocabulary: form.vocabulary.map((v, i) => (i === index ? { ...v, term: e.target.value } : v)) })}
              />
              <input
                aria-label={`Definition ${index + 1}`}
                placeholder="definition"
                value={item.definition}
                onChange={(e) => patch({ vocabulary: form.vocabulary.map((v, i) => (i === index ? { ...v, definition: e.target.value } : v)) })}
              />
              <input
                aria-label={`Example ${index + 1}`}
                placeholder="example sentence"
                value={item.example_in_story}
                onChange={(e) => patch({ vocabulary: form.vocabulary.map((v, i) => (i === index ? { ...v, example_in_story: e.target.value } : v)) })}
              />
              <button
                className="ghost-button small"
                type="button"
                aria-label={`Remove term ${index + 1}`}
                onClick={() => patch({ vocabulary: form.vocabulary.filter((_, i) => i !== index) })}
              >
                <Trash2 size={14} aria-hidden="true" />
              </button>
            </div>
          ))}
          <div>
            <button className="ghost-button small" type="button" onClick={() => patch({ vocabulary: [...form.vocabulary, emptyVocabulary()] })}>
              <Plus size={14} aria-hidden="true" /> Add term
            </button>
          </div>
        </div>
      </details>

      <details open={form.grammar.length > 0}>
        <summary className="table-title">Grammar points ({form.grammar.filter((g) => g.grammar_structure.trim()).length})</summary>
        <div className="form" style={{ marginTop: 8 }}>
          {form.grammar.map((item, index) => (
            <div className="panel-inner" key={index}>
              <div className="form-row" style={{ alignItems: "start" }}>
                <input
                  aria-label={`Structure ${index + 1}`}
                  placeholder="structure, e.g. Polite requests with could"
                  value={item.grammar_structure}
                  onChange={(e) => patch({ grammar: form.grammar.map((g, i) => (i === index ? { ...g, grammar_structure: e.target.value } : g)) })}
                />
                <input
                  aria-label={`Explanation ${index + 1}`}
                  placeholder="one-sentence explanation"
                  value={item.explanation}
                  onChange={(e) => patch({ grammar: form.grammar.map((g, i) => (i === index ? { ...g, explanation: e.target.value } : g)) })}
                />
                <button
                  className="ghost-button small"
                  type="button"
                  aria-label={`Remove grammar point ${index + 1}`}
                  onClick={() => patch({ grammar: form.grammar.filter((_, i) => i !== index) })}
                >
                  <Trash2 size={14} aria-hidden="true" />
                </button>
              </div>
              <textarea
                aria-label={`Examples ${index + 1}`}
                placeholder="examples, one per line"
                rows={2}
                value={item.examples.join("\n")}
                onChange={(e) => patch({ grammar: form.grammar.map((g, i) => (i === index ? { ...g, examples: e.target.value.split("\n") } : g)) })}
              />
            </div>
          ))}
          <div>
            <button className="ghost-button small" type="button" onClick={() => patch({ grammar: [...form.grammar, emptyGrammar()] })}>
              <Plus size={14} aria-hidden="true" /> Add grammar point
            </button>
          </div>
        </div>
      </details>

      {(check.errors.length > 0 || check.warnings.length > 0) && (
        <div className="panel-inner" aria-label="Before you save">
          {check.errors.map((message) => <div key={message} className="form-error">{message}</div>)}
          {check.warnings.map((message) => <div key={message} className="form-hint">{message}</div>)}
        </div>
      )}

      <div className="inline-actions" style={{ justifyContent: "flex-end" }}>
        <button className="ghost-button" type="button" onClick={onCancel}>Cancel</button>
        <button className="primary-button" type="submit" disabled={saving || drafting}>
          {saving ? t.common.saving : mode === "edit" ? t.adminPages.topicsUpdate : t.adminPages.topicsSave}
        </button>
      </div>
    </form>
  );
};
