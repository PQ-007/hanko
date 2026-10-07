// Writing-lesson planning — a port of mobile's lesson.dart and
// writing_rules.dart. lesson.test.ts runs the same cases as lesson_test.dart.

/** Whether a string contains a kanji (々 included). */
export function hasKanji(s: string): boolean {
  for (const ch of s) {
    const c = ch.codePointAt(0)!;
    if ((c >= 0x4e00 && c <= 0x9fff) || (c >= 0x3400 && c <= 0x4dbf) || c === 0x3005) return true;
  }
  return false;
}

/** The ladder for a new kanji (trace → some strokes → memory), then the word. */
export type StepKind = "trace" | "partial" | "blank" | "word";

export interface LessonStep {
  kind: StepKind;
  wordIndex: number;
  /** The kanji practised, for the three single-kanji steps. */
  char?: string;
}

export const WORDS_PER_LESSON = 5;

export function kanjiOf(term: string): string[] {
  return [...term].filter(hasKanji);
}

/** Indexes of the kanji in the term's characters (kana around them are given). */
export function kanjiPositions(term: string): number[] {
  return [...term].flatMap((ch, i) => (hasKanji(ch) ? [i] : []));
}

/**
 * A new kanji gets the full ladder the first time it appears; a learned one
 * (here or before) only appears inside its word. Each word ends with the word
 * step — unless it's a single kanji just taught (asking twice in a row).
 */
export function planLesson(terms: string[], learned: Set<string> = new Set()): LessonStep[] {
  const taught = new Set<string>();
  const steps: LessonStep[] = [];
  terms.forEach((term, w) => {
    const kanji = kanjiOf(term);
    let taughtHere = false;
    for (const k of kanji) {
      if (learned.has(k) || taught.has(k)) continue;
      taught.add(k);
      taughtHere = true;
      steps.push({ kind: "trace", wordIndex: w, char: k });
      steps.push({ kind: "partial", wordIndex: w, char: k });
      steps.push({ kind: "blank", wordIndex: w, char: k });
    }
    const singleJustTaught = taughtHere && [...term].length === 1;
    if (kanji.length > 0 && !singleJustTaught) steps.push({ kind: "word", wordIndex: w });
  });
  return steps;
}

/** Strokes shown on the "some strokes" step: the first half, rounded down. */
export function partialStrokes(count: number): number {
  return Math.floor(count / 2);
}

/** Every kanji in the terms, once, in first-appearance order. */
export function kanjiInOrder(terms: Iterable<string>): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const t of terms) {
    for (const k of kanjiOf(t)) {
      if (!seen.has(k)) {
        seen.add(k);
        out.push(k);
      }
    }
  }
  return out;
}

/** For each picked kanji, the first word containing it — each word once. */
export function wordsForKanji<T>(kanji: string[], words: T[], termOf: (w: T) => string): T[] {
  const out: T[] = [];
  for (const k of kanji) {
    if (out.some((w) => termOf(w).includes(k))) continue;
    const w = words.find((w) => termOf(w).includes(k));
    if (w !== undefined) out.push(w);
  }
  return out;
}
