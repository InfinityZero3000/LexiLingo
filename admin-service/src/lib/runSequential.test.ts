import { describe, expect, it } from "vitest";
import { runSequential } from "./runSequential";

const tick = () => new Promise((r) => setTimeout(r, 1));

describe("runSequential", () => {
  it("runs in order, one at a time", async () => {
    let active = 0;
    let maxActive = 0;
    const seen: number[] = [];
    const res = await runSequential([1, 2, 3], async (n) => {
      active++;
      maxActive = Math.max(maxActive, active);
      await tick();
      seen.push(n);
      active--;
    });
    expect(seen).toEqual([1, 2, 3]);
    expect(maxActive).toBe(1);
    expect(res.succeeded).toEqual([1, 2, 3]);
    expect(res.failed).toEqual([]);
    expect(res.stopped).toBe(false);
  });

  it("continues after a rejection and reports it", async () => {
    const res = await runSequential(["a", "b", "c"], async (x) => {
      if (x === "b") throw new Error("boom");
    });
    expect(res.succeeded).toEqual(["a", "c"]);
    expect(res.failed).toEqual([{ item: "b", message: "boom" }]);
  });

  it("honours stop before the next item", async () => {
    let stop = false;
    const progress: number[] = [];
    const res = await runSequential(
      [1, 2, 3],
      async (n) => {
        if (n === 1) stop = true;
      },
      { shouldStop: () => stop, onProgress: (i) => progress.push(i) },
    );
    expect(res.succeeded).toEqual([1]);
    expect(res.stopped).toBe(true);
    expect(progress).toEqual([0]);
  });
});
