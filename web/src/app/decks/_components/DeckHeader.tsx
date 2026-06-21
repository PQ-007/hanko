"use client";

import { useState } from "react";
import { FolderClosed, LayoutGrid, LayoutList, Plus } from "lucide-react";
import type { DeckWithCount, Folder } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import type { WordView } from "../_lib/types";

export default function DeckHeader({
  deck,
  folders,
  adding,
  onToggleAdd,
  view,
  onView,
  onChanged,
}: {
  deck: DeckWithCount;
  folders: Folder[];
  adding: boolean;
  onToggleAdd: () => void;
  view: WordView;
  onView: (v: WordView) => void;
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
        {/* View toggle: list / card grid */}
        <div className="flex shrink-0 overflow-hidden rounded border border-gray-300">
          <button
            onClick={() => onView("grid")}
            title={T.gridView}
            className={`p-1.5 transition ${
              view === "grid" ? "bg-gray-900 text-white" : "text-gray-500 hover:bg-gray-50"
            }`}
          >
            <LayoutGrid size={16} />
          </button>
          <button
            onClick={() => onView("list")}
            title={T.listView}
            className={`p-1.5 transition ${
              view === "list" ? "bg-gray-900 text-white" : "text-gray-500 hover:bg-gray-50"
            }`}
          >
            <LayoutList size={16} />
          </button>
        </div>
        <div className="flex min-w-0 flex-1 items-center gap-1.5 rounded border border-gray-300 px-2 py-1 sm:flex-none">
          <FolderClosed size={15} className="shrink-0 text-gray-500" />
          <select
            value={deck.folder_id ?? ""}
            onChange={(e) => moveToFolder(e.target.value)}
            className="min-w-0 flex-1 bg-transparent text-sm text-gray-700 focus:outline-none"
          >
            <option value="">{T.noFolderOption}</option>
            {folders.map((f) => (
              <option key={f.id} value={f.id}>
                {f.name}
              </option>
            ))}
          </select>
        </div>
        <button
          onClick={onToggleAdd}
          className={`flex items-center gap-1 rounded px-3 py-1.5 text-sm font-medium transition ${
            adding
              ? "border border-gray-300 text-gray-700 hover:bg-gray-50"
              : "bg-gray-900 text-white hover:bg-gray-800"
          }`}
        >
          {adding ? (
            T.cancel
          ) : (
            <>
              <Plus size={15} /> {T.addWord}
            </>
          )}
        </button>
        <button
          onClick={() => download("apkg")}
          disabled={exporting !== null}
          className="rounded bg-gray-900 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-gray-800 disabled:opacity-60"
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
          className="rounded border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-800 transition hover:bg-gray-50"
        >
          {T.delete}
        </button>
      </div>
    </div>
  );
}
