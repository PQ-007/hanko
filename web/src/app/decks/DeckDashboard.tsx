"use client";

import { useCallback, useEffect, useState } from "react";
import { Search } from "lucide-react";
import type { Deck, DeckWithCount, Folder, Word } from "@/lib/types";
import { supabase } from "./_lib/db";
import { T } from "./_lib/strings";
import type { WordHit } from "./_lib/types";
import Sidebar from "./_components/Sidebar";
import SearchResults from "./_components/SearchResults";
import DeckDetail from "./_components/DeckDetail";

export default function DeckDashboard() {
  const [folders, setFolders] = useState<Folder[]>([]);
  const [decks, setDecks] = useState<DeckWithCount[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [words, setWords] = useState<Word[]>([]);
  const [loadingDecks, setLoadingDecks] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [query, setQuery] = useState("");
  const [results, setResults] = useState<WordHit[] | null>(null);

  const loadFolders = useCallback(async () => {
    const { data } = await supabase
      .from("folders")
      .select("*")
      .eq("deleted", false)
      .order("created_at", { ascending: true });
    setFolders((data as Folder[]) ?? []);
  }, []);

  const loadDecks = useCallback(async () => {
    setLoadingDecks(true);
    const { data: deckRows, error: deckErr } = await supabase
      .from("decks")
      .select("*")
      .eq("deleted", false)
      .order("created_at", { ascending: true });
    if (deckErr) {
      setError(deckErr.message);
      setLoadingDecks(false);
      return;
    }
    const { data: wordRows } = await supabase
      .from("words")
      .select("deck_id")
      .eq("deleted", false);
    const counts = new Map<string, number>();
    (wordRows ?? []).forEach((w: { deck_id: string }) =>
      counts.set(w.deck_id, (counts.get(w.deck_id) ?? 0) + 1)
    );
    const withCounts: DeckWithCount[] = (deckRows as Deck[]).map((d) => ({
      ...d,
      word_count: counts.get(d.id) ?? 0,
    }));
    setDecks(withCounts);
    setLoadingDecks(false);
    setSelectedId((prev) => prev ?? withCounts[0]?.id ?? null);
  }, []);

  const loadWords = useCallback(async (deckId: string) => {
    const { data, error: err } = await supabase
      .from("words")
      .select("*")
      .eq("deck_id", deckId)
      .eq("deleted", false)
      .order("date_added", { ascending: false });
    if (err) {
      setError(err.message);
      return;
    }
    setWords((data as Word[]) ?? []);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadFolders();
    loadDecks();
  }, [loadFolders, loadDecks]);

  useEffect(() => {
    let active = true;
    (async () => {
      if (selectedId) await loadWords(selectedId);
      else if (active) setWords([]);
    })();
    return () => {
      active = false;
    };
  }, [selectedId, loadWords]);

  // Debounced global word search across the user's whole collection.
  useEffect(() => {
    const q = query.trim().replace(/[,()%*]/g, " ").trim();
    if (!q) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setResults(null);
      return;
    }
    const handle = setTimeout(async () => {
      const { data } = await supabase
        .from("words")
        .select("*, deck:decks(name)")
        .eq("deleted", false)
        .or(
          `term.ilike.%${q}%,reading.ilike.%${q}%,meaning.ilike.%${q}%,meaning_mn.ilike.%${q}%`
        )
        .order("date_added", { ascending: false })
        .limit(100);
      setResults((data as WordHit[]) ?? []);
    }, 250);
    return () => clearTimeout(handle);
  }, [query]);

  const selectedDeck = decks.find((d) => d.id === selectedId) ?? null;
  const searching = results !== null;

  return (
    <div className="mx-auto flex max-w-[1700px] flex-col gap-4 p-4 sm:px-8 sm:py-6 lg:flex-row lg:gap-6">
      <Sidebar
        folders={folders}
        decks={decks}
        loading={loadingDecks}
        selectedId={selectedId}
        onSelect={(id) => {
          setSelectedId(id);
          setQuery("");
        }}
        onFoldersChanged={loadFolders}
        onDecksChanged={loadDecks}
      />
      <section className="min-w-0 flex-1">
        <div className="relative mb-4">
          <Search
            size={16}
            className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
          />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T.search}
            className="w-full rounded-lg border border-gray-300 bg-white py-2.5 pl-9 pr-4 text-sm shadow-sm focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-100"
          />
        </div>
        {error && (
          <p className="mb-4 rounded bg-red-50 px-4 py-2 text-sm text-red-600">{error}</p>
        )}
        {searching ? (
          <SearchResults
            hits={results!}
            onOpenDeck={(id) => {
              setSelectedId(id);
              setQuery("");
            }}
          />
        ) : selectedDeck ? (
          <DeckDetail
            deck={selectedDeck}
            folders={folders}
            words={words}
            onWordsChanged={() => {
              loadWords(selectedDeck.id);
              loadDecks();
            }}
          />
        ) : (
          <div className="rounded-lg border border-dashed border-gray-300 bg-white p-10 text-center text-gray-500">
            {T.createDeckToStart}
          </div>
        )}
      </section>
    </div>
  );
}
