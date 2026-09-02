import type { DuelAnswer } from "./duel";
import { botAnswer, botBaselineMs, type BotProfile } from "./bot";

// The seam between the arena and whoever it is fighting.
//
// The arena must not know whether the other side is a bot sampling a
// distribution or a person on another machine — otherwise the Realtime work in
// PVP.md phase 4 becomes a rewrite of the round loop rather than a second
// implementation of this interface. Both drivers answer the same question:
// "what did the opponent do in round N, and when?"
//
// Every driver's `answerFor` MUST settle within the round's duration. The
// round closes when both sides have answered, so a driver that can hang would
// hang the match.

export interface OpponentDriver {
  /** Display name. */
  name: string;
  /** Sprite slug, resolved by the caller so a duel can mirror a real hero. */
  slug: string;
  /**
   * The opponent's own median response time, for damage scaling. Null falls
   * back to the constant in duel.ts — see speedRatio's note on why both sides
   * are measured against themselves.
   */
  baselineMs: number | null;
  answerFor(roundNo: number, durationMs: number, signal: AbortSignal): Promise<DuelAnswer | null>;
  /** Publishes the local player's answer. No-op for a bot — nobody is watching. */
  submit?(roundNo: number, answer: DuelAnswer | null, cardId: string | null): Promise<void>;
  dispose?(): void;
}

/**
 * A bot that answers in its own time.
 *
 * The sample is drawn at the top of the round but only *revealed* when its
 * reaction time elapses, so the wait feels like an opponent thinking rather
 * than a number appearing. That the answer is already decided is invisible and
 * has to be: resolving it late would mean a bot whose accuracy changed
 * depending on how fast the player was.
 */
export function createBotOpponent(
  name: string,
  slug: string,
  profile: BotProfile
): OpponentDriver {
  return {
    name,
    slug,
    baselineMs: botBaselineMs(profile),
    answerFor(_roundNo, durationMs, signal) {
      const answer = botAnswer(profile, Math.random, durationMs);
      // A miss is revealed at the buzzer, exactly like a human running out of
      // time — not instantly, which would leak that the bot had given up.
      const revealAt = answer ? answer.elapsedMs : durationMs;
      return new Promise((resolve) => {
        if (signal.aborted) return resolve(null);
        const id = setTimeout(() => resolve(answer), revealAt);
        signal.addEventListener("abort", () => {
          clearTimeout(id);
          resolve(null);
        });
      });
    },
  };
}
