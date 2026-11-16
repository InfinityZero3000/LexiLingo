// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { IeltsProvenancePanel } from "./IeltsProvenancePanel";
import { passageLicenseProblem } from "../lib/ieltsProvenance";

const content = {
  sections: [
    { skill: "listening", parts: [{ order: 1 }] },
    {
      skill: "reading",
      parts: [
        { order: 1, passage_title: "Bees" },
        { order: 2, passage_title: "Canals" },
        { order: 3, passage_title: "Glass" },
      ],
    },
  ],
};

const provenance = {
  passages: [
    {
      section: "reading:1",
      title: "Bees",
      license_id: "CC-BY-SA-4.0",
      attribution: "From Wikipedia article 'Bee' (rev 1), CC BY-SA 4.0",
      source_url: "https://en.wikipedia.org/wiki/Bee",
      retrieved_at: "2026-11-10T00:00:00Z",
      adapted: true,
    },
    { section: "reading:2", title: "Canals", license_id: "All-Rights-Reserved" },
  ],
};

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
});
afterEach(cleanup);

const mount = (prov: unknown) =>
  render(
    <I18nProvider>
      <IeltsProvenancePanel content={content} provenance={prov as never} />
    </I18nProvider>,
  );

describe("IeltsProvenancePanel", () => {
  it("shows licence, attribution, safe source link and adapted flag", () => {
    mount(provenance);
    const row = within(screen.getByTestId("passage-1"));
    expect(row.getByText("CC-BY-SA-4.0")).toBeTruthy();
    expect(row.getByText(/From Wikipedia article 'Bee'/)).toBeTruthy();
    expect(row.getByText("Adapted")).toBeTruthy();
    const link = row.getByRole("link") as HTMLAnchorElement;
    expect(link.href).toBe("https://en.wikipedia.org/wiki/Bee");
    expect(link.target).toBe("_blank");
    expect(link.rel).toContain("noopener");
  });

  it("warns about an invalid licence and a passage with no entry, mirroring the gate", () => {
    mount(provenance);
    expect(screen.getByText(/Unknown licence id \(All-Rights-Reserved\)/)).toBeTruthy();
    expect(screen.getByText(/No provenance entry/)).toBeTruthy();
    expect(screen.getByText("2 passage(s) would block publishing")).toBeTruthy();
  });

  it("warns for every passage when the paper has no provenance at all", () => {
    mount(null);
    expect(screen.getByText("3 passage(s) would block publishing")).toBeTruthy();
  });

  it("does not turn a javascript: source into a link", () => {
    mount({
      passages: [
        { section: "reading:1", license_id: "LicenseRef-Generated", source_url: "javascript:alert(1)" },
      ],
    });
    expect(within(screen.getByTestId("passage-1")).queryByRole("link")).toBeNull();
  });
});

describe("passageLicenseProblem", () => {
  it("matches the backend rules", () => {
    expect(passageLicenseProblem(undefined)?.kind).toBe("missing");
    expect(passageLicenseProblem({ license_id: "LicenseRef-CMUdict" })?.kind).toBe("forbidden_license");
    expect(passageLicenseProblem({ license_id: "CC-BY-SA-4.0", attribution: "x" })).toEqual({
      kind: "missing_field",
      license: "CC-BY-SA-4.0",
      field: "source_url",
    });
    expect(passageLicenseProblem({ license_id: "LicenseRef-Public-Domain" })).toBeNull();
  });
});
