// Monster Hunt's question kinds — the web port of mobile's
// question_kinds.dart. A question either asks for the meaning (buildQuiz,
// unchanged and still pinned by battle.fixture.json) or for the word to be
// written, a kanji at a time, on a pad. questionKinds.test.ts runs the same
// cases as question_kinds_test.dart.

import { hasKanji, kanjiOf } from "../../../writing/_lib/lesson.ts";

export type QuestionKind = "meaning" | "write";

/** Relative frequency when both are possible: writing is the rarer one. */
export const KIND_WEIGHTS: Record<QuestionKind, number> = { meaning: 3, write: 2 };

/** A written answer hits this much harder than a picked one. */
export const WRITE_DAMAGE_BONUS = 1.5;

/** Words with more kanji than this are asked by meaning. */
export const MAX_WRITE_KANJI = 3;

/** Writing gets this much time per kanji; a choice question gets 10 s. */
export const WRITE_MS_PER_KANJI = 12_000;
export const QUESTION_TIME_LIMIT_MS = 10_000;

/**
 * The kinds a word can be asked as. `canWrite(k)` must hold for every kanji
 * in the word: the arena passes "learned in a writing lesson AND its stroke
 * data has loaded" (the web has no recogniser to fall back on). Same rule as
 * mobile's eligibleKinds(learned:).
 */
export function eligibleKinds(term: string, canWrite: (kanji: string) => boolean): Set<QuestionKind> {
  const kanji = kanjiOf(term);
  const kinds = new Set<QuestionKind>(["meaning"]);
  if (hasKanji(term) && kanji.length > 0 && kanji.length <= MAX_WRITE_KANJI && kanji.every(canWrite)) {
    kinds.add("write");
  }
  return kinds;
}

/** One weighted pick among the eligible kinds, from one `rand()` draw. */
export function pickKind(eligible: Set<QuestionKind>, rand: () => number): QuestionKind {
  const kinds = (["meaning", "write"] as const).filter((k) => eligible.has(k));
  if (kinds.length === 0) return "meaning";
  const total = kinds.reduce((s, k) => s + KIND_WEIGHTS[k], 0);
  let roll = rand() * total;
  for (const k of kinds) {
    roll -= KIND_WEIGHTS[k];
    if (roll < 0) return k;
  }
  return kinds[kinds.length - 1];
}

export function timeLimitFor(kind: QuestionKind, term: string): number {
  return kind === "write" ? WRITE_MS_PER_KANJI * kanjiOf(term).length : QUESTION_TIME_LIMIT_MS;
}

type Speed = "easy" | "good" | "hard";

/**
 * A correct answer's speed tier, judged against that question's own limit —
 * a word written in a third of its time is as fast as a pick in a third of
 * ten seconds.
 */
export function speedFor(elapsedMs: number, limitMs: number): Speed {
  const scaled = Math.round((elapsedMs * QUESTION_TIME_LIMIT_MS) / limitMs);
  if (scaled < QUESTION_TIME_LIMIT_MS / 3) return "easy";
  if (scaled < (QUESTION_TIME_LIMIT_MS * 2) / 3) return "good";
  return "hard";
}
