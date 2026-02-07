import React, { useState } from "react";
import {
  createCourse,
  createUnit,
  createLesson,
  type CourseItem,
} from "../lib/adminApi";

type ImportTab = "text" | "json" | "csv";

interface ImportResult {
  courses: number;
  units: number;
  lessons: number;
  errors: string[];
}

const SAMPLE_TEXT = `# English for Daily Life
Mô tả: Learn English through everyday situations
Ngôn ngữ: en
Trình độ: A2
Tags: daily, conversation, beginner
Xuất bản: true

## Unit 1: At Home
Mô tả: Vocabulary and phrases for home activities

### Lesson 1: Morning Routine
Mô tả: Learn to describe your morning activities
Loại: lesson
XP: 15

### Lesson 2: Cooking & Kitchen
Mô tả: Kitchen vocabulary and cooking instructions
Loại: lesson
XP: 15

## Unit 2: At Work
Mô tả: Office and workplace English

### Lesson 1: Meeting People
Mô tả: Greetings and introductions at work
Loại: lesson
XP: 10

### Lesson 2: Making Requests
Mô tả: Polite requests and offers
Loại: lesson
XP: 10
`;

const SAMPLE_JSON = `[
  {
    "title": "English for Daily Life",
    "description": "Learn English through everyday situations",
    "language": "en",
    "level": "A2",
    "tags": ["daily", "conversation"],
    "is_published": true,
    "units": [
      {
        "title": "At Home",
        "description": "Vocabulary and phrases for home",
        "lessons": [
          {
            "title": "Morning Routine",
            "description": "Morning activities",
            "lesson_type": "lesson",
            "xp_reward": 15
          }
        ]
      }
    ]
  }
]`;

const SAMPLE_CSV = `course_title,course_description,course_language,course_level,course_tags,course_published,unit_title,unit_description,lesson_title,lesson_description,lesson_type,lesson_xp
English for Daily Life,Learn English everyday,en,A2,"daily,conversation",true,At Home,Home vocabulary,Morning Routine,Morning activities,lesson,15
English for Daily Life,Learn English everyday,en,A2,"daily,conversation",true,At Home,Home vocabulary,Cooking & Kitchen,Kitchen vocabulary,lesson,15
English for Daily Life,Learn English everyday,en,A2,"daily,conversation",true,At Work,Office English,Meeting People,Greetings at work,lesson,10`;

// Parse text format (Markdown-like)
function parseTextFormat(text: string): any[] {
  const courses: any[] = [];
  let currentCourse: any = null;
  let currentUnit: any = null;

  const lines = text.split("\n");

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    // Course title (# heading)
    if (line.startsWith("# ") && !line.startsWith("## ") && !line.startsWith("### ")) {
      currentCourse = {
        title: line.replace(/^#\s+/, ""),
        description: "",
        language: "en",
        level: "A1",
        tags: [],
        is_published: false,
        units: [],
      };
      courses.push(currentCourse);
      currentUnit = null;
      continue;
    }

    // Unit title (## heading)
    if (line.startsWith("## ") && !line.startsWith("### ") && currentCourse) {
      currentUnit = {
        title: line.replace(/^##\s+/, "").replace(/^Unit\s*\d+:\s*/i, ""),
        description: "",
        lessons: [],
      };
      currentCourse.units.push(currentUnit);
      continue;
    }

    // Lesson title (### heading)
    if (line.startsWith("### ") && currentUnit) {
      const lesson: any = {
        title: line.replace(/^###\s+/, "").replace(/^Lesson\s*\d+:\s*/i, ""),
        description: "",
        lesson_type: "lesson",
        xp_reward: 10,
      };
      currentUnit.lessons.push(lesson);
      continue;
    }

    // Properties (key: value)
    const propMatch = line.match(/^(Mô tả|Ngôn ngữ|Trình độ|Tags|Xuất bản|Loại|XP|Description|Language|Level|Type|Published):\s*(.+)$/i);
    if (propMatch) {
      const key = propMatch[1].toLowerCase();
      const val = propMatch[2].trim();

      // Determine target: last lesson > last unit > current course
      const lastLesson = currentUnit?.lessons?.[currentUnit.lessons.length - 1];

      if (key === "mô tả" || key === "description") {
        if (lastLesson && currentUnit.lessons.length > 0) lastLesson.description = val;
        else if (currentUnit) currentUnit.description = val;
        else if (currentCourse) currentCourse.description = val;
      } else if ((key === "ngôn ngữ" || key === "language") && currentCourse) {
        currentCourse.language = val;
      } else if ((key === "trình độ" || key === "level") && currentCourse) {
        currentCourse.level = val;
      } else if (key === "tags" && currentCourse) {
        currentCourse.tags = val.split(",").map((t: string) => t.trim()).filter(Boolean);
      } else if ((key === "xuất bản" || key === "published") && currentCourse) {
        currentCourse.is_published = val === "true" || val === "có" || val === "yes";
      } else if ((key === "loại" || key === "type") && lastLesson) {
        lastLesson.lesson_type = val;
      } else if (key === "xp" && lastLesson) {
        lastLesson.xp_reward = parseInt(val) || 10;
      }
    }
  }

  return courses;
}

// Parse CSV format
function parseCSV(text: string): any[] {
  const lines = text.split("\n").filter((l) => l.trim());
  if (lines.length < 2) return [];

  const headers = lines[0].split(",").map((h) => h.trim().toLowerCase());
  const courseMap = new Map<string, any>();

  for (let i = 1; i < lines.length; i++) {
    const values = parseCSVLine(lines[i]);
    const row: Record<string, string> = {};
    headers.forEach((h, idx) => (row[h] = (values[idx] || "").trim()));

    const courseTitle = row["course_title"];
    if (!courseTitle) continue;

    if (!courseMap.has(courseTitle)) {
      courseMap.set(courseTitle, {
        title: courseTitle,
        description: row["course_description"] || "",
        language: row["course_language"] || "en",
        level: row["course_level"] || "A1",
        tags: (row["course_tags"] || "").split(",").map((t) => t.trim().replace(/^"|"$/g, "")).filter(Boolean),
        is_published: row["course_published"] === "true",
        units: [],
      });
    }

    const course = courseMap.get(courseTitle);
    const unitTitle = row["unit_title"];
    if (!unitTitle) continue;

    let unit = course.units.find((u: any) => u.title === unitTitle);
    if (!unit) {
      unit = { title: unitTitle, description: row["unit_description"] || "", lessons: [] };
      course.units.push(unit);
    }

    const lessonTitle = row["lesson_title"];
    if (lessonTitle) {
      unit.lessons.push({
        title: lessonTitle,
        description: row["lesson_description"] || "",
        lesson_type: row["lesson_type"] || "lesson",
        xp_reward: parseInt(row["lesson_xp"] || "10") || 10,
      });
    }
  }

  return Array.from(courseMap.values());
}

function parseCSVLine(line: string): string[] {
  const result: string[] = [];
  let current = "";
  let inQuotes = false;

  for (const char of line) {
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === "," && !inQuotes) {
      result.push(current);
      current = "";
    } else {
      current += char;
    }
  }
  result.push(current);
  return result;
}

// Import courses via API
async function importCoursesToAPI(courses: any[]): Promise<ImportResult> {
  const result: ImportResult = { courses: 0, units: 0, lessons: 0, errors: [] };

  for (const courseData of courses) {
    try {
      const res = await createCourse({
        title: courseData.title,
        description: courseData.description || "",
        language: courseData.language || "en",
        level: courseData.level || "A1",
        tags: courseData.tags || [],
        thumbnail_url: courseData.thumbnail_url || "",
        is_published: courseData.is_published || false,
      });

      const courseId = res.data?.id;
      if (!courseId) {
        result.errors.push(`Tạo khóa học "${courseData.title}" thất bại`);
        continue;
      }
      result.courses++;

      // Create units
      if (courseData.units) {
        for (let ui = 0; ui < courseData.units.length; ui++) {
          const unitData = courseData.units[ui];
          try {
            const unitRes = await createUnit({
              course_id: courseId,
              title: unitData.title,
              description: unitData.description || "",
              order_index: ui + 1,
              background_color: unitData.background_color || "",
              icon_url: unitData.icon_url || "",
            });

            const unitId = unitRes.data?.id;
            if (!unitId) {
              result.errors.push(`Tạo chương "${unitData.title}" thất bại`);
              continue;
            }
            result.units++;

            // Create lessons
            if (unitData.lessons) {
              for (let li = 0; li < unitData.lessons.length; li++) {
                const lessonData = unitData.lessons[li];
                try {
                  await createLesson({
                    unit_id: unitId,
                    title: lessonData.title,
                    description: lessonData.description || "",
                    order_index: li + 1,
                    lesson_type: lessonData.lesson_type || "lesson",
                    xp_reward: lessonData.xp_reward || 10,
                    pass_threshold: lessonData.pass_threshold || 80,
                  });
                  result.lessons++;
                } catch (err: any) {
                  result.errors.push(`Bài học "${lessonData.title}": ${err?.message || "lỗi"}`);
                }
              }
            }
          } catch (err: any) {
            result.errors.push(`Chương "${unitData.title}": ${err?.message || "lỗi"}`);
          }
        }
      }
    } catch (err: any) {
      result.errors.push(`Khóa học "${courseData.title}": ${err?.message || "lỗi"}`);
    }
  }

  return result;
}

export const CourseImportModal = ({
  onClose,
  onImported,
}: {
  onClose: () => void;
  onImported: () => void;
}) => {
  const [tab, setTab] = useState<ImportTab>("text");
  const [textInput, setTextInput] = useState("");
  const [preview, setPreview] = useState<any[] | null>(null);
  const [importing, setImporting] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);

  const handleParse = () => {
    setParseError(null);
    setResult(null);
    try {
      let parsed: any[];
      if (tab === "text") {
        parsed = parseTextFormat(textInput);
      } else if (tab === "json") {
        const json = JSON.parse(textInput);
        parsed = Array.isArray(json) ? json : [json];
      } else {
        parsed = parseCSV(textInput);
      }

      if (parsed.length === 0) {
        setParseError("Không tìm thấy dữ liệu hợp lệ. Kiểm tra lại định dạng.");
        return;
      }
      setPreview(parsed);
    } catch (err: any) {
      setParseError(`Lỗi phân tích: ${err?.message || "Định dạng không hợp lệ"}`);
    }
  };

  const handleImport = async () => {
    if (!preview) return;
    setImporting(true);
    setResult(null);
    try {
      const res = await importCoursesToAPI(preview);
      setResult(res);
      if (res.courses > 0) onImported();
    } catch (err: any) {
      setResult({ courses: 0, units: 0, lessons: 0, errors: [err?.message || "Import thất bại"] });
    } finally {
      setImporting(false);
    }
  };

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (ev) => {
      const content = ev.target?.result as string;
      setTextInput(content);

      // Auto-detect format
      const ext = file.name.split(".").pop()?.toLowerCase();
      if (ext === "json") setTab("json");
      else if (ext === "csv") setTab("csv");
      else setTab("text");

      setPreview(null);
      setResult(null);
    };
    reader.readAsText(file);
  };

  const loadSample = () => {
    if (tab === "text") setTextInput(SAMPLE_TEXT);
    else if (tab === "json") setTextInput(SAMPLE_JSON);
    else setTextInput(SAMPLE_CSV);
    setPreview(null);
    setResult(null);
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 720, maxHeight: "90vh", display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
          <h3 style={{ margin: 0 }}>Nhập dữ liệu khóa học</h3>
          <button className="ghost-button small" onClick={onClose} style={{ fontSize: 18, padding: "4px 8px" }}>&times;</button>
        </div>

        {/* Tab bar */}
        <div style={{ display: "flex", gap: 4, marginBottom: 16 }}>
          {([
            { key: "text" as ImportTab, label: "Văn bản" },
            { key: "json" as ImportTab, label: "JSON" },
            { key: "csv" as ImportTab, label: "CSV" },
          ]).map((t) => (
            <button
              key={t.key}
              className={tab === t.key ? "tab active" : "tab"}
              onClick={() => { setTab(t.key); setPreview(null); setResult(null); setParseError(null); }}
            >
              {t.label}
            </button>
          ))}
        </div>

        {/* File upload */}
        <div style={{ display: "flex", gap: 8, marginBottom: 12, alignItems: "center" }}>
          <label className="ghost-button small" style={{ cursor: "pointer" }}>
            Tải file lên
            <input type="file" accept=".txt,.md,.json,.csv,.xlsx" onChange={handleFileUpload} style={{ display: "none" }} />
          </label>
          <button className="ghost-button small" onClick={loadSample}>Xem mẫu</button>
          <span style={{ fontSize: 12, color: "var(--muted)" }}>
            Hỗ trợ: .txt, .md, .json, .csv
          </span>
        </div>

        {/* Text area */}
        <div style={{ flex: 1, minHeight: 0 }}>
          <textarea
            value={textInput}
            onChange={(e) => { setTextInput(e.target.value); setPreview(null); setResult(null); }}
            placeholder={tab === "text"
              ? "# Tên khóa học\n## Unit 1: Tên chương\n### Lesson 1: Tên bài học"
              : tab === "json"
              ? '[{"title": "...", "units": [...]}]'
              : "course_title,unit_title,lesson_title,..."}
            style={{
              width: "100%",
              height: 200,
              fontFamily: "monospace",
              fontSize: 13,
              resize: "vertical",
              borderRadius: 8,
              border: "1px solid var(--line)",
              padding: 12,
              background: "var(--panel-soft)",
            }}
          />
        </div>

        {parseError && <div className="form-error" style={{ marginTop: 8 }}>{parseError}</div>}

        {/* Preview */}
        {preview && (
          <div style={{ marginTop: 12, padding: 12, background: "var(--panel-soft)", borderRadius: 8, maxHeight: 200, overflow: "auto" }}>
            <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 8, color: "var(--text)" }}>
              Xem trước ({preview.length} khóa học)
            </div>
            {preview.map((course, i) => (
              <div key={i} style={{ marginBottom: 8 }}>
                <div style={{ fontWeight: 600, fontSize: 13 }}>
                  {course.title} <span style={{ color: "var(--muted)", fontWeight: 400 }}>({course.level} · {course.language})</span>
                </div>
                {course.units?.map((unit: any, ui: number) => (
                  <div key={ui} style={{ paddingLeft: 16, fontSize: 12, color: "var(--muted)" }}>
                    {unit.title} — {unit.lessons?.length || 0} bài học
                  </div>
                ))}
              </div>
            ))}
          </div>
        )}

        {/* Result */}
        {result && (
          <div style={{
            marginTop: 12,
            padding: 12,
            background: result.errors.length === 0 ? "rgba(42, 167, 161, 0.08)" : "rgba(255, 77, 0, 0.06)",
            borderRadius: 8,
            border: `1px solid ${result.errors.length === 0 ? "rgba(42, 167, 161, 0.2)" : "rgba(255, 77, 0, 0.15)"}`,
          }}>
            <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>
              {result.errors.length === 0 ? "Nhập thành công!" : "Kết quả nhập dữ liệu"}
            </div>
            <div style={{ fontSize: 12, color: "var(--muted)" }}>
              {result.courses} khóa học · {result.units} chương · {result.lessons} bài học
            </div>
            {result.errors.length > 0 && (
              <div style={{ marginTop: 8, fontSize: 12, color: "var(--accent)" }}>
                {result.errors.map((err, i) => <div key={i}>- {err}</div>)}
              </div>
            )}
          </div>
        )}

        {/* Actions */}
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 16 }}>
          <button className="ghost-button" onClick={onClose}>Đóng</button>
          {!preview ? (
            <button className="primary-button" onClick={handleParse} disabled={!textInput.trim()}>
              Phân tích dữ liệu
            </button>
          ) : (
            <button className="primary-button" onClick={handleImport} disabled={importing}>
              {importing ? "Đang nhập..." : `Nhập ${preview.length} khóa học`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
