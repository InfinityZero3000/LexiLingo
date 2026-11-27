// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { UnitsPage } from "./UnitsPage";

const api = vi.hoisted(() => ({
  listUnitsAdmin: vi.fn(), listCoursesAdmin: vi.fn(), createUnit: vi.fn(), updateUnit: vi.fn(), deleteUnit: vi.fn(),
}));
vi.mock("../lib/adminApi", () => api);

describe("standalone units page", () => {
  afterEach(() => { cleanup(); vi.clearAllMocks(); });

  it("saves an edit while the course filter is on all courses", async () => {
    api.listCoursesAdmin.mockResolvedValue({ data: { courses: [] } });
    api.listUnitsAdmin.mockResolvedValue({ data: [{ id: "u1", course_id: "c1", title: "Old unit", description: "", order_index: 1, total_lessons: 0 }] });
    api.updateUnit.mockResolvedValue({});

    render(<I18nProvider><ConfirmProvider><MemoryRouter><UnitsPage /></MemoryRouter></ConfirmProvider></I18nProvider>);
    fireEvent.click(await screen.findByRole("button", { name: "Edit" }));
    fireEvent.change(screen.getByDisplayValue("Old unit"), { target: { value: "New unit" } });
    fireEvent.submit(screen.getByDisplayValue("New unit").closest("form") as HTMLFormElement);

    await waitFor(() => expect(api.updateUnit).toHaveBeenCalledWith("u1", expect.objectContaining({ title: "New unit" })));
  });
});
