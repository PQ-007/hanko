import { useEffect, useRef, useState } from "react";

// The per-question clock, owned in one place.
//
// It used to be two: BattleArena held a setTimeout that auto-answered a miss,
// and CountdownBar held its own interval driving the bar and the seconds
// readout. Started together they agreed closely enough, but neither could be
// stopped without the other — which is exactly what a pause button needs. One
// clock also means the bar can never disagree with the deadline it's drawing.
//
// Pause is `running: false`: the interval is torn down and `remainingRef`
// keeps whatever was left, so resuming picks up from there instead of
// restarting the question or expiring instantly.

const TICK_MS = 100;

export interface QuestionClock {
  /** Milliseconds left, updated ~10x a second. For display. */
  remainingMs: number;
  /**
   * Exact milliseconds spent on the current question, read on demand.
   * Not derived from `remainingMs`: that's quantised to TICK_MS, and the
   * speed tiers are decided on 3333ms/6667ms boundaries where 100ms of slop
   * would change the rating a real answer gets.
   */
  elapsedMs: () => number;
}

export function useQuestionClock({
  durationMs,
  resetKey,
  running,
  onExpire,
}: {
  durationMs: number;
  /**
   * Must be unique per question *presentation*, not per card: a card requeued
   * by the learning steps comes back with the same card_id, and keying on
   * that alone leaves the clock stuck at zero when it reappears.
   */
  resetKey: string | number;
  running: boolean;
  onExpire: () => void;
}): QuestionClock {
  const [remainingMs, setRemainingMs] = useState(durationMs);
  const remainingRef = useRef(durationMs);
  // Wall-clock anchor for the currently running segment. A question that has
  // been paused and resumed has several of these; elapsed is always measured
  // against the current one plus whatever was banked before it.
  const segment = useRef({ startedAt: 0, startRemaining: durationMs });
  const expireRef = useRef(onExpire);

  // Kept fresh in an effect rather than assigned during render. The callback
  // it holds reads BattleArena's refs, not its state, so a one-render-stale
  // reference would be harmless anyway — but writing refs during render isn't
  // something to do casually.
  useEffect(() => {
    expireRef.current = onExpire;
  });

  useEffect(() => {
    // Deliberate synchronous reset: a new question must snap the clock back to
    // full immediately, not one tick later (which would briefly show the
    // previous question's leftover time, and could expire it instantly).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setRemainingMs(durationMs);
    remainingRef.current = durationMs;
    segment.current = { startedAt: Date.now(), startRemaining: durationMs };
  }, [resetKey, durationMs]);

  useEffect(() => {
    if (!running || remainingRef.current <= 0) return;
    segment.current = { startedAt: Date.now(), startRemaining: remainingRef.current };
    const id = setInterval(() => {
      const left = Math.max(
        0,
        segment.current.startRemaining - (Date.now() - segment.current.startedAt)
      );
      remainingRef.current = left;
      setRemainingMs(left);
      if (left <= 0) {
        clearInterval(id);
        expireRef.current();
      }
    }, TICK_MS);
    return () => clearInterval(id);
  }, [running, resetKey]);

  return {
    remainingMs,
    elapsedMs: () => {
      const left = running
        ? Math.max(
            0,
            segment.current.startRemaining - (Date.now() - segment.current.startedAt)
          )
        : remainingRef.current;
      return durationMs - left;
    },
  };
}
