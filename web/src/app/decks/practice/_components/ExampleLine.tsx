"use client";

import { useState } from "react";
import { highlightRange, rubyUnits } from "@/lib/examples";
import type { WordExample } from "../../_lib/exampleStore";
import { T } from "../../_lib/strings";

/**
 * The word's example sentence under the answer: one quiet line of Japanese
 * with the word picked out and furigana over its kanji (when the sentence
 * came with a reading — one the user wrote has none), the translations behind
 * a click — so the card gains a line, not three. Key it by card, so the next
 * card starts hidden. The mobile side is example_line.dart.
 */
export default function ExampleLine({ example, term }: { example: WordExample; term: string }) {
  const [open, setOpen] = useState(false);
  const units = rubyUnits(example.ja, example.furigana);
  const mark = highlightRange(example.ja, term);
  const hasTranslation = !!(example.mn || example.en);
  // Each unit's start in the sentence, to know which ones the word covers.
  const starts = units.map((_, i) => units.slice(0, i).reduce((n, u) => n + u.text.length, 0));
  return (
    <button
      type="button"
      onClick={() => hasTranslation && setOpen((o) => !o)}
      disabled={!hasTranslation}
      className="mx-auto mt-4 block max-w-md rounded-control px-3 py-1.5 text-center transition enabled:hover:bg-paper-dim"
    >
      <span lang="ja" className="block text-[15px] leading-[2.1] text-ink-soft">
        {units.map((u, i) => {
          const start = starts[i];
          const marked = mark !== null && start < mark[1] && start + u.text.length > mark[0];
          const cls = marked ? "font-semibold text-seal" : undefined;
          return u.reading ? (
            <ruby key={i} className={cls}>
              {u.text}
              <rt className="text-[0.6em] font-normal text-ink-mute">{u.reading}</rt>
            </ruby>
          ) : (
            <span key={i} className={cls}>
              {u.text}
            </span>
          );
        })}
      </span>
      {hasTranslation && !open && <span className="block text-[11px] text-ink-mute">{T.exampleShowTranslation}</span>}
      {open && (
        <>
          {example.mn && <span className="mt-1 block text-sm text-ink">{example.mn}</span>}
          {example.en && <span className="mt-0.5 block text-xs text-ink-mute">{example.en}</span>}
        </>
      )}
    </button>
  );
}
