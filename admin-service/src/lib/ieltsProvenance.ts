// Mirror of backend-service/app/core/content_licenses.py (passage_license_problem) and
// provenance_problems in app/routes/admin_ielts.py, so the admin sees why publish would be
// refused before clicking it. The backend stays the authority.

export type IeltsPassageProvenance = {
  section?: string;
  title?: string;
  license_id?: string;
  attribution?: string;
  source_url?: string;
  retrieved_at?: string;
  adapted?: boolean;
  revision?: string | number;
};

export type IeltsProvenance = { passages?: IeltsPassageProvenance[] } | null | undefined;

const ALLOWED_LICENSE_IDS = new Set([
  "CC0-1.0",
  "CC-BY-2.0-FR",
  "CC-BY-4.0",
  "LicenseRef-CMUdict",
  "LicenseRef-CEFR-J-Commercial",
  "LicenseRef-Admin-Owned",
  "LicenseRef-Generated",
  "CC-BY-SA-4.0",
  "CC-BY-SA-3.0",
  "LicenseRef-Public-Domain",
  "LicenseRef-US-Gov-Public-Domain",
]);
const PASSAGE_FORBIDDEN = new Set(["LicenseRef-CEFR-J-Commercial", "LicenseRef-CMUdict"]);

export type PassageProblem =
  | { kind: "missing" }
  | { kind: "invalid_license"; got: string }
  | { kind: "forbidden_license"; license: string }
  | { kind: "missing_field"; license: string; field: "attribution" | "source_url" };

export const passageLicenseProblem = (entry: IeltsPassageProvenance | undefined): PassageProblem | null => {
  if (!entry) return { kind: "missing" };
  const id = entry.license_id;
  if (typeof id !== "string" || !ALLOWED_LICENSE_IDS.has(id)) {
    return { kind: "invalid_license", got: String(id) };
  }
  if (PASSAGE_FORBIDDEN.has(id)) return { kind: "forbidden_license", license: id };
  if (id.startsWith("CC-BY")) {
    for (const field of ["attribution", "source_url"] as const) {
      const value = entry[field];
      if (typeof value !== "string" || !value.trim()) return { kind: "missing_field", license: id, field };
    }
  }
  return null;
};

export type ReadingPassageRow = {
  order: number;
  title: string | null;
  entry: IeltsPassageProvenance | undefined;
  problem: PassageProblem | null;
};

type Json = Record<string, unknown>;
const isObj = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v);

export const readingPassageRows = (content: unknown, provenance: IeltsProvenance): ReadingPassageRow[] => {
  const entries = (provenance?.passages ?? []).filter(isObj) as IeltsPassageProvenance[];
  const rows: ReadingPassageRow[] = [];
  const sections = isObj(content) && Array.isArray(content.sections) ? content.sections : [];
  for (const section of sections) {
    if (!isObj(section) || String(section.skill ?? "").toLowerCase() !== "reading") continue;
    const parts = Array.isArray(section.parts) ? section.parts : [];
    parts.forEach((part, index) => {
      if (!isObj(part)) return;
      const order = Number(part.order) || index + 1;
      const title = (part.passage_title as string) || (part.title as string) || null;
      const entry = entries.find((e) => e.section === `reading:${order}` || (title && e.title === title));
      rows.push({ order, title, entry, problem: passageLicenseProblem(entry) });
    });
  }
  return rows;
};

// Only http(s) links are rendered as anchors; anything else (javascript:, data:) stays text.
export const safeHttpUrl = (value: string | undefined): string | null => {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
};
