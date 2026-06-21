"use client";

import { type DragEvent, useState } from "react";
import {
  ChevronDown,
  ChevronRight,
  FolderClosed,
  FolderOpen,
  FolderPlus,
  Layers,
  X,
} from "lucide-react";
import type { DeckWithCount, Folder } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";

export default function Sidebar({
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
  // Drag-and-drop: which drop target ("ungrouped" or a folder id) is hovered.
  const [dragOver, setDragOver] = useState<string | null>(null);

  const decksIn = (folderId: string | null) =>
    decks.filter((d) => (d.folder_id ?? null) === folderId);

  // Move a dragged deck into a folder (or out, when target is null).
  async function moveDeck(deckId: string, folderId: string | null) {
    setDragOver(null);
    const deck = decks.find((d) => d.id === deckId);
    if (!deck || (deck.folder_id ?? null) === folderId) return;
    await supabase.from("decks").update({ folder_id: folderId }).eq("id", deckId);
    onDecksChanged();
  }

  function onDrop(e: DragEvent, folderId: string | null) {
    e.preventDefault();
    e.stopPropagation();
    const deckId = e.dataTransfer.getData("text/plain");
    if (deckId) moveDeck(deckId, folderId);
  }

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

  function DeckItem({ d, depth = 0 }: { d: DeckWithCount; depth?: number }) {
    return (
      <button
        draggable
        onDragStart={(e) => {
          e.dataTransfer.setData("text/plain", d.id);
          e.dataTransfer.effectAllowed = "move";
        }}
        onClick={() => onSelect(d.id)}
        style={{ paddingLeft: 12 + depth * 16 }}
        className={`flex w-full cursor-grab items-center gap-1.5 py-1 pr-2 text-left transition hover:bg-gray-100 active:cursor-grabbing ${
          d.id === selectedId
            ? "bg-gray-900 font-medium text-white"
            : "text-gray-700"
        }`}
      >
        <Layers size={14} className="shrink-0 text-gray-400" />
        <span className="truncate">{d.name}</span>
        <span className="ml-auto shrink-0 pl-2 text-xs text-gray-400">{d.word_count}</span>
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
            className="rounded p-1 text-gray-600 transition hover:bg-gray-50"
          >
            <FolderPlus size={16} />
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
              className="rounded bg-gray-900 px-3 py-1 text-sm font-medium text-white transition hover:bg-gray-800"
            >
              {T.add}
            </button>
          </div>
        )}

        <div className="max-h-[55vh] overflow-auto py-1 text-[13px]">
          {loading && <div className="px-3 py-2 text-gray-400">{T.loading}</div>}
          {!loading && decks.length === 0 && folders.length === 0 && (
            <div className="px-3 py-2 text-gray-400">{T.noDecks}</div>
          )}

          {/* Folders with their decks (drop a deck here to file it) */}
          {folders.map((f) => {
            const isCollapsed = !!collapsed[f.id];
            const children = decksIn(f.id);
            return (
              <div
                key={f.id}
                onDragOver={(e) => {
                  e.preventDefault();
                  setDragOver(f.id);
                }}
                onDragLeave={() => setDragOver((p) => (p === f.id ? null : p))}
                onDrop={(e) => onDrop(e, f.id)}
                className={dragOver === f.id ? "rounded bg-gray-50 ring-1 ring-gray-300" : ""}
              >
                <div className="group flex items-center hover:bg-gray-100">
                  <button
                    onClick={() => setCollapsed((c) => ({ ...c, [f.id]: !isCollapsed }))}
                    className="flex min-w-0 flex-1 items-center gap-1 px-2 py-1 text-left text-gray-700"
                  >
                    {isCollapsed ? (
                      <ChevronRight size={14} className="shrink-0 text-gray-400" />
                    ) : (
                      <ChevronDown size={14} className="shrink-0 text-gray-400" />
                    )}
                    {isCollapsed ? (
                      <FolderClosed size={15} className="shrink-0 text-gray-500" />
                    ) : (
                      <FolderOpen size={15} className="shrink-0 text-gray-500" />
                    )}
                    <span className="truncate font-medium">{f.name}</span>
                    <span className="ml-auto shrink-0 pr-1 text-xs text-gray-400">
                      {children.length}
                    </span>
                  </button>
                  <button
                    onClick={() => deleteFolder(f)}
                    title={T.delete}
                    className="px-2 text-gray-300 opacity-0 transition hover:text-gray-900 group-hover:opacity-100"
                  >
                    <X size={14} />
                  </button>
                </div>
                {!isCollapsed &&
                  (children.length === 0 ? (
                    <div className="py-1 pl-9 text-xs text-gray-300">{T.emptyFolder}</div>
                  ) : (
                    children.map((d) => <DeckItem key={d.id} d={d} depth={1} />)
                  ))}
              </div>
            );
          })}

          {/* Ungrouped decks (drop a deck here to remove it from its folder) */}
          <div
            onDragOver={(e) => {
              e.preventDefault();
              setDragOver("ungrouped");
            }}
            onDragLeave={() => setDragOver((p) => (p === "ungrouped" ? null : p))}
            onDrop={(e) => onDrop(e, null)}
            className={`mt-1 min-h-[2rem] ${
              dragOver === "ungrouped" ? "rounded bg-gray-50 ring-1 ring-gray-300" : ""
            }`}
          >
            {folders.length > 0 && (
              <div className="px-3 pb-0.5 pt-1 text-[11px] font-medium uppercase tracking-wide text-gray-400">
                {T.noFolder}
              </div>
            )}
            {ungrouped.map((d) => (
              <DeckItem key={d.id} d={d} depth={0} />
            ))}
          </div>
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
            className="rounded bg-gray-900 px-3 py-1 text-sm font-medium text-white transition hover:bg-gray-800"
          >
            {T.add}
          </button>
        </div>
      </div>
    </aside>
  );
}
