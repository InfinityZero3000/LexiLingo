import React, { useEffect, useState } from "react";
import { SectionHeader } from "../components/SectionHeader";
import { DataTable } from "../components/DataTable";
import {
  GrammarItem,
  QuestionItem,
  TestExam,
  createGrammar,
  createQuestion,
  createTestExam,
  deleteGrammar,
  deleteQuestion,
  deleteTestExam,
  listGrammar,
  listQuestions,
  listTestExams
} from "../lib/adminApi";

const tabs = [
  { key: "grammar", label: "Ngữ pháp" },
  { key: "questions", label: "Question Bank" },
  { key: "tests", label: "Test Exams" }
] as const;

type TabKey = (typeof tabs)[number]["key"];

export const ContentLabPage = () => {
  const [tab, setTab] = useState<TabKey>("grammar");
  const [grammar, setGrammar] = useState<GrammarItem[]>([]);
  const [questions, setQuestions] = useState<QuestionItem[]>([]);
  const [tests, setTests] = useState<TestExam[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [grammarForm, setGrammarForm] = useState({
    title: "",
    level: "A1",
    topic: "",
    summary: "",
    content: "",
    tags: ""
  });
  const [questionForm, setQuestionForm] = useState({
    prompt: "",
    question_type: "mcq",
    difficulty_level: "A1",
    options: "",
    answer: "",
    explanation: "",
    tags: ""
  });
  const [testForm, setTestForm] = useState({
    title: "",
    description: "",
    level: "A1",
    duration_minutes: 20,
    passing_score: 70,
    question_ids: "",
    is_published: false
  });

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

  const handleCreateGrammar = async (event: React.FormEvent) => {
    event.preventDefault();
    try {
      await createGrammar({
        title: grammarForm.title,
        level: grammarForm.level,
        topic: grammarForm.topic || undefined,
        summary: grammarForm.summary || undefined,
        content: grammarForm.content,
        tags: grammarForm.tags.split(",").map((t) => t.trim()).filter(Boolean)
      });
      setGrammarForm({ title: "", level: "A1", topic: "", summary: "", content: "", tags: "" });
      await loadAll();
    } catch (err: any) {
      setError(err?.message || "Tạo grammar thất bại");
    }
  };

  const handleCreateQuestion = async (event: React.FormEvent) => {
    event.preventDefault();
    try {
      await createQuestion({
        prompt: questionForm.prompt,
        question_type: questionForm.question_type,
        difficulty_level: questionForm.difficulty_level,
        options: questionForm.options ? JSON.parse(questionForm.options) : undefined,
        answer: questionForm.answer ? JSON.parse(questionForm.answer) : undefined,
        explanation: questionForm.explanation || undefined,
        tags: questionForm.tags.split(",").map((t) => t.trim()).filter(Boolean)
      });
      setQuestionForm({
        prompt: "",
        question_type: "mcq",
        difficulty_level: "A1",
        options: "",
        answer: "",
        explanation: "",
        tags: ""
      });
      await loadAll();
    } catch (err: any) {
      setError(err?.message || "Tạo question thất bại");
    }
  };

  const handleCreateTest = async (event: React.FormEvent) => {
    event.preventDefault();
    try {
      await createTestExam({
        title: testForm.title,
        description: testForm.description || undefined,
        level: testForm.level,
        duration_minutes: Number(testForm.duration_minutes),
        passing_score: Number(testForm.passing_score),
        question_ids: testForm.question_ids
          ? testForm.question_ids.split(",").map((id) => id.trim()).filter(Boolean)
          : undefined,
        is_published: testForm.is_published
      });
      setTestForm({
        title: "",
        description: "",
        level: "A1",
        duration_minutes: 20,
        passing_score: 70,
        question_ids: "",
        is_published: false
      });
      await loadAll();
    } catch (err: any) {
      setError(err?.message || "Tạo test exam thất bại");
    }
  };

  return (
    <div className="panel">
      <SectionHeader title="Content Lab" description="Grammar / Questions / Test-Exam" />
      <div className="tab-row">
        {tabs.map((t) => (
          <button
            key={t.key}
            className={tab === t.key ? "tab active" : "tab"}
            onClick={() => setTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </div>
      {error && <div className="form-error">{error}</div>}
      {loading && <div className="loading">Đang tải dữ liệu...</div>}

      {tab === "grammar" && (
        <div className="grid-2">
          <div className="panel-inner">
            <SectionHeader title="Grammar list" />
            <DataTable
              columns={[
                {
                  header: "Tiêu đề",
                  render: (row) => (
                    <div>
                      <div className="table-title">{row.title}</div>
                      <div className="table-sub">{row.topic || ""}</div>
                    </div>
                  )
                },
                {
                  header: "Level",
                  render: (row) => <span className="table-meta">{row.level}</span>,
                  align: "center"
                },
                {
                  header: "Action",
                  render: (row) => (
                    <button className="ghost-button small danger" onClick={() => deleteGrammar(row.id).then(loadAll)}>
                      Xóa
                    </button>
                  ),
                  align: "right"
                }
              ]}
              rows={grammar}
            />
          </div>
          <div className="panel-inner">
            <SectionHeader title="Tạo Grammar" />
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
              <label>
                Tags (csv)
                <input value={grammarForm.tags} onChange={(e) => setGrammarForm({ ...grammarForm, tags: e.target.value })} />
              </label>
              <button className="primary-button" type="submit">Tạo</button>
            </form>
          </div>
        </div>
      )}

      {tab === "questions" && (
        <div className="grid-2">
          <div className="panel-inner">
            <SectionHeader title="Question bank" />
            <DataTable
              columns={[
                {
                  header: "Prompt",
                  render: (row) => (
                    <div>
                      <div className="table-title">{row.prompt.slice(0, 60)}...</div>
                      <div className="table-sub">{row.question_type}</div>
                    </div>
                  )
                },
                {
                  header: "Level",
                  render: (row) => <span className="table-meta">{row.difficulty_level}</span>,
                  align: "center"
                },
                {
                  header: "Action",
                  render: (row) => (
                    <button className="ghost-button small danger" onClick={() => deleteQuestion(row.id).then(loadAll)}>
                      Xóa
                    </button>
                  ),
                  align: "right"
                }
              ]}
              rows={questions}
            />
          </div>
          <div className="panel-inner">
            <SectionHeader title="Tạo Question" />
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
              <label>
                Options (JSON array)
                <textarea rows={2} value={questionForm.options} onChange={(e) => setQuestionForm({ ...questionForm, options: e.target.value })} />
              </label>
              <label>
                Answer (JSON)
                <textarea rows={2} value={questionForm.answer} onChange={(e) => setQuestionForm({ ...questionForm, answer: e.target.value })} />
              </label>
              <label>
                Explanation
                <textarea rows={2} value={questionForm.explanation} onChange={(e) => setQuestionForm({ ...questionForm, explanation: e.target.value })} />
              </label>
              <label>
                Tags (csv)
                <input value={questionForm.tags} onChange={(e) => setQuestionForm({ ...questionForm, tags: e.target.value })} />
              </label>
              <button className="primary-button" type="submit">Tạo</button>
            </form>
          </div>
        </div>
      )}

      {tab === "tests" && (
        <div className="grid-2">
          <div className="panel-inner">
            <SectionHeader title="Test exams" />
            <DataTable
              columns={[
                {
                  header: "Bài test",
                  render: (row) => (
                    <div>
                      <div className="table-title">{row.title}</div>
                      <div className="table-sub">{row.level} • {row.duration_minutes}m</div>
                    </div>
                  )
                },
                {
                  header: "Publish",
                  render: (row) => <span className="table-meta">{row.is_published ? "Yes" : "No"}</span>,
                  align: "center"
                },
                {
                  header: "Action",
                  render: (row) => (
                    <button className="ghost-button small danger" onClick={() => deleteTestExam(row.id).then(loadAll)}>
                      Xóa
                    </button>
                  ),
                  align: "right"
                }
              ]}
              rows={tests}
            />
          </div>
          <div className="panel-inner">
            <SectionHeader title="Tạo Test Exam" />
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
              <label>
                Question IDs (csv)
                <input
                  value={testForm.question_ids}
                  onChange={(e) => setTestForm({ ...testForm, question_ids: e.target.value })}
                />
              </label>
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked={testForm.is_published}
                  onChange={(e) => setTestForm({ ...testForm, is_published: e.target.checked })}
                />
                Publish
              </label>
              <button className="primary-button" type="submit">Tạo</button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
