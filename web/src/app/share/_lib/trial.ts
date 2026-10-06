// The share page's trial review: a deck someone shared, played by a visitor
// who may have no account. Nothing reaches the server — this is a local stand-
// in for usePracticeSession with the same queue/card/rate/undo shape, so the
// real Monster Hunt arena can run on it unchanged.
//
// Rules, kept deliberately simple (it's a taste, not a scheduler): words come
// in shuffled; a miss puts the word back a few cards later so it's seen again;
// anything else retires it. Pure, so trial.test.ts can pin it.

import type { QueueCard } from "../../decks/_lib/types";

export interface SharedWord {
  term: string;
  reading: string | null;
  meaning: string | null;
  meaning_mn: string | null;
}

export interface SharedDeck {
  name: string;
  words: SharedWord[];
}

/** A missed word comes back this many cards later (or last, if fewer remain). */
export const REQUEUE_GAP = 3;

/** A word's local id — the same in trialCards and the arena's distractor pool. */
export const trialWordId = (i: number) => `trial-word-${i}`;

/** A trial session's words, as the queue cards the arena expects. Ids are local. */
export function trialCards(words: SharedWord[]): QueueCard[] {
  return words.map((w, i) => ({
    card_id: `trial-card-${i}`,
    word_id: trialWordId(i),
    deck_id: "trial",
    template: "recognition",
    state: "new",
    learning_step: 0,
    due_at: "",
    interval_days: 0,
    repetitions: 0,
    ease_factor: 2.5,
    stability: null,
    difficulty: null,
    last_reviewed_at: null,
    term: w.term,
    reading: w.reading,
    meaning: w.meaning,
    meaning_mn: w.meaning_mn,
    audio_path: null,
  }));
}

/** Fisher–Yates, with the random source injected for tests. */
export function shuffled<T>(items: T[], rand: () => number = Math.random): T[] {
  const out = items.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export interface TrialState {
  queue: QueueCard[];
  reviewed: number;
  /** Earlier states, newest last — undo pops one. */
  past: { queue: QueueCard[]; reviewed: number }[];
}

export function startTrial(cards: QueueCard[]): TrialState {
  return { queue: cards, reviewed: 0, past: [] };
}

/** Answer the card at the front. "again" sends it back REQUEUE_GAP cards. */
export function answerTrial(s: TrialState, rating: string): TrialState {
  if (!s.queue.length) return s;
  const [head, ...rest] = s.queue;
  const queue =
    rating === "again"
      ? [...rest.slice(0, REQUEUE_GAP), head, ...rest.slice(REQUEUE_GAP)]
      : rest;
  return {
    queue,
    reviewed: s.reviewed + 1,
    past: [...s.past, { queue: s.queue, reviewed: s.reviewed }],
  };
}

export function undoTrial(s: TrialState): TrialState {
  const prev = s.past[s.past.length - 1];
  if (!prev) return s;
  return { ...prev, past: s.past.slice(0, -1) };
}
