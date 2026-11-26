import { useConfirm } from "../components/ConfirmDialog";
import React, { useEffect, useRef, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { DataTable } from "../components/DataTable";
import { StatusPill } from "../components/StatusPill";
import { TagInput } from "../components/TagInput";
import { ChoiceEditor } from "../components/ChoiceEditor";
import { QuestionPicker } from "../components/QuestionPicker";
import { useI18n } from "../lib/i18n";
import { isChoiceType, loadChoiceState, loadPlainAnswer, validateChoices } from "../lib/questionForm";
import {
  type GrammarItem,
  type QuestionItem,
  type TestExam,
  bulkImportGrammar,
  bulkImportQuestions,
  bulkImportTestExams,
  createGrammar,
  createQuestion,
  createTestExam,
  deleteGrammar,
  deleteQuestion,
  deleteTestExam,
  listGrammar,
  listQuestions,
  listTestExams,
  updateGrammar,
  updateQuestion,
  updateTestExam
} from "../lib/adminApi";

type BulkImportResult = { created: number; skipped: number; errors: string[] };

const tabs = [
  { key: "grammar", label: "Ngữ pháp" },
  { key: "questions", label: "Question Bank" },
  { key: "tests", label: "Test Exams" }
] as const;

type TabKey = (typeof tabs)[number]["key"];

const emptyGrammarForm = { title: "", level: "A1", topic: "", summary: "", content: "", tags: [] as string[] };
const emptyQuestionForm = {
  prompt: "",
  question_type: "mcq",
  difficulty_level: "A1",
  explanation: "",
  tags: [] as string[]
};
const emptyChoices = () => ["", ""];
const emptyTestForm = {
  title: "",
  description: "",
  level: "A1",
  duration_minutes: 20,
  passing_score: 70,
  question_ids: [] as string[],
  is_published: false
};
const BASE_QUESTION_TYPES = ["mcq", "fill_blank", "true_false"];

const levelTone = (level: string): "info" | "success" | "warning" | "danger" => {
  if (level === "B1" || level === "B2") return "success";
  if (level === "C1") return "warning";
  if (level === "C2") return "danger";
  return "info";
};

export const ContentLabPage = () => {
  const confirm = useConfirm();
  const { t } = useI18n();
  const [tab, setTab] = useState<TabKey>("grammar");
  const [grammar, setGrammar] = useState<GrammarItem[]>([]);
  const [questions, setQuestions] = useState<QuestionItem[]>([]);
  const [tests, setTests] = useState<TestExam[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [editingGrammarId, setEditingGrammarId] = useState<string | null>(null);
  const [editingQuestionId, setEditingQuestionId] = useState<string | null>(null);
  const [editingTestId, setEditingTestId] = useState<string | null>(null);

  const [importing, setImporting] = useState(false);
  const [importResult, setImportResult] = useState<BulkImportResult | null>(null);
  const grammarFileRef = useRef<HTMLInputElement>(null);
  const questionFileRef = useRef<HTMLInputElement>(null);
  const testFileRef = useRef<HTMLInputElement>(null);

  const [grammarForm, setGrammarForm] = useState(emptyGrammarForm);
  const [questionForm, setQuestionForm] = useState(emptyQuestionForm);
  const [choices, setChoices] = useState<string[]>(emptyChoices);
  const [correct, setCorrect] = useState<number | null>(null);
  const [answerText, setAnswerText] = useState("");
  const [answerUnmatched, setAnswerUnmatched] = useState(false);
  const [triedSave, setTriedSave] = useState(false);
  const [testForm, setTestForm] = useState(emptyTestForm);

  const loadAll = async () => {
    setLoading(true);
    setError(null);
    try {
      const [g, q, t] = await Promise.all([listGrammar(), listQuestions(), listTestExams()]);
      setGrammar(g.data || []);
      setQuestions(q.data || []);
      setTests(t.data || []);
    } catch (err: any) {
      setError(err?.message || "Không tải được dữ liệu content lab");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadAll();
  }, []);

  const handleBulkImport = async (
    file: File | undefined,
    importFn: (file: File) => Promise<{ data?: BulkImportResult | null }>,
    fileRef: React.RefObject<HTMLInputElement | null>
  ) => {
    if (!file) return;
    setImporting(true);
    setError(null);
    setImportResult(null);
    try {
      const res = await importFn(file);
      setImportResult(res.data || null);
      await loadAll();
    } catch (err: any) {
      setError(err?.message || "Import thất bại");
    } finally {
      setImporting(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  const handleEditGrammar = (row: GrammarItem) => {
    setEditingGrammarId(row.id);
    setGrammarForm({
      title: row.title,
      level: row.level,
      topic: row.topic || "",
      summary: row.summary || "",
      content: row.content,
      tags: row.tags || []
    });
  };

  const handleCancelGrammar = () => {
    setEditingGrammarId(null);
    setGrammarForm(emptyGrammarForm);
  };

  const handleCreateGrammar = async (event: React.FormEvent) => {
    event.preventDefault();
    try {
      const payload = {
        title: grammarForm.title,
        level: grammarForm.level,
        topic: grammarForm.topic || null,
        summary: grammarForm.summary || null,
        content: grammarForm.content,
        tags: grammarForm.tags
      };
      if (editingGrammarId) {
        await updateGrammar(editingGrammarId, payload);
      } else {
        await createGrammar(payload);
      }
      handleCancelGrammar();
      await loadAll();
    } catch (err: any) {
      setError(err?.message || (editingGrammarId ? "Cập nhật grammar thất bại" : "Tạo grammar thất bại"));
    }
  };

  const handleEditQuestion = (row: QuestionItem) => {
    setEditingQuestionId(row.id);
    setQuestionForm({
      prompt: row.prompt,
      question_type: row.question_type,
      difficulty_level: row.difficulty_level,
      explanation: row.explanation || "",
      tags: row.tags || []
    });
    setTriedSave(false);
    if (isChoiceType(row.question_type)) {
      const state = loadChoiceState(row.options, row.answer);
      setChoices(state.options.length >= 2 ? state.options : [...state.options, ...emptyChoices()].slice(0, 2));
      setCorrect(state.correct);
      setAnswerUnmatched(state.unmatched);
      setAnswerText("");
    } else {
      setChoices(loadChoiceState(row.options, null).options);
      setCorrect(null);
      setAnswerUnmatched(false);
      setAnswerText(loadPlainAnswer(row.answer));
    }
  };

  const handleCancelQuestion = () => {
    setEditingQuestionId(null);
    setQuestionForm(emptyQuestionForm);
    setChoices(emptyChoices());
    setCorrect(null);
    setAnswerText("");
    setAnswerUnmatched(false);
    setTriedSave(false);
  };

  const choiceType = isChoiceType(questionForm.question_type);
  const choiceProblems = choiceType ? validateChoices(choices, correct) : [];

  const handleCreateQuestion = async (event: React.FormEvent) => {
    event.preventDefault();
    if (choiceProblems.length > 0) {
      setTriedSave(true);
      return;
    }
    try {
      const options = choices.map((o) => o.trim()).filter(Boolean);
      const payload = {
        prompt: questionForm.prompt,
        question_type: questionForm.question_type,
        difficulty_level: questionForm.difficulty_level,
        options: choiceType ? options : options.length > 0 ? options : null,
        answer: choiceType ? choices[correct as number].trim() : answerText.trim() || null,
        explanation: questionForm.explanation || null,
        tags: questionForm.tags
      };
      if (editingQuestionId) {
        await updateQuestion(editingQuestionId, payload);
      } else {
        await createQuestion(payload);
      }
      handleCancelQuestion();
      await loadAll();
    } catch (err: any) {
      setError(err?.message || (editingQuestionId ? "Cập nhật question thất bại" : "Tạo question thất bại"));
    }
  };

  const handleEditTest = (row: TestExam) => {
    setEditingTestId(row.id);
    setTestForm({
      title: row.title,
      description: row.description || "",
      level: row.level,
      duration_minutes: row.duration_minutes,
      passing_score: row.passing_score,
      question_ids: row.question_ids || [],
      is_published: row.is_published
    });
  };

  const handleCancelTest = () => {
    setEditingTestId(null);
    setTestForm(emptyTestForm);
  };

  const handleCreateTest = async (event: React.FormEvent) => {
    event.preventDefault();
    try {
      const payload = {
        title: testForm.title,
        description: testForm.description || null,
        level: testForm.level,
        duration_minutes: Number(testForm.duration_minutes),
        passing_score: Number(testForm.passing_score),
        question_ids: testForm.question_ids,
        is_published: testForm.is_published
      };
      if (editingTestId) {
        await updateTestExam(editingTestId, payload);
      } else {
        await createTestExam(payload);
      }
      handleCancelTest();
      await loadAll();
    } catch (err: any) {
      setError(err?.message || (editingTestId ? "Cập nhật test exam thất bại" : "Tạo test exam thất bại"));
    }
  };

  return (
    <div className="panel">
      <SectionHeader title="Content Lab" description="Grammar / Questions / Test-Exam" />
      <div
        className="tab-row"
        role="tablist"
        style={{
          display: "inline-flex",
          gap: 4,
          padding: 4,
          borderRadius: 999,
          background: "var(--panel-soft-2, #F8FAFC)",
          border: "1px solid var(--line)",
          marginBottom: 16,
        }}
      >
        {tabs.map((t) => (
          <button
            key={t.key}
            role="tab"
            aria-selected={tab === t.key}
            className={tab === t.key ? "tab active" : "tab"}
            style={{ borderRadius: 999 }}
            onClick={() => setTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </div>
      {error && <div className="form-error">{error}</div>}
      {loading && <div className="loading">Đang tải dữ liệu...</div>}
      {importResult && (
        <div
          className="panel"
          style={{
            padding: "12px 16px",
            background: "rgba(255, 77, 0, 0.08)",
            border: "1px solid rgba(255, 77, 0, 0.25)",
            borderRadius: 14,
          }}
        >
          <strong>Import hoàn tất:</strong> {importResult.created} tạo mới, {importResult.skipped} bỏ qua
          {importResult.errors.length > 0 && (
            <ul style={{ margin: "4px 0 0", paddingLeft: 20, color: "var(--danger, #DC2626)" }}>
              {importResult.errors.slice(0, 5).map((e, i) => <li key={i}>{e}</li>)}
            </ul>
          )}
        </div>
      )}

      {tab === "grammar" && (
        <div className="grid-2">
          <div className="panel-inner">
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <SectionHeader title="Grammar list" />
              <input
                type="file"
                accept=".csv,.pdf"
                ref={grammarFileRef}
                onChange={(e) => handleBulkImport(e.target.files?.[0], bulkImportGrammar, grammarFileRef)}
                hidden
              />
              <button className="ghost-button small" style={{ borderRadius: 999 }} onClick={() => grammarFileRef.current?.click()} disabled={importing}>
                {importing ? "Đang import..." : "Import CSV/PDF"}
              </button>
            </div>
            <DataTable
              columns={[
                {
                  header: "Tiêu đề",
                  sortValue: (row) => row.title,
                  render: (row) => (
                    <div>
                      <div className="table-title">{row.title}</div>
                      <div className="table-sub">{row.topic || ""}</div>
                    </div>
                  )
                },
                {
                  header: "Level",
                  sortValue: (row) => row.level,
                  render: (row) => <StatusPill tone={levelTone(row.level)} label={row.level} />,
                  align: "center"
                },
                {
                  header: "Action",
                  render: (row) => (
                    <div className="table-actions">
                      <button className="ghost-button small" onClick={() => handleEditGrammar(row)}>
                        Sửa
                      </button>
                      <button className="ghost-button small danger" onClick={async () => {
                        if (!(await confirm({ message: "Xóa grammar rule này?", confirmLabel: "Xóa", danger: true }))) return;
                        deleteGrammar(row.id).then(loadAll).catch((e: any) => setError(e?.message || "Xóa thất bại"));
                      }}>
                        Xóa
                      </button>
                    </div>
                  ),
                  align: "right"
                }
              ]}
              rows={grammar}
            />
          </div>
          <div className="panel-inner">
            <SectionHeader title={editingGrammarId ? "Sửa Grammar" : "Tạo Grammar"} />
            <form className="form" onSubmit={handleCreateGrammar}>
              <label>
                Tiêu đề
                <input value={grammarForm.title} onChange={(e) => setGrammarForm({ ...grammarForm, title: e.target.value })} />
              </label>
              <label>
                Level
                <select value={grammarForm.level} onChange={(e) => setGrammarForm({ ...grammarForm, level: e.target.value })}>
                  {"A1 A2 B1 B2 C1 C2".split(" ").map((lvl) => (
                    <option key={lvl} value={lvl}>
                      {lvl}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Topic
                <input value={grammarForm.topic} onChange={(e) => setGrammarForm({ ...grammarForm, topic: e.target.value })} />
              </label>
              <label>
                Summary
                <input value={grammarForm.summary} onChange={(e) => setGrammarForm({ ...grammarForm, summary: e.target.value })} />
              </label>
              <label>
                Content
                <textarea rows={4} value={grammarForm.content} onChange={(e) => setGrammarForm({ ...grammarForm, content: e.target.value })} />
              </label>
              <TagInput
                label={t.contentLab.tags}
                placeholder={t.contentLab.tagPlaceholder}
                value={grammarForm.tags}
                onChange={(tags) => setGrammarForm({ ...grammarForm, tags })}
              />
              <div className="form-row">
                <button className="primary-button" type="submit">{editingGrammarId ? "Cập nhật" : "Tạo"}</button>
                {editingGrammarId && (
                  <button className="ghost-button" type="button" onClick={handleCancelGrammar}>Huỷ</button>
                )}
              </div>
            </form>
          </div>
        </div>
      )}

      {tab === "questions" && (
        <div className="grid-2">
          <div className="panel-inner">
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <SectionHeader title="Question bank" />
              <input
                type="file"
                accept=".csv,.pdf"
                ref={questionFileRef}
                onChange={(e) => handleBulkImport(e.target.files?.[0], bulkImportQuestions, questionFileRef)}
                hidden
              />
              <button className="ghost-button small" style={{ borderRadius: 999 }} onClick={() => questionFileRef.current?.click()} disabled={importing}>
                {importing ? "Đang import..." : "Import CSV/PDF"}
              </button>
            </div>
            <DataTable
              columns={[
                {
                  header: "Prompt",
                  sortValue: (row) => row.prompt,
                  render: (row) => (
                    <div>
                      <div className="table-title">{(row.prompt || "").length > 60 ? `${row.prompt.slice(0, 60)}…` : (row.prompt || "—")}</div>
                      <div className="table-sub">{row.question_type}</div>
                    </div>
                  )
                },
                {
                  header: "Level",
                  sortValue: (row) => row.difficulty_level,
                  render: (row) => <StatusPill tone={levelTone(row.difficulty_level)} label={row.difficulty_level} />,
                  align: "center"
                },
                {
                  header: "Action",
                  render: (row) => (
                    <div className="table-actions">
                      <button className="ghost-button small" onClick={() => handleEditQuestion(row)}>
                        Sửa
                      </button>
                      <button className="ghost-button small danger" onClick={async () => {
                        if (!(await confirm({ message: "Xóa câu hỏi này?", confirmLabel: "Xóa", danger: true }))) return;
                        deleteQuestion(row.id).then(loadAll).catch((e: any) => setError(e?.message || "Xóa thất bại"));
                      }}>
                        Xóa
                      </button>
                    </div>
                  ),
                  align: "right"
                }
              ]}
              rows={questions}
            />
          </div>
          <div className="panel-inner">
            <SectionHeader title={editingQuestionId ? "Sửa Question" : "Tạo Question"} />
            <form className="form" onSubmit={handleCreateQuestion}>
              <label>
                Prompt
                <textarea rows={3} value={questionForm.prompt} onChange={(e) => setQuestionForm({ ...questionForm, prompt: e.target.value })} />
              </label>
              <label>
                Type
                <select value={questionForm.question_type} onChange={(e) => setQuestionForm({ ...questionForm, question_type: e.target.value })}>
                  <option value="mcq">MCQ</option>
                  <option value="fill_blank">Fill Blank</option>
                  <option value="true_false">True/False</option>
                  {!BASE_QUESTION_TYPES.includes(questionForm.question_type) && (
                    <option value={questionForm.question_type}>{questionForm.question_type}</option>
                  )}
                </select>
              </label>
              <label>
                Difficulty
                <select value={questionForm.difficulty_level} onChange={(e) => setQuestionForm({ ...questionForm, difficulty_level: e.target.value })}>
                  {"A1 A2 B1 B2 C1 C2".split(" ").map((lvl) => (
                    <option key={lvl} value={lvl}>
                      {lvl}
                    </option>
                  ))}
                </select>
              </label>
              {choiceType ? (
                <ChoiceEditor
                  label={t.contentLab.options}
                  options={choices}
                  onOptionsChange={setChoices}
                  correct={correct}
                  onCorrectChange={(index) => {
                    setCorrect(index);
                    setAnswerUnmatched(false);
                  }}
                  problems={triedSave ? choiceProblems : []}
                  warning={answerUnmatched ? t.contentLab.errAnswerMismatch : null}
                />
              ) : (
                <>
                  <label>
                    {t.contentLab.answer}
                    <input value={answerText} onChange={(e) => setAnswerText(e.target.value)} />
                  </label>
                  <ChoiceEditor
                    label={t.contentLab.optionsOptional}
                    options={choices}
                    onOptionsChange={setChoices}
                    correct={undefined}
                  />
                </>
              )}
              <label>
                Explanation
                <textarea rows={2} value={questionForm.explanation} onChange={(e) => setQuestionForm({ ...questionForm, explanation: e.target.value })} />
              </label>
              <TagInput
                label={t.contentLab.tags}
                placeholder={t.contentLab.tagPlaceholder}
                value={questionForm.tags}
                onChange={(tags) => setQuestionForm({ ...questionForm, tags })}
              />
              <div className="form-row">
                <button className="primary-button" type="submit">{editingQuestionId ? "Cập nhật" : "Tạo"}</button>
                {editingQuestionId && (
                  <button className="ghost-button" type="button" onClick={handleCancelQuestion}>Huỷ</button>
                )}
              </div>
            </form>
          </div>
        </div>
      )}

      {tab === "tests" && (
        <div className="grid-2">
          <div className="panel-inner">
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <SectionHeader title="Test exams" />
              <input
                type="file"
                accept=".csv,.pdf"
                ref={testFileRef}
                onChange={(e) => handleBulkImport(e.target.files?.[0], bulkImportTestExams, testFileRef)}
                hidden
              />
              <button className="ghost-button small" style={{ borderRadius: 999 }} onClick={() => testFileRef.current?.click()} disabled={importing}>
                {importing ? "Đang import..." : "Import CSV/PDF"}
              </button>
            </div>
            <DataTable
              columns={[
                {
                  header: "Bài test",
                  sortValue: (row) => row.title,
                  render: (row) => (
                    <div>
                      <div className="table-title">{row.title}</div>
                      <div className="table-sub">{row.level} • {row.duration_minutes}m</div>
                    </div>
                  )
                },
                {
                  header: "Publish",
                  sortValue: (row) => (row.is_published ? 1 : 0),
                  render: (row) => <StatusPill tone={row.is_published ? "success" : "neutral"} label={row.is_published ? "Yes" : "No"} />,
                  align: "center"
                },
                {
                  header: "Action",
                  render: (row) => (
                    <div className="table-actions">
                      <button className="ghost-button small" onClick={() => handleEditTest(row)}>
                        Sửa
                      </button>
                      <button className="ghost-button small danger" onClick={async () => {
                        if (!(await confirm({ message: "Xóa bài test này?", confirmLabel: "Xóa", danger: true }))) return;
                        deleteTestExam(row.id).then(loadAll).catch((e: any) => setError(e?.message || "Xóa thất bại"));
                      }}>
                        Xóa
                      </button>
                    </div>
                  ),
                  align: "right"
                }
              ]}
              rows={tests}
            />
          </div>
          <div className="panel-inner">
            <SectionHeader title={editingTestId ? "Sửa Test Exam" : "Tạo Test Exam"} />
            <form className="form" onSubmit={handleCreateTest}>
              <label>
                Title
                <input value={testForm.title} onChange={(e) => setTestForm({ ...testForm, title: e.target.value })} />
              </label>
              <label>
                Description
                <textarea rows={2} value={testForm.description} onChange={(e) => setTestForm({ ...testForm, description: e.target.value })} />
              </label>
              <label>
                Level
                <select value={testForm.level} onChange={(e) => setTestForm({ ...testForm, level: e.target.value })}>
                  {"A1 A2 B1 B2 C1 C2".split(" ").map((lvl) => (
                    <option key={lvl} value={lvl}>
                      {lvl}
                    </option>
                  ))}
                </select>
              </label>
              <div className="form-row">
                <label>
                  Duration (min)
                  <input
                    type="number"
                    value={testForm.duration_minutes}
                    onChange={(e) => setTestForm({ ...testForm, duration_minutes: Number(e.target.value) })}
                  />
                </label>
                <label>
                  Passing score
                  <input
                    type="number"
                    value={testForm.passing_score}
                    onChange={(e) => setTestForm({ ...testForm, passing_score: Number(e.target.value) })}
                  />
                </label>
              </div>
              <QuestionPicker
                key={editingTestId ?? "new"}
                examLevel={testForm.level}
                selected={testForm.question_ids}
                onChange={(question_ids) => setTestForm({ ...testForm, question_ids })}
                known={questions}
              />
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked={testForm.is_published}
                  onChange={(e) => setTestForm({ ...testForm, is_published: e.target.checked })}
                />
                Publish
              </label>
              <div className="form-row">
                <button className="primary-button" type="submit">{editingTestId ? "Cập nhật" : "Tạo"}</button>
                {editingTestId && (
                  <button className="ghost-button" type="button" onClick={handleCancelTest}>Huỷ</button>
                )}
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
