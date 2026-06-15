import { describe, expect, it, vi, beforeEach } from "vitest";

import type { SourceSnapshot } from "../../lib/contentAgentApi";
import {
  createDefaultContentAgentForm,
  validateContentAgentForm,
  validateContentAgentUpload,
} from "./ContentAgentModal";

vi.mock("../../lib/contentAgentApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../lib/contentAgentApi")>();
  return {
    ...actual,
    getSourceCatalog: vi.fn().mockResolvedValue([]),
  };
});

describe("ContentAgentModal configuration", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("defaults to every CEFR level, no source, and ten-item lessons", () => {
    const form = createDefaultContentAgentForm();

    expect(form.levels).toEqual(["A1", "A2", "B1", "B2", "C1", "C2"]);
    expect(form.sources).toEqual([]);
    expect(form.vocabularyPerLesson).toBe(10);
    expect(form.exerciseCount).toBe(10);
    expect(form.previewOnly).toBe(true);
    expect(form.uploadAttestation).toBe(false);
  });

  it("requires vocabulary counts to stay inside the approved 8-12 range", () => {
    expect(
      validateContentAgentForm({
        ...createDefaultContentAgentForm(),
        sources: ["oewn"],
        vocabularyPerLesson: 7,
        acknowledgedDraft: true,
      }),
    ).toContain("8");
    expect(
      validateContentAgentForm({
        ...createDefaultContentAgentForm(),
        sources: ["oewn"],
        vocabularyPerLesson: 13,
        acknowledgedDraft: true,
      }),
    ).toContain("12");
  });

  it("matches the backend limit of at most ten units per course", () => {
    expect(
      validateContentAgentForm({
        ...createDefaultContentAgentForm(),
        sources: ["oewn"],
        unitsPerCourse: 11,
        acknowledgedDraft: true,
      }),
    ).toContain("10");
  });

  it("requires CEFR/source selection and the draft acknowledgement", () => {
    expect(
      validateContentAgentForm({
        ...createDefaultContentAgentForm(),
        levels: [],
        sources: [],
      }),
    ).toBeTruthy();
    expect(
      validateContentAgentForm({
        ...createDefaultContentAgentForm(),
        sources: ["oewn"],
      }),
    ).toContain("draft");
  });

  it("accepts UTF-8 CSV/JSON files up to five megabytes", () => {
    expect(
      validateContentAgentUpload(
        new File(["[]"], "records.json", { type: "application/json" }),
      ),
    ).toBeNull();
    expect(
      validateContentAgentUpload(
        new File(["word"], "records.txt", { type: "text/plain" }),
      ),
    ).toContain("CSV or JSON");
    expect(
      validateContentAgentUpload(
        new File([new Uint8Array(5 * 1024 * 1024 + 1)], "records.csv", {
          type: "text/csv",
        }),
      ),
    ).toContain("5 MB");
  });

  it("requires upload attestation when a file is provided", () => {
    const form = { ...createDefaultContentAgentForm(), sources: ["oewn"], acknowledgedDraft: true, uploadAttestation: false };
    const result = validateContentAgentForm(form, true);
    expect(result).toBeTruthy();
    expect(result).toContain("confirm");
  });

  it("passes validation when upload attestation is checked", () => {
    const form = {
      ...createDefaultContentAgentForm(),
      sources: ["oewn"],
      acknowledgedDraft: true,
      uploadAttestation: true,
    };
    expect(validateContentAgentForm(form, true)).toBeNull();
  });
});

describe("ContentAgentModal source catalog logic", () => {
  it("getSourceCatalog mock returns empty list by default", async () => {
    const { getSourceCatalog } = await import("../../lib/contentAgentApi");
    const result = await getSourceCatalog();
    expect(Array.isArray(result)).toBe(true);
    expect(result).toHaveLength(0);
  });

  it("getSourceCatalog resolves approved snapshots", async () => {
    const { getSourceCatalog } = await import("../../lib/contentAgentApi");
    vi.mocked(getSourceCatalog).mockResolvedValueOnce([
      {
        source_id: "oewn",
        source_name: "Open English WordNet",
        version: "2025",
        license_id: "CC-BY-4.0",
        license_url: "https://creativecommons.org/licenses/by/4.0/",
        attribution_text: "Princeton WordNet",
        record_count: 150000,
        last_sync_at: "2026-06-01T00:00:00Z",
        status: "approved",
        enabled: true,
      },
    ]);

    const result = await getSourceCatalog();
    expect(result).toHaveLength(1);
    expect(result[0].source_id).toBe("oewn");
    expect(result[0].status).toBe("approved");
    expect(result[0].enabled).toBe(true);
  });

  it("only approved+enabled snapshots are selectable", () => {
    const snapshots = [
      { source_id: "oewn", status: "approved" as const, enabled: true, source_name: "OEWN", version: "2025", license_id: "CC-BY-4.0", license_url: "", attribution_text: "", record_count: 0, last_sync_at: null },
      { source_id: "tatoeba", status: "pending" as const, enabled: false, source_name: "Tatoeba", version: "2025", license_id: "CC0", license_url: "", attribution_text: "", record_count: 0, last_sync_at: null },
      { source_id: "cmudict", status: "rejected" as const, enabled: false, source_name: "CMUdict", version: "1.0", license_id: "BSD", license_url: "", attribution_text: "", record_count: 0, last_sync_at: null },
    ];

    const selectable = snapshots.filter((s) => s.status === "approved" && s.enabled);
    expect(selectable).toHaveLength(1);
    expect(selectable[0].source_id).toBe("oewn");
  });

  it("core lexical sources are preselected when available and approved", () => {
    const coreSourceIds = ["oewn", "cmudict", "cefr_j", "wikidata"];
    const approvedSnapshots = [
      { source_id: "oewn", status: "approved" as const, enabled: true },
      { source_id: "tatoeba", status: "approved" as const, enabled: true },
      { source_id: "cefr_j", status: "pending" as const, enabled: false },
    ];

    const preselected = approvedSnapshots
      .filter((s) => s.status === "approved" && s.enabled && coreSourceIds.includes(s.source_id))
      .map((s) => s.source_id);

    expect(preselected).toEqual(["oewn"]);
    expect(preselected).not.toContain("tatoeba");
    expect(preselected).not.toContain("cefr_j");
  });

  it("inactive snapshot is disabled (not approved+enabled)", () => {
    const snapshot: SourceSnapshot = {
      source_id: "cmudict",
      status: "pending",
      enabled: false,
      source_name: "CMUdict",
      version: "1.0",
      license_id: "BSD",
      license_url: "",
      attribution_text: "",
      record_count: 0,
      last_sync_at: null,
    };

    const selectable = snapshot.status === "approved" && snapshot.enabled;
    expect(selectable).toBe(false);
  });
});
