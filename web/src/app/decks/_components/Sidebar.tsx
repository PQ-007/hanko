"use client";

import { type DragEvent, type MouseEvent, useEffect, useState } from "react";
import {
  ChevronDown,
  ChevronRight,
  FolderClosed,
  FolderOpen,
  FolderPlus,
  Layers,
  Search,
  Trash2,
  X,
} from "@/ui/icons";
import type { DeckWithCount, Folder } from "@/lib/types";
import { supabase } from "../_lib/db";
import { buildLibraryTree, subtreeIds, totalDecks, type FolderNode } from "../_lib/folderTree";
import { T } from "../_lib/strings";
import { askConfirm, askText } from "@/ui/Dialog";

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
  // One "add" field for both: the switch above it says what it creates.
  const [newName, setNewName] = useState("");
  const [newKind, setNewKind] = useState<"deck" | "folder">("deck");
  // Folders are expanded by default; track only the collapsed ones.
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});
  // Drag-and-drop: which drop target ("ungrouped" or a folder id) is hovered.
  const [dragOver, setDragOver] = useState<string | null>(null);
  // Quick filter, shown once the library is big enough to need it. While it's
  // non-empty the tree shows only matching decks (and the folders they're in).
  const [filter, setFilter] = useState("");
  // Right-click menu: what was clicked and where (viewport coordinates).
  const [menu, setMenu] = useState<
    { x: number; y: number; deck?: DeckWithCount; folder?: Folder } | null
  >(null);

  // The menu closes on any outside press, scroll, resize or Escape.
  useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(null);
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && close();
    window.addEventListener("pointerdown", close);
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("pointerdown", close);
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
      window.removeEventListener("keydown", onKey);
    };
  }, [menu]);

  function openMenu(e: MouseEvent, target: { deck?: DeckWithCount; folder?: Folder }) {
    e.preventDefault();
    e.stopPropagation();
    // Keep the menu on screen near the right/bottom edges.
    const x = Math.min(e.clientX, window.innerWidth - 220);
    const y = Math.min(e.clientY, window.innerHeight - 140);
    setMenu({ x, y, ...target });
  }
  const q = filter.trim().toLowerCase();
  const shown = q ? decks.filter((d) => d.name.toLowerCase().includes(q)) : decks;

  const tree = buildLibraryTree(folders, shown);
  // A folder with nothing matching inside it is hidden while filtering.
  const hasMatch = (node: FolderNode<DeckWithCount>): boolean =>
    node.decks.length > 0 || node.children.some(hasMatch);

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
    const name = await askText({
      title: T.newSubfolder,
      placeholder: T.subfolderName,
      confirmLabel: T.create,
    });
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

  async function create() {
    const name = newName.trim();
    if (!name) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    if (newKind === "deck") {
      await supabase.from("decks").insert({ name, user_id: user.id });
      onDecksChanged();
    } else {
      await supabase.from("folders").insert({ name, user_id: user.id });
      onFoldersChanged();
    }
    setNewName("");
  }

  async function deleteFolder(f: Folder) {
    const ok = await askConfirm({
      title: T.deleteFolderTitle,
      body: T.deleteFolderConfirm(f.name),
      danger: true,
    });
    if (!ok) return;
    await supabase.from("folders").update({ deleted: true }).eq("id", f.id);
    onFoldersChanged();
    onDecksChanged();
  }

  // Same semantics as DeckHeader's delete: tombstone the words, then the deck
  // (cards stay, so a restored deck keeps its schedules).
  async function deleteDeck(d: DeckWithCount) {
    const ok = await askConfirm({
      title: T.deleteDeckTitle,
      body: T.deleteDeckConfirm(d.name),
      danger: true,
    });
    if (!ok) return;
    await supabase.from("words").update({ deleted: true }).eq("deck_id", d.id);
    await supabase.from("decks").update({ deleted: true }).eq("id", d.id);
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
        onContextMenu={(e) => openMenu(e, { deck: d })}
        style={{ paddingLeft: 12 + depth * 20 }}
        title={d.name}
        className={`flex min-h-10 w-full cursor-grab items-center gap-2.5 rounded-control py-2 pr-2.5 text-left transition active:cursor-grabbing ${
          d.id === selectedId
            ? "bg-seal font-semibold text-white"
            : "text-ink hover:bg-paper-dim"
        }`}
      >
        <Layers size={17} className={`shrink-0 ${d.id === selectedId ? "text-white/80" : "text-ink-mute"}`} />
        <span className="min-w-0 flex-1 truncate">{d.name}</span>
        <span
          className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium tabular-nums ${
            d.id === selectedId ? "bg-white/20 text-white" : "bg-paper-dim text-ink-soft"
          }`}
        >
          {d.word_count}
        </span>
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
    if (q && !hasMatch(node)) return null;
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
        <div className="group flex min-h-10 items-center rounded-control hover:bg-paper-dim">
          <button
            draggable
            onDragStart={(e) => {
              e.stopPropagation();
              e.dataTransfer.setData("text/plain", FOLDER + f.id);
              e.dataTransfer.effectAllowed = "move";
            }}
            onClick={() => setCollapsed((c) => ({ ...c, [f.id]: !isCollapsed }))}
            onContextMenu={(e) => openMenu(e, { folder: f })}
            style={{ paddingLeft: 6 + depth * 20 }}
            aria-expanded={!isCollapsed}
            className="flex min-w-0 flex-1 cursor-grab items-center gap-2 py-2 pr-2 text-left text-ink active:cursor-grabbing"
          >
            {isCollapsed ? (
              <ChevronRight size={16} className="shrink-0 text-ink-mute" />
            ) : (
              <ChevronDown size={16} className="shrink-0 text-ink-mute" />
            )}
            {isCollapsed ? (
              <FolderClosed size={17} className="shrink-0 text-ink-soft" />
            ) : (
              <FolderOpen size={17} className="shrink-0 text-ink-soft" />
            )}
            <span className="min-w-0 flex-1 truncate font-semibold">{f.name}</span>
            <span className="shrink-0 text-xs tabular-nums text-ink-mute">{totalDecks(node)}</span>
          </button>
          {/* Always visible on touch screens (no hover there); on hover with a mouse. */}
          <div className="flex shrink-0 items-center pr-1 transition lg:opacity-0 lg:focus-within:opacity-100 lg:group-hover:opacity-100">
            <button
              onClick={() => createSubfolder(f)}
              title={T.newSubfolder}
              aria-label={T.newSubfolder}
              className="rounded-control p-1.5 text-ink-mute hover:bg-paper hover:text-ink"
            >
              <FolderPlus size={16} />
            </button>
            <button
              onClick={() => deleteFolder(f)}
              title={T.delete}
              aria-label={T.delete}
              className="rounded-control p-1.5 text-ink-mute hover:bg-paper hover:text-red-700"
            >
              <X size={16} />
            </button>
          </div>
        </div>
        {!isCollapsed &&
          (empty ? (
            <div style={{ paddingLeft: 44 + depth * 20 }} className="py-2 text-sm text-ink-mute">
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
    <aside className="w-full shrink-0 lg:sticky lg:top-6 lg:w-80 lg:self-start xl:w-[22rem]">
      <div className="hk-card flex flex-col lg:max-h-[calc(100dvh-9rem)]">
        <div className="flex items-center justify-between gap-2 border-b border-line-soft px-4 py-3.5">
          <span className="text-base font-semibold text-ink">
            {T.decks}
            <span className="ml-1.5 text-sm font-normal text-ink-mute">{decks.length}</span>
          </span>
        </div>

        {decks.length > 6 && (
          <div className="border-b border-line-soft px-3 py-2.5">
            <label className="hk-field flex items-center gap-2 rounded-control bg-paper-dim px-2.5 py-2 focus-within:ring-2 focus-within:ring-seal-tint">
              <Search size={15} className="shrink-0 text-ink-mute" />
              <input
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                onKeyDown={(e) => e.key === "Escape" && setFilter("")}
                placeholder={T.filterDecks}
                className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-ink-mute"
              />
              {filter && (
                <button onClick={() => setFilter("")} aria-label={T.clearFilter} className="text-ink-mute hover:text-ink">
                  <X size={14} />
                </button>
              )}
            </label>
          </div>
        )}

        <div className="min-h-0 flex-1 overflow-auto px-2 py-2 text-[15px]">
          {loading && <div className="px-3 py-2 text-ink-mute">{T.loading}</div>}
          {!loading && decks.length === 0 && folders.length === 0 && (
            <div className="px-3 py-2 text-ink-mute">{T.noDecks}</div>
          )}
          {q && shown.length === 0 && <div className="px-3 py-2 text-sm text-ink-mute">{T.noResults}</div>}

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
            {folders.length > 0 && tree.unfiled.length > 0 && (
              <div className="px-3 pb-1 pt-3 text-xs font-semibold uppercase tracking-wide text-ink-mute">
                {T.noFolder}
              </div>
            )}
            {tree.unfiled.map((d) => (
              <DeckItem key={d.id} d={d} depth={0} />
            ))}
          </div>
        </div>

        <div className="border-t border-line-soft p-3">
          <div role="radiogroup" aria-label={T.newKindLabel} className="mb-2 inline-flex rounded-control bg-paper-dim p-0.5 text-xs">
            {(["deck", "folder"] as const).map((k) => (
              <button
                key={k}
                role="radio"
                aria-checked={newKind === k}
                onClick={() => setNewKind(k)}
                className={`flex items-center gap-1.5 rounded-control px-2.5 py-1 font-medium transition ${
                  newKind === k ? "bg-surface text-ink shadow-sm" : "text-ink-soft hover:text-ink"
                }`}
              >
                {k === "deck" ? <Layers size={13} /> : <FolderPlus size={13} />}
                {k === "deck" ? T.deckShort : T.folderShort}
              </button>
            ))}
          </div>
          <div className="flex gap-2">
            <input
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && create()}
              placeholder={newKind === "deck" ? T.newDeck : T.newFolder}
              className="min-w-0 flex-1 rounded-control border border-line px-3 py-2 text-sm"
            />
            <button onClick={create} disabled={!newName.trim()} className="hk-btn hk-btn-primary px-4 py-2 text-sm disabled:opacity-50">
              {T.add}
            </button>
          </div>
        </div>
      </div>

      {menu && (
        <div
          role="menu"
          onPointerDown={(e) => e.stopPropagation()}
          style={{ left: menu.x, top: menu.y }}
          className="hk-menu fixed z-[90] w-52 rounded-control border border-line bg-surface p-1 shadow-xl"
        >
          <div className="truncate px-3 pb-1 pt-1.5 text-xs font-medium text-ink-mute">
            {menu.deck?.name ?? menu.folder?.name}
          </div>
          {menu.deck && (
            <button
              role="menuitem"
              onClick={() => {
                onSelect(menu.deck!.id);
                setMenu(null);
              }}
              className="flex w-full items-center gap-2.5 rounded-[8px] px-3 py-2 text-left text-sm transition text-ink hover:bg-paper-dim"
            >
              <Layers size={16} className="text-ink-mute" />
              {T.openDeck}
            </button>
          )}
          {menu.folder && (
            <button
              role="menuitem"
              onClick={() => {
                const f = menu.folder!;
                setMenu(null);
                createSubfolder(f);
              }}
              className="flex w-full items-center gap-2.5 rounded-[8px] px-3 py-2 text-left text-sm transition text-ink hover:bg-paper-dim"
            >
              <FolderPlus size={16} className="text-ink-mute" />
              {T.newSubfolder}
            </button>
          )}
          <div className="my-1 h-px bg-line-soft" />
          <button
            role="menuitem"
            onClick={() => {
              const { deck, folder } = menu;
              setMenu(null);
              if (deck) deleteDeck(deck);
              else if (folder) deleteFolder(folder);
            }}
            className="flex w-full items-center gap-2.5 rounded-[8px] px-3 py-2 text-left text-sm transition text-red-600 hover:bg-red-50 dark:text-red-300"
          >
            <Trash2 size={16} />
            {T.delete}
          </button>
        </div>
      )}
    </aside>
  );
}
