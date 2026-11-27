import React, { useEffect, useMemo, useState } from "react";
import { Copy, MessageSquare, Pencil, Search } from "lucide-react";
import { useI18n } from "../lib/i18n";
import { DataTable } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { SectionHeader } from "../components/SectionHeader";
import { StatusPill } from "../components/StatusPill";
import { TableSkeleton } from "../components/Skeleton";
import { TopicForm, type TopicFormMode } from "../components/topics/TopicForm";
import { iconFor } from "../components/topics/topicIcons";
import {
  getTopicStoryAdmin,
  listTopicStoriesAdmin,
  type TopicDifficulty,
  type TopicItem,
} from "../lib/adminApi";
import { DIFFICULTIES, emptyForm, formFromStory, type TopicFormState } from "../lib/topicForm";

type SourceFilter = "all" | "custom" | "builtin";
type Editor = { mode: TopicFormMode; initial: TopicFormState; key: number };

const levelTone = (level: string): "info" | "success" | "warning" | "danger" => {
  if (level === "B1" || level === "B2") return "success";
  if (level === "C1") return "warning";
  if (level === "C2") return "danger";
  return "info";
};

export const TopicsPage = () => {
  const { t } = useI18n();
  const [topics, setTopics] = useState<TopicItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editor, setEditor] = useState<Editor | null>(null);
  const [opening, setOpening] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [source, setSource] = useState<SourceFilter>("all");
  const [level, setLevel] = useState<"" | TopicDifficulty>("");

  const loadTopics = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await listTopicStoriesAdmin();
      setTopics(res.data?.topics || []);
    } catch (err: any) {
      setError(err?.message || t.adminPages.topicsLoadFailed);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadTopics();
  }, []);

  const openEditor = (mode: TopicFormMode, initial: TopicFormState) => {
    setNotice(null);
    setEditor({ mode, initial, key: Date.now() });
  };

  /** Loads the full story first: the list only carries what a card shows. */
  const openExisting = async (mode: "edit" | "clone", topic: TopicItem) => {
    setOpening(topic.story_id);
    setError(null);
    try {
      const res = await getTopicStoryAdmin(topic.story_id);
      if (!res.data) throw new Error("Topic not found");
      openEditor(mode, formFromStory(res.data, mode));
    } catch (err: any) {
      setError(err?.message || t.adminPages.topicsLoadFailed);
    } finally {
      setOpening(null);
    }
  };

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return topics.filter((topic) => {
      if (source !== "all" && (topic.source ?? "custom") !== source) return false;
      if (level && topic.difficulty_level !== level) return false;
      if (!needle) return true;
      return [topic.title.en, topic.title.vi, topic.category, topic.story_id].some((v) => v.toLowerCase().includes(needle));
    });
  }, [topics, query, source, level]);

  const customCount = topics.filter((topic) => (topic.source ?? "custom") === "custom").length;

  return (
    <div className="stack">
      <SectionHeader
        title="Conversation Topics"
        description={`${topics.length} topics: ${customCount} created here, ${topics.length - customCount} built in`}
        action={
          <button
            className="primary-button small"
            style={{ borderRadius: 999 }}
            onClick={() => (editor?.mode === "create" ? setEditor(null) : openEditor("create", emptyForm()))}
          >
            {editor?.mode === "create" ? t.adminPages.topicsHideForm : t.adminPages.topicsCreate}
          </button>
        }
      />

      {error && <div className="form-error" role="alert">{error}</div>}
      {notice && <div className="form-hint" role="status">{notice}</div>}

      {editor && (
        <TopicForm
          key={editor.key}
          mode={editor.mode}
          initial={editor.initial}
          onCancel={() => setEditor(null)}
          onSaved={() => {
            setEditor(null);
            setNotice("Topic saved. Learners see it now.");
            void loadTopics();
          }}
        />
      )}

      <div className="panel filter-panel">
        <div className="filter-bar">
          <div className="filter-search-form">
            <input
              className="search-input"
              aria-label="Search"
              placeholder="title, category or id"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
            <span className="filter-search-button" aria-hidden="true" style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", pointerEvents: "none" }}>
              <Search size={16} />
            </span>
          </div>
          <select
            className="filter-select"
            aria-label="Level"
            value={level}
            onChange={(e) => setLevel(e.target.value as "" | TopicDifficulty)}
          >
            <option value="">All levels</option>
            {DIFFICULTIES.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
          <div
            className="tab-row"
            role="group"
            aria-label="Source"
            style={{
              display: "inline-flex",
              gap: 4,
              padding: 4,
              borderRadius: 999,
              background: "var(--panel-soft-2, #F8FAFC)",
              border: "1px solid var(--line)",
            }}
          >
            {(
              [
                ["all", "All"],
                ["custom", "Created here"],
                ["builtin", "Built in"],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                type="button"
                className={`tab${source === key ? " active" : ""}`}
                style={{ borderRadius: 999 }}
                aria-pressed={source === key}
                onClick={() => setSource(key)}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="panel">
        {loading ? (
          <TableSkeleton rows={5} cols={5} />
        ) : topics.length === 0 ? (
          <EmptyState
            title="No topics"
            description="Create the first topic from this admin panel."
            icon={<MessageSquare size={40} aria-hidden="true" />}
            action={<button className="primary-button" onClick={() => openEditor("create", emptyForm())}>Create Topic</button>}
          />
        ) : visible.length === 0 ? (
          <EmptyState
            title="No topic matches"
            description="Change the search or the filters."
            icon={<Search size={40} aria-hidden="true" />}
          />
        ) : (
          <DataTable
            columns={[
              {
                header: "Topic",
                sortValue: (row) => row.title.en,
                render: (row) => {
                  const Icon = iconFor(row.icon_key, row.category);
                  return (
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <span className="stat-icon" style={{ width: 36, height: 36 }}>
                        <Icon size={18} aria-hidden="true" />
                      </span>
                      <div>
                        <div className="table-title">{row.title.en}</div>
                        <div className="table-sub">{row.title.vi}</div>
                      </div>
                    </div>
                  );
                },
              },
              {
                header: "Source",
                sortValue: (row) => row.source ?? "custom",
                render: (row) =>
                  (row.source ?? "custom") === "builtin"
                    ? <StatusPill tone="neutral" label="Built in" />
                    : <StatusPill tone="success" label="Created here" />,
              },
              { header: "Category", sortValue: (row) => row.category, render: (row) => <StatusPill tone="info" label={row.category} /> },
              { header: "Level", sortValue: (row) => row.difficulty_level, render: (row) => <StatusPill tone={levelTone(row.difficulty_level)} label={row.difficulty_level} />, align: "center" },
              { header: "Minutes", sortValue: (row) => row.estimated_minutes, render: (row) => <span className="table-meta">{row.estimated_minutes}</span>, align: "center" },
              {
                header: "",
                render: (row) => (
                  <div className="inline-actions" style={{ justifyContent: "flex-end" }}>
                    {(row.source ?? "custom") === "custom" && (
                      <button
                        className="ghost-button small"
                        type="button"
                        disabled={opening === row.story_id}
                        onClick={() => void openExisting("edit", row)}
                      >
                        <Pencil size={13} aria-hidden="true" /> {t.adminPages.topicsEdit}
                      </button>
                    )}
                    <button
                      className="ghost-button small"
                      type="button"
                      disabled={opening === row.story_id}
                      onClick={() => void openExisting("clone", row)}
                    >
                      <Copy size={13} aria-hidden="true" /> Clone
                    </button>
                  </div>
                ),
                align: "right",
              },
            ]}
            rows={visible}
            rowKey={(row) => row.story_id}
          />
        )}
      </div>
    </div>
  );
};
