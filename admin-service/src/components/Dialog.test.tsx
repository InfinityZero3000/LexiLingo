// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { Dialog } from "./Dialog";

afterEach(cleanup);

const press = (key: string, init: KeyboardEventInit = {}) =>
  fireEvent.keyDown(document, { key, ...init });

const Sample = ({ onClose }: { onClose: () => void }) => (
  <Dialog onClose={onClose} maxWidth={400}>
    <h3>Edit word</h3>
    <input aria-label="word" />
    <button>Middle</button>
    <button>Last</button>
  </Dialog>
);

describe("Dialog", () => {
  it("is a modal dialog labelled by its heading", () => {
    render(<Sample onClose={() => {}} />);
    const dialog = screen.getByRole("dialog");
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(screen.getByRole("dialog", { name: "Edit word" })).toBe(dialog);
  });

  it("moves focus to the first field", () => {
    render(<Sample onClose={() => {}} />);
    expect(document.activeElement).toBe(screen.getByLabelText("word"));
  });

  it("closes on Escape but not on a backdrop click", () => {
    const onClose = vi.fn();
    const { container } = render(<Sample onClose={onClose} />);
    fireEvent.click(container.querySelector(".modal-overlay")!);
    expect(onClose).not.toHaveBeenCalled();
    press("Escape");
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("keeps Tab inside, wrapping in both directions", () => {
    render(<Sample onClose={() => {}} />);
    const last = screen.getByRole("button", { name: "Last" });
    last.focus();
    press("Tab");
    expect(document.activeElement).toBe(screen.getByLabelText("word"));
    press("Tab", { shiftKey: true });
    expect(document.activeElement).toBe(last);
  });

  it("hands focus back to the opener when it closes", () => {
    const opener = document.createElement("button");
    document.body.appendChild(opener);
    opener.focus();
    const { unmount } = render(<Sample onClose={() => {}} />);
    expect(document.activeElement).not.toBe(opener);
    unmount();
    expect(document.activeElement).toBe(opener);
    opener.remove();
  });

  it("lets only the topmost dialog react to Escape", () => {
    const outer = vi.fn();
    const inner = vi.fn();
    render(
      <>
        <Dialog onClose={outer}><h3>Outer</h3><button>a</button></Dialog>
        <Dialog onClose={inner}><h3>Inner</h3><button>b</button></Dialog>
      </>,
    );
    press("Escape");
    expect(inner).toHaveBeenCalledTimes(1);
    expect(outer).not.toHaveBeenCalled();
  });
});
