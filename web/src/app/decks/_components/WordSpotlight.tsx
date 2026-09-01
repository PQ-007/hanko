"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ArrowRight, Play, Shuffle, Sparkle } from "lucide-react";
import type { Deck, Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";
import { T } from "../_lib/strings";
import { playWordAudio } from "../_lib/audio";

// A stable, well-spread index from the day key. Not security, not
// statistics — it just has to give a different word on consecutive days and
// the same word all day, which a running sum of char codes does not (adjacent
// dates differ by one character, so they'd land on adjacent words).
function seedFrom(key: string): number {
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

// One of the user's own words, shown in full on the dashboard.
//
// Everything else on this page is a number about the collection; nothing on it
// was ever the collection. This is the one place a word you saved months ago
// can resurface without going looking for it — which is also the cheapest
// prompt there is to notice a word whose meaning has gone.
//
// Seeded from the scheduler's day (current_srs_day, 0019) rather than
// Math.random, so it is the same word all day across reloads and devices —
// "today's word", not a slot machine. The button steps forward from there for
// anyone who wants more.
export default function WordSpotlight({
  words,
  decks,
  dayKey,
}: {
  words: Word[];
  decks: Deck[];
  dayKey: string | null;
}) {
  const [step, setStep] = useState(0);
  // Paths for audio generated during this session. Without it, a second play
  // of the same word re-runs TTS: the row on the server now has a path, but
  // the `words` array this page was rendered from doesn't, and reloading the
  // whole dashboard to learn one path would swap the page for its spinner.
  const [freshAudio, setFreshAudio] = useState<Record<string, string>>({});
  const [playing, setPlaying] = useState(false);

  const deckNames = useMemo(
    () => new Map(decks.map((d) => [d.id, d.name])),
    [decks]
  );

  const word = useMemo(() => {
    if (words.length === 0) return null;
    const seed = seedFrom(dayKey ?? "");
    return words[(seed + step) % words.length];
  }, [words, dayKey, step]);

  if (!word) return null;

  const grade = gradeFor(word);
  const deckName = deckNames.get(word.deck_id);
  const audioPath = freshAudio[word.id] ?? word.audio_path;

  async function play() {
    if (!word) return;
    setPlaying(true);
    try {
      const path = await playWordAudio({ id: word.id, audio_path: audioPath });
      if (path && path !== audioPath) {
        setFreshAudio((m) => ({ ...m, [word.id]: path }));
      }
    } finally {
      setPlaying(false);
    }
  }

  return (
    <div className="hk-card relative overflow-hidden">
      <div className="flex items-center justify-between gap-3 border-b border-line-soft px-5 py-3">
        <h3 className="flex items-center gap-2 text-sm font-semibold text-ink">
          <Sparkle size={15} className="text-seal" />
          {T.spotlightTitle}
          {deckName && (
            <span className="rounded-full bg-paper-dim px-2 py-0.5 text-[11px] font-medium text-ink-mute">
              {deckName}
            </span>
          )}
        </h3>
        <button
          onClick={() => setStep((s) => s + 1)}
          disabled={words.length < 2}
          className="hk-btn hk-btn-ghost px-2.5 py-1.5 text-xs disabled:opacity-40"
        >
          <Shuffle size={13} /> {T.spotlightAnother}
        </button>
      </div>

      <div className="relative flex flex-col gap-5 px-5 py-6 sm:flex-row sm:items-center sm:gap-8">
        {/* The mastery letter as a watermark, same device the deck cards use. */}
        <span
          aria-hidden
          className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 select-none text-[130px] font-semibold leading-none tracking-tighter text-paper-deep/60"
        >
          {grade === "new" ? "N" : grade}
        </span>

        <div className="relative flex shrink-0 items-center gap-3">
          <div className="min-w-0">
            <p className="break-words text-4xl font-bold leading-tight text-ink sm:text-5xl">
              {word.term}
            </p>
            {word.reading && (
              <p className="mt-1 text-sm text-ink-mute">{word.reading}</p>
            )}
          </div>
          <button
            onClick={play}
            disabled={playing}
            title={T.playAudio}
            aria-label={T.playAudio}
            className="shrink-0 rounded-full border border-line-soft bg-white p-2 text-ink-soft transition hover:bg-paper-dim disabled:opacity-50"
          >
            <Play size={14} className={playing ? "animate-pulse" : ""} />
          </button>
        </div>

        <div className="relative min-w-0 flex-1">
          {word.meaning_mn || word.meaning ? (
            <>
              {word.meaning_mn && (
                <p className="break-words text-lg font-semibold leading-snug text-ink">
                  {word.meaning_mn}
                </p>
              )}
              {word.meaning && (
                <p className="mt-1 break-words text-sm leading-relaxed text-ink-soft">
                  {word.meaning}
                </p>
              )}
            </>
          ) : (
            <p className="text-sm text-ink-mute">{T.spotlightNoMeaning}</p>
          )}

          <Link
            href={`/decks?deck=${word.deck_id}`}
            className="group mt-3 inline-flex items-center gap-1.5 text-xs font-medium text-seal transition hover:text-seal-dark"
          >
            {T.spotlightOpenDeck}
            <ArrowRight
              size={13}
              className="transition-transform group-hover:translate-x-0.5"
            />
          </Link>
        </div>
      </div>
    </div>
  );
}
