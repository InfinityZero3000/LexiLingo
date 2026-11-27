// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { ShopPage } from "./ShopPage";

const api = vi.hoisted(() => ({ listShopItems: vi.fn(), createShopItem: vi.fn(), updateShopItem: vi.fn(), deleteShopItem: vi.fn() }));
vi.mock("../lib/adminApi", () => api);

describe("shop item edit", () => {
  afterEach(() => { cleanup(); vi.clearAllMocks(); });

  it("sends null when the stock and icon are cleared, so the item goes back to unlimited", async () => {
    api.listShopItems.mockResolvedValue({ data: [{ id: "1", name: "Freeze", description: "d", item_type: "streak_freeze", price_gems: 5, is_available: true, stock_quantity: 3, icon_url: "https://x/y.png" }] });
    api.updateShopItem.mockResolvedValue({});

    render(<I18nProvider><ConfirmProvider><ShopPage /></ConfirmProvider></I18nProvider>);
    fireEvent.click((await screen.findAllByRole("button", { name: "Edit" }))[0]);
    fireEvent.change(screen.getByDisplayValue("3"), { target: { value: "" } });
    fireEvent.change(screen.getByDisplayValue("https://x/y.png"), { target: { value: "" } });
    fireEvent.submit(screen.getByDisplayValue("Freeze").closest("form") as HTMLFormElement);

    await waitFor(() => expect(api.updateShopItem).toHaveBeenCalled());
    expect(api.updateShopItem.mock.calls[0][1]).toMatchObject({ stock_quantity: null, icon_url: null });
  });
});
