"use client";

import { useState } from "react";
import type { ArenaSession } from "../../decks/review/battle/_components/BattleArena";
import type { OwnWord } from "../../decks/review/battle/_lib/quiz";
import { answerTrial, shuffled, startTrial, trialCards, trialWordId, undoTrial, type SharedWord } from "./trial";

/** The trial as an ArenaSession: local state only, nothing sent anywhere. */
export function useTrialSession(words: SharedWord[]) {
  const deal = () => startTrial(shuffled(trialCards(words)));
  const [state, setState] = useState(deal);

  const session: ArenaSession = {
    queue: state.queue,
    card: state.queue[0] ?? null,
    reviewedCount: state.reviewed,
    error: false,
    loadError: null,
    rate: async (rating) => setState((s) => answerTrial(s, rating)),
    undo: async () => setState((s) => undoTrial(s)),
  };
  return { session, restart: () => setState(deal()) };
}

/** The deck as the arena's distractor pool — ids match trialCards' word ids. */
export function trialPool(words: SharedWord[]): OwnWord[] {
  return words.map((w, i) => ({ id: trialWordId(i), ...w }));
}
