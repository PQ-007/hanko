"use client";

import type { WordHit } from "../_lib/types";
import { T } from "../_lib/strings";

export default function SearchResults({
  hits,
  onOpenDeck,
}: {
  hits: WordHit[];
  onOpenDeck: (deckId: string) => void;
}) {
  return (
    <div className="hk-card">
      <div className="border-b border-line-soft px-4 py-3 text-sm font-semibold text-ink">
        {T.searchResults} ({hits.length})
      </div>
      {hits.length === 0 ? (
        <p className="px-4 py-8 text-center text-sm text-ink-mute">{T.noResults}</p>
      ) : (
        <ul className="divide-y divide-line-soft">
          {hits.map((w) => (
            <li key={w.id} className="flex items-center justify-between gap-3 px-4 py-2">
              <div className="min-w-0">
                <div className="flex items-baseline gap-2">
                  <span className="font-medium">{w.term}</span>
                  {w.reading && <span className="text-sm text-ink-soft">{w.reading}</span>}
                </div>
                {w.meaning && <div className="break-words text-sm text-ink-soft">{w.meaning}</div>}
                {w.meaning_mn && (
                  <div className="break-words text-sm text-ink">{w.meaning_mn}</div>
                )}
              </div>
              {w.deck?.name && (
                <button
                  onClick={() => onOpenDeck(w.deck_id)}
                  className="shrink-0 rounded-full bg-paper-dim px-3 py-1 text-xs text-ink-soft transition hover:bg-paper-deep"
                >
                  {w.deck.name}
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
