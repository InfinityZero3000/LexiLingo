// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { CategoriesPage } from "./CategoriesPage";

const api = vi.hoisted(() => ({
  listCategories: vi.fn(),
  createCategory: vi.fn(),
  updateCategory: vi.fn(),
  hideCategory: vi.fn(),
}));
vi.mock("../lib/categoriesApi", () => ({ ...api }));

const category = (over = {}) => ({
  id: "c1", name: "Grammar", slug: "grammar", description: null, icon: "📚", color: "#2196f3",
  order_index: 2, is_active: true, course_count: 4, ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.listCategories.mockResolvedValue([
    category({ id: "c2", name: "Travel", slug: "travel", order_index: 1, course_count: 0, is_active: false }),
    category(),
  ]);
});
afterEach(cleanup);

const mount = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ConfirmProvider>
          <CategoriesPage />
        </ConfirmProvider>
      </I18nProvider>
    </QueryClientProvider>,
  );

describe("CategoriesPage", () => {
  it("lists hidden categories too, in display order, with the live course count", async () => {
    mount();

    await screen.findByRole("button", { name: "Hide" });
    const rows = within(screen.getByRole("table")).getAllByRole("row").slice(1);
    expect(rows[0].textContent).toContain("Travel");
    expect(rows[0].textContent).toContain("Hidden");
    expect(rows[1].textContent).toContain("Grammar");
    expect(rows[1].textContent).toContain("4");
  });

  it("derives the slug from the name until the admin edits it", async () => {
    api.createCategory.mockResolvedValue({});
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "Create category", hidden: false }));
    const dialog = within(await screen.findByRole("dialog"));

    fireEvent.change(dialog.getByLabelText("Category name"), { target: { value: "Tiếng Anh du lịch" } });
    expect((dialog.getByLabelText(/URL slug/) as HTMLInputElement).value).toBe("tieng-anh-du-lich");

    fireEvent.change(dialog.getByLabelText(/URL slug/), { target: { value: "travel-en" } });
    fireEvent.change(dialog.getByLabelText("Category name"), { target: { value: "Travel English" } });
    expect((dialog.getByLabelText(/URL slug/) as HTMLInputElement).value).toBe("travel-en");

    fireEvent.click(dialog.getByRole("button", { name: "Create" }));
    await waitFor(() =>
      expect(api.createCategory).toHaveBeenCalledWith(expect.objectContaining({ name: "Travel English", slug: "travel-en", is_active: true })),
    );
  });

  it("shows the server's rejection inside the open form", async () => {
    api.createCategory.mockRejectedValue(new Error("Category with this slug already exists"));
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "Create category" }));
    const dialog = within(await screen.findByRole("dialog"));
    fireEvent.change(dialog.getByLabelText("Category name"), { target: { value: "Grammar" } });
    fireEvent.click(dialog.getByRole("button", { name: "Create" }));

    await waitFor(() => expect(dialog.getByRole("alert").textContent).toBe("Category with this slug already exists"));
  });

  it("hides a category only after confirmation and can show it again", async () => {
    api.hideCategory.mockResolvedValue({});
    api.updateCategory.mockResolvedValue({});
    mount();

    fireEvent.click(await screen.findByRole("button", { name: "Hide" }));
    const confirmDialog = within(await screen.findByRole("dialog"));
    expect(api.hideCategory).not.toHaveBeenCalled();
    fireEvent.click(confirmDialog.getByRole("button", { name: "Hide" }));
    await waitFor(() => expect(api.hideCategory).toHaveBeenCalledWith("c1"));

    fireEvent.click(screen.getByRole("button", { name: "Show again" }));
    await waitFor(() => expect(api.updateCategory).toHaveBeenCalledWith("c2", { is_active: true }));
  });
});
