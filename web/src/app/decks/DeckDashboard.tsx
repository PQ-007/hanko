"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Deck, DeckWithCount, Word } from "@/lib/types";

const supabase = createClient();

export default function DeckDashboard() {
  const [decks, setDecks] = useState<DeckWithCount[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [words, setWords] = useState<Word[]>([]);
  const [loadingDecks, setLoadingDecks] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
    // Load decks once on mount (subscribing to our external store).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadDecks();
  }, [loadDecks]);

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

  const selectedDeck = decks.find((d) => d.id === selectedId) ?? null;

  return (
    <div className="mx-auto flex max-w-6xl gap-6 p-6">
      <DeckSidebar
        decks={decks}
        loading={loadingDecks}
        selectedId={selectedId}
        onSelect={setSelectedId}
        onChanged={loadDecks}
      />
      <section className="flex-1">
        {error && (
          <p className="mb-4 rounded bg-red-50 px-4 py-2 text-sm text-red-600">
            {error}
          </p>
        )}
        {selectedDeck ? (
          <DeckDetail
            deck={selectedDeck}
            words={words}
            onWordsChanged={() => {
              loadWords(selectedDeck.id);
              loadDecks();
            }}
          />
        ) : (
          <div className="rounded-lg border border-dashed border-gray-300 bg-white p-10 text-center text-gray-500">
            Create a deck to get started.
          </div>
        )}
      </section>
    </div>
  );
}

// --------------------------------------------------------------------------
// Sidebar: deck list + create
// --------------------------------------------------------------------------
function DeckSidebar({
  decks,
  loading,
  selectedId,
  onSelect,
  onChanged,
}: {
  decks: DeckWithCount[];
  loading: boolean;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onChanged: () => void;
}) {
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);

  async function createDeck() {
    const trimmed = name.trim();
    if (!trimmed) return;
    setBusy(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      await supabase.from("decks").insert({ name: trimmed, user_id: user.id });
    }
    setName("");
    setBusy(false);
    onChanged();
  }

  return (
    <aside className="w-64 shrink-0">
      <div className="rounded-lg border border-gray-200 bg-white">
        <div className="border-b border-gray-100 px-4 py-3 text-sm font-semibold text-gray-700">
          Decks
        </div>
        <ul className="max-h-[60vh] overflow-auto">
          {loading && (
            <li className="px-4 py-3 text-sm text-gray-400">Loading…</li>
          )}
          {!loading && decks.length === 0 && (
            <li className="px-4 py-3 text-sm text-gray-400">No decks yet</li>
          )}
          {decks.map((d) => (
            <li key={d.id}>
              <button
                onClick={() => onSelect(d.id)}
                className={`flex w-full items-center justify-between px-4 py-2 text-left text-sm transition hover:bg-gray-50 ${
                  d.id === selectedId ? "bg-indigo-50 font-medium text-indigo-700" : ""
                }`}
              >
                <span className="truncate">{d.name}</span>
                <span className="ml-2 shrink-0 text-xs text-gray-400">
                  {d.word_count}
                </span>
              </button>
            </li>
          ))}
        </ul>
        <div className="flex gap-2 border-t border-gray-100 p-3">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && createDeck()}
            placeholder="New deck name"
            className="min-w-0 flex-1 rounded border border-gray-300 px-2 py-1 text-sm"
          />
          <button
            onClick={createDeck}
            disabled={busy}
            className="rounded bg-indigo-600 px-3 py-1 text-sm font-medium text-white transition hover:bg-indigo-700 disabled:opacity-60"
          >
            Add
          </button>
        </div>
      </div>
    </aside>
  );
}

// --------------------------------------------------------------------------
// Deck detail: word table + add word + export
// --------------------------------------------------------------------------
function DeckDetail({
  deck,
  words,
  onWordsChanged,
}: {
  deck: DeckWithCount;
  words: Word[];
  onWordsChanged: () => void;
}) {
  return (
    <div className="space-y-4">
      <DeckHeader deck={deck} onChanged={onWordsChanged} />
      <AddWordForm deck={deck} onAdded={onWordsChanged} />
      <div className="rounded-lg border border-gray-200 bg-white">
        {words.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-gray-400">
            No words in this deck yet. Add one above, or save words from the
            browser extension.
          </p>
        ) : (
          <ul className="divide-y divide-gray-100">
            {words.map((w) => (
              <WordRow key={w.id} word={w} onChanged={onWordsChanged} />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function DeckHeader({
  deck,
  onChanged,
}: {
  deck: DeckWithCount;
  onChanged: () => void;
}) {
  const [renaming, setRenaming] = useState(false);
  const [name, setName] = useState(deck.name);
  const [exporting, setExporting] = useState<"apkg" | "txt" | null>(null);

  async function rename() {
    const trimmed = name.trim();
    if (trimmed && trimmed !== deck.name) {
      await supabase.from("decks").update({ name: trimmed }).eq("id", deck.id);
      onChanged();
    }
    setRenaming(false);
  }

  async function remove() {
    if (
      !confirm(`Delete deck "${deck.name}" and all its words? This can't be undone.`)
    )
      return;
    // Soft-delete (tombstone) so the extension picks up the deletion on sync.
    await supabase.from("words").update({ deleted: true }).eq("deck_id", deck.id);
    await supabase.from("decks").update({ deleted: true }).eq("id", deck.id);
    onChanged();
  }

  async function download(format: "apkg" | "txt") {
    setExporting(format);
    try {
      const res = await fetch(`/api/decks/${deck.id}/${format}`, {
        method: "POST",
      });
      if (!res.ok) {
        alert((await res.json().catch(() => null))?.error ?? "Export failed");
        return;
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${deck.name.replace(/[^a-z0-9-_]+/gi, "_") || "deck"}.${format}`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
    } finally {
      setExporting(null);
    }
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      {renaming ? (
        <input
          autoFocus
          value={name}
          onChange={(e) => setName(e.target.value)}
          onBlur={rename}
          onKeyDown={(e) => e.key === "Enter" && rename()}
          className="rounded border border-gray-300 px-2 py-1 text-xl font-semibold"
        />
      ) : (
        <h2
          onClick={() => {
            setName(deck.name);
            setRenaming(true);
          }}
          className="cursor-text text-xl font-semibold"
          title="Click to rename"
        >
          {deck.name}{" "}
          <span className="text-sm font-normal text-gray-400">
            ({deck.word_count})
          </span>
        </h2>
      )}
      <div className="flex gap-2">
        <button
          onClick={() => download("apkg")}
          disabled={exporting !== null}
          className="rounded bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-emerald-700 disabled:opacity-60"
        >
          {exporting === "apkg" ? "Building…" : "Export .apkg"}
        </button>
        <button
          onClick={() => download("txt")}
          disabled={exporting !== null}
          className="rounded border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-60"
        >
          .txt
        </button>
        <button
          onClick={remove}
          className="rounded border border-red-200 px-3 py-1.5 text-sm font-medium text-red-600 transition hover:bg-red-50"
        >
          Delete
        </button>
      </div>
    </div>
  );
}

function AddWordForm({
  deck,
  onAdded,
}: {
  deck: Deck;
  onAdded: () => void;
}) {
  const [term, setTerm] = useState("");
  const [reading, setReading] = useState("");
  const [meaning, setMeaning] = useState("");
  const [meaningMn, setMeaningMn] = useState("");
  const [busy, setBusy] = useState(false);
  const [looking, setLooking] = useState(false);

  async function lookup() {
    const t = term.trim();
    if (!t) return;
    setLooking(true);
    try {
      const res = await fetch(`/api/lookup?term=${encodeURIComponent(t)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.reading && !reading) setReading(data.reading);
        if (data.meaning && !meaning) setMeaning(data.meaning);
        if (data.meaning_mn && !meaningMn) setMeaningMn(data.meaning_mn);
      }
    } finally {
      setLooking(false);
    }
  }

  // Translate the English meaning to Mongolian via bolor-toli (server-side).
  async function translateMn() {
    const text = meaning.trim();
    if (!text || meaningMn.trim()) return;
    try {
      const res = await fetch(`/api/translate?text=${encodeURIComponent(text)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.mongolian) setMeaningMn(data.mongolian);
      }
    } catch {
      // leave blank; user can type it
    }
  }

  async function add() {
    const t = term.trim();
    if (!t) return;
    setBusy(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      await supabase.from("words").insert({
        deck_id: deck.id,
        user_id: user.id,
        term: t,
        reading: reading.trim() || null,
        meaning: meaning.trim() || null,
        meaning_mn: meaningMn.trim() || null,
      });
    }
    setTerm("");
    setReading("");
    setMeaning("");
    setMeaningMn("");
    setBusy(false);
    onAdded();
  }

  return (
    <div className="rounded-lg border border-gray-200 bg-white p-4">
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_1fr_1.5fr_1.5fr_auto]">
        <input
          value={term}
          onChange={(e) => setTerm(e.target.value)}
          onBlur={lookup}
          placeholder="Term (e.g. 勉強)"
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <input
          value={reading}
          onChange={(e) => setReading(e.target.value)}
          placeholder={looking ? "Looking up…" : "Reading"}
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <input
          value={meaning}
          onChange={(e) => setMeaning(e.target.value)}
          onBlur={translateMn}
          placeholder="Meaning (English)"
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <input
          value={meaningMn}
          onChange={(e) => setMeaningMn(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && add()}
          placeholder="Монгол"
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <button
          onClick={add}
          disabled={busy || !term.trim()}
          className="rounded bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-indigo-700 disabled:opacity-60"
        >
          Add word
        </button>
      </div>
    </div>
  );
}

function WordRow({ word, onChanged }: { word: Word; onChanged: () => void }) {
  const [genAudio, setGenAudio] = useState(false);

  async function remove() {
    await supabase.from("words").update({ deleted: true }).eq("id", word.id);
    onChanged();
  }

  async function play() {
    let path = word.audio_path;
    if (!path) {
      setGenAudio(true);
      try {
        const res = await fetch(`/api/words/${word.id}/audio`, { method: "POST" });
        if (!res.ok) {
          alert((await res.json().catch(() => null))?.error ?? "Audio failed");
          return;
        }
        path = (await res.json()).audio_path as string;
        onChanged();
      } finally {
        setGenAudio(false);
      }
    }
    if (!path) return;
    const { data } = await supabase.storage
      .from("word-audio")
      .createSignedUrl(path, 60);
    if (data?.signedUrl) new Audio(data.signedUrl).play();
  }

  return (
    <li className="flex items-center gap-3 px-4 py-2">
      <button
        onClick={play}
        disabled={genAudio}
        title={word.audio_path ? "Play pronunciation" : "Generate & play audio"}
        className="shrink-0 rounded-full border border-gray-200 px-2 py-1 text-xs text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
      >
        {genAudio ? "…" : "▶"}
      </button>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <span className="font-medium">{word.term}</span>
          {word.reading && (
            <span className="text-sm text-gray-500">{word.reading}</span>
          )}
        </div>
        {word.meaning && (
          <div className="truncate text-sm text-gray-600">{word.meaning}</div>
        )}
        {word.meaning_mn && (
          <div className="truncate text-sm text-indigo-700">{word.meaning_mn}</div>
        )}
      </div>
      <button
        onClick={remove}
        title="Remove word"
        className="shrink-0 text-gray-300 transition hover:text-red-500"
      >
        ✕
      </button>
    </li>
  );
}
