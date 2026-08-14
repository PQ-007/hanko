"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Undo2, X } from "lucide-react";
import type { Word } from "@/lib/types";
import { computeNextReview, type Rating } from "@/lib/srs";
import { supabase } from "../../_lib/db";
import { T } from "../../_lib/strings";
import PracticeCard from "./PracticeCard";
import RatingButtons from "./RatingButtons";
import SessionComplete from "./SessionComplete";

// One answered card, kept so it can be undone: the word exactly as it was
// before the rating, plus the log row that hasn't been written yet.
interface AnsweredStep {
  word: Word;
  rating: Rating;
  intervalDays: number;
  requeued: boolean;
}

export default function PracticeSession() {
  const params = useSearchParams();
  const deckId = params.get("deck");

  const [queue, setQueue] = useState<Word[] | null>(null);
  const [revealed, setRevealed] = useState(false);
  const [reviewedCount, setReviewedCount] = useState(0);
  const [history, setHistory] = useState<AnsweredStep[]>([]);

  // The most recent answer is held here rather than written immediately, so
  // Undo can drop it. Without this the log would keep a row the user took
  // back — and review_log is append-only by design (no delete policy).
  const pending = useRef<AnsweredStep | null>(null);

  const flushPending = useCallback(() => {
    const step = pending.current;
    if (!step) return;
    pending.current = null;
    supabase
      .from("review_log")
      .insert({
        user_id: step.word.user_id,
        word_id: step.word.id,
        deck_id: step.word.deck_id,
        rating: step.rating,
        interval_days: step.intervalDays,
      })
      .then(undefined, () => {});
  }, []);

  const load = useCallback(async () => {
    let query = supabase
      .from("words")
      .select("*")
      .eq("deleted", false)
      .lte("due_at", new Date().toISOString())
      .order("due_at", { ascending: true })
      .limit(20);
    if (deckId) query = query.eq("deck_id", deckId);
    const { data } = await query;
    setQueue((data as Word[]) ?? []);
  }, [deckId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  // Never lose the last answer if the tab goes away mid-session.
  useEffect(() => {
    const onHide = () => flushPending();
    window.addEventListener("pagehide", onHide);
    return () => {
      window.removeEventListener("pagehide", onHide);
      flushPending();
    };
  }, [flushPending]);

  const word = queue?.[0] ?? null;

  const rate = useCallback(
    async (rating: Rating) => {
      if (!word) return;
      const next = computeNextReview(word, rating);
      const requeued = rating === "again";

      flushPending(); // commit the previous answer; this one becomes undoable
      pending.current = { word, rating, intervalDays: next.interval_days, requeued };
      setHistory((h) => [...h, { word, rating, intervalDays: next.interval_days, requeued }]);

      setReviewedCount((c) => c + 1);
      setRevealed(false);
      setQueue((prev) => {
        const rest = (prev ?? []).slice(1);
        return requeued ? [...rest, word] : rest;
      });

      await supabase.from("words").update(next).eq("id", word.id);
    },
    [word, flushPending]
  );

  const undo = useCallback(async () => {
    const last = history[history.length - 1];
    if (!last) return;

    pending.current = null; // the answer being undone is never logged
    setHistory((h) => h.slice(0, -1));
    setReviewedCount((c) => Math.max(0, c - 1));
    setRevealed(true); // you were looking at the answer when you mis-clicked

    setQueue((prev) => {
      const rest = [...(prev ?? [])];
      // "Again" pushed the card to the back — take it out before re-heading it.
      if (last.requeued) {
        const at = rest.findIndex((w) => w.id === last.word.id);
        if (at !== -1) rest.splice(at, 1);
      }
      return [last.word, ...rest];
    });

    // Restore the pre-answer scheduling state.
    await supabase
      .from("words")
      .update({
        ease_factor: last.word.ease_factor,
        interval_days: last.word.interval_days,
        repetitions: last.word.repetitions,
        due_at: last.word.due_at,
        last_reviewed_at: last.word.last_reviewed_at,
      })
      .eq("id", last.word.id);
  }, [history]);

  // Keyboard: space/enter reveals, 1-4 rate, u undoes.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) {
        return;
      }
      if (!word) return;

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
  }, [word, revealed, rate, undo]);

  if (queue === null) {
    return <p className="p-8 text-center text-sm text-gray-500">{T.loadingWords}</p>;
  }

  if (!word) {
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
              onClick={flushPending}
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

      <PracticeCard word={word} revealed={revealed} onReveal={() => setRevealed(true)} />

      {revealed ? (
        <RatingButtons word={word} onRate={rate} />
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
