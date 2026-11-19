// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { LessonsPage } from "./LessonsPage";

const api = vi.hoisted(() => ({
  listLessonsAdmin: vi.fn(),
  listCoursesAdmin: vi.fn(),
  listUnitsAdmin: vi.fn(),
  createLesson: vi.fn(),
  updateLesson: vi.fn(),
  deleteLesson: vi.fn(),
  generateLessonExercises: vi.fn(),
  updateLessonContent: vi.fn(),
}));
vi.mock("../lib/adminApi", async (orig) => ({ ...(await orig<object>()), ...api }));

const lesson = (id: string, title: string, exercise_count: number, over = {}) => ({
  id, unit_id: "u1", title, description: null, order_index: 0, lesson_type: "lesson",
  xp_reward: 10, pass_threshold: 80, total_exercises: exercise_count, exercise_count,
  prerequisites: [], created_at: "", updated_at: "", ...over,
});
const drafts = (id: string) => ({ success: true, data: { exercises: [{ id: `x_${id}` }] } });

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.listCoursesAdmin.mockResolvedValue({ data: { courses: [] } });
  api.listUnitsAdmin.mockResolvedValue({ data: [] });
  api.listLessonsAdmin.mockResolvedValue({
    data: [lesson("a", "Alpha", 0, { estimated_minutes: 25 }), lesson("b", "Beta", 3), lesson("c", "Gamma", 0), lesson("d", "Delta", 0)],
  });
  api.updateLessonContent.mockResolvedValue({ success: true });
});
afterEach(cleanup);

const mount = () =>
  render(
    <I18nProvider>
      <ConfirmProvider>
        <MemoryRouter initialEntries={["/admin/lessons"]}>
          <Routes>
            <Route path="/admin/lessons" element={<LessonsPage />} />
          </Routes>
        </MemoryRouter>
      </ConfirmProvider>
    </I18nProvider>,
  );

const bulkButton = () => screen.findByRole("button", { name: "Generate for 3 empty lessons" });

describe("LessonsPage bulk AI generation", () => {
  it("targets only empty lessons, generates then saves each, and survives one failure", async () => {
    api.generateLessonExercises.mockImplementation(async (id: string) => {
      if (id === "c") throw Object.assign(new Error("AI could not produce"), { status: 502 });
      return drafts(id);
    });
    mount();
    fireEvent.click(await bulkButton());
    fireEvent.click(await screen.findByRole("button", { name: "Generate and save" }));

    await screen.findByText(/Exercises generated for 2 lessons/);
    expect(api.generateLessonExercises.mock.calls.map((c) => c[0])).toEqual(["a", "c", "d"]);
    expect(api.updateLessonContent.mock.calls).toEqual([
      ["a", [{ id: "x_a" }], 25],
      ["d", [{ id: "x_d" }], 10],
    ]);
    expect(screen.getByText(/Could not generate for 1 lessons/)).toBeTruthy();
    expect(screen.getByText("Gamma: AI could not produce")).toBeTruthy();
    expect(api.listLessonsAdmin).toHaveBeenCalledTimes(2);
  });

  it("does nothing when the confirmation is cancelled", async () => {
    mount();
    fireEvent.click(await bulkButton());
    fireEvent.click(await screen.findByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("button", { name: "Generate and save" })).toBeNull());
    expect(api.generateLessonExercises).not.toHaveBeenCalled();
    expect(api.updateLessonContent).not.toHaveBeenCalled();
  });

  it("stops after the current lesson", async () => {
    let release: (v: unknown) => void = () => {};
    api.generateLessonExercises.mockImplementationOnce(() => new Promise((r) => { release = r; }));
    mount();
    fireEvent.click(await bulkButton());
    fireEvent.click(await screen.findByRole("button", { name: "Generate and save" }));
    expect((await screen.findByRole("status")).textContent).toContain("1 / 3 — Alpha");
    fireEvent.click(screen.getByRole("button", { name: "Stop" }));
    release(drafts("a"));
    await screen.findByText(/Stopped — 1 lessons were generated/);
    expect(api.generateLessonExercises).toHaveBeenCalledTimes(1);
    expect(api.updateLessonContent).toHaveBeenCalledTimes(1);
  });

  it("hides the button when no lesson is empty", async () => {
    api.listLessonsAdmin.mockResolvedValue({ data: [lesson("b", "Beta", 3)] });
    mount();
    await screen.findByText("Beta");
    expect(screen.queryByRole("button", { name: /Generate for/ })).toBeNull();
  });
});
