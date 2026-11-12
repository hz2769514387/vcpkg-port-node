// Reached through a dynamic import, and only after a top-level await in the entry point.
export async function compute(n) {
  await Promise.resolve();
  return n * n;
}
