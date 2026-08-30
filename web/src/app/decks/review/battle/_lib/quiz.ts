import type { QueueCard } from "../../../_lib/types";

// Quiz generation for Monster Hunt. Revision note: this used to call
// /api/lookup + /api/distractors (Jisho-backed, cached in Postgres) — real
// playtesting found the per-question network round-trips too slow to feel
// good. Replaced with the player's own word library, fetched ONCE when the
// battle screen mounts and passed in here: buildQuiz is now synchronous, no
// network call per question at all. See CLAUDE.md's plan notes for the full
// before/after.
//
// Quizzes on MEANING, not reading, even though the reference mockup this
// feature was inspired by shows a reading question — meaning is what
// Classic mode actually reveals as the primary answer everywhere else in
// this app (PracticeCard, the stats dashboard's grade tiers), and Monster
// Hunt is meant to be the same real review, fight-themed, not a different
// study mode wearing the same clothes.

export interface QuizOption {
  term: string;
  reading: string | null;
  answerText: string;
  correct: boolean;
}

// The subset of a `words` row the quiz needs. Fetched once by BattleArena
// (RLS already scopes it to the signed-in user) — this is intentionally NOT
// QueueCard, since it needs to cover every captured word, not just today's
// due cards.
export interface OwnWord {
  id: string;
  term: string;
  reading: string | null;
  meaning: string | null;
  meaning_mn: string | null;
}

// Below this many total captured words, a 4-option quiz can't be built at
// all (need the correct word plus 3 distinct wrong ones). BattleArena checks
// this before offering the mode.
export const MIN_WORDS_FOR_BATTLE = 4;

function answerText(w: { meaning_mn?: string | null; meaning?: string | null }): string {
  return w.meaning_mn?.trim() || w.meaning?.trim() || "";
}

// Fisher-Yates, not .sort(() => Math.random() - 0.5) — the sort-comparator
// trick is a well-documented non-uniform shuffle, and a biased shuffle here
// would mean the correct answer lands in some positions more often than
// others, letting a player learn to guess-optimize instead of actually
// recalling the word.
function shuffle<T>(items: T[]): T[] {
  const arr = [...items];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// Pure and synchronous — no I/O. `allWords` should already exclude nothing;
// filtering out the correct word happens here, by id (not term: two
// different words could in principle share a term with different readings).
export function buildQuiz(card: QueueCard, allWords: OwnWord[]): QuizOption[] {
  const correct: QuizOption = {
    term: card.term,
    reading: card.reading,
    answerText: answerText(card),
    correct: true,
  };

  const pool = allWords.filter((w) => w.id !== card.word_id && answerText(w));
  const distractors = shuffle(pool)
    .slice(0, 3)
    .map((w) => ({
      term: w.term,
      reading: w.reading,
      answerText: answerText(w),
      correct: false,
    }));

  return shuffle([correct, ...distractors]);
}
