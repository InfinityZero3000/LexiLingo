import React, { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, CheckCircle2, FileAudio, Plus, RefreshCw, Trash2 } from "lucide-react";

import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import {
  createIeltsTest,
  deleteIeltsTest,
  getIeltsTest,
  listIeltsAttempts,
  listIeltsTests,
  updateIeltsTest,
  uploadIeltsAudio,
  validateIeltsTest,
  type IeltsAttemptRow,
  type IeltsSkillScope,
  type IeltsTest,
  type IeltsTestType,
  type IeltsValidation,
} from "../lib/adminApi";

const TEST_TYPES: IeltsTestType[] = ["academic", "general_training"];
const SKILL_SCOPES: IeltsSkillScope[] = ["full", "listening", "reading", "writing", "speaking"];

/**
 * A skeleton paper. Authors start from this rather than an empty box because
 * the shape is unforgiving: a Listening question needs `key` and
 * `accepted_answers`, and a paper missing either cannot be published.
 */
const STARTER_CONTENT = {
  sections: [
    {
      skill: "listening",
      duration_minutes: 30,
      parts: [
        {
          order: 1,
          title: "Part 1",
          audio_url: "",
          transcript: "Paste the recording script here — learners never see it.",
          instructions: "Complete the notes below. Write ONE WORD ONLY for each answer.",
          question_groups: [
            {
              question_type: "note_completion",
              instructions: "Write ONE WORD ONLY.",
              questions: [
                { key: "L1", number: 1, prompt: "The meeting is on ___.", accepted_answers: ["Tuesday"] },
              ],
            },
          ],
        },
      ],
    },
    {
      skill: "reading",
      duration_minutes: 60,
      parts: [
        {
          order: 1,
          passage_title: "Passage 1",
          passage_text: "Paste the reading passage here.",
          question_groups: [
            {
              question_type: "true_false_notgiven",
              instructions: "Write TRUE, FALSE or NOT GIVEN.",
              questions: [
                { key: "R1", number: 1, prompt: "Statement to judge.", accepted_answers: ["TRUE"] },
              ],
            },
          ],
        },
      ],
    },
    {
      skill: "writing",
      duration_minutes: 60,
      parts: [
        {
          order: 1,
          part_key: "writing_task_1",
          prompt: "Describe the chart below.",
          image_url: "",
          min_words: 150,
          suggested_minutes: 20,
        },
        {
          order: 2,
          part_key: "writing_task_2",
          prompt: "Discuss both views and give your own opinion.",
          min_words: 250,
          suggested_minutes: 40,
        },
      ],
    },
    {
      skill: "speaking",
      duration_minutes: 14,
      parts: [
        {
          order: 1,
          part_key: "speaking_part_1",
          prompt: "Where do you live? Do you work or study?",
        },
        {
          order: 2,
          part_key: "speaking_part_2",
          cue_card: "Describe a book you enjoyed reading.",
          prep_seconds: 60,
          speak_seconds: 120,
        },
        {
          order: 3,
          part_key: "speaking_part_3",
          prompt: "Do people read less than they used to? Why?",
        },
      ],
    },
  ],
};

type Draft = {
  title: string;
  description: string;
  test_type: IeltsTestType;
  skill_scope: IeltsSkillScope;
  target_band: string;
  contentText: string;
};

const emptyDraft = (): Draft => ({
  title: "",
  description: "",
  test_type: "academic",
  skill_scope: "full",
  target_band: "",
  contentText: JSON.stringify(STARTER_CONTENT, null, 2),
});

export const IeltsTestsPage = () => {
  const [tests, setTests] = useState<IeltsTest[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [draft, setDraft] = useState<Draft>(emptyDraft());
  const [validation, setValidation] = useState<IeltsValidation | null>(null);
  const [attempts, setAttempts] = useState<IeltsAttemptRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const selected = useMemo(
    () => tests.find((t) => t.id === selectedId) ?? null,
    [tests, selectedId]
  );

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const response = await listIeltsTests();
      setTests(response.data ?? []);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load tests");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const contentError = useMemo(() => {
    if (!draft.contentText.trim()) return null;
    try {
      JSON.parse(draft.contentText);
      return null;
    } catch (err) {
      return err instanceof Error ? err.message : "Invalid JSON";
    }
  }, [draft.contentText]);

  const openTest = async (id: string) => {
    setSelectedId(id);
    setValidation(null);
    setNotice(null);
    try {
      const [detail, attemptList] = await Promise.all([
        getIeltsTest(id),
        listIeltsAttempts(id),
      ]);
      const test = detail.data;
      if (test) {
        setDraft({
          title: test.title,
          description: test.description ?? "",
          test_type: test.test_type,
          skill_scope: test.skill_scope,
          target_band: test.target_band ?? "",
          contentText: JSON.stringify(test.content ?? { sections: [] }, null, 2),
        });
      }
      setAttempts(attemptList.data ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open test");
    }
  };

  const startNew = () => {
    setSelectedId(null);
    setDraft(emptyDraft());
    setValidation(null);
    setAttempts([]);
    setNotice(null);
  };

  const save = async () => {
    if (contentError) return;
    setBusy(true);
    setNotice(null);
    try {
      const payload = {
        title: draft.title.trim(),
        description: draft.description.trim() || null,
        test_type: draft.test_type,
        skill_scope: draft.skill_scope,
        target_band: draft.target_band.trim() || null,
        content: JSON.parse(draft.contentText || "{}"),
      };
      if (selectedId) {
        await updateIeltsTest(selectedId, payload);
        setNotice("Saved");
      } else {
        const created = await createIeltsTest(payload);
        setSelectedId(created.data?.id ?? null);
        setNotice("Created as a draft — validate it before publishing");
      }
      await refresh();
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    } finally {
      setBusy(false);
    }
  };

  const runValidation = async () => {
    if (!selectedId) return;
    setBusy(true);
    try {
      const response = await validateIeltsTest(selectedId);
      setValidation(response.data ?? null);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Validation failed");
    } finally {
      setBusy(false);
    }
  };

  const togglePublish = async () => {
    if (!selectedId || !selected) return;
    setBusy(true);
    try {
      await updateIeltsTest(selectedId, {
        title: draft.title,
        is_published: !selected.is_published,
      });
      setNotice(selected.is_published ? "Unpublished" : "Published");
      setError(null);
      await refresh();
    } catch (err) {
      // The publish gate returns the blocking problems — surface them rather
      // than a bare 400, because the whole point is telling the author what to fix.
      setError(err instanceof Error ? err.message : "Publish failed");
      await runValidation();
    } finally {
      setBusy(false);
    }
  };

  const removeTest = async (id: string) => {
    setBusy(true);
    try {
      await deleteIeltsTest(id);
      if (selectedId === id) startNew();
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Delete failed");
    } finally {
      setBusy(false);
    }
  };

  const handleAudioUpload = async (file: File) => {
    setBusy(true);
    try {
      const response = await uploadIeltsAudio(file);
      const url = response.data?.url;
      if (url) {
        await navigator.clipboard?.writeText(url).catch(() => undefined);
        setNotice(`Audio uploaded — URL copied: ${url}`);
      }
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Audio upload failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="stack">
      <SectionHeader
        title="IELTS mock tests"
        description="Author four-skill papers. Listening and Reading are graded from the answer key; Writing and Speaking are graded by AI against the band descriptors."
        action={
          <button className="primary-button" onClick={startNew} type="button">
            <Plus size={16} /> New test
          </button>
        }
      />

      {error && (
        <div className="panel form-error" role="alert">
          <AlertTriangle size={16} /> {error}
        </div>
      )}
      {notice && <div className="panel">{notice}</div>}

      <div className="panel">
        {loading ? (
          <TableSkeleton />
        ) : tests.length === 0 ? (
          <EmptyState
            title="No IELTS tests yet"
            description="Create one to get a starter paper with all four sections."
          />
        ) : (
          <table>
            <thead>
              <tr>
                <th>Title</th>
                <th>Type</th>
                <th>Scope</th>
                <th>Questions</th>
                <th>Attempts</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {tests.map((test) => (
                <tr
                  key={test.id}
                  onClick={() => void openTest(test.id)}
                  style={{ cursor: "pointer" }}
                  aria-selected={test.id === selectedId}
                >
                  <td>
                    <div className="table-title">{test.title}</div>
                    {test.target_band && (
                      <div className="table-sub">Target {test.target_band}</div>
                    )}
                  </td>
                  <td>{test.test_type === "academic" ? "Academic" : "General Training"}</td>
                  <td>{test.skill_scope}</td>
                  <td>{test.question_count}</td>
                  <td>{test.attempt_count}</td>
                  <td>
                    <StatusPill
                      tone={test.is_published ? "success" : "warning"}
                      label={test.is_published ? "Published" : "Draft"}
                    />
                  </td>
                  <td>
                    <button
                      className="ghost-button small"
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation();
                        void removeTest(test.id);
                      }}
                      aria-label={`Delete ${test.title}`}
                    >
                      <Trash2 size={14} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="panel stack">
        <SectionHeader
          title={selectedId ? "Edit test" : "New test"}
          description={
            selectedId
              ? "Validate before publishing — the gate refuses a paper a learner could not finish."
              : "Starts from a four-section skeleton you can edit."
          }
        />

        <div className="form-grid">
          <label>
            Title
            <input
              value={draft.title}
              onChange={(e) => setDraft({ ...draft, title: e.target.value })}
              placeholder="IELTS Academic Mock 1"
            />
          </label>
          <label>
            Target band
            <input
              value={draft.target_band}
              onChange={(e) => setDraft({ ...draft, target_band: e.target.value })}
              placeholder="6.0-7.0"
            />
          </label>
          <label>
            Test type
            <select
              value={draft.test_type}
              onChange={(e) =>
                setDraft({ ...draft, test_type: e.target.value as IeltsTestType })
              }
            >
              {TEST_TYPES.map((type) => (
                <option key={type} value={type}>
                  {type === "academic" ? "Academic" : "General Training"}
                </option>
              ))}
            </select>
          </label>
          <label>
            Skill scope
            <select
              value={draft.skill_scope}
              onChange={(e) =>
                setDraft({ ...draft, skill_scope: e.target.value as IeltsSkillScope })
              }
            >
              {SKILL_SCOPES.map((scope) => (
                <option key={scope} value={scope}>
                  {scope === "full" ? "Full test (all four skills)" : `${scope} only`}
                </option>
              ))}
            </select>
          </label>
        </div>

        <label>
          Description
          <textarea
            rows={2}
            value={draft.description}
            onChange={(e) => setDraft({ ...draft, description: e.target.value })}
          />
        </label>

        <label>
          Paper content (JSON)
          <textarea
            rows={20}
            spellCheck={false}
            style={{ fontFamily: "ui-monospace, monospace", fontSize: 13 }}
            value={draft.contentText}
            onChange={(e) => setDraft({ ...draft, contentText: e.target.value })}
          />
        </label>
        {contentError && (
          <div className="form-error">
            <AlertTriangle size={14} /> JSON error: {contentError}
          </div>
        )}

        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <button
            className="primary-button"
            type="button"
            onClick={() => void save()}
            disabled={busy || !draft.title.trim() || Boolean(contentError)}
          >
            {selectedId ? "Save changes" : "Create draft"}
          </button>
          <button
            className="ghost-button"
            type="button"
            onClick={() => void runValidation()}
            disabled={busy || !selectedId}
          >
            <RefreshCw size={14} /> Validate
          </button>
          <button
            className="ghost-button"
            type="button"
            onClick={() => void togglePublish()}
            disabled={busy || !selectedId}
          >
            {selected?.is_published ? "Unpublish" : "Publish"}
          </button>
          <label className="ghost-button" style={{ cursor: "pointer" }}>
            <FileAudio size={14} /> Upload listening audio
            <input
              type="file"
              accept="audio/*"
              style={{ display: "none" }}
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) void handleAudioUpload(file);
                e.target.value = "";
              }}
            />
          </label>
        </div>

        {validation && (
          <div className="panel">
            {validation.publishable ? (
              <div>
                <CheckCircle2 size={16} /> Ready to publish — Listening{" "}
                {validation.counts.listening ?? 0} questions, Reading{" "}
                {validation.counts.reading ?? 0}, {validation.counts.productive_parts ?? 0}{" "}
                AI-graded parts.
              </div>
            ) : (
              <div>
                <div className="form-error">
                  <AlertTriangle size={16} /> {validation.problems.length} problem
                  {validation.problems.length === 1 ? "" : "s"} blocking publish:
                </div>
                <ul>
                  {validation.problems.map((problem) => (
                    <li key={problem}>{problem}</li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}

        {attempts.length > 0 && (
          <div className="panel">
            <SectionHeader title="Recent attempts" description={`${attempts.length} shown`} />
            <table>
              <thead>
                <tr>
                  <th>Attempt</th>
                  <th>Status</th>
                  <th>Overall band</th>
                  <th>Submitted</th>
                </tr>
              </thead>
              <tbody>
                {attempts.map((attempt) => (
                  <tr key={attempt.attempt_id}>
                    <td className="table-meta">{attempt.attempt_id.slice(0, 8)}</td>
                    <td>{attempt.status}</td>
                    <td>{attempt.overall_band ?? "—"}</td>
                    <td className="table-meta">
                      {attempt.submitted_at
                        ? new Date(attempt.submitted_at).toLocaleString()
                        : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};
