// Classic SM-2 spaced-repetition scheduler. Pure function: no Supabase/React
// dependency so it's trivially testable and reusable.
//
// IMPORTANT: this is no longer the thing that schedules cards. Since
// supabase/migrations/0009_review_card.sql, the authoritative scheduler is the
// `review_card()` Postgres function, so that web, mobile and any future client
// can't disagree about when a card is next due. What lives here is (a) the
// grade helper the dashboard uses and (b) the rating-button *previews*, which
// have to mirror the server closely enough to not lie to the user.
//
// If you change the arithmetic below, change 0009_review_card.sql to match, and
// vice versa. (Anki, incidentally, has defaulted to FSRS rather than SM-2 since
// 23.10 — see the migration notes before claiming parity anywhere user-facing.)

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

// Anki-style per-answer multipliers applied on top of the ease factor. Plain
// SM-2 grows every passing answer by the same EF, which makes "Хэцүү" and
// "Амархан" schedule identically to "Сайн" — the button choice carries no
// weight. Hard pulls the card back in, Easy pushes it further out.
const HARD_MULTIPLIER = 1.2;
const EASY_BONUS = 1.3;

export function computeNextReview(state: SrsState, rating: Rating, now = new Date()): SrsResult {
  const q = QUALITY[rating];
  let { ease_factor, interval_days, repetitions } = state;

  // Update the ease factor first so this answer's own interval reflects it;
  // applying it only from the next review is what made Hard/Easy inert.
  ease_factor = Math.max(MIN_EASE, ease_factor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));

  if (q < 3) {
    // Lapse ("Again") — start the interval progression over.
    repetitions = 0;
    interval_days = 1;
  } else {
    repetitions += 1;
    if (repetitions === 1) {
      interval_days = rating === "easy" ? 4 : 1;
    } else if (repetitions === 2) {
      interval_days = rating === "hard" ? 3 : rating === "easy" ? 8 : 6;
    } else {
      const factor =
        rating === "hard"
          ? HARD_MULTIPLIER
          : rating === "easy"
            ? ease_factor * EASY_BONUS
            : ease_factor;
      // Easy rounds up so it can't collide with Good on short intervals
      // (at 1 day both otherwise round to 3).
      const grown =
        rating === "easy"
          ? Math.ceil(interval_days * factor)
          : Math.round(interval_days * factor);
      // A passing answer never leaves the card on the same interval. The
      // floor is graduated by rating so that on short intervals at low ease —
      // where the floor, not the multiplier, decides — a better answer still
      // buys strictly more time instead of all three collapsing together.
      const floor = interval_days + (rating === "hard" ? 1 : rating === "easy" ? 3 : 2);
      interval_days = Math.max(floor, grown);
    }
  }

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

// ---------------------------------------------------------------------------
// Rating-button previews
//
// Each button shows what it will cost you before you press it. Once learning
// steps exist, a new card answered "Good" comes back in 10 minutes, not a day —
// so a preview built on computeNextReview() alone would be wrong for every card
// that hasn't graduated yet.
//
// These constants MUST match v_learn_steps / v_relearn_steps in
// supabase/migrations/0009_review_card.sql.
// ---------------------------------------------------------------------------
export const LEARN_STEPS_MINUTES = [1, 10];
export const RELEARN_STEPS_MINUTES = [10];
const GRADUATING_INTERVAL = 1;
const EASY_INTERVAL = 4;

export type CardState = "new" | "learning" | "review" | "relearning";

export interface PreviewCard extends SrsState {
  state: CardState;
  learning_step: number;
}

export type Preview =
  | { unit: "minutes"; value: number }
  | { unit: "days"; value: number };

export function previewNext(card: PreviewCard, rating: Rating): Preview {
  const step = card.learning_step;

  if (card.state === "new" || card.state === "learning") {
    if (rating === "again") return { unit: "minutes", value: LEARN_STEPS_MINUTES[0] };
    // Hard repeats the step the card is sitting on.
    if (rating === "hard") {
      return {
        unit: "minutes",
        value: LEARN_STEPS_MINUTES[Math.min(step, LEARN_STEPS_MINUTES.length - 1)],
      };
    }
    if (rating === "easy") return { unit: "days", value: EASY_INTERVAL };
    const next = step + 1;
    return next >= LEARN_STEPS_MINUTES.length
      ? { unit: "days", value: GRADUATING_INTERVAL }
      : { unit: "minutes", value: LEARN_STEPS_MINUTES[next] };
  }

  if (card.state === "relearning") {
    return rating === "again"
      ? { unit: "minutes", value: RELEARN_STEPS_MINUTES[0] }
      : { unit: "days", value: Math.max(1, card.interval_days) };
  }

  // Review state: a lapse drops into relearning; anything else follows SM-2.
  // The server also applies ±5% fuzz, which is deliberately not previewed —
  // showing "24 өдөр" and then scheduling 25 would read as a bug.
  return rating === "again"
    ? { unit: "minutes", value: RELEARN_STEPS_MINUTES[0] }
    : { unit: "days", value: computeNextReview(card, rating).interval_days };
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
