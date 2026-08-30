"use client";

import type { DeckWithCount, Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";
import { T } from "../_lib/strings";

const MASTERED_FILL = "#0d366b"; // GRADE_COLOR.A — same ramp step as "fully mastered"

// Per-deck rollup: word count, due-now count, and a mastered-share meter
// (A+B grades). The meter's unfilled track is a lighter step of the same
// ramp the value uses, so state reads at a glance without a legend.
export default function DeckBreakdownTable({
  decks,
  words,
  onSelectDeck,
}: {
  decks: DeckWithCount[];
  words: Word[];
  onSelectDeck: (id: string) => void;
}) {
  const now = new Date();
  const byDeck = new Map<string, Word[]>();
  for (const w of words) {
    const list = byDeck.get(w.deck_id);
    if (list) list.push(w);
    else byDeck.set(w.deck_id, [w]);
  }

  const rows = decks.map((deck) => {
    const deckWords = byDeck.get(deck.id) ?? [];
    const due = deckWords.filter((w) => new Date(w.due_at) <= now).length;
    const mastered = deckWords.filter((w) => {
      const g = gradeFor(w);
      return g === "A" || g === "B";
    }).length;
    const masteredPct = deckWords.length === 0 ? 0 : Math.round((mastered / deckWords.length) * 100);
    return { deck, due, masteredPct };
  });

  return (
    <div className="overflow-hidden hk-card">
      <h3 className="border-b border-line-soft px-4 py-3 text-sm font-semibold text-ink-soft">
        {T.deckBreakdownTitle}
      </h3>
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="text-xs text-ink-mute">
              <th className="px-4 py-2 font-medium">{T.colDeck}</th>
              <th className="px-4 py-2 font-medium tabular-nums">{T.colWords}</th>
              <th className="px-4 py-2 font-medium tabular-nums">{T.colDue}</th>
              <th className="px-4 py-2 font-medium">{T.colMastered}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line-soft">
            {rows.map(({ deck, due, masteredPct }) => (
              <tr key={deck.id} className="hover:bg-paper-dim">
                <td className="px-4 py-2.5">
                  <button
                    onClick={() => onSelectDeck(deck.id)}
                    className="font-medium text-ink hover:underline"
                  >
                    {deck.name}
                  </button>
                </td>
                <td className="px-4 py-2.5 tabular-nums text-ink-soft">{deck.word_count}</td>
                <td className="px-4 py-2.5 tabular-nums text-ink-soft">{due}</td>
                <td className="px-4 py-2.5">
                  <div className="flex items-center gap-2">
                    <div className="h-1.5 w-24 overflow-hidden rounded-full bg-paper-dim">
                      <div
                        style={{ width: `${masteredPct}%`, backgroundColor: MASTERED_FILL }}
                        className="h-full rounded-full"
                      />
                    </div>
                    <span className="w-9 shrink-0 tabular-nums text-xs text-ink-soft">
                      {masteredPct}%
                    </span>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {decks.length === 0 && (
        <p className="px-4 py-6 text-center text-sm text-ink-mute">{T.noStatsData}</p>
      )}
    </div>
  );
}
