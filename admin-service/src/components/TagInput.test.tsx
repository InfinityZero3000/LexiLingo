// @vitest-environment jsdom
import { useState } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { TagInput } from "./TagInput";

const Harness = ({ initial = [] as string[], spy }: { initial?: string[]; spy?: (v: string[]) => void }) => {
  const [tags, setTags] = useState(initial);
  return (
    <I18nProvider>
      <TagInput label="Tags" value={tags} onChange={(v) => { setTags(v); spy?.(v); }} />
      <output data-testid="out">{tags.join("|")}</output>
    </I18nProvider>
  );
};

const out = () => screen.getByTestId("out").textContent;

beforeEach(() => {
  vi.stubGlobal("localStorage", { getItem: () => "en", setItem: () => {}, removeItem: () => {} });
});
afterEach(cleanup);

describe("TagInput", () => {
  it("adds a tag on Enter and on comma, trimmed", () => {
    render(<Harness />);
    const input = screen.getByLabelText("Tags");
    fireEvent.change(input, { target: { value: "  grammar " } });
    fireEvent.keyDown(input, { key: "Enter" });
    fireEvent.change(input, { target: { value: "verbs," } });
    expect(out()).toBe("grammar|verbs");
    expect((input as HTMLInputElement).value).toBe("");
  });

  it("ignores empty and duplicate tags", () => {
    render(<Harness initial={["a1"]} />);
    const input = screen.getByLabelText("Tags");
    fireEvent.keyDown(input, { key: "Enter" });
    fireEvent.change(input, { target: { value: "A1," } });
    fireEvent.change(input, { target: { value: "," } });
    expect(out()).toBe("a1");
  });

  it("Backspace on an empty input removes the last tag, but not while typing", () => {
    render(<Harness initial={["a", "b"]} />);
    const input = screen.getByLabelText("Tags");
    fireEvent.change(input, { target: { value: "x" } });
    fireEvent.keyDown(input, { key: "Backspace" });
    expect(out()).toBe("a|b");
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.keyDown(input, { key: "Backspace" });
    expect(out()).toBe("a");
  });

  it("removes a tag with its × button", () => {
    render(<Harness initial={["a", "b"]} />);
    fireEvent.click(screen.getByRole("button", { name: "Remove tag a" }));
    expect(out()).toBe("b");
  });

  it("splits a pasted list into separate tags", () => {
    render(<Harness />);
    fireEvent.change(screen.getByLabelText("Tags"), { target: { value: "a, b, c" } });
    expect(out()).toBe("a|b|c");
  });

  it("commits a pending draft on blur", () => {
    render(<Harness />);
    const input = screen.getByLabelText("Tags");
    fireEvent.change(input, { target: { value: "draft" } });
    fireEvent.blur(input);
    expect(out()).toBe("draft");
  });
});
