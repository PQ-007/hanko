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
import { buildLibraryTree, subtreeIds, totalDecks, type FolderNode } from "../_lib/folderTree";
import { T } from "../_lib/strings";

// Drag payloads carry their kind, since both decks and folders can be dropped
// onto a folder now.
const DECK = "deck:";
const FOLDER = "folder:";

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

  const tree = buildLibraryTree(folders, decks);

  // Move a dragged deck into a folder (or out, when target is null).
  async function moveDeck(deckId: string, folderId: string | null) {
    const deck = decks.find((d) => d.id === deckId);
    if (!deck || (deck.folder_id ?? null) === folderId) return;
    await supabase.from("decks").update({ folder_id: folderId }).eq("id", deckId);
    onDecksChanged();
  }

  // Nest a folder under another (or back to root). A folder can't go into its
  // own subtree; the folders_check_parent trigger (0024) enforces the same, so
  // this check is only to skip a doomed round trip.
  async function moveFolder(folderId: string, parentId: string | null) {
    const f = folders.find((x) => x.id === folderId);
    if (!f || (f.parent_id ?? null) === parentId) return;
    if (parentId && subtreeIds(folders, folderId).has(parentId)) return;
    const { error } = await supabase
      .from("folders")
      .update({ parent_id: parentId })
      .eq("id", folderId);
    if (error) alert(`${T.folderMoveFailed} ${error.message}`);
    onFoldersChanged();
  }

  function onDrop(e: DragEvent, folderId: string | null) {
    e.preventDefault();
    e.stopPropagation();
    setDragOver(null);
    const payload = e.dataTransfer.getData("text/plain");
    if (payload.startsWith(DECK)) moveDeck(payload.slice(DECK.length), folderId);
    else if (payload.startsWith(FOLDER)) moveFolder(payload.slice(FOLDER.length), folderId);
  }

  async function createSubfolder(parent: Folder) {
    const name = prompt(T.newSubfolder)?.trim();
    if (!name) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      await supabase.from("folders").insert({ name, user_id: user.id, parent_id: parent.id });
    }
    setCollapsed((c) => ({ ...c, [parent.id]: false }));
    onFoldersChanged();
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
          e.dataTransfer.setData("text/plain", DECK + d.id);
          e.dataTransfer.effectAllowed = "move";
        }}
        onClick={() => onSelect(d.id)}
        style={{ paddingLeft: 12 + depth * 16 }}
        className={`flex w-full cursor-grab items-center gap-1.5 py-1 pr-2 text-left transition hover:bg-paper-dim active:cursor-grabbing ${
          d.id === selectedId
            ? "bg-seal font-medium text-white"
            : "text-ink"
        }`}
      >
        <Layers size={14} className="shrink-0 text-ink-mute" />
        <span className="truncate">{d.name}</span>
        <span className="ml-auto shrink-0 pl-2 text-xs text-ink-mute">{d.word_count}</span>
      </button>
    );
  }

  // Recursive, so a folder renders its sub-folders before its own decks.
  // Called as a function rather than mounted as <FolderItem/>: a component
  // defined inside Sidebar would get a new identity every render, remounting
  // the whole tree (and losing drag state) on each hover.
  function renderFolder(node: FolderNode<DeckWithCount>, depth: number) {
    const f = node.folder;
    const isCollapsed = !!collapsed[f.id];
    const empty = node.children.length === 0 && node.decks.length === 0;
    return (
      <div
        key={f.id}
        onDragOver={(e) => {
          e.preventDefault();
          e.stopPropagation();
          setDragOver(f.id);
        }}
        onDragLeave={() => setDragOver((p) => (p === f.id ? null : p))}
        onDrop={(e) => onDrop(e, f.id)}
        className={dragOver === f.id ? "rounded-control bg-paper ring-1 ring-line" : ""}
      >
        <div className="group flex items-center hover:bg-paper-dim">
          <button
            draggable
            onDragStart={(e) => {
              e.stopPropagation();
              e.dataTransfer.setData("text/plain", FOLDER + f.id);
              e.dataTransfer.effectAllowed = "move";
            }}
            onClick={() => setCollapsed((c) => ({ ...c, [f.id]: !isCollapsed }))}
            style={{ paddingLeft: 8 + depth * 16 }}
            className="flex min-w-0 flex-1 cursor-grab items-center gap-1 py-1 pr-2 text-left text-ink active:cursor-grabbing"
          >
            {isCollapsed ? (
              <ChevronRight size={14} className="shrink-0 text-ink-mute" />
            ) : (
              <ChevronDown size={14} className="shrink-0 text-ink-mute" />
            )}
            {isCollapsed ? (
              <FolderClosed size={15} className="shrink-0 text-ink-soft" />
            ) : (
              <FolderOpen size={15} className="shrink-0 text-ink-soft" />
            )}
            <span className="truncate font-medium">{f.name}</span>
            <span className="ml-auto shrink-0 pr-1 text-xs text-ink-mute">{totalDecks(node)}</span>
          </button>
          <button
            onClick={() => createSubfolder(f)}
            title={T.newSubfolder}
            className="px-1 text-ink-mute opacity-0 transition hover:text-ink group-hover:opacity-100"
          >
            <FolderPlus size={14} />
          </button>
          <button
            onClick={() => deleteFolder(f)}
            title={T.delete}
            className="px-2 text-ink-mute opacity-0 transition hover:text-ink group-hover:opacity-100"
          >
            <X size={14} />
          </button>
        </div>
        {!isCollapsed &&
          (empty ? (
            <div style={{ paddingLeft: 36 + depth * 16 }} className="py-1 text-xs text-ink-mute">
              {T.emptyFolder}
            </div>
          ) : (
            <>
              {node.children.map((c) => renderFolder(c, depth + 1))}
              {node.decks.map((d) => (
                <DeckItem key={d.id} d={d} depth={depth + 1} />
              ))}
            </>
          ))}
      </div>
    );
  }

  return (
    <aside className="w-full shrink-0 lg:w-64">
      <div className="hk-card">
        <div className="flex items-center justify-between border-b border-line-soft px-4 py-3">
          <span className="text-sm font-semibold text-ink">{T.decks}</span>
          <button
            onClick={() => setAddingFolder((v) => !v)}
            title={T.newFolderTitle}
            className="rounded-control p-1 text-ink-soft transition hover:bg-paper-dim"
          >
            <FolderPlus size={16} />
          </button>
        </div>

        {addingFolder && (
          <div className="flex gap-2 border-b border-line-soft p-3">
            <input
              autoFocus
              value={folderName}
              onChange={(e) => setFolderName(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && createFolder()}
              placeholder={T.newFolder}
              className="min-w-0 flex-1 rounded-control border border-line px-2 py-1 text-sm"
            />
            <button
              onClick={createFolder}
              className="hk-btn hk-btn-primary px-3 py-1 text-sm"
            >
              {T.add}
            </button>
          </div>
        )}

        <div className="max-h-[55vh] overflow-auto py-1 text-[13px]">
          {loading && <div className="px-3 py-2 text-ink-mute">{T.loading}</div>}
          {!loading && decks.length === 0 && folders.length === 0 && (
            <div className="px-3 py-2 text-ink-mute">{T.noDecks}</div>
          )}

          {/* Folder tree (drop a deck or a folder onto a folder to nest it) */}
          {tree.roots.map((node) => renderFolder(node, 0))}

          {/* Ungrouped decks (drop a deck here to unfile it, or a folder to
              move it back to the top level) */}
          <div
            onDragOver={(e) => {
              e.preventDefault();
              setDragOver("ungrouped");
            }}
            onDragLeave={() => setDragOver((p) => (p === "ungrouped" ? null : p))}
            onDrop={(e) => onDrop(e, null)}
            className={`mt-1 min-h-[2rem] ${
              dragOver === "ungrouped" ? "rounded-control bg-paper ring-1 ring-line" : ""
            }`}
          >
            {folders.length > 0 && (
              <div className="px-3 pb-0.5 pt-1 text-[11px] font-medium uppercase tracking-wide text-ink-mute">
                {T.noFolder}
              </div>
            )}
            {tree.unfiled.map((d) => (
              <DeckItem key={d.id} d={d} depth={0} />
            ))}
          </div>
        </div>

        <div className="flex gap-2 border-t border-line-soft p-3">
          <input
            value={deckName}
            onChange={(e) => setDeckName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && createDeck()}
            placeholder={T.newDeck}
            className="min-w-0 flex-1 rounded-control border border-line px-2 py-1 text-sm"
          />
          <button
            onClick={createDeck}
            className="hk-btn hk-btn-primary px-3 py-1 text-sm"
          >
            {T.add}
          </button>
        </div>
      </div>
    </aside>
  );
}
