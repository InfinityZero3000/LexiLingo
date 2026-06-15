import { describe, expect, it } from "vitest";

import { UI_TYPES, UI_TYPE_TO_TYPE } from "./adminApi";


describe("shared content contracts", () => {
  it("maps every UI type to a supported database exercise type", () => {
    const supported = new Set([
      "multiple_choice",
      "true_false",
      "fill_blank",
      "translate",
      "matching",
      "reorder",
    ]);

    expect(Object.keys(UI_TYPE_TO_TYPE).sort()).toEqual([...UI_TYPES].sort());
    expect(
      Object.values(UI_TYPE_TO_TYPE).every((type) => supported.has(type)),
    ).toBe(true);
  });
});
