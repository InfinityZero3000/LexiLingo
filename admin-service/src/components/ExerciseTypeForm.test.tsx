// @vitest-environment jsdom
import { useState } from "react";
import { afterEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { ExerciseTypeForm } from "./ExerciseTypeForm";
import type { Exercise } from "../lib/adminApi";

const blank: Exercise = {
  id: "x", type: "reorder", ui_type: "arrange_the_sentence", question: "Arrange", options: null,
  correct_answer: "", explanation: null, hint: null, audio_url: null, image_url: null, difficulty: 1, points: 10,
};

let latest: Exercise = blank;
const Harness = () => {
  const [value, setValue] = useState(blank);
  latest = value;
  return <ExerciseTypeForm uiType="arrange_the_sentence" value={value} onChange={setValue} />;
};

describe("arrange-the-sentence word bank", () => {
  afterEach(cleanup);

  it("can be typed one character at a time, separators included", () => {
    render(<Harness />);
    const input = screen.getByPlaceholderText("they / study / every / day") as HTMLInputElement;

    for (const char of "they / study") fireEvent.change(input, { target: { value: input.value + char } });

    expect(input.value).toBe("they / study");
    expect(latest.options?.map((o) => o.text)).toEqual(["they", "study"]);
  });
});
