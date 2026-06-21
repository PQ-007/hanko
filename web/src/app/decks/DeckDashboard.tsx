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
  newFolderTitle: "Шинэ хавтас нэмэх",
  emptyFolder: "хоосон",
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
  edit: "Засах",
  save: "Хадгалах",
  cancel: "Болих",
  noFolderOption: "— Хавтасгүй —",
  audioFailed: "Дуу үүсгэж чадсангүй",
  deleteDeckConfirm: (n: string) =>
    `“${n}” багц болон доторх бүх үгийг устгах уу? Буцаах боломжгүй.`,
  deleteFolderConfirm: (n: string) =>
    `“${n}” хавтсыг устгах уу? Доторх багцууд устахгүй, хавтасгүй болно.`,
};

type WordHit = Word & { deck?: { name: string } | null };

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
    <div className="mx-auto flex max-w-6xl flex-col gap-4 p-4 sm:p-6 lg:flex-row lg:gap-6">
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
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={T.search}
          className="mb-4 w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-sm shadow-sm focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-100"
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
  selectedId,
  onSelect,
  onFoldersChanged,
  onDecksChanged,
}: {
  folders: Folder[];
  decks: DeckWithCount[];
  loading: boolean;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onFoldersChanged: () => void;
  onDecksChanged: () => void;
}) {
  const [deckName, setDeckName] = useState("");
  const [folderName, setFolderName] = useState("");
  const [addingFolder, setAddingFolder] = useState(false);
  // Folders are expanded by default; track only the collapsed ones.
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  const decksIn = (folderId: string | null) =>
    decks.filter((d) => (d.folder_id ?? null) === folderId);

  async function createDeck() {
    const name = deckName.trim();
    if (!name) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) await supabase.from("decks").insert({ name, user_id: user.id });
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
    setAddingFolder(false);
    onFoldersChanged();
  }

  async function deleteFolder(f: Folder) {
    if (!confirm(T.deleteFolderConfirm(f.name))) return;
    await supabase.from("folders").update({ deleted: true }).eq("id", f.id);
    onFoldersChanged();
    onDecksChanged();
  }

  function DeckItem({ d }: { d: DeckWithCount }) {
    return (
      <button
        onClick={() => onSelect(d.id)}
        className={`flex w-full items-center justify-between gap-2 rounded px-2 py-1.5 text-left text-sm transition hover:bg-gray-50 ${
          d.id === selectedId ? "bg-indigo-50 font-medium text-indigo-700" : "text-gray-700"
        }`}
      >
        <span className="truncate">{d.name}</span>
        <span className="shrink-0 text-xs text-gray-400">{d.word_count}</span>
      </button>
    );
  }

  const ungrouped = decksIn(null);

  return (
    <aside className="w-full shrink-0 lg:w-64">
      <div className="rounded-lg border border-gray-200 bg-white shadow-sm">
        <div className="flex items-center justify-between border-b border-gray-100 px-4 py-3">
          <span className="text-sm font-semibold text-gray-700">{T.decks}</span>
          <button
            onClick={() => setAddingFolder((v) => !v)}
            title={T.newFolderTitle}
            className="rounded px-2 py-0.5 text-sm text-amber-700 transition hover:bg-amber-50"
          >
            + 📁
          </button>
        </div>

        {addingFolder && (
          <div className="flex gap-2 border-b border-gray-100 p-3">
            <input
              autoFocus
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
        )}

        <div className="max-h-[55vh] overflow-auto p-2">
          {loading && <div className="px-2 py-3 text-sm text-gray-400">{T.loading}</div>}
          {!loading && decks.length === 0 && folders.length === 0 && (
            <div className="px-2 py-3 text-sm text-gray-400">{T.noDecks}</div>
          )}

          {/* Folders with their decks */}
          {folders.map((f) => {
            const isCollapsed = !!collapsed[f.id];
            const children = decksIn(f.id);
            return (
              <div key={f.id} className="mb-1">
                <div className="group flex items-center rounded hover:bg-gray-50">
                  <button
                    onClick={() => setCollapsed((c) => ({ ...c, [f.id]: !isCollapsed }))}
                    className="flex min-w-0 flex-1 items-center gap-1 px-2 py-1.5 text-left text-sm font-medium text-gray-700"
                  >
                    <span className="w-3 shrink-0 text-xs text-gray-400">
                      {isCollapsed ? "▸" : "▾"}
                    </span>
                    <span className="shrink-0">📁</span>
                    <span className="truncate">{f.name}</span>
                    <span className="ml-auto shrink-0 text-xs text-gray-400">
                      {children.length}
                    </span>
                  </button>
                  <button
                    onClick={() => deleteFolder(f)}
                    title={T.delete}
                    className="px-2 text-gray-300 opacity-0 transition hover:text-red-500 group-hover:opacity-100"
                  >
                    ✕
                  </button>
                </div>
                {!isCollapsed && (
                  <div className="ml-3 border-l border-gray-100 pl-2">
                    {children.length === 0 ? (
                      <div className="px-2 py-1 text-xs text-gray-300">{T.emptyFolder}</div>
                    ) : (
                      children.map((d) => <DeckItem key={d.id} d={d} />)
                    )}
                  </div>
                )}
              </div>
            );
          })}

          {/* Ungrouped decks */}
          {ungrouped.length > 0 && (
            <div className="mt-1">
              {folders.length > 0 && (
                <div className="px-2 pb-1 pt-2 text-xs font-medium uppercase tracking-wide text-gray-400">
                  {T.noFolder}
                </div>
              )}
              {ungrouped.map((d) => (
                <DeckItem key={d.id} d={d} />
              ))}
            </div>
          )}
        </div>

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
  const [adding, setAdding] = useState(false);
  // Only one word card is editable at a time; opening another closes the first.
  const [editingId, setEditingId] = useState<string | null>(null);

  return (
    <div className="space-y-4">
      <DeckHeader
        deck={deck}
        folders={folders}
        adding={adding}
        onToggleAdd={() => setAdding((v) => !v)}
        onChanged={onWordsChanged}
      />
      {adding && <AddWordForm deck={deck} onAdded={onWordsChanged} />}
      <div className="rounded-lg border border-gray-200 bg-white shadow-sm">
        {words.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-gray-400">{T.noWords}</p>
        ) : (
          <ul className="divide-y divide-gray-100">
            {words.map((w) => (
              <WordRow
                key={w.id}
                word={w}
                editing={editingId === w.id}
                onEdit={() => setEditingId(w.id)}
                onClose={() => setEditingId(null)}
                onChanged={onWordsChanged}
              />
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
  adding,
  onToggleAdd,
  onChanged,
}: {
  deck: DeckWithCount;
  folders: Folder[];
  adding: boolean;
  onToggleAdd: () => void;
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
    <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
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
      <div className="flex w-full flex-wrap items-center gap-2 sm:w-auto">
        <select
          value={deck.folder_id ?? ""}
          onChange={(e) => moveToFolder(e.target.value)}
          className="min-w-0 flex-1 rounded border border-gray-300 px-2 py-1.5 text-sm text-gray-700 sm:flex-none"
        >
          <option value="">{T.noFolderOption}</option>
          {folders.map((f) => (
            <option key={f.id} value={f.id}>
              📁 {f.name}
            </option>
          ))}
        </select>
        <button
          onClick={onToggleAdd}
          className={`rounded px-3 py-1.5 text-sm font-medium transition ${
            adding
              ? "border border-gray-300 text-gray-700 hover:bg-gray-50"
              : "bg-indigo-600 text-white hover:bg-indigo-700"
          }`}
        >
          {adding ? T.cancel : `+ ${T.addWord}`}
        </button>
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
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-[1fr_1fr_1.5fr_1.5fr_auto]">
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
          className="rounded bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-700 disabled:opacity-60 sm:col-span-2 lg:col-span-1"
        >
          {T.addWord}
        </button>
      </div>
    </div>
  );
}

function WordRow({
  word,
  editing,
  onEdit,
  onClose,
  onChanged,
}: {
  word: Word;
  editing: boolean;
  onEdit: () => void;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [genAudio, setGenAudio] = useState(false);
  const [saving, setSaving] = useState(false);
  const [term, setTerm] = useState(word.term);
  const [reading, setReading] = useState(word.reading ?? "");
  const [meaning, setMeaning] = useState(word.meaning ?? "");
  const [meaningMn, setMeaningMn] = useState(word.meaning_mn ?? "");

  // When this row enters edit mode, populate the fields from the word.
  useEffect(() => {
    /* eslint-disable react-hooks/set-state-in-effect */
    if (editing) {
      setTerm(word.term);
      setReading(word.reading ?? "");
      setMeaning(word.meaning ?? "");
      setMeaningMn(word.meaning_mn ?? "");
    }
    /* eslint-enable react-hooks/set-state-in-effect */
  }, [editing, word]);

  async function remove() {
    await supabase.from("words").update({ deleted: true }).eq("id", word.id);
    onChanged();
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
      // leave as-is
    }
  }

  async function save() {
    if (!term.trim()) return;
    setSaving(true);
    await supabase
      .from("words")
      .update({
        term: term.trim(),
        reading: reading.trim() || null,
        meaning: meaning.trim() || null,
        meaning_mn: meaningMn.trim() || null,
      })
      .eq("id", word.id);
    setSaving(false);
    onChanged();
    onClose();
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

  const inputCls = "rounded border border-gray-300 px-2 py-1.5 text-sm";

  if (editing) {
    return (
      <li className="px-4 py-3">
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <input value={term} onChange={(e) => setTerm(e.target.value)} placeholder={T.term} className={inputCls} />
          <input value={reading} onChange={(e) => setReading(e.target.value)} placeholder={T.reading} className={inputCls} />
          <input value={meaning} onChange={(e) => setMeaning(e.target.value)} onBlur={translateMn} placeholder={T.meaningEn} className={inputCls} />
          <input value={meaningMn} onChange={(e) => setMeaningMn(e.target.value)} placeholder={T.mongolian} className={inputCls} />
        </div>
        <div className="mt-2 flex gap-2">
          <button
            onClick={save}
            disabled={saving || !term.trim()}
            className="rounded bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-indigo-700 disabled:opacity-60"
          >
            {T.save}
          </button>
          <button
            onClick={onClose}
            className="rounded border border-gray-300 px-4 py-1.5 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
          >
            {T.cancel}
          </button>
        </div>
      </li>
    );
  }

  return (
    <li className="group flex items-center gap-3 px-4 py-2">
      <button
        onClick={play}
        disabled={genAudio}
        title={T.playAudio}
        className="shrink-0 rounded-full border border-gray-200 px-2 py-1 text-xs text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
      >
        {genAudio ? "…" : "▶"}
      </button>
      <button onClick={onEdit} className="min-w-0 flex-1 text-left" title={T.edit}>
        <div className="flex items-baseline gap-2">
          <span className="font-medium">{word.term}</span>
          {word.reading && <span className="text-sm text-gray-500">{word.reading}</span>}
        </div>
        {word.meaning && <div className="break-words text-sm text-gray-600">{word.meaning}</div>}
        {word.meaning_mn && (
          <div className="break-words text-sm text-indigo-700">{word.meaning_mn}</div>
        )}
      </button>
      <div className="flex shrink-0 items-center gap-2">
        <button
          onClick={onEdit}
          title={T.edit}
          className="text-gray-300 transition hover:text-indigo-600 sm:opacity-0 sm:group-hover:opacity-100"
        >
          ✎
        </button>
        <button
          onClick={remove}
          title={T.removeWord}
          className="text-gray-300 transition hover:text-red-500"
        >
          ✕
        </button>
      </div>
    </li>
  );
}
