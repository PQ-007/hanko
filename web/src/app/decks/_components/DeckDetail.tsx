"use client";

import { useEffect, useState } from "react";
import type { DeckWithCount, Folder, Word } from "@/lib/types";
import { gradeFor, type Grade } from "@/lib/srs";
import { T } from "../_lib/strings";
import type { WordView } from "../_lib/types";
import DeckHeader from "./DeckHeader";
import AddWordForm from "./AddWordForm";
import GradeChart from "./GradeChart";
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
  const [selectedGrade, setSelectedGrade] = useState<Grade | null>(null);

  // A filter picked on one deck shouldn't silently carry over and hide
  // everything when the user switches to another deck.
  useEffect(() => {
    setSelectedGrade(null);
  }, [deck.id]);

  const visibleWords = selectedGrade === null ? words : words.filter((w) => gradeFor(w) === selectedGrade);

  const rows = visibleWords.map((w) => (
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
      {adding && <AddWordForm deck={deck} words={words} onAdded={onWordsChanged} />}
      {words.length > 0 && (
        <GradeChart words={words} selected={selectedGrade} onSelect={setSelectedGrade} />
      )}
      {words.length === 0 ? (
        <div className="hk-card">
          <p className="px-4 py-8 text-center text-sm text-ink-mute">{T.noWords}</p>
        </div>
      ) : visibleWords.length === 0 ? (
        <div className="hk-card">
          <p className="px-4 py-8 text-center text-sm text-ink-mute">{T.gradeFilterEmpty}</p>
        </div>
      ) : view === "grid" ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">{rows}</div>
      ) : (
        <div className="hk-card">
          <ul className="divide-y divide-line-soft">{rows}</ul>
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
