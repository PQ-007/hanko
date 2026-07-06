"use client";

import type { Word } from "@/lib/types";
import { frontText, backText } from "@/lib/wordText";
import { T } from "../../_lib/strings";

// Click-to-reveal flip card, styled after the flashcard grid view in
// WordRow.tsx but with an explicit reveal step instead of hover.
export default function PracticeCard({
  word,
  revealed,
  onReveal,
}: {
  word: Word;
  revealed: boolean;
  onReveal: () => void;
}) {
  return (
    <div className="h-72 w-full perspective-[1000px]">
      <div
        className={`relative h-full w-full transform-3d transition-transform duration-500 ${
          revealed ? "rotate-y-180" : ""
        }`}
      >
        <button
          onClick={onReveal}
          disabled={revealed}
          style={{ WebkitBackfaceVisibility: "hidden", backfaceVisibility: "hidden" }}
          className="absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-xl border border-gray-200 bg-white p-6 text-center shadow-sm backface-hidden disabled:cursor-default"
        >
          {/* Term only — the reading is part of the answer, revealed on flip. */}
          <div className="text-4xl font-bold leading-tight text-gray-900">{word.term}</div>
          {!revealed && <span className="text-sm text-gray-400">{T.showAnswer}</span>}
        </button>

        <div
          style={{ WebkitBackfaceVisibility: "hidden", backfaceVisibility: "hidden" }}
          className="absolute inset-0 flex flex-col items-center justify-center gap-2 overflow-hidden rounded-xl border border-gray-300 bg-gray-50 p-6 text-center shadow-sm backface-hidden rotate-y-180"
        >
          <div className="text-2xl font-bold leading-tight text-gray-900">{frontText(word)}</div>
          <div className="whitespace-pre-line text-base text-gray-700">{backText(word)}</div>
        </div>
      </div>
    </div>
  );
}
