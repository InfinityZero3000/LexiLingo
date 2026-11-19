import type {
  TopicDifficulty,
  TopicDraft,
  TopicFull,
  TopicGrammar,
  TopicPersona,
  TopicSavePayload,
  TopicVocabulary,
} from "./adminApi";

export const DIFFICULTIES: TopicDifficulty[] = ["A1", "A2", "B1", "B2", "C1", "C2"];

export const CATEGORIES = [
  "travel", "work", "business", "services", "health", "food", "social", "finance", "shopping",
  "education", "technology", "housing", "culture", "leisure", "media", "emergency", "environment",
  "daily_life",
] as const;

/** Keys the app can draw. Keep in step with ICON_KEYS in ai-service api/services/topic_meta.py. */
export const ICON_KEYS = [
  ...CATEGORIES,
  "hotel", "directions", "transport", "cafe", "doctor", "library", "classroom", "internet",
  "repair", "achievement", "ai", "chat",
] as const;

/** Line fields hold the raw textarea lines, empties included, so typing a newline does not jump the cursor. */
export type TopicFormState = {
  story_id: string;
  title_en: string;
  title_vi: string;
  difficulty_level: TopicDifficulty;
  category: string;
  estimated_minutes: number;
  icon_key: string;
  opening_prompt: string;
  suggested_prompts: string[];
  tags: string;
  persona: TopicPersona;
  setting: string;
  scenario: string;
  objectives: string[];
  vocabulary: TopicVocabulary[];
  grammar: TopicGrammar[];
};

export const emptyPersona = (): TopicPersona => ({
  name: "", role: "", personality: "", speaking_style: "", background: "",
});

export const emptyVocabulary = (): TopicVocabulary => ({ term: "", definition: "", example_in_story: "" });
export const emptyGrammar = (): TopicGrammar => ({ grammar_structure: "", explanation: "", usage_in_story: "", examples: [""] });

export const emptyForm = (): TopicFormState => ({
  story_id: "",
  title_en: "",
  title_vi: "",
  difficulty_level: "A2",
  category: "daily_life",
  estimated_minutes: 15,
  icon_key: "chat",
  opening_prompt: "",
  suggested_prompts: [""],
  tags: "",
  persona: emptyPersona(),
  setting: "",
  scenario: "",
  objectives: [""],
  vocabulary: [],
  grammar: [],
});

const lines = (values: string[]) => values.map((v) => v.trim()).filter(Boolean);

/** What the service adds on its own; showing it in the tag box would only be noise. */
const AUTO_TAGS = new Set(["admin_topic", "topic_expansion", "tracecag"]);

/** The id the service will give a topic with this title (it slugifies the English title). */
export const topicIdFromTitle = (title: string) =>
  `story_${title.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "") || "topic"}`;

export const formFromStory = (story: TopicFull, mode: "edit" | "clone"): TopicFormState => {
  const clone = mode === "clone";
  const skip = new Set([...AUTO_TAGS, story.category, story.difficulty_level]);
  return {
    story_id: clone ? "" : story.story_id,
    title_en: clone ? `${story.title.en} (copy)` : story.title.en,
    title_vi: clone && story.title.vi ? `${story.title.vi} (bản sao)` : story.title.vi,
    difficulty_level: story.difficulty_level,
    category: story.category,
    estimated_minutes: story.estimated_minutes,
    icon_key: story.icon_key || story.category,
    opening_prompt: story.conversation_flow?.opening_prompt ?? "",
    suggested_prompts: story.suggested_prompts?.length ? [...story.suggested_prompts] : [""],
    tags: (story.tags ?? []).filter((tag) => !skip.has(tag)).join(", "),
    persona: { ...emptyPersona(), ...(story.role_persona ?? {}) },
    setting: story.context_description?.setting ?? "",
    scenario: story.context_description?.scenario ?? "",
    objectives: story.context_description?.objectives?.length ? [...story.context_description.objectives] : [""],
    vocabulary: (story.vocabulary_list ?? []).map((item) => ({ ...item })),
    grammar: (story.grammar_points ?? []).map((item) => ({ ...item, examples: [...(item.examples ?? [])] })),
  };
};

const personaFilled = (p: TopicPersona) => Object.values(p).some((v) => v.trim());
const personaComplete = (p: TopicPersona) => Object.values(p).every((v) => v.trim());

/** True when the form already holds content an AI draft would overwrite. */
export const hasAuthoredContent = (form: TopicFormState) =>
  personaFilled(form.persona) ||
  Boolean(form.scenario.trim()) ||
  form.vocabulary.some((v) => v.term.trim()) ||
  form.grammar.some((g) => g.grammar_structure.trim());

/** Fills everything the AI wrote and keeps what the admin chose: title, id, level, tags. */
export const applyDraft = (form: TopicFormState, draft: TopicDraft): TopicFormState => ({
  ...form,
  title_vi: draft.title_vi || form.title_vi,
  category: draft.category || form.category,
  icon_key: draft.icon_key || form.icon_key,
  estimated_minutes: draft.estimated_minutes || form.estimated_minutes,
  opening_prompt: draft.opening_prompt,
  suggested_prompts: draft.suggested_prompts.length ? [...draft.suggested_prompts] : form.suggested_prompts,
  persona: { ...emptyPersona(), ...draft.role_persona },
  setting: draft.context_description.setting,
  scenario: draft.context_description.scenario,
  objectives: draft.context_description.objectives.length ? [...draft.context_description.objectives] : [""],
  vocabulary: draft.vocabulary_list.map((item) => ({ ...item })),
  grammar: draft.grammar_points.map((item) => ({ ...item, examples: [...item.examples] })),
});

export type FormCheck = { errors: string[]; warnings: string[] };

/** Errors block saving (the service would refuse or the topic would be broken); warnings only advise. */
export const checkForm = (form: TopicFormState): FormCheck => {
  const errors: string[] = [];
  const warnings: string[] = [];

  if (form.title_en.trim().length < 3) errors.push("Give the topic an English title.");
  if (personaFilled(form.persona) && !personaComplete(form.persona)) {
    errors.push("Character: fill all five fields, or leave them all empty.");
  }
  if (Boolean(form.setting.trim()) !== Boolean(form.scenario.trim())) {
    errors.push("Scenario: fill both the setting and the scenario, or neither.");
  }
  for (const item of form.vocabulary) {
    if (item.term.trim() && (!item.definition.trim() || !item.example_in_story.trim())) {
      errors.push(`Vocabulary "${item.term.trim()}": add a definition and an example sentence.`);
    }
  }
  for (const item of form.grammar) {
    if (item.grammar_structure.trim() && !item.explanation.trim()) {
      errors.push(`Grammar "${item.grammar_structure.trim()}": add an explanation.`);
    }
  }

  const prompts = lines(form.suggested_prompts).length;
  if (prompts < 3) warnings.push(`Only ${prompts} suggested prompt${prompts === 1 ? "" : "s"}: they are the chips learners tap (3 works best).`);
  if (!form.opening_prompt.trim()) warnings.push("No opening line: a generic one will be used.");
  if (!personaFilled(form.persona)) warnings.push("No character: the AI will play a generic partner.");
  if (!form.scenario.trim()) warnings.push("No scenario: the conversation has no setting to follow.");
  const terms = form.vocabulary.filter((v) => v.term.trim()).length;
  if (terms === 0) warnings.push("No vocabulary: the AI has no target words to work in.");
  else if (terms < 6) warnings.push(`Only ${terms} vocabulary term${terms === 1 ? "" : "s"} (6 to 10 works best).`);
  if (!form.grammar.some((g) => g.grammar_structure.trim())) warnings.push("No grammar points.");
  if (!form.title_vi.trim()) warnings.push("No Vietnamese title: the English one will be shown.");

  return { errors, warnings };
};

export const payloadFromForm = (form: TopicFormState): TopicSavePayload => {
  const titleEn = form.title_en.trim();
  const minutes = Math.min(60, Math.max(5, Math.round(Number(form.estimated_minutes)) || 15));
  const payload: TopicSavePayload = {
    story_id: form.story_id.trim() || undefined,
    title: { en: titleEn, vi: form.title_vi.trim() || titleEn },
    difficulty_level: form.difficulty_level,
    category: form.category,
    estimated_minutes: minutes,
    icon_key: form.icon_key,
    opening_prompt: form.opening_prompt.trim() || undefined,
    suggested_prompts: lines(form.suggested_prompts),
    tags: form.tags.split(",").map((t) => t.trim()).filter(Boolean),
    is_published: true,
    vocabulary_list: form.vocabulary
      .filter((v) => v.term.trim())
      .map((v) => ({ ...v, term: v.term.trim(), definition: v.definition.trim(), example_in_story: v.example_in_story.trim() })),
    grammar_points: form.grammar
      .filter((g) => g.grammar_structure.trim())
      .map((g) => ({
        ...g,
        grammar_structure: g.grammar_structure.trim(),
        explanation: g.explanation.trim(),
        usage_in_story: (g.usage_in_story ?? "").trim(),
        examples: lines(g.examples),
      })),
  };
  if (personaFilled(form.persona)) {
    const p = form.persona;
    payload.role_persona = {
      name: p.name.trim(), role: p.role.trim(), personality: p.personality.trim(),
      speaking_style: p.speaking_style.trim(), background: p.background.trim(),
    };
  }
  if (form.setting.trim() && form.scenario.trim()) {
    payload.context_description = {
      setting: form.setting.trim(), scenario: form.scenario.trim(), objectives: lines(form.objectives),
    };
  }
  return payload;
};
