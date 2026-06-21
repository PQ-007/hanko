"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Deck, DeckWithCount, Folder, Word } from "@/lib/types";

const supabase = createClient();

// Mongolian UI strings (all users are Mongolian).
const T = {
  folders: "Хавтаснууд",
  allDecks: "Бүх багц",
  noFolder: "Хавтасгүй",
  newFolder: "Шинэ хавтасны нэр",
  decks: "Багцууд",
  newDeck: "Шинэ багцын нэр",
  add: "Нэмэх",
  noDecks: "Багц алга",
  loading: "Ачааллаж байна…",
  createDeckToStart: "Эхлэхийн тулд багц үүсгэнэ үү.",
  search: "Үг хайх…",
  searchResults: "Хайлтын үр дүн",
  noResults: "Илэрц олдсонгүй",
  noWords: "Энэ багцад үг алга. Дээр нэмэх эсвэл өргөтгөлөөс хадгална уу.",
  exportApkg: ".apkg татах",
  building: "Бэлдэж байна…",
  exportFailed: "Экспорт амжилтгүй",
  delete: "Устгах",
  term: "Үг (ж: 勉強)",
  reading: "Дуудлага",
  lookingUp: "Хайж байна…",
  meaningEn: "Утга (Англи)",
  mongolian: "Монгол",
  addWord: "Үг нэмэх",
  clickToRename: "Нэр солих бол дарна уу",
  playAudio: "Дуудлага сонсох",
  removeWord: "Үг устгах",
  noFolderOption: "— Хавтасгүй —",
  audioFailed: "Дуу үүсгэж чадсангүй",
  deleteDeckConfirm: (n: string) =>
    `“${n}” багц болон доторх бүх үгийг устгах уу? Буцаах боломжгүй.`,
  deleteFolderConfirm: (n: string) =>
    `“${n}” хавтсыг устгах уу? Доторх багцууд устахгүй, хавтасгүй болно.`,
};

type FolderFilter = "all" | "none" | string;
type WordHit = Word & { deck?: { name: string } | null };

export default function DeckDashboard() {
  const [folders, setFolders] = useState<Folder[]>([]);
  const [decks, setDecks] = useState<DeckWithCount[]>([]);
  const [folderFilter, setFolderFilter] = useState<FolderFilter>("all");
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

  const visibleDecks = decks.filter((d) =>
    folderFilter === "all"
      ? true
      : folderFilter === "none"
        ? !d.folder_id
        : d.folder_id === folderFilter
  );
  const selectedDeck = decks.find((d) => d.id === selectedId) ?? null;
  const searching = results !== null;

  return (
    <div className="mx-auto flex max-w-6xl gap-6 p-6">
      <Sidebar
        folders={folders}
        decks={visibleDecks}
        loading={loadingDecks}
        folderFilter={folderFilter}
        onFolderFilter={setFolderFilter}
        selectedId={selectedId}
        onSelect={(id) => {
          setSelectedId(id);
          setQuery("");
        }}
        onFoldersChanged={loadFolders}
        onDecksChanged={loadDecks}
      />
      <section className="flex-1">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={T.search}
          className="mb-4 w-full rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm"
        />
        {error && (
          <p className="mb-4 rounded bg-red-50 px-4 py-2 text-sm text-red-600">
            {error}
          </p>
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

// --------------------------------------------------------------------------
// Sidebar: folders + decks
// --------------------------------------------------------------------------
function Sidebar({
  folders,
  decks,
  loading,
  folderFilter,
  onFolderFilter,
  selectedId,
  onSelect,
  onFoldersChanged,
  onDecksChanged,
}: {
  folders: Folder[];
  decks: DeckWithCount[];
  loading: boolean;
  folderFilter: FolderFilter;
  onFolderFilter: (f: FolderFilter) => void;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onFoldersChanged: () => void;
  onDecksChanged: () => void;
}) {
  const [deckName, setDeckName] = useState("");
  const [folderName, setFolderName] = useState("");

  async function createDeck() {
    const name = deckName.trim();
    if (!name) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      const folder_id =
        folderFilter !== "all" && folderFilter !== "none" ? folderFilter : null;
      await supabase.from("decks").insert({ name, user_id: user.id, folder_id });
    }
    setDeckName("");
    onDecksChanged();
  }

  async function createFolder() {
    const name = folderName.trim();
    if (!name) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) await supabase.from("folders").insert({ name, user_id: user.id });
    setFolderName("");
    onFoldersChanged();
  }

  async function deleteFolder(f: Folder) {
    if (!confirm(T.deleteFolderConfirm(f.name))) return;
    await supabase.from("folders").update({ deleted: true }).eq("id", f.id);
    if (folderFilter === f.id) onFolderFilter("all");
    onFoldersChanged();
    onDecksChanged();
  }

  const filterBtn = (active: boolean) =>
    `flex w-full items-center justify-between px-4 py-1.5 text-left text-sm transition hover:bg-gray-50 ${
      active ? "bg-amber-50 font-medium text-amber-800" : "text-gray-700"
    }`;

  return (
    <aside className="w-64 shrink-0 space-y-4">
      {/* Folders */}
      <div className="rounded-lg border border-gray-200 bg-white">
        <div className="border-b border-gray-100 px-4 py-3 text-sm font-semibold text-gray-700">
          {T.folders}
        </div>
        <ul>
          <li>
            <button className={filterBtn(folderFilter === "all")} onClick={() => onFolderFilter("all")}>
              {T.allDecks}
            </button>
          </li>
          <li>
            <button className={filterBtn(folderFilter === "none")} onClick={() => onFolderFilter("none")}>
              {T.noFolder}
            </button>
          </li>
          {folders.map((f) => (
            <li key={f.id} className="group flex items-center">
              <button className={filterBtn(folderFilter === f.id)} onClick={() => onFolderFilter(f.id)}>
                <span className="truncate">📁 {f.name}</span>
              </button>
              <button
                onClick={() => deleteFolder(f)}
                title={T.delete}
                className="px-2 text-gray-300 opacity-0 transition hover:text-red-500 group-hover:opacity-100"
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
        <div className="flex gap-2 border-t border-gray-100 p-3">
          <input
            value={folderName}
            onChange={(e) => setFolderName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && createFolder()}
            placeholder={T.newFolder}
            className="min-w-0 flex-1 rounded border border-gray-300 px-2 py-1 text-sm"
          />
          <button
            onClick={createFolder}
            className="rounded bg-amber-600 px-3 py-1 text-sm font-medium text-white transition hover:bg-amber-700"
          >
            {T.add}
          </button>
        </div>
      </div>

      {/* Decks */}
      <div className="rounded-lg border border-gray-200 bg-white">
        <div className="border-b border-gray-100 px-4 py-3 text-sm font-semibold text-gray-700">
          {T.decks}
        </div>
        <ul className="max-h-[45vh] overflow-auto">
          {loading && <li className="px-4 py-3 text-sm text-gray-400">{T.loading}</li>}
          {!loading && decks.length === 0 && (
            <li className="px-4 py-3 text-sm text-gray-400">{T.noDecks}</li>
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
                <span className="ml-2 shrink-0 text-xs text-gray-400">{d.word_count}</span>
              </button>
            </li>
          ))}
        </ul>
        <div className="flex gap-2 border-t border-gray-100 p-3">
          <input
            value={deckName}
            onChange={(e) => setDeckName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && createDeck()}
            placeholder={T.newDeck}
            className="min-w-0 flex-1 rounded border border-gray-300 px-2 py-1 text-sm"
          />
          <button
            onClick={createDeck}
            className="rounded bg-indigo-600 px-3 py-1 text-sm font-medium text-white transition hover:bg-indigo-700"
          >
            {T.add}
          </button>
        </div>
      </div>
    </aside>
  );
}

// --------------------------------------------------------------------------
// Search results
// --------------------------------------------------------------------------
function SearchResults({
  hits,
  onOpenDeck,
}: {
  hits: WordHit[];
  onOpenDeck: (deckId: string) => void;
}) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white">
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
                {w.meaning && <div className="truncate text-sm text-gray-600">{w.meaning}</div>}
                {w.meaning_mn && (
                  <div className="truncate text-sm text-indigo-700">{w.meaning_mn}</div>
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

// --------------------------------------------------------------------------
// Deck detail
// --------------------------------------------------------------------------
function DeckDetail({
  deck,
  folders,
  words,
  onWordsChanged,
}: {
  deck: DeckWithCount;
  folders: Folder[];
  words: Word[];
  onWordsChanged: () => void;
}) {
  return (
    <div className="space-y-4">
      <DeckHeader deck={deck} folders={folders} onChanged={onWordsChanged} />
      <AddWordForm deck={deck} onAdded={onWordsChanged} />
      <div className="rounded-lg border border-gray-200 bg-white">
        {words.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-gray-400">{T.noWords}</p>
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
  folders,
  onChanged,
}: {
  deck: DeckWithCount;
  folders: Folder[];
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

  async function moveToFolder(folderId: string) {
    await supabase
      .from("decks")
      .update({ folder_id: folderId || null })
      .eq("id", deck.id);
    onChanged();
  }

  async function remove() {
    if (!confirm(T.deleteDeckConfirm(deck.name))) return;
    await supabase.from("words").update({ deleted: true }).eq("deck_id", deck.id);
    await supabase.from("decks").update({ deleted: true }).eq("id", deck.id);
    onChanged();
  }

  async function download(format: "apkg" | "txt") {
    setExporting(format);
    try {
      const res = await fetch(`/api/decks/${deck.id}/${format}`, { method: "POST" });
      if (!res.ok) {
        alert((await res.json().catch(() => null))?.error ?? T.exportFailed);
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
          title={T.clickToRename}
        >
          {deck.name}{" "}
          <span className="text-sm font-normal text-gray-400">({deck.word_count})</span>
        </h2>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={deck.folder_id ?? ""}
          onChange={(e) => moveToFolder(e.target.value)}
          className="rounded border border-gray-300 px-2 py-1.5 text-sm text-gray-700"
        >
          <option value="">{T.noFolderOption}</option>
          {folders.map((f) => (
            <option key={f.id} value={f.id}>
              📁 {f.name}
            </option>
          ))}
        </select>
        <button
          onClick={() => download("apkg")}
          disabled={exporting !== null}
          className="rounded bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-emerald-700 disabled:opacity-60"
        >
          {exporting === "apkg" ? T.building : T.exportApkg}
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
          {T.delete}
        </button>
      </div>
    </div>
  );
}

function AddWordForm({ deck, onAdded }: { deck: Deck; onAdded: () => void }) {
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
          placeholder={T.term}
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <input
          value={reading}
          onChange={(e) => setReading(e.target.value)}
          placeholder={looking ? T.lookingUp : T.reading}
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <input
          value={meaning}
          onChange={(e) => setMeaning(e.target.value)}
          onBlur={translateMn}
          placeholder={T.meaningEn}
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <input
          value={meaningMn}
          onChange={(e) => setMeaningMn(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && add()}
          placeholder={T.mongolian}
          className="rounded border border-gray-300 px-2 py-1.5 text-sm"
        />
        <button
          onClick={add}
          disabled={busy || !term.trim()}
          className="rounded bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-indigo-700 disabled:opacity-60"
        >
          {T.addWord}
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
          alert((await res.json().catch(() => null))?.error ?? T.audioFailed);
          return;
        }
        path = (await res.json()).audio_path as string;
        onChanged();
      } finally {
        setGenAudio(false);
      }
    }
    if (!path) return;
    const { data } = await supabase.storage.from("word-audio").createSignedUrl(path, 60);
    if (data?.signedUrl) new Audio(data.signedUrl).play();
  }

  return (
    <li className="flex items-center gap-3 px-4 py-2">
      <button
        onClick={play}
        disabled={genAudio}
        title={T.playAudio}
        className="shrink-0 rounded-full border border-gray-200 px-2 py-1 text-xs text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
      >
        {genAudio ? "…" : "▶"}
      </button>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <span className="font-medium">{word.term}</span>
          {word.reading && <span className="text-sm text-gray-500">{word.reading}</span>}
        </div>
        {word.meaning && <div className="truncate text-sm text-gray-600">{word.meaning}</div>}
        {word.meaning_mn && (
          <div className="truncate text-sm text-indigo-700">{word.meaning_mn}</div>
        )}
      </div>
      <button
        onClick={remove}
        title={T.removeWord}
        className="shrink-0 text-gray-300 transition hover:text-red-500"
      >
        ✕
      </button>
    </li>
  );
}
