// @vitest-environment jsdom
// The three super-admin pages must show only what an endpoint actually reported.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { SuperAdminDashboard } from "./SuperAdminDashboard";
import { AiModelsPage } from "./AiModelsPage";
import { DatabasePage } from "./DatabasePage";

const ai = vi.hoisted(() => ({ getMonitoringDashboard: vi.fn(), getLlmKeyMonitoring: vi.fn(), getSpoolMonitoring: vi.fn() }));
vi.mock("../lib/aiApi", () => ai);
vi.mock("../lib/adminApi", () => ({
  getSystemInfo: vi.fn(async () => ({ data: { app_env: "testing", debug: false, log_level: "INFO", token_expire_minutes: 30, google_oauth: false, firebase: false, totals: { users: 3, courses: 1, vocabulary: 0, achievements: 0 } } })),
}));
// What VITE_AI_URL resolves to behind the gateway: the backend's own /health.
vi.mock("../lib/healthApi", () => ({
  checkBackendHealth: vi.fn(async () => ({ json: async () => ({ status: "healthy", version: "9.9.9" }) })),
  checkAiHealth: vi.fn(async () => ({ json: async () => ({ status: "healthy", version: "9.9.9" }) })),
}));

const row = (title: string) => screen.getByText(title).closest(".pill-item") as HTMLElement;
const page = (node: React.ReactElement) => render(<I18nProvider>{node}</I18nProvider>);

describe("super admin service status", () => {
  beforeEach(() => {
    ai.getMonitoringDashboard.mockResolvedValue({ trace_cag: { status: "active", backend: "LangGraph" } });
    ai.getLlmKeyMonitoring.mockResolvedValue({ mode: "pool", model: "qwen/qwen3.8-27b", keys: [], totals: { keys: 34 } });
    ai.getSpoolMonitoring.mockResolvedValue({ queue_depth: 0 });
  });
  afterEach(() => { cleanup(); vi.clearAllMocks(); });

  it("names the model the AI service reports, not a hardcoded list", async () => {
    page(<SuperAdminDashboard />);

    expect(await screen.findByText("qwen/qwen3.8-27b")).toBeTruthy();
    expect(screen.queryByText(/Gemini|Whisper|Piper/)).toBeNull();
    expect(within(row("MongoDB")).getByText("Connected")).toBeTruthy();
  });

  it("does not call the AI service online because the backend is healthy", async () => {
    ai.getMonitoringDashboard.mockRejectedValue(new Error("502"));
    ai.getLlmKeyMonitoring.mockRejectedValue(new Error("502"));
    ai.getSpoolMonitoring.mockRejectedValue(new Error("502"));

    page(<SuperAdminDashboard />);

    await screen.findByText("Service Status");
    expect(within(row("AI Service")).getByText("Offline")).toBeTruthy();
    expect(within(row("MongoDB")).getByText("Unknown")).toBeTruthy();
  });

  it("AI models page shows the reported model and no static registry or pipelines", async () => {
    page(<AiModelsPage />);

    expect(await screen.findByText("qwen/qwen3.8-27b")).toBeTruthy();
    expect(screen.queryByText(/Whisper|Piper|Pipeline/)).toBeNull();
  });

  it("database page leaves MongoDB unknown when the AI service cannot read it", async () => {
    ai.getSpoolMonitoring.mockRejectedValue(new Error("503"));

    page(<DatabasePage />);

    await screen.findByText("AI Database (MongoDB)");
    expect(screen.queryByText("Redis Cache")).toBeNull();
    expect(screen.getAllByText("Unknown").length).toBeGreaterThan(0);
  });
});
