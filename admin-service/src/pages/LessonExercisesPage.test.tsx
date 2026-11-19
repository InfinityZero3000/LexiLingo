// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { LessonExercisesPage } from "./LessonExercisesPage";

const api = vi.hoisted(() => ({
  getLessonDetail: vi.fn(),
  updateLessonContent: vi.fn(),
  generateLessonExercises: vi.fn(),
}));
vi.mock("../lib/adminApi", async (orig) => ({ ...(await orig<object>()), ...api }));

const ex = (id: string, question: string) => ({
  id, type: "multiple_choice", ui_type: "multiple_choice", question,
  options: ["a", "b"], correct_answer: "a", explanation: null,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.getLessonDetail.mockResolvedValue({
    success: true,
    data: { id: "l1", title: "Greetings", estimated_minutes: 10, content: { exercises: [ex("e1", "Existing question")] } },
  });
});
afterEach(cleanup);

const mount = () =>
  render(
    <I18nProvider>
      <ConfirmProvider>
        <MemoryRouter initialEntries={["/admin/courses/c/units/u/lessons/l1/exercises"]}>
          <Routes>
            <Route path="/admin/courses/:courseId/units/:unitId/lessons/:lessonId/exercises" element={<LessonExercisesPage />} />
          </Routes>
        </MemoryRouter>
      </ConfirmProvider>
    </I18nProvider>,
  );

const saveBtn = () => screen.getByRole("button", { name: /Save all|Lưu tất cả/ }) as HTMLButtonElement;

describe("LessonExercisesPage AI generation", () => {
  it("appends drafts after existing ones, marks dirty, never saves", async () => {
    api.generateLessonExercises.mockResolvedValue({
      success: true, data: { exercises: [ex("g1", "Draft one"), ex("g2", "Draft two")] },
    });
    mount();
    await screen.findByText("Existing question");
    expect(saveBtn().disabled).toBe(true);

    fireEvent.click(screen.getByRole("button", { name: "Generate with AI" }));
    await screen.findByText("Draft two");

    const questions = Array.from(document.querySelectorAll(".exercise-question")).map((e) => e.textContent);
    expect(questions).toEqual(["Existing question", "Draft one", "Draft two"]);
    expect(screen.getByRole("status").textContent).toContain("2 exercises added — review them, then Save");
    expect(saveBtn().disabled).toBe(false);
    expect(api.generateLessonExercises).toHaveBeenCalledWith("l1");
    expect(api.updateLessonContent).not.toHaveBeenCalled();
  });

  it("ignores a second click while running", async () => {
    let resolve: (v: unknown) => void = () => {};
    api.generateLessonExercises.mockReturnValue(new Promise((r) => { resolve = r; }));
    mount();
    await screen.findByText("Existing question");
    fireEvent.click(screen.getByRole("button", { name: "Generate with AI" }));
    const running = await screen.findByRole("button", { name: /Generating/ });
    expect((running as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(running);
    resolve({ success: true, data: { exercises: [] } });
    await waitFor(() => expect(screen.getByRole("button", { name: "Generate with AI" })).toBeTruthy());
    expect(api.generateLessonExercises).toHaveBeenCalledTimes(1);
  });

  it("shows a friendly 502 message with Retry, and the backend message otherwise", async () => {
    api.generateLessonExercises.mockRejectedValueOnce(Object.assign(new Error("raw"), { status: 502 }));
    mount();
    await screen.findByText("Existing question");
    fireEvent.click(screen.getByRole("button", { name: "Generate with AI" }));
    expect((await screen.findByRole("alert")).textContent).toContain("Retrying may work");

    api.generateLessonExercises.mockRejectedValueOnce(Object.assign(new Error("Lesson not found"), { status: 404 }));
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("Lesson not found"));
    expect(screen.queryByRole("button", { name: "Retry" })).toBeNull();
    expect(saveBtn().disabled).toBe(true);
    expect(api.updateLessonContent).not.toHaveBeenCalled();
  });
});
