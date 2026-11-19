// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { ContentLabPage } from "./ContentLabPage";

const api = vi.hoisted(() => ({
  bulkImportGrammar: vi.fn(),
  bulkImportQuestions: vi.fn(),
  bulkImportTestExams: vi.fn(),
  createGrammar: vi.fn(),
  createQuestion: vi.fn(),
  createTestExam: vi.fn(),
  deleteGrammar: vi.fn(),
  deleteQuestion: vi.fn(),
  deleteTestExam: vi.fn(),
  listGrammar: vi.fn(),
  listQuestions: vi.fn(),
  listTestExams: vi.fn(),
  updateGrammar: vi.fn(),
  updateQuestion: vi.fn(),
  updateTestExam: vi.fn(),
}));
vi.mock("../lib/adminApi", () => ({ ...api }));

const question = (over = {}) => ({
  id: "q1", prompt: "Pick the noun", question_type: "mcq", options: ["run", "table", "quickly"],
  answer: "table", explanation: null, difficulty_level: "A1", tags: ["nouns"], is_active: true, ...over,
});
const exam = (over = {}) => ({
  id: "e1", title: "Placement", description: null, level: "A1", duration_minutes: 20, passing_score: 70,
  question_ids: ["q1"], is_published: false, ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.listGrammar.mockResolvedValue({ data: [] });
  api.listQuestions.mockResolvedValue({ data: [question()] });
  api.listTestExams.mockResolvedValue({ data: [exam()] });
  api.createQuestion.mockResolvedValue({ success: true });
  api.updateQuestion.mockResolvedValue({ success: true });
  api.createTestExam.mockResolvedValue({ success: true });
  api.updateTestExam.mockResolvedValue({ success: true });
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const mount = () =>
  render(
    <I18nProvider>
      <ConfirmProvider>
        <ContentLabPage />
      </ConfirmProvider>
    </I18nProvider>,
  );

const openTab = async (name: string) => {
  fireEvent.click(await screen.findByRole("tab", { name }));
};
const rowOf = async (text: string) => {
  await screen.findByText(text);
  return screen.getAllByRole("row").find((r) => r.textContent?.includes(text)) as HTMLElement;
};

describe("question form", () => {
  it("creates an mcq with options array and the selected option text as answer", async () => {
    mount();
    await openTab("Question Bank");
    fireEvent.change(screen.getByLabelText("Prompt"), { target: { value: "Capital of France?" } });
    fireEvent.change(screen.getByLabelText("Option 1"), { target: { value: " Paris " } });
    fireEvent.change(screen.getByLabelText("Option 2"), { target: { value: "Rome" } });
    fireEvent.click(screen.getByRole("button", { name: "+ Add option" }));
    fireEvent.click(screen.getByLabelText("Mark option 1 as the correct answer"));
    fireEvent.click(screen.getByRole("button", { name: "Tạo" }));
    await waitFor(() => expect(api.createQuestion).toHaveBeenCalledTimes(1));
    expect(api.createQuestion.mock.calls[0][0]).toMatchObject({
      prompt: "Capital of France?",
      question_type: "mcq",
      options: ["Paris", "Rome"],
      answer: "Paris",
      tags: [],
    });
  });

  it("blocks save and shows errors when no option is marked correct", async () => {
    mount();
    await openTab("Question Bank");
    fireEvent.change(screen.getByLabelText("Option 1"), { target: { value: "a" } });
    fireEvent.change(screen.getByLabelText("Option 2"), { target: { value: "A " } });
    fireEvent.click(screen.getByRole("button", { name: "Tạo" }));
    expect(await screen.findByText(/same once extra spaces/)).toBeTruthy();
    expect(screen.getByText("Mark exactly one option as correct.")).toBeTruthy();
    expect(api.createQuestion).not.toHaveBeenCalled();
  });

  it("loads an existing question with its options and correct radio, tags as chips", async () => {
    mount();
    await openTab("Question Bank");
    fireEvent.click(within(await rowOf("Pick the noun")).getByRole("button", { name: "Sửa" }));
    expect((screen.getByLabelText("Option 2") as HTMLInputElement).value).toBe("table");
    expect((screen.getByLabelText("Mark option 2 as the correct answer") as HTMLInputElement).checked).toBe(true);
    expect((screen.getByLabelText("Mark option 1 as the correct answer") as HTMLInputElement).checked).toBe(false);
    expect(screen.getByRole("button", { name: "Remove tag nouns" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Cập nhật" }));
    await waitFor(() => expect(api.updateQuestion).toHaveBeenCalled());
    expect(api.updateQuestion.mock.calls[0][1]).toMatchObject({ answer: "table", options: ["run", "table", "quickly"], tags: ["nouns"] });
  });

  it("maps a legacy index answer and warns when the stored answer matches nothing", async () => {
    api.listQuestions.mockResolvedValue({
      data: [question({ answer: 0 }), question({ id: "q2", prompt: "Broken one", answer: "missing" })],
    });
    mount();
    await openTab("Question Bank");
    fireEvent.click(within(await rowOf("Pick the noun")).getByRole("button", { name: "Sửa" }));
    expect((screen.getByLabelText("Mark option 1 as the correct answer") as HTMLInputElement).checked).toBe(true);
    fireEvent.click(within(await rowOf("Broken one")).getByRole("button", { name: "Sửa" }));
    expect((await screen.findByRole("alert")).textContent).toContain("does not match any option");
  });

  it("uses a plain answer input for fill_blank", async () => {
    mount();
    await openTab("Question Bank");
    fireEvent.change(screen.getByLabelText("Type"), { target: { value: "fill_blank" } });
    fireEvent.change(screen.getByLabelText("Prompt"), { target: { value: "She ___ home." } });
    fireEvent.change(screen.getByLabelText("Answer"), { target: { value: "went" } });
    fireEvent.click(screen.getByRole("button", { name: "Tạo" }));
    await waitFor(() => expect(api.createQuestion).toHaveBeenCalled());
    expect(api.createQuestion.mock.calls[0][0]).toMatchObject({ question_type: "fill_blank", answer: "went", options: undefined });
  });
});

describe("test exam picker", () => {
  const pool = ["a", "b", "c", "d", "e"].map((x) => question({ id: `id-${x}`, prompt: `Question ${x}` }));

  const openPicker = async () => {
    api.listQuestions.mockResolvedValue({ data: pool });
    mount();
    await openTab("Test Exams");
    await screen.findByLabelText(/Question a/);
  };

  it("requests the filtered list at the exam level with limit 200", async () => {
    await openPicker();
    expect(api.listQuestions).toHaveBeenCalledWith({ level: "A1", q: undefined, limit: 200 });
  });

  it("sends the ticked questions in selection order as an array", async () => {
    await openPicker();
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Quiz" } });
    fireEvent.click(screen.getByLabelText(/Question c/));
    fireEvent.click(screen.getByLabelText(/Question a/));
    expect(screen.getByText("Selected (2)")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Tạo" }));
    await waitFor(() => expect(api.createTestExam).toHaveBeenCalled());
    expect(api.createTestExam.mock.calls[0][0].question_ids).toEqual(["id-c", "id-a"]);
  });

  it("removes a selected question with its × button", async () => {
    await openPicker();
    fireEvent.click(screen.getByLabelText(/Question b/));
    fireEvent.click(screen.getByRole("button", { name: "Remove selected question 1" }));
    expect(screen.getByText("Selected (0)")).toBeTruthy();
  });

  it("random pick adds N distinct questions that are not already selected", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0.5);
    await openPicker();
    fireEvent.click(screen.getByLabelText(/Question a/));
    fireEvent.change(screen.getByLabelText("How many"), { target: { value: "3" } });
    fireEvent.click(screen.getByRole("button", { name: "Pick 3 random" }));
    fireEvent.click(screen.getByRole("button", { name: "Tạo" }));
    await waitFor(() => expect(api.createTestExam).toHaveBeenCalled());
    const ids: string[] = api.createTestExam.mock.calls[0][0].question_ids;
    expect(ids).toHaveLength(4);
    expect(new Set(ids).size).toBe(4);
    expect(ids[0]).toBe("id-a");
  });

  it("random pick takes everything left and reports how many were added", async () => {
    await openPicker();
    for (const x of ["a", "b", "c"]) fireEvent.click(screen.getByLabelText(new RegExp(`Question ${x}`)));
    fireEvent.change(screen.getByLabelText("How many"), { target: { value: "9" } });
    fireEvent.click(screen.getByRole("button", { name: "Pick 9 random" }));
    expect(screen.getByText("Selected (5)")).toBeTruthy();
    expect(screen.getByRole("status").textContent).toContain("Added 2 of 9");
  });

  it("loads an existing exam's question ids, showing known prompts", async () => {
    mount();
    await openTab("Test Exams");
    fireEvent.click(within(await rowOf("Placement")).getByRole("button", { name: "Sửa" }));
    expect(screen.getByText("Selected (1)")).toBeTruthy();
    const selected = screen.getByRole("list");
    expect(within(selected).getByText("Pick the noun")).toBeTruthy();
  });
});
