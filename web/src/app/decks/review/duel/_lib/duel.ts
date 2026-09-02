// Duel rules — Найзтайгаа тулах (PVP.md phase 1).
//
// Deliberately NOT built on damage.ts. That module encodes player-vs-
// environment rules which are quietly wrong here rather than loudly: its fold
// exists to refill a *respawning* monster (monsterStartIndex), its armour is
// granted off an endless-gauntlet streak, its `battleOutcome` ends the run
// when the review queue empties, and above all it assumes ONE answer stream.
// A duel has two, each side's damage is a function of the other's answer, and
// it ends on HP or on a round count that has nothing to do with any queue.
//
// What IS inherited is the architecture note at the top of damage.ts: resolve
// once, then fold purely. So resolveRound() decides a round's damage exactly
// once, and deriveDuelState() only ever adds up already-decided numbers — safe
// to call from a useMemo on every render.
//
// One deliberate difference from damage.ts: there is NO randomness here. No
// crit roll, no evade roll. That is not an omission — from PVP.md phase 3 on,
// Postgres computes damage and the client only renders it, and a rule with no
// RNG is one both sides can compute and compare. A crit roll would make client
// and server disagree by design.
//
// Every number below is a first-pass tunable, not a designed system. PVP.md
// phase 5 is where they get earned.

export const DUEL_MAX_HP = 100;

// Bounded match length. Twelve rounds of a ~4s timer is about a minute of
// play, and at the damage numbers below a flawless run lands just short of a
// kill — so most matches are decided by streaks and speed in the last few
// rounds rather than by a knockout at round four.
export const DUEL_ROUND_COUNT = 12;

// PVP.md / CLAUDE.md 3.2: "round timer 3-5s, tightening as the match
// progresses". Linear from 5s, floored at 3s by round 9, flat thereafter.
const FIRST_ROUND_MS = 5000;
const FINAL_ROUND_MS = 3000;
const TIGHTEN_PER_ROUND_MS = 250;

export function roundDurationMs(roundNo: number): number {
  const shortened = FIRST_ROUND_MS - (Math.max(1, roundNo) - 1) * TIGHTEN_PER_ROUND_MS;
  return Math.max(FINAL_ROUND_MS, shortened);
}

// Used when response_baseline() returns null — fewer than its minimum sample
// count of real reviews, so there is no honest personal median to scale
// against yet. A constant is the correct answer there: a baseline computed
// from three answers is noise dressed up as personalisation.
export const FALLBACK_BASELINE_MS = 4500;

// Below this, an "answer" is a reflex or a script, not recall. Also stops a
// near-zero elapsed time from dividing the ratio to infinity.
const ELAPSED_FLOOR_MS = 350;

const MIN_SPEED_RATIO = 0.6;
const MAX_SPEED_RATIO = 1.6;

const BASE_DAMAGE = 8;

// The streak meter (CLAUDE.md 3.2: "correct-answer streaks fill a meter for a
// bigger finisher hit"). Tiered rather than continuous so the jump is
// something the player can feel and the UI can announce.
export const DUEL_STREAK_TIERS = [3, 6] as const;
const STREAK_MULTIPLIERS = [1, 1.2, 1.4] as const;

export function duelStreakTier(streak: number): number {
  if (streak >= DUEL_STREAK_TIERS[1]) return 2;
  if (streak >= DUEL_STREAK_TIERS[0]) return 1;
  return 0;
}

/**
 * How fast this answer was *for this player*, as a multiple of their own
 * median response time.
 *
 * This is the whole reason Phase 0.4 insisted `review_log.duration_ms` land
 * before mobile rather than alongside battle mode. Both players are measured
 * against themselves, so a habitual 2-second answerer does not beat a
 * 6-second answerer by default — each has to beat their own normal. Without
 * it, PvP is a typing-speed contest with vocabulary decoration.
 */
export function speedRatio(elapsedMs: number, baselineMs: number | null): number {
  const baseline = baselineMs && baselineMs > 0 ? baselineMs : FALLBACK_BASELINE_MS;
  const elapsed = Math.max(ELAPSED_FLOOR_MS, elapsedMs);
  const raw = baseline / elapsed;
  return Math.min(MAX_SPEED_RATIO, Math.max(MIN_SPEED_RATIO, raw));
}

export interface DuelAnswer {
  correct: boolean;
  /** Time from question shown to pick. For a timeout this is the full round. */
  elapsedMs: number;
}

/**
 * Damage one answer deals. `null` is a round the player let expire.
 *
 * A wrong answer and a timeout both deal nothing — and neither carries a
 * self-penalty. Losing the exchange is the penalty: taking damage for being
 * wrong on top of dealing none makes a bad run unrecoverable, which is
 * exactly when a player quits.
 */
export function roundDamage(
  answer: DuelAnswer | null,
  baselineMs: number | null,
  streakBefore: number
): number {
  if (!answer || !answer.correct) return 0;
  const multiplier = STREAK_MULTIPLIERS[duelStreakTier(streakBefore)];
  return Math.round(BASE_DAMAGE * speedRatio(answer.elapsedMs, baselineMs) * multiplier);
}

export interface ResolvedRound {
  roundNo: number;
  you: DuelAnswer | null;
  them: DuelAnswer | null;
  /** Damage YOU dealt to THEM this round. */
  yourDamage: number;
  /** Damage THEY dealt to YOU this round. */
  theirDamage: number;
}

export interface DuelState {
  yourHp: number;
  theirHp: number;
  yourStreak: number;
  theirStreak: number;
  roundsPlayed: number;
  /** The most recent round's damage, for the floating numbers. */
  lastYourDamage: number;
  lastTheirDamage: number;
  yourDefeated: boolean;
  theirDefeated: boolean;
}

export const INITIAL_DUEL_STATE: DuelState = {
  yourHp: DUEL_MAX_HP,
  theirHp: DUEL_MAX_HP,
  yourStreak: 0,
  theirStreak: 0,
  roundsPlayed: 0,
  lastYourDamage: 0,
  lastTheirDamage: 0,
  yourDefeated: false,
  theirDefeated: false,
};

/**
 * Decides one round's damage. Impure only in the sense that it must be called
 * exactly once per round — it reads `stateBefore` for the streak multipliers
 * and must not be re-run against a state that already includes its own result.
 */
export function resolveRound(
  roundNo: number,
  you: DuelAnswer | null,
  them: DuelAnswer | null,
  yourBaselineMs: number | null,
  theirBaselineMs: number | null,
  stateBefore: DuelState
): ResolvedRound {
  return {
    roundNo,
    you,
    them,
    yourDamage: roundDamage(you, yourBaselineMs, stateBefore.yourStreak),
    theirDamage: roundDamage(them, theirBaselineMs, stateBefore.theirStreak),
  };
}

/** Pure fold over already-resolved rounds. Never decides anything. */
export function deriveDuelState(rounds: ResolvedRound[]): DuelState {
  let yourHp = DUEL_MAX_HP;
  let theirHp = DUEL_MAX_HP;
  let yourStreak = 0;
  let theirStreak = 0;
  let lastYourDamage = 0;
  let lastTheirDamage = 0;

  for (const r of rounds) {
    // Damage applies to the OTHER side. Both land together, which is what
    // makes a simultaneous knockout — and therefore a draw — reachable.
    theirHp = Math.max(0, theirHp - r.yourDamage);
    yourHp = Math.max(0, yourHp - r.theirDamage);

    yourStreak = r.you?.correct ? yourStreak + 1 : 0;
    theirStreak = r.them?.correct ? theirStreak + 1 : 0;

    lastYourDamage = r.yourDamage;
    lastTheirDamage = r.theirDamage;
  }

  return {
    yourHp,
    theirHp,
    yourStreak,
    theirStreak,
    roundsPlayed: rounds.length,
    lastYourDamage,
    lastTheirDamage,
    yourDefeated: yourHp <= 0,
    theirDefeated: theirHp <= 0,
  };
}

export type DuelOutcome = "ongoing" | "won" | "lost" | "draw";

/**
 * A draw is a real outcome, not an edge case to round away: both sides' damage
 * lands in the same round, so a simultaneous knockout genuinely happens, and
 * equal HP after the final round is the ordinary way a match between two
 * evenly-matched players ends. Without a state for it, both render as a loss.
 */
export function duelOutcome(
  state: DuelState,
  roundCount: number = DUEL_ROUND_COUNT
): DuelOutcome {
  if (state.yourDefeated && state.theirDefeated) return "draw";
  if (state.yourDefeated) return "lost";
  if (state.theirDefeated) return "won";
  if (state.roundsPlayed >= roundCount) {
    if (state.yourHp > state.theirHp) return "won";
    if (state.yourHp < state.theirHp) return "lost";
    return "draw";
  }
  return "ongoing";
}
