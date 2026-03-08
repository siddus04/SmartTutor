type AttemptState = {
  incorrectCount: number;
  updatedAt: number;
};

const ATTEMPT_TTL_MS = 1000 * 60 * 60 * 24 * 7;
const attemptStore = new Map<string, AttemptState>();

function keyFor(learnerId: string, questionId: string) {
  return `${learnerId}::${questionId}`;
}

function pruneExpired(now: number) {
  for (const [key, value] of attemptStore.entries()) {
    if (now - value.updatedAt > ATTEMPT_TTL_MS) {
      attemptStore.delete(key);
    }
  }
}

export function getIncorrectAttempts(learnerId: string, questionId: string): number {
  const now = Date.now();
  pruneExpired(now);
  const key = keyFor(learnerId, questionId);
  return attemptStore.get(key)?.incorrectCount ?? 0;
}

export function recordOutcome(learnerId: string, questionId: string, correctness: "correct" | "incorrect" | "ambiguous" | "error"): number {
  const now = Date.now();
  pruneExpired(now);
  const key = keyFor(learnerId, questionId);
  if (correctness === "correct") {
    attemptStore.delete(key);
    return 0;
  }
  const current = attemptStore.get(key)?.incorrectCount ?? 0;
  const next = current + 1;
  attemptStore.set(key, { incorrectCount: next, updatedAt: now });
  return next;
}
