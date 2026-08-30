"use client";

import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Undo2, X } from "lucide-react";
import { T } from "../../_lib/strings";
import { usePracticeSession } from "../../_lib/usePracticeSession";
import PracticeCard from "./PracticeCard";
import RatingButtons from "./RatingButtons";
import SessionComplete from "./SessionComplete";
import LoadingScene from "../../review/battle/_components/LoadingScene";

export default function PracticeSession() {
  const params = useSearchParams();
  const deckId = params.get("deck");

  const {
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
  } = usePracticeSession(deckId);

  if (queue === null) {
    return <LoadingScene label={T.loadingWords} />;
  }

  if (!card) {
    if (reviewedCount > 0) return <SessionComplete count={reviewedCount} />;
    return (
      <div className="mx-auto max-w-md p-8 text-center">
        {loadError ? (
          // Distinct from the ordinary empty state: a failed review_queue()
          // call used to fall through to "nothing due", hiding real breakage.
          <div className="rounded-control border border-red-200 bg-red-50 p-6 text-sm text-red-700">
            <p className="font-medium">{T.queueLoadFailed}</p>
            <p className="mt-2 text-xs opacity-80">{loadError}</p>
          </div>
        ) : (
          <div className="rounded-control border border-dashed border-line bg-white p-10 text-ink-soft">
            {T.noWordsDue}
          </div>
        )}
        <Link href="/decks" className="mt-4 inline-block text-sm font-medium text-ink underline">
          {T.backToDecks}
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-5 px-4 py-6 sm:py-10">
      {/* Progress + session controls */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-xs text-ink-soft">
          <span className="font-medium tabular-nums">
            {T.progressLabel(reviewedCount, total)}
          </span>
          <div className="flex items-center gap-1">
            <button
              onClick={undo}
              disabled={history.length === 0}
              title={T.undoTitle}
              className="flex items-center gap-1 rounded-control px-2 py-1 font-medium text-ink-soft transition hover:bg-paper-dim disabled:opacity-40 disabled:hover:bg-transparent"
            >
              <Undo2 size={13} /> {T.undo}
            </button>
            <Link
              href="/decks/stats"
              title={T.exitSession}
              className="flex items-center gap-1 rounded-control px-2 py-1 font-medium text-ink-soft transition hover:bg-paper-dim"
            >
              <X size={13} /> {T.exitSession}
            </Link>
          </div>
        </div>
        <div className="h-1 overflow-hidden rounded-full bg-paper-deep">
          <div
            style={{ width: `${pct}%` }}
            className="h-full rounded-full bg-seal transition-[width] duration-300"
          />
        </div>
      </div>

      {error && (
        <p className="rounded-control border border-red-200 bg-red-50 px-3 py-2 text-center text-xs text-red-700">
          {T.saveFailed}
        </p>
      )}

      <PracticeCard card={card} revealed={revealed} onReveal={() => setRevealed(true)} />

      {revealed ? (
        <RatingButtons card={card} onRate={rate} />
      ) : (
        <button
          onClick={() => setRevealed(true)}
          className="w-full hk-btn hk-btn-primary px-4 py-3 text-sm"
        >
          {T.showAnswer}
        </button>
      )}

      <p className="text-center text-[11px] text-ink-mute">
        {T.remainingN(remaining)} · {T.keyboardHint}
      </p>
    </div>
  );
}
