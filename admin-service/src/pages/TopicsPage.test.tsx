// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { I18nProvider } from "../lib/i18n";
import { ConfirmProvider } from "../components/ConfirmDialog";
import { TopicsPage } from "./TopicsPage";

const api = vi.hoisted(() => ({
  listTopicStoriesAdmin: vi.fn(),
  getTopicStoryAdmin: vi.fn(),
  suggestTopicMetaAdmin: vi.fn(),
  draftTopicStoryAdmin: vi.fn(),
  createTopicStoryAdmin: vi.fn(),
}));
vi.mock("../lib/adminApi", () => ({ ...api }));

const item = (over = {}) => ({
  story_id: "story_dental", title: { en: "Dental Appointment", vi: "Khám răng" }, difficulty_level: "B1",
  category: "health", estimated_minutes: 15, icon_key: "doctor", source: "builtin", ...over,
});

const full = () => ({
  ...item(),
  conversation_flow: { opening_prompt: "Hello!" },
  role_persona: { name: "Dr. Kim", role: "Dentist", personality: "Calm", speaking_style: "Clear", background: "Ten years." },
  context_description: { setting: "Clinic", scenario: "A check-up.", objectives: ["Describe the pain"] },
  vocabulary_list: [{ term: "cavity", definition: "A hole in a tooth.", example_in_story: "I think I have a cavity.", collocations: ["fill a cavity"] }],
  grammar_points: [{ grammar_structure: "Present perfect", explanation: "Have plus participle.", usage_in_story: "", examples: ["I have had it."] }],
  suggested_prompts: ["I have a toothache."],
  tags: ["health"],
});

const draft = () => ({
  title_vi: "Đặt phòng khách sạn", category: "travel", icon_key: "hotel", difficulty_level: "A2", estimated_minutes: 12,
  role_persona: { name: "Anna", role: "Receptionist", personality: "Warm", speaking_style: "Clear", background: "Small hotel." },
  context_description: { setting: "Hotel desk", scenario: "You arrive late.", objectives: ["Greet", "Confirm", "Ask"] },
  opening_prompt: "Good evening!", suggested_prompts: ["I have a booking.", "Is breakfast included?", "Could I have a quiet room?"],
  vocabulary_list: [{ term: "key card", definition: "A card that opens a door.", example_in_story: "I lost my key card." }],
  grammar_points: [{ grammar_structure: "Could", explanation: "Polite requests.", usage_in_story: "", examples: ["Could I?", "Could you?"] }],
});

beforeEach(() => {
  const store = new Map<string, string>([["lexi_admin_locale", "en"]]);
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  });
  Object.values(api).forEach((fn) => fn.mockReset());
  api.listTopicStoriesAdmin.mockResolvedValue({
    success: true,
    data: {
      total: 2,
      topics: [
        item({ story_id: "story_mine", title: { en: "My Topic", vi: "Của tôi" }, category: "work", icon_key: "work", source: "custom" }),
        item(),
      ],
    },
  });
  api.getTopicStoryAdmin.mockResolvedValue({ success: true, data: full() });
  api.suggestTopicMetaAdmin.mockResolvedValue({ success: true, data: { category: "health", icon_key: "doctor", confidence: "high", matched: ["dental"] } });
  api.createTopicStoryAdmin.mockResolvedValue({ success: true, data: item() });
});
afterEach(cleanup);

const mount = () =>
  render(
    <I18nProvider>
      <ConfirmProvider>
        <TopicsPage />
      </ConfirmProvider>
    </I18nProvider>,
  );

const rowOf = (name: string) => screen.getByText(name).closest("tr") as HTMLElement;

describe("TopicsPage", () => {
  it("lists built-in and custom topics; only the custom one can be edited, both can be cloned", async () => {
    mount();

    await screen.findByText("My Topic");
    expect(within(rowOf("My Topic")).getByText("Created here")).toBeTruthy();
    expect(within(rowOf("My Topic")).getByRole("button", { name: /Edit/ })).toBeTruthy();
    expect(within(rowOf("Dental Appointment")).getByText("Built in")).toBeTruthy();
    expect(within(rowOf("Dental Appointment")).queryByRole("button", { name: /Edit/ })).toBeNull();
    expect(within(rowOf("Dental Appointment")).getByRole("button", { name: /Clone/ })).toBeTruthy();
  });

  it("searches and filters by source", async () => {
    mount();
    await screen.findByText("My Topic");

    fireEvent.click(screen.getByRole("button", { name: "Built in" }));
    expect(screen.queryByText("My Topic")).toBeNull();
    expect(screen.getByText("Dental Appointment")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "All" }));
    fireEvent.change(screen.getByPlaceholderText(/title, category/), { target: { value: "khám" } });
    expect(screen.queryByText("My Topic")).toBeNull();
    expect(screen.getByText("Dental Appointment")).toBeTruthy();
  });

  it("clone opens the full story as a copy with no id, and saves its vocabulary extras", async () => {
    mount();
    await screen.findByText("My Topic");

    fireEvent.click(within(rowOf("Dental Appointment")).getByRole("button", { name: /Clone/ }));

    const title = (await screen.findByLabelText("English title")) as HTMLInputElement;
    expect(api.getTopicStoryAdmin).toHaveBeenCalledWith("story_dental");
    expect(title.value).toBe("Dental Appointment (copy)");
    expect((screen.getByLabelText("Topic ID") as HTMLInputElement).placeholder).toBe("story_dental_appointment_copy");
    expect((screen.getByLabelText("Term 1") as HTMLInputElement).value).toBe("cavity");

    fireEvent.click(screen.getByRole("button", { name: "Save topic" }));

    await waitFor(() => expect(api.createTopicStoryAdmin).toHaveBeenCalled());
    const payload = api.createTopicStoryAdmin.mock.calls[0][0];
    expect(payload.story_id).toBeUndefined();
    expect(payload.vocabulary_list[0].collocations).toEqual(["fill a cavity"]);
    await screen.findByText("Topic saved. Learners see it now.");
  });

  it("a new topic gets its category and icon from the title, until the admin picks an icon", async () => {
    mount();
    await screen.findByText("My Topic");
    fireEvent.click(screen.getByRole("button", { name: "Create topic" }));

    fireEvent.change(await screen.findByLabelText("English title"), { target: { value: "Dental Appointment Checkup" } });

    await waitFor(() => expect(api.suggestTopicMetaAdmin).toHaveBeenCalledWith("Dental Appointment Checkup"), { timeout: 2000 });
    await waitFor(() => expect(screen.getByRole("button", { name: "Doctor" }).getAttribute("aria-pressed")).toBe("true"));
    expect((screen.getByLabelText("Category") as HTMLSelectElement).value).toBe("health");
    expect(screen.getByText(/chosen from the title/)).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Library" }));
    api.suggestTopicMetaAdmin.mockClear();
    fireEvent.change(screen.getByLabelText("English title"), { target: { value: "Dental Appointment Checkup Today" } });

    await waitFor(() => expect(api.suggestTopicMetaAdmin).toHaveBeenCalled(), { timeout: 2000 });
    await waitFor(() => expect((screen.getByLabelText("Category") as HTMLSelectElement).value).toBe("health"));
    expect(screen.getByRole("button", { name: "Library" }).getAttribute("aria-pressed")).toBe("true");
  });

  it("says so when it is not sure of the icon", async () => {
    api.suggestTopicMetaAdmin.mockResolvedValue({ success: true, data: { category: "daily_life", icon_key: "chat", confidence: "low", matched: [] } });
    mount();
    await screen.findByText("My Topic");
    fireEvent.click(screen.getByRole("button", { name: "Create topic" }));

    fireEvent.change(await screen.findByLabelText("English title"), { target: { value: "Quantum widgets" } });

    await screen.findByText(/not sure: please check it/, undefined, { timeout: 2000 });
  });

  it("Draft with AI fills the whole form, keeps the typed title and shows the warnings", async () => {
    api.draftTopicStoryAdmin.mockResolvedValue({ success: true, data: { draft: draft(), warnings: ["Could not tell the icon from the title; check the icon."] } });
    mount();
    await screen.findByText("My Topic");
    fireEvent.click(screen.getByRole("button", { name: "Create topic" }));
    fireEvent.change(await screen.findByLabelText("English title"), { target: { value: "Hotel Check-In" } });

    fireEvent.click(screen.getByRole("button", { name: /Draft with AI/ }));

    await screen.findByText(/Draft ready/);
    expect(api.draftTopicStoryAdmin).toHaveBeenCalledWith({ title_en: "Hotel Check-In", difficulty_level: "A2", category: "", notes: "" });
    expect((screen.getByLabelText("English title") as HTMLInputElement).value).toBe("Hotel Check-In");
    expect((screen.getByLabelText("Vietnamese title") as HTMLInputElement).value).toBe("Đặt phòng khách sạn");
    expect((screen.getByLabelText("Name") as HTMLInputElement).value).toBe("Anna");
    expect((screen.getByLabelText("Term 1") as HTMLInputElement).value).toBe("key card");
    expect(screen.getByRole("button", { name: "Hotel" }).getAttribute("aria-pressed")).toBe("true");
    expect(screen.getByText(/Could not tell the icon/)).toBeTruthy();
  });

  it("refuses to draft without a title, and shows the service's reason when the draft fails", async () => {
    api.draftTopicStoryAdmin.mockRejectedValue(new Error("the AI service is busy (Groq 429); try again shortly"));
    mount();
    await screen.findByText("My Topic");
    fireEvent.click(screen.getByRole("button", { name: "Create topic" }));
    await screen.findByLabelText("English title");

    fireEvent.click(screen.getByRole("button", { name: /Draft with AI/ }));
    expect((await screen.findByRole("alert")).textContent).toMatch(/English title first/);
    expect(api.draftTopicStoryAdmin).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("English title"), { target: { value: "Hotel Check-In" } });
    fireEvent.click(screen.getByRole("button", { name: /Draft with AI/ }));
    await waitFor(() => expect(screen.getByRole("alert").textContent).toMatch(/busy/));
  });

  it("shows the service's refusal when a save collides with a built-in id, and keeps the form", async () => {
    api.createTopicStoryAdmin.mockRejectedValue(new Error("'story_dental' is a built-in topic. Use Clone to make an editable copy with a new id."));
    mount();
    await screen.findByText("My Topic");
    fireEvent.click(screen.getByRole("button", { name: "Create topic" }));
    fireEvent.change(await screen.findByLabelText("English title"), { target: { value: "Dental" } });
    fireEvent.change(screen.getByLabelText("Topic ID"), { target: { value: "story_dental" } });

    fireEvent.click(screen.getByRole("button", { name: "Save topic" }));

    await waitFor(() => expect(screen.getByRole("alert").textContent).toMatch(/Use Clone/));
    expect((screen.getByLabelText("English title") as HTMLInputElement).value).toBe("Dental");
  });

  it("does not save a form with an error, and says which", async () => {
    mount();
    await screen.findByText("My Topic");
    fireEvent.click(screen.getByRole("button", { name: "Create topic" }));
    fireEvent.change(await screen.findByLabelText("English title"), { target: { value: "Hotel" } });
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Anna" } });

    fireEvent.click(screen.getByRole("button", { name: "Save topic" }));

    expect((await screen.findByRole("alert")).textContent).toMatch(/Character/);
    expect(api.createTopicStoryAdmin).not.toHaveBeenCalled();
  });
});
