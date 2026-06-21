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
    <div className="rounded-lg border border-gray-200 bg-white shadow-sm">
      <div className="border-b border-gray-100 px-4 py-3 text-sm font-semibold text-gray-700">
        {T.searchResults} ({hits.length})
      </div>
      {hits.length === 0 ? (
        <p className="px-4 py-8 text-center text-sm text-gray-400">{T.noResults}</p>
      ) : (
        <ul className="divide-y divide-gray-100">
          {hits.map((w) => (
            <li key={w.id} className="flex items-center justify-between gap-3 px-4 py-2">
              <div className="min-w-0">
                <div className="flex items-baseline gap-2">
                  <span className="font-medium">{w.term}</span>
                  {w.reading && <span className="text-sm text-gray-500">{w.reading}</span>}
                </div>
                {w.meaning && <div className="break-words text-sm text-gray-600">{w.meaning}</div>}
                {w.meaning_mn && (
                  <div className="break-words text-sm text-indigo-700">{w.meaning_mn}</div>
                )}
              </div>
              {w.deck?.name && (
                <button
                  onClick={() => onOpenDeck(w.deck_id)}
                  className="shrink-0 rounded-full bg-gray-100 px-3 py-1 text-xs text-gray-600 transition hover:bg-gray-200"
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
