// Share an active refresh so timer, visibility and button events cannot overlap.
export function singleFlight<T>(task: () => Promise<T>): () => Promise<T> {
  let active: Promise<T> | undefined;
  return () => {
    if (!active) {
      active = Promise.resolve().then(task).finally(() => { active = undefined; });
    }
    return active;
  };
}

// Wait for every request even on failure before allowing another refresh.
export async function settledValues<T extends readonly unknown[]>(requests: { [K in keyof T]: Promise<T[K]> }): Promise<T> {
  const results = await Promise.allSettled(requests);
  return results.map((result) => {
    if (result.status === 'rejected') throw result.reason;
    return result.value;
  }) as unknown as T;
}
