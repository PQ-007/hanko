import type { Example } from "../../../lib/examples.ts";
import type { WordExample } from "./exampleStore.ts";

// "Add example sentences" for a whole deck: every word without a sentence
// gets a Tatoeba suggestion, its Mongolian translated from the English.
// Words that already have one are never fetched and never written — and the
// save itself only writes a word whose sentence is still empty (see
// DeckFillExamples.tsx), so a sentence typed meanwhile on another device
// survives too.
//
// A port of fill_examples.dart, pinned by the same cases
// (fillExamples.test.ts / fill_examples_test.dart). Pure, with the network
// and the database injected.

/** At most this many words in flight: polite to a free API, still quick. */
export const FILL_CONCURRENCY = 3;

export interface FillDeps {
  find: (term: string) => Promise<Example | null>;
  /** English → Mongolian, whole sentence; "" on failure. */
  translate: (text: string) => Promise<string>;
  /** Writes the sentence if the word still has none; true when it did. */
  save: (wordId: string, e: WordExample) => Promise<boolean>;
  onProgress?: (done: number, total: number) => void;
  cancelled?: () => boolean;
}

export interface FillResult {
  /** Words that got a sentence. */
  added: number;
  /** Tatoeba had nothing good (or couldn't be reached) — worth trying again later. */
  missing: number;
  /** The save failed, or the word got a sentence some other way meanwhile. */
  skipped: number;
}

export async function fillExamples(
  words: { id: string; term: string }[],
  deps: FillDeps,
  concurrency = FILL_CONCURRENCY
): Promise<FillResult> {
  const result: FillResult = { added: 0, missing: 0, skipped: 0 };
  let next = 0;
  let done = 0;
  async function worker() {
    while (next < words.length && !deps.cancelled?.()) {
      const w = words[next++];
      const hit = await deps.find(w.term);
      if (!hit) {
        result.missing++;
      } else {
        const mn = await deps.translate(hit.en);
        let saved = false;
        try {
          saved = await deps.save(w.id, { ja: hit.ja, en: hit.en, mn });
        } catch {
          saved = false;
        }
        if (saved) result.added++;
        else result.skipped++;
      }
      deps.onProgress?.(++done, words.length);
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, worker));
  return result;
}
