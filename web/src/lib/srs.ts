// FSRS-5 spaced-repetition scheduler (client-side preview only).
//
// The authoritative scheduler is public.review_card() in
// supabase/migrations/0021_fsrs.sql — Postgres is the single source of truth
// so web, mobile and any future client can't disagree. What lives here is:
//   (a) previewNext() — what each rating button shows before you press it
//   (b) gradeFor()    — five-tier mastery label used by the dashboard
//
// Keep the arithmetic here in sync with 0021_fsrs.sql. When you change one,
// change the other. The test suite (srs.test.ts) pins the preview values
// against the same golden fixture used to validate the SQL.

export type Rating = "again" | "hard" | "good" | "easy";

// -------------------------------------------------------------------------
// FSRS-5 constants and default weights
// -------------------------------------------------------------------------

const DECAY = -0.5;
// FACTOR = 0.9^(1/DECAY) - 1 = 0.9^(-2) - 1 = 100/81 - 1 = 19/81
const FACTOR = 19 / 81;
// INTERVAL_FACTOR: I = S * INTERVAL_FACTOR gives the 90%-retention interval.
// Derived by solving R(I,S) = 0.9:
//   (1 + FACTOR*I/S)^(1/DECAY) = 0.9
//   I = S * (0.9^DECAY - 1) / FACTOR ≈ S * 0.2306
const INTERVAL_FACTOR = (Math.pow(0.9, DECAY) - 1) / FACTOR;

// Hard ceiling regardless of stability — must match v_max_interval in
// 0021_fsrs.sql, or the preview would show a number the server won't honor.
const MAX_INTERVAL_DAYS = 365;

// w[0]..w[18], 0-indexed. Source: ts-fsrs reference implementation.
const W = [
  0.4072, 1.1829, 3.1262, 15.4722, // w[0-3]  S_0 per rating (Again/Hard/Good/Easy)
  7.2102, 0.5316,                   // w[4-5]  initial difficulty formula
  1.0651, 0.0589,                   // w[6-7]  difficulty mean-reversion
  1.9395, 0.1100, 1.0145,           // w[8-10] recall stability
  1.9395, 0.1100, 1.0145, 0.2232,   // w[11-15] lapse stability + hard penalty
  2.9898,                           // w[16]   easy bonus
  0.5100, 2.9898, 0.5100,           // w[17-18] short-term (server-only)
];

// D_0(Easy) — the mean-reversion anchor (pre-computed, constant).
const D0_EASY = Math.max(1, Math.min(10, W[4] - Math.exp(W[5] * 3) + 1));

function initialDifficulty(g: 1 | 2 | 3 | 4): number {
  return Math.max(1, Math.min(10, W[4] - Math.exp(W[5] * (g - 1)) + 1));
}

function forgetting(elapsedDays: number, stability: number): number {
  return Math.pow(1 + FACTOR * elapsedDays / stability, 1 / DECAY);
}

// Recall stability (Hard/Good/Easy on a review card).
// W[15]=2.9898 boosts Easy; W[16]=0.51 penalises Hard.
function recallStability(D: number, S: number, R: number, rating: Rating): number {
  const hardPenalty = rating === "hard" ? W[16] : 1;
  const easyBonus   = rating === "easy" ? W[15] : 1;
  return S * (
    Math.exp(W[8]) * (11 - D) * Math.pow(S, -W[9])
    * (Math.exp(W[10] * (1 - R)) - 1)
    * hardPenalty * easyBonus
    + 1
  );
}

// Lapse stability (Again on a review card).
function lapseStability(D: number, S: number, R: number): number {
  return W[11] * Math.pow(D, -W[12]) * (Math.pow(S + 1, W[13]) - 1) * Math.exp(W[14] * (1 - R));
}

function updateDifficulty(D: number, g: 1 | 2 | 3 | 4): number {
  // Two-step: shift by current rating, then weakly revert to D_0(G).
  // W[6]=1.0651 is the per-rating step; W[7]=0.0589 is the mean-reversion weight.
  const next_d = D - W[6] * (g - 3);
  const D0_g   = initialDifficulty(g);
  return Math.max(1, Math.min(10, W[7] * D0_g + (1 - W[7]) * next_d));
}

function intervalFromStability(S: number): number {
  return Math.min(MAX_INTERVAL_DAYS, Math.max(1, Math.round(S * INTERVAL_FACTOR)));
}

// -------------------------------------------------------------------------
// Exported types
// -------------------------------------------------------------------------

export type CardState = "new" | "learning" | "review" | "relearning";

export interface PreviewCard {
  state: CardState;
  learning_step: number;
  interval_days: number;
  stability: number | null;
  difficulty: number | null;
  last_reviewed_at: string | null;
}

export type Preview =
  | { unit: "minutes"; value: number }
  | { unit: "days"; value: number };

// Learning step minutes — must match v_learn_steps in 0021_fsrs.sql.
export const LEARN_STEPS_MINUTES = [1, 10];
export const RELEARN_STEPS_MINUTES = [10];

// -------------------------------------------------------------------------
// previewNext: what each button shows before you press it
// -------------------------------------------------------------------------
export function previewNext(card: PreviewCard, rating: Rating): Preview {
  const step = card.learning_step;

  // New / learning — show intraday step consequences.
  if (card.state === "new" || card.state === "learning") {
    if (rating === "again") return { unit: "minutes", value: LEARN_STEPS_MINUTES[0] };
    if (rating === "hard")  return { unit: "minutes", value: LEARN_STEPS_MINUTES[Math.min(step, LEARN_STEPS_MINUTES.length - 1)] };
    if (rating === "easy") {
      // Skip steps, graduate with FSRS S_0(Easy).
      return { unit: "days", value: intervalFromStability(W[3]) };
    }
    // Good: advance one step; if this is the last step, graduate with S_0(Good).
    const next = step + 1;
    if (next >= LEARN_STEPS_MINUTES.length) {
      return { unit: "days", value: intervalFromStability(W[2]) };
    }
    return { unit: "minutes", value: LEARN_STEPS_MINUTES[next] };
  }

  // Relearning — show relearn step or graduation interval.
  if (card.state === "relearning") {
    if (rating === "again") return { unit: "minutes", value: RELEARN_STEPS_MINUTES[0] };
    const S = card.stability ?? Math.max(0.1, card.interval_days / INTERVAL_FACTOR);
    return { unit: "days", value: intervalFromStability(S) };
  }

  // Review state — FSRS formulas. The server also applies ±5% fuzz, which is
  // deliberately not previewed here: showing "23 days" and scheduling 24 would
  // read as a lie rather than a rounding note.
  const S = card.stability ?? Math.max(0.1, card.interval_days / INTERVAL_FACTOR);
  const D = card.difficulty ?? 5;

  const elapsedMs = card.last_reviewed_at
    ? Date.now() - new Date(card.last_reviewed_at).getTime()
    : 0;
  const elapsedDays = elapsedMs / 86_400_000;
  const R = Math.max(0.0001, Math.min(1, forgetting(elapsedDays, S)));

  if (rating === "again") {
    // Again moves the card to relearning → first relearn step fires immediately.
    // The post-relearn interval is not shown here (matches Anki's button label).
    return { unit: "minutes", value: RELEARN_STEPS_MINUTES[0] };
  }

  const g = rating === "hard" ? 2 : rating === "good" ? 3 : 4;
  const newD = updateDifficulty(D, g);
  const newS = Math.max(0.1, recallStability(newD, S, R, rating));
  return { unit: "days", value: intervalFromStability(newS) };
}

// -------------------------------------------------------------------------
// gradeFor: five-tier mastery label used by the stats dashboard
// -------------------------------------------------------------------------
export type Grade = "new" | "F" | "D" | "C" | "B" | "A";

export function gradeFor(word: { repetitions: number; interval_days: number }): Grade {
  if (word.repetitions === 0) return "new";
  if (word.interval_days <= 1)  return "F";
  if (word.interval_days <= 6)  return "D";
  if (word.interval_days <= 21) return "C";
  if (word.interval_days <= 60) return "B";
  return "A";
}
