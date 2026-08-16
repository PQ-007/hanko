"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Undo2, X } from "lucide-react";
import type { Card } from "@/lib/types";
import type { Rating } from "@/lib/srs";
import type { QueueCard } from "../../_lib/types";
import { supabase } from "../../_lib/db";
import { T } from "../../_lib/strings";
import PracticeCard from "./PracticeCard";
import RatingButtons from "./RatingButtons";
import SessionComplete from "./SessionComplete";

// One answered card, kept so it can be undone. The log id is generated here on
// the client: review_card() uses it as an idempotency key, so a retried answer
// is applied exactly once, and undo_review() uses it to find the row.
interface AnsweredStep {
  logId: string;
  card: QueueCard;
  requeued: boolean;
}

export default function PracticeSession() {
  const params = useSearchParams();
  const deckId = params.get("deck");

  const [queue, setQueue] = useState<QueueCard[] | null>(null);
  const [revealed, setRevealed] = useState(false);
  const [reviewedCount, setReviewedCount] = useState(0);
  const [history, setHistory] = useState<AnsweredStep[]>([]);
  const [error, setError] = useState(false);

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
    const { data } = await supabase.rpc("review_queue", {
      p_deck_id: deckId,
      p_limit: 60,
    });
    setQueue((data as QueueCard[]) ?? []);
  }, [deckId]);

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

      setHistory((h) => [...h, { logId, card, requeued }]);
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
    [card]
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

  // Keyboard: space/enter reveals, 1-4 rate, u undoes.
  useEffect(() => {
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
  }, [card, revealed, rate, undo]);

  if (queue === null) {
    return <p className="p-8 text-center text-sm text-gray-500">{T.loadingWords}</p>;
  }

  if (!card) {
    if (reviewedCount > 0) return <SessionComplete count={reviewedCount} />;
    return (
      <div className="mx-auto max-w-md p-8 text-center">
        <div className="rounded-lg border border-dashed border-gray-300 bg-white p-10 text-gray-500">
          {T.noWordsDue}
        </div>
        <Link href="/decks" className="mt-4 inline-block text-sm font-medium text-gray-700 underline">
          {T.backToDecks}
        </Link>
      </div>
    );
  }

  const remaining = queue.length;
  const total = reviewedCount + remaining;
  const pct = total === 0 ? 0 : (reviewedCount / total) * 100;

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-5 px-4 py-6 sm:py-10">
      {/* Progress + session controls */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-xs text-gray-500">
          <span className="font-medium tabular-nums">
            {T.progressLabel(reviewedCount, total)}
          </span>
          <div className="flex items-center gap-1">
            <button
              onClick={undo}
              disabled={history.length === 0}
              title={T.undoTitle}
              className="flex items-center gap-1 rounded px-2 py-1 font-medium text-gray-500 transition hover:bg-gray-100 disabled:opacity-40 disabled:hover:bg-transparent"
            >
              <Undo2 size={13} /> {T.undo}
            </button>
            <Link
              href="/decks/stats"
              title={T.exitSession}
              className="flex items-center gap-1 rounded px-2 py-1 font-medium text-gray-500 transition hover:bg-gray-100"
            >
              <X size={13} /> {T.exitSession}
            </Link>
          </div>
        </div>
        <div className="h-1 overflow-hidden rounded-full bg-gray-200">
          <div
            style={{ width: `${pct}%` }}
            className="h-full rounded-full bg-gray-900 transition-[width] duration-300"
          />
        </div>
      </div>

      {error && (
        <p className="rounded border border-red-200 bg-red-50 px-3 py-2 text-center text-xs text-red-700">
          {T.saveFailed}
        </p>
      )}

      <PracticeCard card={card} revealed={revealed} onReveal={() => setRevealed(true)} />

      {revealed ? (
        <RatingButtons card={card} onRate={rate} />
      ) : (
        <button
          onClick={() => setRevealed(true)}
          className="w-full rounded-lg bg-gray-900 px-4 py-3 text-sm font-medium text-white transition hover:bg-gray-800"
        >
          {T.showAnswer}
        </button>
      )}

      <p className="text-center text-[11px] text-gray-400">
        {T.remainingN(remaining)} · {T.keyboardHint}
      </p>
    </div>
  );
}
