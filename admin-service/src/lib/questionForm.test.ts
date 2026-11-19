import { describe, expect, it } from "vitest";
import { isChoiceType, isGradableQuestion, loadChoiceState, loadPlainAnswer, normaliseOption, pickRandom, validateChoices } from "./questionForm";

describe("validateChoices", () => {
  it("needs two options", () => {
    expect(validateChoices(["a", ""], 0)).toContain("tooFew");
    expect(validateChoices(["a", "b"], 0)).toEqual([]);
  });
  it("rejects options equal after whitespace and case normalisation", () => {
    expect(validateChoices(["Hello  world", " hello world "], 0)).toContain("duplicate");
    expect(validateChoices(["a", "b"], 1)).toEqual([]);
  });
  it("needs a correct option that is not blank", () => {
    expect(validateChoices(["a", "b"], null)).toContain("noCorrect");
    expect(validateChoices(["a", "b", ""], 2)).toContain("noCorrect");
  });
});

describe("loadChoiceState", () => {
  const opts = ["Cat", "Dog", "Bird"];
  it("maps an int index", () => expect(loadChoiceState(opts, 1)).toEqual({ options: opts, correct: 1, unmatched: false }));
  it("maps a one-element list", () => expect(loadChoiceState(opts, ["Bird"]).correct).toBe(2));
  it("maps a dict", () => {
    expect(loadChoiceState(opts, { correct: "Cat" }).correct).toBe(0);
    expect(loadChoiceState(opts, { answer: 1 }).correct).toBe(1);
    expect(loadChoiceState(opts, { value: " dog " }).correct).toBe(1);
  });
  it("matches a string by normalisation", () => expect(loadChoiceState(opts, "  dOg ").correct).toBe(1));
  it("flags an answer that matches nothing", () => {
    expect(loadChoiceState(opts, "Fish")).toMatchObject({ correct: null, unmatched: true });
    expect(loadChoiceState(opts, 7)).toMatchObject({ correct: null, unmatched: true });
    expect(loadChoiceState(opts, ["a", "b"])).toMatchObject({ unmatched: true });
  });
  it("does not warn when there is no stored answer", () => {
    expect(loadChoiceState(opts, null)).toMatchObject({ correct: null, unmatched: false });
  });
});

describe("helpers", () => {
  it("recognises choice types case-insensitively", () => {
    expect(isChoiceType(" MCQ ")).toBe(true);
    expect(isChoiceType("fill_blank")).toBe(false);
  });
  it("normalises", () => expect(normaliseOption("  A\tB  ")).toBe("a b"));
  it("reads a plain answer", () => {
    expect(loadPlainAnswer("go")).toBe("go");
    expect(loadPlainAnswer(true)).toBe("true");
    expect(loadPlainAnswer({ correct: "x" })).toBe("x");
    expect(loadPlainAnswer(null)).toBe("");
  });
  it("pickRandom takes distinct items, all when short, using the injected rng", () => {
    const pool = [1, 2, 3, 4, 5];
    const rng = () => 0;
    const got = pickRandom(pool, 3, rng);
    expect(got).toHaveLength(3);
    expect(new Set(got).size).toBe(3);
    expect(pickRandom(pool, 3, rng)).toEqual(got);
    expect(pickRandom([1, 2], 5).sort()).toEqual([1, 2]);
    expect(pool).toEqual([1, 2, 3, 4, 5]);
  });
});

describe("isGradableQuestion", () => {
  const base = { is_active: true, question_type: "MCQ", options: ["Cat", "Dog"], answer: " dog " };
  it("accepts an active choice question whose answer matches one option", () => {
    expect(isGradableQuestion(base)).toBe(true);
  });
  it("rejects inactive, non-choice, short or unmatched questions", () => {
    expect(isGradableQuestion({ ...base, is_active: false })).toBe(false);
    expect(isGradableQuestion({ ...base, question_type: "fill_blank" })).toBe(false);
    expect(isGradableQuestion({ ...base, options: ["Cat"], answer: "Cat" })).toBe(false);
    expect(isGradableQuestion({ ...base, answer: "Fish" })).toBe(false);
    expect(isGradableQuestion({ ...base, answer: null })).toBe(false);
  });
  it("rejects options that collide after normalisation (answer would match two)", () => {
    expect(isGradableQuestion({ ...base, options: ["Dog", " dog ", "Cat"], answer: "dog" })).toBe(false);
  });
});
