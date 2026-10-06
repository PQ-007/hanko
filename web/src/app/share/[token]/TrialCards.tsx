"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, RotateCcw, Undo2 } from "lucide-react";
import { T } from "../../decks/_lib/strings";
import type { SharedWord } from "../_lib/trial";
import { useTrialSession } from "../_lib/useTrialSession";

/**
 * The simple trial: see the word, try to recall it, flip, say whether you
 * knew it. A miss comes back a few cards later. Nothing is saved.
 * Keys: space flips, 1 = again, 2 = knew it, u = undo.
 */
export default function TrialCards({
  words,
  exitHref,
  cta,
}: {
  words: SharedWord[];
  exitHref: string;
  cta: React.ReactNode;
}) {
  const { session, restart } = useTrialSession(words);
  const [flip, setFlip] = useState({ key: "", shown: false });
  const card = session.card;
  const cardKey = `${card?.card_id}:${session.reviewedCount}`;
  const shown = flip.key === cardKey && flip.shown;
  const done = !card;

  function answer(knew: boolean) {
    if (!card || !shown) return;
    void session.rate(knew ? "good" : "again");
  }

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey || done) return;
      if (e.key === " ") {
        e.preventDefault();
        setFlip({ key: cardKey, shown: true });
      } else if (e.key === "1") answer(false);
      else if (e.key === "2") answer(true);
      else if (e.key.toLowerCase() === "u") void session.undo();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const progress = words.length ? Math.min(1, (words.length - session.queue!.length) / words.length) : 1;
  const meaning = card ? [card.meaning_mn, card.meaning].filter(Boolean) : [];

  return (
    <div className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 py-6">
      <div className="flex items-center gap-3">
        <Link href={exitHref} aria-label={T.sharedBack} className="text-ink-soft hover:text-ink">
          <ArrowLeft size={18} />
        </Link>
        <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-line-soft">
          <div className="h-full bg-emerald-500 transition-all" style={{ width: `${progress * 100}%` }} />
        </div>
        <button
          onClick={() => void session.undo()}
          disabled={session.reviewedCount === 0}
          aria-label={T.undo}
          className="text-ink-soft hover:text-ink disabled:opacity-30"
        >
          <Undo2 size={17} />
        </button>
      </div>
      <p className="rounded-control bg-seal-tint px-3 py-2 text-center text-xs text-seal-dark">{T.sharedTrialBanner}</p>

      {done ? (
        <div className="flex flex-col items-center gap-3 rounded-card border border-line bg-white p-8 text-center">
          <p className="text-2xl font-extrabold text-ink">{T.sharedCardsDone}</p>
          <p className="text-sm text-ink-soft">{T.sharedCardsDoneDesc(session.reviewedCount)}</p>
          <div className="mt-2 flex w-full flex-col gap-2">
            {cta}
            <button onClick={restart} className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm">
              <RotateCcw size={15} /> {T.sharedCardsRestart}
            </button>
          </div>
        </div>
      ) : (
        <>
          <button
            onClick={() => setFlip({ key: cardKey, shown: true })}
            className="flex min-h-[300px] flex-col items-center justify-center gap-3 rounded-card border border-line bg-white p-8 text-center shadow-sm"
          >
            <span className="text-5xl font-extrabold tracking-tight text-ink">{card.term}</span>
            {shown ? (
              <>
                {card.reading && card.reading !== card.term && (
                  <span className="text-lg text-ink-soft">{card.reading}</span>
                )}
                <span className="mt-2 border-t border-line pt-3 text-lg font-semibold text-ink">
                  {meaning.join(" · ")}
                </span>
              </>
            ) : (
              <span className="text-xs text-ink-mute">{T.sharedCardsShow} (space)</span>
            )}
          </button>
          {shown ? (
            <div className="grid grid-cols-2 gap-2">
              <button onClick={() => answer(false)} className="hk-btn bg-red-600 py-3 text-sm text-white hover:bg-red-700">
                {T.sharedCardsAgain} <span className="opacity-60">1</span>
              </button>
              <button onClick={() => answer(true)} className="hk-btn bg-emerald-600 py-3 text-sm text-white hover:bg-emerald-700">
                {T.sharedCardsKnew} <span className="opacity-60">2</span>
              </button>
            </div>
          ) : (
            <button onClick={() => setFlip({ key: cardKey, shown: true })} className="hk-btn hk-btn-primary py-3 text-sm">
              {T.sharedCardsShow}
            </button>
          )}
        </>
      )}
    </div>
  );
}
