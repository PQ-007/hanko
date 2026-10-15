"use client";

import { useState } from "react";
import { highlightParts } from "@/lib/examples";
import type { WordExample } from "../../_lib/exampleStore";
import { T } from "../../_lib/strings";

/**
 * The word's example sentence under the answer: one quiet line of Japanese
 * with the word picked out, the translations behind a click — so the card
 * gains a line, not three. Key it by card, so the next card starts hidden.
 * The mobile side is example_line.dart.
 */
export default function ExampleLine({ example, term }: { example: WordExample; term: string }) {
  const [open, setOpen] = useState(false);
  const p = highlightParts(example.ja, term);
  const hasTranslation = !!(example.mn || example.en);
  return (
    <button
      type="button"
      onClick={() => hasTranslation && setOpen((o) => !o)}
      disabled={!hasTranslation}
      className="mx-auto mt-4 block max-w-md rounded-control px-3 py-1.5 text-center transition enabled:hover:bg-paper-dim"
    >
      <span lang="ja" className="block text-[15px] leading-relaxed text-ink-soft">
        {p.before}
        {p.mark && <span className="font-semibold text-seal">{p.mark}</span>}
        {p.after}
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
