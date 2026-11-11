// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { Pagination } from "./Pagination";

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
});
afterEach(cleanup);

const renderPager = (props: Partial<React.ComponentProps<typeof Pagination>> = {}) => {
  const onChange = vi.fn();
  render(
    <I18nProvider>
      <Pagination page={5} pages={20} total={600} onChange={onChange} {...props} />
    </I18nProvider>,
  );
  return onChange;
};

describe("Pagination", () => {
  it("renders nothing for a single page", () => {
    renderPager({ pages: 1, page: 1 });
    expect(screen.queryByRole("navigation")).toBeNull();
  });

  it("pins first and last pages, windows the middle and marks the gap", () => {
    renderPager();
    const labels = screen.getAllByRole("button").map((b) => b.textContent);
    expect(labels).toEqual(["Previous", "1", "3", "4", "5", "6", "7", "20", "Next"]);
    expect(screen.getAllByText("…")).toHaveLength(2); // a gap after page 1 and before page 20
    expect(screen.getByRole("button", { name: "5" }).getAttribute("aria-current")).toBe("page");
  });

  it("moves to the chosen page and disables the ends", () => {
    const onChange = renderPager({ page: 1 });
    expect((screen.getByText("Previous") as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByText("Next"));
    expect(onChange).toHaveBeenCalledWith(2);
  });
});
