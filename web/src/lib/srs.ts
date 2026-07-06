// Classic SM-2 spaced-repetition scheduler (the algorithm Anki itself is
// built on). Pure function: no Supabase/React dependency so it's trivially
// testable and reusable.

export type Rating = "again" | "hard" | "good" | "easy";

export interface SrsState {
  ease_factor: number;
  interval_days: number;
  repetitions: number;
}

export interface SrsResult extends SrsState {
  due_at: string;
  last_reviewed_at: string;
}

// Maps the 4-button UI onto SM-2's 0-5 quality scale.
const QUALITY: Record<Rating, number> = { again: 0, hard: 3, good: 4, easy: 5 };

const MIN_EASE = 1.3;

export function computeNextReview(state: SrsState, rating: Rating, now = new Date()): SrsResult {
  const q = QUALITY[rating];
  let { ease_factor, interval_days, repetitions } = state;

  if (q < 3) {
    // Lapse ("Again") — start the interval progression over.
    repetitions = 0;
    interval_days = 1;
  } else {
    repetitions += 1;
    if (repetitions === 1) interval_days = 1;
    else if (repetitions === 2) interval_days = 6;
    else interval_days = Math.round(interval_days * ease_factor);
  }

  ease_factor = Math.max(MIN_EASE, ease_factor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));

  const due = new Date(now);
  due.setDate(due.getDate() + interval_days);

  return {
    ease_factor: Math.round(ease_factor * 100) / 100,
    interval_days,
    repetitions,
    due_at: due.toISOString(),
    last_reviewed_at: now.toISOString(),
  };
}

// Five-tier mastery grade derived from how far out a word's next review sits.
// "new" means it's never been reviewed; F-A track interval_days growth.
export type Grade = "new" | "F" | "D" | "C" | "B" | "A";

export function gradeFor(word: Pick<SrsState, "repetitions" | "interval_days">): Grade {
  if (word.repetitions === 0) return "new";
  if (word.interval_days <= 1) return "F";
  if (word.interval_days <= 6) return "D";
  if (word.interval_days <= 21) return "C";
  if (word.interval_days <= 60) return "B";
  return "A";
}
