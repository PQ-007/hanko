"use client";

import { useState } from "react";
import Link from "next/link";
import { FolderClosed, GraduationCap, LayoutGrid, LayoutList, Plus, RefreshCw } from "lucide-react";
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
  const [refreshing, setRefreshing] = useState(false);

  function refresh() {
    setRefreshing(true);
    onChanged(); // reloads this deck's words + deck counts
    setTimeout(() => setRefreshing(false), 600);
  }

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
          className="rounded-control border border-line px-2 py-1 text-xl font-semibold"
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
          <span className="text-sm font-normal text-ink-mute">({deck.word_count})</span>
        </h2>
      )}
      <div className="flex w-full flex-wrap items-center gap-2 sm:w-auto">
        <button
          onClick={refresh}
          title={T.refresh}
          className="shrink-0 rounded-control border border-line p-1.5 text-ink-soft transition hover:bg-paper-dim"
        >
          <RefreshCw size={16} className={refreshing ? "animate-spin" : ""} />
        </button>
        {/* View toggle: list / card grid */}
        <div className="flex shrink-0 overflow-hidden rounded-control border border-line">
          <button
            onClick={() => onView("grid")}
            title={T.gridView}
            className={`p-1.5 transition ${
              view === "grid" ? "bg-seal text-paper" : "text-ink-soft hover:bg-paper-dim"
            }`}
          >
            <LayoutGrid size={16} />
          </button>
          <button
            onClick={() => onView("list")}
            title={T.listView}
            className={`p-1.5 transition ${
              view === "list" ? "bg-seal text-paper" : "text-ink-soft hover:bg-paper-dim"
            }`}
          >
            <LayoutList size={16} />
          </button>
        </div>
        <div className="flex min-w-0 flex-1 items-center gap-1.5 rounded-control border border-line px-2 py-1 sm:flex-none">
          <FolderClosed size={15} className="shrink-0 text-ink-soft" />
          <select
            value={deck.folder_id ?? ""}
            onChange={(e) => moveToFolder(e.target.value)}
            className="min-w-0 flex-1 bg-transparent text-sm text-ink focus:outline-none"
          >
            <option value="">{T.noFolderOption}</option>
            {folders.map((f) => (
              <option key={f.id} value={f.id}>
                {f.name}
              </option>
            ))}
          </select>
        </div>
        <Link
          href={`/decks/practice?deck=${deck.id}`}
          className="flex shrink-0 items-center gap-1 hk-btn hk-btn-primary px-3 py-1.5 text-sm"
        >
          <GraduationCap size={15} /> {T.practice}
        </Link>
        <button
          onClick={onToggleAdd}
          className={`flex items-center gap-1 rounded-control px-3 py-1.5 text-sm font-medium transition ${
            adding
              ? "border border-line text-ink hover:bg-paper-dim"
              : "bg-seal text-paper hover:bg-seal-dark"
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
          className="hk-btn hk-btn-primary px-3 py-1.5 text-sm disabled:opacity-60"
        >
          {exporting === "apkg" ? T.building : T.exportApkg}
        </button>
        <button
          onClick={() => download("txt")}
          disabled={exporting !== null}
          className="rounded-control border border-line px-3 py-1.5 text-sm font-medium text-ink transition hover:bg-paper-dim disabled:opacity-60"
        >
          .txt
        </button>
        <button
          onClick={remove}
          className="rounded-control border border-line px-3 py-1.5 text-sm font-medium text-ink transition hover:bg-paper-dim"
        >
          {T.delete}
        </button>
      </div>
    </div>
  );
}
