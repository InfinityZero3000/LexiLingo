import { describe, expect, it } from "vitest";
import type { TopicDraft, TopicFull } from "./adminApi";
import {
  applyDraft, checkForm, emptyForm, formFromStory, hasAuthoredContent, payloadFromForm, topicIdFromTitle,
} from "./topicForm";

const story = (over: Partial<TopicFull> = {}): TopicFull => ({
  story_id: "story_dental_appointment",
  title: { en: "Dental Appointment", vi: "Khám răng" },
  difficulty_level: "B1",
  category: "health",
  estimated_minutes: 15,
  icon_key: "doctor",
  suggested_prompts: ["I have a toothache."],
  tags: ["health", "B1", "topic_expansion", "tracecag", "dentist"],
  source: "builtin",
  conversation_flow: { opening_prompt: "Hello, how can I help?" },
  role_persona: { name: "Dr. Kim", role: "Dentist", personality: "Calm", speaking_style: "Clear", background: "Ten years in practice." },
  context_description: { setting: "Dental clinic", scenario: "A check-up.", objectives: ["Describe the pain"] },
  vocabulary_list: [{ term: "cavity", definition: "A hole in a tooth.", example_in_story: "I think I have a cavity.", collocations: ["fill a cavity"] }],
  grammar_points: [{ grammar_structure: "Present perfect", explanation: "Use have plus a participle.", usage_in_story: "Pain history.", examples: ["I have had it for days."] }],
  ...over,
});

const draft = (): TopicDraft => ({
  title_vi: "Đặt phòng", category: "travel", icon_key: "hotel", difficulty_level: "A2", estimated_minutes: 12,
  role_persona: { name: "Anna", role: "Receptionist", personality: "Warm", speaking_style: "Clear", background: "Small hotel." },
  context_description: { setting: "Hotel desk", scenario: "You arrive late.", objectives: ["Greet", "Confirm", "Ask"] },
  opening_prompt: "Good evening!", suggested_prompts: ["a", "b", "c"],
  vocabulary_list: [{ term: "key card", definition: "A card that opens a door.", example_in_story: "I lost my key card." }],
  grammar_points: [{ grammar_structure: "Could", explanation: "Polite requests.", usage_in_story: "", examples: ["Could I?", "Could you?"] }],
});

describe("formFromStory", () => {
  it("edit keeps the id and everything the form shows, minus the tags the service adds itself", () => {
    const form = formFromStory(story(), "edit");

    expect(form.story_id).toBe("story_dental_appointment");
    expect(form.title_en).toBe("Dental Appointment");
    expect(form.tags).toBe("dentist");
    expect(form.persona.name).toBe("Dr. Kim");
    expect(form.opening_prompt).toBe("Hello, how can I help?");
    expect(form.vocabulary[0].term).toBe("cavity");
  });

  it("clone has no id and a title that will not collide with the original's", () => {
    const form = formFromStory(story(), "clone");

    expect(form.story_id).toBe("");
    expect(form.title_en).toBe("Dental Appointment (copy)");
    expect(topicIdFromTitle(form.title_en)).toBe("story_dental_appointment_copy");
  });

  it("does not share its arrays with the story it came from", () => {
    const original = story();
    const form = formFromStory(original, "clone");
    form.vocabulary[0].term = "changed";
    form.grammar[0].examples.push("x");

    expect(original.vocabulary_list?.[0].term).toBe("cavity");
    expect(original.grammar_points?.[0].examples).toHaveLength(1);
  });
});

describe("payloadFromForm", () => {
  it("keeps the extra vocabulary keys a built-in story carries (collocations, common errors)", () => {
    const payload = payloadFromForm(formFromStory(story(), "clone"));

    expect(payload.vocabulary_list?.[0]).toMatchObject({ term: "cavity", collocations: ["fill a cavity"] });
    expect(payload.story_id).toBeUndefined();
    expect(payload.role_persona?.name).toBe("Dr. Kim");
    expect(payload.context_description?.objectives).toEqual(["Describe the pain"]);
  });

  it("drops empty lines and rows, trims, and clamps the minutes", () => {
    const form = { ...emptyForm(), title_en: "  Hotel  ", suggested_prompts: ["  a ", "", "b", "  "], estimated_minutes: 500 };
    form.vocabulary = [{ term: " ", definition: "", example_in_story: "" }];

    const payload = payloadFromForm(form);

    expect(payload.title).toEqual({ en: "Hotel", vi: "Hotel" });
    expect(payload.suggested_prompts).toEqual(["a", "b"]);
    expect(payload.vocabulary_list).toEqual([]);
    expect(payload.estimated_minutes).toBe(60);
    expect(payload.role_persona).toBeUndefined();
    expect(payload.context_description).toBeUndefined();
  });

  it("always sends the vocabulary and grammar lists, so an edit that removes all of them is saved", () => {
    const payload = payloadFromForm({ ...emptyForm(), title_en: "Hotel" });

    expect(payload.vocabulary_list).toEqual([]);
    expect(payload.grammar_points).toEqual([]);
  });
});

describe("checkForm", () => {
  it("a bare title only warns: the service fills in the rest", () => {
    const { errors, warnings } = checkForm({ ...emptyForm(), title_en: "Hotel" });

    expect(errors).toEqual([]);
    expect(warnings.join(" ")).toMatch(/suggested prompt/);
    expect(warnings.join(" ")).toMatch(/No vocabulary/);
  });

  it("blocks what the service would refuse or what would be a broken topic", () => {
    const form = { ...emptyForm(), title_en: "Hi", setting: "Desk" };
    form.persona = { ...form.persona, name: "Anna" };
    form.vocabulary = [{ term: "key", definition: "", example_in_story: "" }];
    form.grammar = [{ grammar_structure: "Could", explanation: "", examples: [""] }];

    const { errors } = checkForm(form);

    expect(errors).toHaveLength(5);
    expect(errors.join("\n")).toMatch(/English title/);
    expect(errors.join("\n")).toMatch(/Character/);
    expect(errors.join("\n")).toMatch(/Scenario/);
    expect(errors.join("\n")).toMatch(/Vocabulary "key"/);
    expect(errors.join("\n")).toMatch(/Grammar "Could"/);
  });

  it("a topic from a built-in story passes with nothing to fix", () => {
    const { errors, warnings } = checkForm(formFromStory(story(), "edit"));

    expect(errors).toEqual([]);
    expect(warnings.some((w) => /Only 1 vocabulary/.test(w))).toBe(true);
  });
});

describe("applyDraft", () => {
  it("fills what the AI wrote and keeps the admin's title, id, level and tags", () => {
    const base = { ...emptyForm(), title_en: "Hotel Check-In", story_id: "story_mine", difficulty_level: "B2" as const, tags: "x, y" };

    const form = applyDraft(base, draft());

    expect(form).toMatchObject({
      title_en: "Hotel Check-In", story_id: "story_mine", difficulty_level: "B2", tags: "x, y",
      title_vi: "Đặt phòng", category: "travel", icon_key: "hotel", opening_prompt: "Good evening!", setting: "Hotel desk",
    });
    expect(form.persona.name).toBe("Anna");
    expect(form.vocabulary).toHaveLength(1);
    expect(form.grammar[0].examples).toEqual(["Could I?", "Could you?"]);
  });

  it("hasAuthoredContent says when a draft would overwrite something", () => {
    expect(hasAuthoredContent(emptyForm())).toBe(false);
    expect(hasAuthoredContent(applyDraft(emptyForm(), draft()))).toBe(true);
  });
});

describe("topicIdFromTitle", () => {
  it("matches the id the service builds from the English title", () => {
    expect(topicIdFromTitle("Hotel Check-In Conversation")).toBe("story_hotel_check_in_conversation");
    expect(topicIdFromTitle("  !!! ")).toBe("story_topic");
  });
});
