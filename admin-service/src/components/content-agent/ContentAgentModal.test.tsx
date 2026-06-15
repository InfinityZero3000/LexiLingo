import { describe, expect, it } from "vitest";

import {
  CONTENT_AGENT_SOURCE_OPTIONS,
  createDefaultContentAgentForm,
  validateContentAgentForm,
  validateContentAgentUpload,
} from "./ContentAgentModal";

describe("ContentAgentModal configuration", () => {
  it("defaults to every CEFR level, no unverified source, and ten-item lessons", () => {
    const form = createDefaultContentAgentForm();

    expect(form.levels).toEqual(["A1", "A2", "B1", "B2", "C1", "C2"]);
    expect(form.sources).toEqual([]);
    expect(form.vocabularyPerLesson).toBe(10);
    expect(form.exerciseCount).toBe(10);
    expect(form.previewOnly).toBe(true);
  });

  it("renders only approved dataset source definitions", () => {
    expect(CONTENT_AGENT_SOURCE_OPTIONS.map((source) => source.id)).toEqual([
      "oewn",
      "cmudict",
      "cefr_j",
      "wikidata",
      "tatoeba",
      "librispeech",
      "common_voice",
    ]);
    expect(
      CONTENT_AGENT_SOURCE_OPTIONS.map((source) => source.label).join(" "),
    ).not.toMatch(
      /VOA|BBC|British Council|Cambridge|Oxford|DOL|PREP|IELTS Workshop/,
    );
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
});
