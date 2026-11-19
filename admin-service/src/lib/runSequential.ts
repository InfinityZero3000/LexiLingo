export type SequentialFailure<T> = { item: T; message: string };

export type SequentialResult<T> = {
  succeeded: T[];
  failed: SequentialFailure<T>[];
  stopped: boolean;
};

// One item at a time, on purpose: the AI provider rate-limits parallel calls.
// A rejected worker is recorded and the run continues; shouldStop is checked
// before each item, so a stop request lets the current item finish.
export const runSequential = async <T>(
  items: T[],
  worker: (item: T, index: number) => Promise<void>,
  opts: {
    shouldStop?: () => boolean;
    onProgress?: (index: number, item: T) => void;
  } = {},
): Promise<SequentialResult<T>> => {
  const result: SequentialResult<T> = { succeeded: [], failed: [], stopped: false };
  for (let i = 0; i < items.length; i++) {
    if (opts.shouldStop?.()) {
      result.stopped = true;
      break;
    }
    opts.onProgress?.(i, items[i]);
    try {
      await worker(items[i], i);
      result.succeeded.push(items[i]);
    } catch (err) {
      result.failed.push({
        item: items[i],
        message: err instanceof Error && err.message ? err.message : String(err),
      });
    }
  }
  return result;
};
