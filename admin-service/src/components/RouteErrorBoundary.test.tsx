// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Link, Route, Routes } from "react-router-dom";
import { I18nProvider } from "../lib/i18n";
import { RouteErrorBoundary } from "./RouteErrorBoundary";

let crashes = true;
const Crashing = () => {
  if (crashes) throw new Error("Cannot read properties of undefined");
  return <p>Recovered page</p>;
};

const mount = () =>
  render(
    <I18nProvider>
      <MemoryRouter initialEntries={["/admin/ops"]}>
        <nav>
          <Link to="/admin/users">Users</Link>
        </nav>
        <RouteErrorBoundary>
          <Routes>
            <Route path="/admin/ops" element={<Crashing />} />
            <Route path="/admin/users" element={<p>Users page</p>} />
          </Routes>
        </RouteErrorBoundary>
      </MemoryRouter>
    </I18nProvider>,
  );

beforeEach(() => {
  crashes = true;
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  vi.spyOn(console, "error").mockImplementation(() => undefined);
});
afterEach(cleanup);

describe("RouteErrorBoundary", () => {
  it("shows the error with a retry instead of a blank app, and leaves the menu working", () => {
    mount();
    expect(screen.getByRole("alert").textContent).toContain("This page hit an error");
    expect(screen.getByRole("alert").textContent).toContain("Cannot read properties of undefined");

    fireEvent.click(screen.getByText("Users"));
    expect(screen.getByText("Users page")).toBeTruthy();
  });

  it("renders the page again when retry is pressed after the cause is gone", () => {
    mount();
    crashes = false;
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(screen.getByText("Recovered page")).toBeTruthy();
  });
});
