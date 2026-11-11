// @vitest-environment jsdom
import { afterEach, describe, expect, it } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider, useConfirm, type ConfirmOptions } from "./ConfirmDialog";

afterEach(cleanup);

let ask: (options: ConfirmOptions) => Promise<boolean>;
const Probe = () => {
  ask = useConfirm();
  return null;
};

const setup = () =>
  render(
    <I18nProvider>
      <ConfirmProvider>
        <Probe />
      </ConfirmProvider>
    </I18nProvider>,
  );

const open = (options: ConfirmOptions) => {
  let result!: Promise<boolean>;
  act(() => {
    result = ask(options);
  });
  return result;
};

describe("useConfirm", () => {
  it("resolves true when confirmed and shows the message", async () => {
    setup();
    const result = open({ message: "Delete this?", confirmLabel: "Delete" });
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(screen.getByText("Delete this?")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    await expect(result).resolves.toBe(true);
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("resolves false on cancel and on Escape", async () => {
    setup();
    const cancelled = open({ message: "Sure?" });
    fireEvent.click(screen.getAllByRole("button").find((b) => b.className.includes("ghost-button"))!);
    await expect(cancelled).resolves.toBe(false);

    const escaped = open({ message: "Sure again?" });
    fireEvent.keyDown(document, { key: "Escape" });
    await expect(escaped).resolves.toBe(false);
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("keeps the confirm button disabled until the required text is typed", async () => {
    setup();
    const result = open({ message: "Remove account", confirmLabel: "Remove", danger: true, requireText: "a@b.co" });
    const confirmBtn = screen.getByRole("button", { name: "Remove" }) as HTMLButtonElement;
    expect(confirmBtn.disabled).toBe(true);
    expect(confirmBtn.className).toContain("danger");

    fireEvent.change(screen.getByRole("textbox"), { target: { value: "a@b" } });
    expect(confirmBtn.disabled).toBe(true);
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "a@b.co" } });
    expect(confirmBtn.disabled).toBe(false);

    fireEvent.click(confirmBtn);
    await expect(result).resolves.toBe(true);
  });

  it("clears the typed text for the next request", async () => {
    setup();
    open({ message: "one", requireText: "x" });
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "x" } });
    fireEvent.keyDown(document, { key: "Escape" });
    open({ message: "two", requireText: "x" });
    expect((screen.getByRole("textbox") as HTMLInputElement).value).toBe("");
  });
});
