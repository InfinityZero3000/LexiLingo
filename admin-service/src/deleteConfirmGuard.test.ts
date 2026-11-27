/// <reference types="vite/client" />
import { describe, expect, it } from "vitest";

// Every call that destroys or revokes something must be behind a question.
const DESTRUCTIVE = /(?<![\w.])(delete[A-Z]\w*|permanentlyDelete\w*|revoke[A-Z]\w*|resetQuota|hideCategory|cancel\w*Job)\(/;
// Confirmed by a dialog of their own that collects a written reason.
const OWN_DIALOG = new Set(["components/user-management/UserPremiumPanel.tsx"]);
const LOOK_BACK = 15;

const sources = import.meta.glob(["./pages/**/*.tsx", "./components/**/*.tsx", "!./**/*.test.tsx"], {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

describe("destructive actions", () => {
  it("ask before they run", () => {
    const unasked: string[] = [];
    expect(Object.keys(sources).length).toBeGreaterThan(30);
    for (const [key, text] of Object.entries(sources)) {
      const path = key.slice(2);
      if (OWN_DIALOG.has(path)) continue;
      const lines = text.split("\n");
      lines.forEach((line, i) => {
        if (!DESTRUCTIVE.test(line) || /^\s*(import|export (const|function)|async function)\b/.test(line)) return;
        const before = lines.slice(Math.max(0, i - LOOK_BACK), i + 1).join("\n");
        const asked =
          /await confirm\(/.test(before) ||
          // BulkBar confirms every action itself.
          /run: \(row\) =>/.test(line) ||
          // A mutation: the question is where it is triggered.
          (/mutationFn/.test(before) && /await confirm\(/.test(text));
        if (!asked) unasked.push(`${path}:${i + 1} ${line.trim()}`);
      });
    }
    expect(unasked).toEqual([]);
  });
});
