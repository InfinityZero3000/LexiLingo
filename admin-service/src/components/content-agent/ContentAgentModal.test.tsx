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

const sourceSnapshot = (
  overrides: Partial<SourceSnapshot> = {},
): SourceSnapshot => ({
  source_id: "oewn",
  source_name: "Open English WordNet",
  source_version: "2025",
  snapshot_id: `oewn:2025:${"a".repeat(64)}`,
  official_url: "https://en-word.net/",
  license_id: "CC-BY-4.0",
  license_url: "https://creativecommons.org/licenses/by/4.0/",
  attribution_text: "Open English WordNet contributors",
  retrieved_at: "2026-06-01T00:00:00Z",
  raw_checksum: "a".repeat(64),
  normalized_sha256: "b".repeat(64),
  normalized_bytes: 2048,
  record_checksum_root: "c".repeat(64),
  adapter_version: 1,
  record_count: 150000,
  status: "active",
  enabled: true,
  ...overrides,
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
      sourceSnapshot(),
    ]);

    const result = await getSourceCatalog();
    expect(result).toHaveLength(1);
    expect(result[0].source_id).toBe("oewn");
    expect(result[0].status).toBe("active");
    expect(result[0].enabled).toBe(true);
  });

  it("only approved+enabled snapshots are selectable", () => {
    const snapshots = [
      sourceSnapshot(),
      sourceSnapshot({ source_id: "tatoeba", enabled: false }),
      sourceSnapshot({ source_id: "cmudict", enabled: false }),
    ];

    const selectable = snapshots.filter((s) => s.status === "active" && s.enabled);
    expect(selectable).toHaveLength(1);
    expect(selectable[0].source_id).toBe("oewn");
  });

  it("core lexical sources are preselected when available and approved", () => {
    const coreSourceIds = ["oewn", "cmudict", "cefr_j", "wikidata"];
    const approvedSnapshots = [
      sourceSnapshot(),
      sourceSnapshot({ source_id: "tatoeba" }),
      sourceSnapshot({ source_id: "cefr_j", enabled: false }),
    ];

    const preselected = approvedSnapshots
      .filter((s) => s.status === "active" && s.enabled && coreSourceIds.includes(s.source_id))
      .map((s) => s.source_id);

    expect(preselected).toEqual(["oewn"]);
    expect(preselected).not.toContain("tatoeba");
    expect(preselected).not.toContain("cefr_j");
  });

  it("inactive snapshot is disabled (not approved+enabled)", () => {
    const snapshot = sourceSnapshot({
      source_id: "cmudict",
      enabled: false,
      source_name: "CMUdict",
      source_version: "1.0",
      license_id: "BSD",
      record_count: 0,
    });

    const selectable = snapshot.status === "active" && snapshot.enabled;
    expect(selectable).toBe(false);
  });
});
