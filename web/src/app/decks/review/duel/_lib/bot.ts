import type { DuelAnswer } from "./duel";

// The bot opponent (PVP.md phase 2).
//
// CLAUDE.md 3.2: "Ship the bot opponent first. It makes the mode playable from
// day one and defers all matchmaking work." This module is the whole of it —
// everything else about a bot duel is the same arena a real duel uses.
//
// `rng` is injected rather than calling Math.random directly, the same trick
// damage.test.ts uses to pin crit and evade: a stubbed generator makes every
// property below testable instead of merely plausible.

export type BotDifficulty = "rookie" | "rival" | "master";

export interface BotProfile {
  /** Probability of answering correctly, when it answers at all. */
  accuracy: number;
  /** Centre of its reaction-time distribution. */
  meanReactionMs: number;
  /** Half-width of the uniform jitter around the mean. */
  reactionJitterMs: number;
}

// Untuned first-pass numbers — PVP.md phase 5. The names are user-facing; the
// numbers are guesses until someone has played all three.
export const BOT_PROFILES: Record<BotDifficulty, BotProfile> = {
  rookie: { accuracy: 0.55, meanReactionMs: 3600, reactionJitterMs: 1400 },
  rival: { accuracy: 0.75, meanReactionMs: 2600, reactionJitterMs: 1100 },
  master: { accuracy: 0.9, meanReactionMs: 1700, reactionJitterMs: 700 },
};

export const BOT_DIFFICULTIES = ["rookie", "rival", "master"] as const;

export function isBotDifficulty(value: string | null): value is BotDifficulty {
  return value !== null && (BOT_DIFFICULTIES as readonly string[]).includes(value);
}

/**
 * Samples one round's answer.
 *
 * Returns `null` when the sampled reaction runs past the round timer — the bot
 * ran out of time, exactly like a human who froze. This matters more than it
 * looks: a bot that always answers inside the timer is not a difficulty
 * setting, it is a different game, and at `master`'s 1.7s mean it would be an
 * unlosable one.
 *
 * Draw order is fixed and part of the contract: reaction first, correctness
 * second. Tests stub `rng` with a scripted sequence, so swapping them would
 * silently invert every expectation.
 */
export function botAnswer(
  profile: BotProfile,
  rng: () => number,
  roundDurationMs: number
): DuelAnswer | null {
  const jitter = (rng() * 2 - 1) * profile.reactionJitterMs;
  const elapsedMs = Math.max(200, Math.round(profile.meanReactionMs + jitter));
  const correct = rng() < profile.accuracy;

  if (elapsedMs >= roundDurationMs) return null;
  return { correct, elapsedMs };
}

/**
 * The baseline the bot's damage is scaled against — its own mean reaction.
 *
 * Same rule as a human: measured against itself. Handing the bot a human's
 * baseline (or a constant) would make `master` hit like a freak of nature
 * simply for being fast, rather than for beating its own normal.
 */
export function botBaselineMs(profile: BotProfile): number {
  return profile.meanReactionMs;
}
