"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { Card } from "@/lib/types";
import type { Rating } from "@/lib/srs";
import type { QueueCard } from "./types";
import { supabase } from "./db";

// Extracted from PracticeSession.tsx (Phase B of the Davtah/Monster Hunt
// plan) so the real review-session logic — the review_queue()/review_card()/
// undo_review() calls, requeue-on-learning-state handling, undo, keyboard
// shortcuts — exists in exactly one place. Both the plain review screen and
// Monster Hunt consume this hook; neither re-implements any of it. That's
// the only way Monster Hunt can be "real scheduling, fight-themed visuals"
// without becoming a second, drift-prone copy of this logic.
//
// This file is a mechanical lift: the state and effects below are unchanged
// from what PracticeSession.tsx had inline, except one addition —
// AnsweredStep now carries `rating`, which Monster Hunt's HP bars derive via
// useMemo over `history` rather than a separate mutable HP value that could
// desync from undo.

export interface AnsweredStep {
  logId: string;
  card: QueueCard;
  requeued: boolean;
  rating: Rating;
}

// "due"  — the real scheduled queue (review_queue), answers reschedule cards.
// "free" — any card regardless of due date (practice_cards), answers change no
//          scheduling state at all.
export type SessionMode = "due" | "free";

// What review_card() is told the answer was. Deliberately separate from
// SessionMode: the mode picks which queue to read, the source decides what the
// answer means, and conflating them is how the wrong one gets sent.
//
//   'review' — classic self-rated practice.
//   'quiz'   — Monster Hunt. Real scheduling, but labelled, so a mode with a
//              25% guess floor can be compared against one without
//              (0018_quiz_source.sql). Identical to 'review' everywhere else:
//              streaks, heatmap and the daily caps all count it.
//   'drill'  — off-schedule practice. Logged and then discarded server-side.
//
// The distinction is enforced server-side too: review_card() returns the card
// untouched for any source it doesn't recognise as real practice, so a bug
// here can't silently corrupt scheduling — the worst case is a drill answer
// that fails to count, never a drill answer that wrongly does.
export type ReviewSource = "review" | "quiz" | "drill";

export interface UsePracticeSessionResult {
  queue: QueueCard[] | null;
  card: QueueCard | null;
  revealed: boolean;
  setRevealed: (revealed: boolean) => void;
  reviewedCount: number;
  history: AnsweredStep[];
  error: boolean;
  // Why the queue is empty, when it's empty for a bad reason. Without this,
  // a failed review_queue() call is indistinguishable from "nothing is due" —
  // both leave `queue` as [] and show the same friendly empty state, which
  // makes a real outage look like a normal quiet day.
  loadError: string | null;
  rate: (rating: Rating) => Promise<void>;
  undo: () => Promise<void>;
  remaining: number;
  total: number;
  pct: number;
}

export interface PracticeSessionOptions {
  mode?: SessionMode;
  source?: ReviewSource;
  /**
   * Whether this hook installs the classic keyboard shortcuts (space to
   * reveal, 1-4 to rate, u to undo).
   *
   * Monster Hunt must set this to false. Its interaction is a four-option
   * pick with no reveal step, so the classic bindings do not adapt to it —
   * they bypass it. Two presses of the space bar used to call rate("good")
   * straight through this hook: the card was scheduled and the queue advanced
   * while the fight never saw the answer at all, so no damage was rolled, no
   * HP moved, and `events` — which the HP bars are folded from — stayed
   * empty. The arena installs its own bindings instead.
   */
  shortcuts?: boolean;
}

export function usePracticeSession(
  deckId: string | null,
  { mode = "due", source = "review", shortcuts = true }: PracticeSessionOptions = {}
): UsePracticeSessionResult {
  const [queue, setQueue] = useState<QueueCard[] | null>(null);
  const [revealed, setRevealed] = useState(false);
  const [reviewedCount, setReviewedCount] = useState(0);
  const [history, setHistory] = useState<AnsweredStep[]>([]);
  const [error, setError] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  // When the current card was first shown, so each answer can report how long
  // it actually took. review_log.duration_ms is what battle mode later scales
  // damage against, and it can only be collected here, at answer time.
  // Set from an effect rather than a render-time initializer: reading the clock
  // during render is impure and the timer should start when the card is
  // actually on screen anyway.
  const shownAt = useRef<number>(0);

  const load = useCallback(async () => {
    // The server owns "what's due": the day cutoff and the per-day new/review
    // caps live in review_queue(), so web and mobile can't disagree about it.
    const { data, error: rpcError } = await supabase.rpc(
      mode === "free" ? "practice_cards" : "review_queue",
      { p_deck_id: deckId, p_limit: 60 }
    );
    // Surfaced rather than swallowed: an RPC failure previously fell through
    // to `[]` and rendered as the ordinary "nothing due" empty state, hiding
    // real breakage (a missing migration, an RLS change, a network drop)
    // behind a reassuring message.
    setLoadError(rpcError ? rpcError.message : null);
    setQueue((data as QueueCard[]) ?? []);
  }, [deckId, mode]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  const card = queue?.[0] ?? null;

  // Restart the clock whenever a different card comes to the front.
  useEffect(() => {
    shownAt.current = Date.now();
  }, [card?.card_id]);

  const rate = useCallback(
    async (rating: Rating) => {
      if (!card) return;
      const logId = crypto.randomUUID();
      const durationMs = shownAt.current ? Date.now() - shownAt.current : null;

      // Move on immediately; the answer is already committed server-side in one
      // transaction, so there's nothing to flush later or lose on navigation.
      setRevealed(false);
      setError(false);
      setReviewedCount((c) => c + 1);
      setQueue((prev) => (prev ?? []).slice(1));

      const { data, error: rpcError } = await supabase.rpc("review_card", {
        p_card_id: card.card_id,
        p_rating: rating,
        p_duration_ms: durationMs,
        p_log_id: logId,
        p_source: source,
      });

      if (rpcError) {
        // Put the card back rather than silently dropping the answer, which is
        // what the old two-call write did when the log insert failed.
        setError(true);
        setReviewedCount((c) => Math.max(0, c - 1));
        setQueue((prev) => [card, ...(prev ?? [])]);
        setRevealed(true);
        return;
      }

      // A card still inside the learning or relearning steps is due again in
      // minutes, so it comes back before the session ends — that's the whole
      // point of the steps. Anything that graduated is gone until its day.
      const updated = data as Card | null;
      const requeued =
        updated?.state === "learning" || updated?.state === "relearning";

      setHistory((h) => [...h, { logId, card, requeued, rating }]);
      if (requeued && updated) {
        setQueue((prev) => [
          ...(prev ?? []),
          {
            ...card,
            state: updated.state,
            learning_step: updated.learning_step,
            interval_days: updated.interval_days,
            repetitions: updated.repetitions,
            ease_factor: updated.ease_factor,
            due_at: updated.due_at,
          },
        ]);
      }
    },
    // `mode` is no longer read here — it picks the queue RPC, not the answer's
    // meaning. That split is the point of ReviewSource.
    [card, source]
  );

  const undo = useCallback(async () => {
    const last = history[history.length - 1];
    if (!last) return;

    setHistory((h) => h.slice(0, -1));
    setReviewedCount((c) => Math.max(0, c - 1));
    setRevealed(true); // you were looking at the answer when you mis-clicked
    setError(false);

    // undo_review() restores the card from the snapshot taken before the answer
    // and marks the log row undone (the log itself is append-only, so nothing
    // is deleted). Unlike the old in-memory undo, this works across devices.
    const { data, error: rpcError } = await supabase.rpc("undo_review", {
      p_log_id: last.logId,
    });
    if (rpcError) {
      setError(true);
      return;
    }

    const restored = data as Card | null;
    setQueue((prev) => {
      const rest = (prev ?? []).filter((c) => c.card_id !== last.card.card_id);
      const head: QueueCard = restored
        ? {
            ...last.card,
            state: restored.state,
            learning_step: restored.learning_step,
            interval_days: restored.interval_days,
            repetitions: restored.repetitions,
            ease_factor: restored.ease_factor,
            due_at: restored.due_at,
          }
        : last.card;
      return [head, ...rest];
    });
  }, [history]);

  // Keyboard: space/enter reveals, 1-4 rate, u undoes. Lives in the hook so the
  // classic screen and anything else that self-rates share one listener —
  // but opt-out, because a mode whose interaction is shaped differently needs
  // its own (see PracticeSessionOptions.shortcuts).
  useEffect(() => {
    if (!shortcuts) return;
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) {
        return;
      }
      if (!card) return;

      if (e.key === " " || e.key === "Enter") {
        e.preventDefault();
        if (!revealed) setRevealed(true);
        else rate("good");
        return;
      }
      if (e.key.toLowerCase() === "u") {
        e.preventDefault();
        undo();
        return;
      }
      if (revealed && ["1", "2", "3", "4"].includes(e.key)) {
        e.preventDefault();
        rate((["again", "hard", "good", "easy"] as Rating[])[Number(e.key) - 1]);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [card, revealed, rate, undo, shortcuts]);

  const remaining = queue?.length ?? 0;
  const total = reviewedCount + remaining;
  const pct = total === 0 ? 0 : (reviewedCount / total) * 100;

  return {
    queue,
    card,
    revealed,
    setRevealed,
    reviewedCount,
    history,
    error,
    loadError,
    rate,
    undo,
    remaining,
    total,
    pct,
  };
}
