"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Download, FolderClosed, GraduationCap, LayoutGrid, LayoutList, MoreHorizontal, Plus, RefreshCw, Share2, Trash2 } from "@/ui/icons";
import type { DeckWithCount, Folder } from "@/lib/types";
import { supabase } from "../_lib/db";
import { buildLibraryTree, flattenTree } from "../_lib/folderTree";
import { T } from "../_lib/strings";
import type { WordView } from "../_lib/types";
import DeckShareModal from "./DeckShareModal";

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
  const [sharing, setSharing] = useState(false);
  // Phones: the less-used actions live behind "⋯" so the toolbar is one row.
  const [menu, setMenu] = useState(false);
  useEffect(() => {
    if (!menu) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setMenu(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [menu]);

  function refresh() {
    onChanged(); // reloads this deck's words + deck counts
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
        <Link
          href={`/decks/practice?deck=${deck.id}`}
          className="flex shrink-0 items-center gap-1 hk-btn hk-btn-primary px-3 py-1.5 text-sm max-sm:flex-1 max-sm:justify-center"
        >
          <GraduationCap size={15} /> {T.practice}
        </Link>
        <button
          onClick={onToggleAdd}
          className={`flex items-center gap-1 rounded-control px-3 py-1.5 text-sm font-medium transition max-sm:flex-1 max-sm:justify-center ${
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
        <div className="relative">
          <button
            onClick={() => setMenu((m) => !m)}
            aria-expanded={menu}
            aria-haspopup="menu"
            aria-label={T.moreActions}
            title={T.moreActions}
            className={`rounded-control border border-line p-1.5 text-ink-soft transition hover:bg-paper-dim ${menu ? "bg-paper-dim" : ""}`}
          >
            <MoreHorizontal size={18} />
          </button>
          {menu && (
            <>
              {/* Click anywhere else (or Escape) closes it. */}
              <div className="fixed inset-0 z-20" onClick={() => setMenu(false)} />
            <div className="absolute right-0 top-full z-30 mt-1.5 flex w-64 flex-col divide-y divide-line-soft overflow-hidden rounded-control border border-line bg-surface text-sm shadow-lg">
              <label className="flex items-center gap-2.5 px-3 py-2.5">
                <FolderClosed size={16} className="shrink-0 text-ink-soft" />
                <select
                  value={folders.some((f) => f.id === deck.folder_id) ? deck.folder_id! : ""}
                  onChange={(e) => moveToFolder(e.target.value)}
                  className="min-w-0 flex-1 bg-transparent text-ink focus:outline-none"
                >
                  <option value="">{T.noFolderOption}</option>
                  {flattenTree(buildLibraryTree(folders, []).roots).map(({ folder, depth }) => (
                    <option key={folder.id} value={folder.id}>
                      {"  ".repeat(depth)}
                      {folder.name}
                    </option>
                  ))}
                </select>
              </label>
              {[
                { icon: Share2, label: T.shareDeck, run: () => setSharing(true) },
                { icon: Download, label: exporting === "apkg" ? T.building : T.exportApkg, run: () => download("apkg") },
                { icon: Download, label: ".txt", run: () => download("txt") },
                { icon: RefreshCw, label: T.refresh, run: refresh },
                { icon: Trash2, label: T.delete, run: remove, danger: true },
              ].map(({ icon: Icon, label, run, danger }) => (
                <button
                  key={label}
                  disabled={exporting !== null}
                  onClick={() => {
                    setMenu(false);
                    run();
                  }}
                  className={`flex items-center gap-2.5 px-3 py-2.5 text-left hover:bg-paper-dim disabled:opacity-50 ${danger ? "text-red-700" : "text-ink"}`}
                >
                  <Icon size={16} className="shrink-0" /> {label}
                </button>
              ))}
            </div>
            </>
          )}
        </div>
      </div>
      {sharing && <DeckShareModal deck={deck} onClose={() => setSharing(false)} />}
    </div>
  );
}
