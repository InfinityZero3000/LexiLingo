// jsdom does no layout, so these pin the three rules whose absence broke pages at 390px.
import { describe, expect, it } from "vitest";
// @ts-expect-error the app tsconfig carries no node types; only this test reads a file
import { readFileSync } from "node:fs";


// @ts-expect-error see above
const css: string = readFileSync(`${process.cwd()}/src/styles.css`, "utf8");

describe("narrow-screen styles", () => {
  it("never breaks table cells letter by letter", () => {
    expect(css).not.toMatch(/\.panel t[dh][^{}]*\{[^}]*word-break:\s*break-all/);
  });

  it("resets the filter bar's width-based flex-basis once it stacks into a column", () => {
    expect(css).toMatch(/\.filter-bar > \.search-input,\s*\.filter-bar > \.filter-search-form,[^{]*\{\s*flex: 0 0 auto;/);
  });

  it("lets a single-column grid shrink below its widest child", () => {
    expect(css).toMatch(/\.grid-2 \{[^}]*minmax\(0, 1fr\) !important/);
  });
});
