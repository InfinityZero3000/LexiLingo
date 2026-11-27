// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { AdsPage, bannerStatus } from "./AdsPage";

const api = vi.hoisted(() => ({
  listBanners: vi.fn(),
  createBanner: vi.fn(),
  updateBanner: vi.fn(),
  deleteBanner: vi.fn(),
  uploadBannerImage: vi.fn(),
}));
vi.mock("../lib/adminApi", () => ({ ...api }));

const banner = (over = {}) => ({
  id: "b1", title: "Spring sale", description: "All courses", image_url: "https://x.test/a.png",
  link_url: null, position: "hero", priority: 1, is_active: true, start_at: null, end_at: null,
  target_min_level: null, target_max_level: null, target_language: null,
  created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z", ...over,
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.listBanners.mockResolvedValue({ data: [banner(), banner({ id: "b2", title: "Side ad", position: "sidebar" })] });
});
afterEach(cleanup);

const mount = () =>
  render(
    <I18nProvider>
      <ConfirmProvider>
        <AdsPage />
      </ConfirmProvider>
    </I18nProvider>,
  );

const rowOf = async (title: string) => {
  await screen.findByText(title);
  return screen.getAllByRole("row").find((r) => r.textContent?.includes(title)) as HTMLElement;
};

describe("bannerStatus", () => {
  const now = new Date("2026-06-15T12:00:00Z");
  it("classifies the four states", () => {
    expect(bannerStatus({ is_active: false, start_at: null, end_at: null }, now)).toBe("off");
    expect(bannerStatus({ is_active: true, start_at: null, end_at: "2026-06-01T00:00:00Z" }, now)).toBe("expired");
    expect(bannerStatus({ is_active: true, start_at: "2026-07-01T00:00:00Z", end_at: null }, now)).toBe("scheduled");
    expect(bannerStatus({ is_active: true, start_at: "2026-06-01T00:00:00Z", end_at: "2026-07-01T00:00:00Z" }, now)).toBe("running");
  });
});

describe("AdsPage", () => {
  it("duplicates a banner into an inactive create form", async () => {
    mount();
    const row = await rowOf("Spring sale");
    fireEvent.click(within(row).getByRole("button", { name: "Duplicate" }));
    expect((screen.getByLabelText(/Title/) as HTMLInputElement).value).toBe("Spring sale (copy)");
    expect((screen.getByLabelText("Active") as HTMLInputElement).checked).toBe(false);
    expect(screen.getByRole("button", { name: "Create" })).toBeTruthy();
  });

  it("fills both dates from the 7 days preset", async () => {
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "+ Create Banner" }));
    fireEvent.click(screen.getByRole("button", { name: "7 days" }));
    const start = (screen.getByLabelText("Start Date") as HTMLInputElement).value;
    const end = (screen.getByLabelText("End Date") as HTMLInputElement).value;
    expect(start).not.toBe("");
    const days = (new Date(end).getTime() - new Date(start).getTime()) / 86_400_000;
    expect(Math.round(days)).toBe(7);
  });

  it("uploads a chosen image and uses the returned url", async () => {
    api.uploadBannerImage.mockResolvedValue({ success: true, data: { url: "https://cdn.test/b.png", filename: "b.png" } });
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "+ Create Banner" }));
    const file = new File(["x"], "b.png", { type: "image/png" });
    fireEvent.change(screen.getByLabelText("Upload image"), { target: { files: [file] } });
    await waitFor(() => expect((screen.getByLabelText(/Image URL/) as HTMLInputElement).value).toBe("https://cdn.test/b.png"));
    expect(api.uploadBannerImage).toHaveBeenCalledWith(file);
  });

  it("drops an upload that finishes after the form was cancelled and another banner opened", async () => {
    let finish: (v: unknown) => void = () => {};
    api.uploadBannerImage.mockReturnValue(new Promise((r) => { finish = r; }));
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "+ Create Banner" }));
    const file = new File(["x"], "b.png", { type: "image/png" });
    fireEvent.change(screen.getByLabelText("Upload image"), { target: { files: [file] } });
    await waitFor(() => expect(api.uploadBannerImage).toHaveBeenCalled());
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    fireEvent.click(within(await rowOf("Spring sale")).getByRole("button", { name: "Edit" }));
    finish({ success: true, data: { url: "https://cdn.test/late.png", filename: "late.png" } });
    await new Promise((r) => setTimeout(r, 20));
    expect((screen.getByLabelText(/Image URL/) as HTMLInputElement).value).toBe("https://x.test/a.png");
  });

  it("adds preset days by calendar, not by 24h blocks, across a DST change", async () => {
    vi.stubEnv("TZ", "America/New_York");
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(2026, 2, 5, 10, 30));
    try {
      mount();
      fireEvent.click(await screen.findByRole("button", { name: "+ Create Banner" }));
      fireEvent.click(screen.getByRole("button", { name: "7 days" }));
      expect((screen.getByLabelText("End Date") as HTMLInputElement).value).toBe("2026-03-12T10:30");
    } finally {
      vi.useRealTimers();
      vi.unstubAllEnvs();
    }
  });

  it("rejects an svg and an oversized file without calling the API", async () => {
    mount();
    fireEvent.click(await screen.findByRole("button", { name: "+ Create Banner" }));
    const input = screen.getByLabelText("Upload image");
    fireEvent.change(input, { target: { files: [new File(["<svg/>"], "a.svg", { type: "image/svg+xml" })] } });
    expect((await screen.findByRole("alert")).textContent).toContain("PNG, JPG or WEBP");
    const big = new File([new Uint8Array(2 * 1024 * 1024 + 1)], "big.png", { type: "image/png" });
    fireEvent.change(input, { target: { files: [big] } });
    await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("2 MB"));
    expect(api.uploadBannerImage).not.toHaveBeenCalled();
  });

  it("flags a non-hero banner in the table and in the edit form", async () => {
    mount();
    const row = await rowOf("Side ad");
    expect(row.textContent).toContain("Not shown in app");
    fireEvent.click(within(row).getByRole("button", { name: "Edit" }));
    expect(screen.getByRole("alert").textContent).toContain("hero");
    expect(within(screen.getByLabelText("Position")).getAllByRole("option").map((o) => o.textContent)).toEqual(["hero", "sidebar"]);
  });

  it("sends null for cleared optional fields so an edit really clears them", async () => {
    api.listBanners.mockResolvedValue({ data: [banner({ link_url: "https://x.test/go", target_min_level: "A2", end_at: "2027-01-01T00:00:00Z" })] });
    api.updateBanner.mockResolvedValue({});
    mount();
    fireEvent.click(within(await rowOf("Spring sale")).getByRole("button", { name: "Edit" }));
    fireEvent.change(screen.getByDisplayValue("All courses"), { target: { value: "" } });
    fireEvent.change(screen.getByDisplayValue("https://x.test/go"), { target: { value: "" } });
    fireEvent.change(screen.getByDisplayValue("A2"), { target: { value: "" } });
    fireEvent.change(screen.getByLabelText("End Date"), { target: { value: "" } });
    fireEvent.submit(screen.getByDisplayValue("Spring sale").closest("form") as HTMLFormElement);
    await waitFor(() => expect(api.updateBanner).toHaveBeenCalled());
    expect(api.updateBanner.mock.calls[0][1]).toMatchObject({ description: null, link_url: null, target_min_level: null, end_at: null });
  });
});
