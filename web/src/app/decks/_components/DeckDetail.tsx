"use client";

import { useState } from "react";
import type { DeckWithCount, Folder, Word } from "@/lib/types";
import { T } from "../_lib/strings";
import type { WordView } from "../_lib/types";
import DeckHeader from "./DeckHeader";
import AddWordForm from "./AddWordForm";
import WordRow from "./WordRow";
import WordEditModal from "./WordEditModal";

export default function DeckDetail({
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
  const [editingId, setEditingId] = useState<string | null>(null);
  const [view, setView] = useState<WordView>("grid");

  const rows = words.map((w) => (
    <WordRow
      key={w.id}
      word={w}
      grid={view === "grid"}
      onEdit={() => setEditingId(w.id)}
      onChanged={onWordsChanged}
    />
  ));
  const editingWord = words.find((w) => w.id === editingId) ?? null;

  return (
    <div className="space-y-4">
      <DeckHeader
        deck={deck}
        folders={folders}
        adding={adding}
        onToggleAdd={() => setAdding((v) => !v)}
        view={view}
        onView={setView}
        onChanged={onWordsChanged}
      />
      {adding && <AddWordForm deck={deck} onAdded={onWordsChanged} />}
      {words.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-white shadow-sm">
          <p className="px-4 py-8 text-center text-sm text-gray-400">{T.noWords}</p>
        </div>
      ) : view === "grid" ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">{rows}</div>
      ) : (
        <div className="rounded-lg border border-gray-200 bg-white shadow-sm">
          <ul className="divide-y divide-gray-100">{rows}</ul>
        </div>
      )}

      {editingWord && (
        <WordEditModal
          word={editingWord}
          onClose={() => setEditingId(null)}
          onSaved={() => {
            setEditingId(null);
            onWordsChanged();
          }}
        />
      )}
    </div>
  );
}
