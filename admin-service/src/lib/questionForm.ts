const CHOICE_TYPES = ["mcq", "multiple_choice", "single_choice"];

export const isChoiceType = (type: string) => CHOICE_TYPES.includes(type.trim().toLowerCase());

// Same normalisation the promotion exam grader applies: collapse whitespace, trim, casefold.
export const normaliseOption = (text: string) => text.replace(/\s+/g, " ").trim().toLowerCase();

export type ChoiceProblem = "tooFew" | "duplicate" | "noCorrect";

export const validateChoices = (rows: string[], correct: number | null): ChoiceProblem[] => {
  const filled = rows.map((r) => r.trim()).filter(Boolean);
  const problems: ChoiceProblem[] = [];
  if (filled.length < 2) problems.push("tooFew");
  if (new Set(filled.map(normaliseOption)).size < filled.length) problems.push("duplicate");
  if (correct === null || !rows[correct]?.trim()) problems.push("noCorrect");
  return problems;
};

const asText = (value: unknown): string =>
  typeof value === "string" || typeof value === "number" || typeof value === "boolean" ? String(value) : "";

// Legacy rows store the answer as an index, a one-element list or {correct|answer|value}.
const unwrapAnswer = (answer: unknown): unknown => {
  let current = answer;
  for (let i = 0; i < 3; i += 1) {
    if (Array.isArray(current)) {
      if (current.length !== 1) return undefined;
      current = current[0];
    } else if (current && typeof current === "object") {
      const dict = current as Record<string, unknown>;
      current = dict.correct ?? dict.answer ?? dict.value;
    } else break;
  }
  return current;
};

export type ChoiceState = { options: string[]; correct: number | null; unmatched: boolean };

export const loadChoiceState = (options: unknown, answer: unknown): ChoiceState => {
  const rows = Array.isArray(options) ? options.map(asText) : [];
  if (answer === null || answer === undefined || answer === "") return { options: rows, correct: null, unmatched: false };
  const value = unwrapAnswer(answer);
  let correct: number | null = null;
  if (typeof value === "number" && Number.isInteger(value)) {
    correct = value >= 0 && value < rows.length ? value : null;
  } else if (typeof value === "string" || typeof value === "boolean") {
    const wanted = normaliseOption(String(value));
    const hit = rows.findIndex((r) => normaliseOption(r) === wanted);
    correct = hit >= 0 ? hit : null;
  }
  return { options: rows, correct, unmatched: correct === null };
};

export const loadPlainAnswer = (answer: unknown): string => asText(unwrapAnswer(answer));

export const pickRandom = <T,>(pool: T[], count: number, rng: () => number = Math.random): T[] => {
  const copy = [...pool];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(rng() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy.slice(0, Math.max(0, count));
};

// Mirrors what the promotion exam can grade: active, a choice type, 2+ options and an
// answer that matches exactly one of them. Anything else is silently left out of the paper.
export const isGradableQuestion = (q: {
  is_active: boolean;
  question_type: string;
  options?: unknown;
  answer?: unknown;
}): boolean => {
  if (!q.is_active || !isChoiceType(q.question_type)) return false;
  const { options, correct } = loadChoiceState(q.options, q.answer);
  if (options.length < 2 || correct === null) return false;
  return new Set(options.map(normaliseOption)).size === options.length;
};
