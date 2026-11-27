// @vitest-environment jsdom
// Deleting a paper cascades to every learner's attempt on it, so one click must not do it.
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import * as page from "./IeltsTestsPage";

const api = vi.hoisted(() => ({
  createIeltsTest: vi.fn(), deleteIeltsTest: vi.fn(), getIeltsTest: vi.fn(), listIeltsAttempts: vi.fn(),
  listIeltsTests: vi.fn(), updateIeltsTest: vi.fn(), uploadIeltsAudio: vi.fn(), validateIeltsTest: vi.fn(),
}));
vi.mock("../lib/adminApi", () => api);

const IeltsTestsPage = (page as any).IeltsTestsPage ?? (page as any).default;

describe("deleting an IELTS test", () => {
  afterEach(() => { cleanup(); vi.clearAllMocks(); });

  const paper = (attempts: number) => ({
    data: [{ id: "t1", title: "Mock 1", test_type: "academic", skill_scope: "full", question_count: 3, attempt_count: attempts, is_published: true }],
  });
  const mount = () =>
    render(<I18nProvider><ConfirmProvider><IeltsTestsPage /></ConfirmProvider></I18nProvider>);

  it("asks first, naming the paper", async () => {
    api.listIeltsTests.mockResolvedValue(paper(0));
    api.deleteIeltsTest.mockResolvedValue({});
    mount();

    fireEvent.click(await screen.findByRole("button", { name: "Delete Mock 1" }));
    const dialog = await screen.findByRole("dialog");
    expect(dialog.textContent).toContain("Mock 1");
    expect(api.deleteIeltsTest).not.toHaveBeenCalled();

    fireEvent.click(within(dialog).getByRole("button", { name: "Delete" }));
    await waitFor(() => expect(api.deleteIeltsTest).toHaveBeenCalledWith("t1"));
  });

  it("does not offer to delete a paper learners have sat", async () => {
    api.listIeltsTests.mockResolvedValue(paper(12));
    mount();

    const button = (await screen.findByRole("button", { name: "Delete Mock 1" })) as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    expect(button.title).toContain("12");
  });
});
