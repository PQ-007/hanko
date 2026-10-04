import type { Folder } from "@/lib/types";

// Nested folders (0024_mobile_parity.sql). Same rules as the Flutter app's
// mobile/lib/features/library/folder_tree.dart, so both clients put every
// deck in the same place:
//
//   - a folder whose parent can't be found (tombstoned, or just not loaded) is
//     a root folder;
//   - a deck whose folder can't be found is unfiled.
//
// The second rule also fixes the old flat sidebar, which only treated
// folder_id = null as unfiled — a deck in a deleted folder vanished from the
// sidebar entirely, though the delete dialog promised it would become unfiled.

export interface FolderNode<D> {
  folder: Folder;
  children: FolderNode<D>[];
  decks: D[];
}

export interface LibraryTree<D> {
  roots: FolderNode<D>[];
  unfiled: D[];
}

export function buildLibraryTree<D extends { folder_id: string | null }>(
  folders: Folder[],
  decks: D[]
): LibraryTree<D> {
  const nodes = new Map<string, FolderNode<D>>(
    folders.map((f) => [f.id, { folder: f, children: [], decks: [] }])
  );

  // Walks up from `parentId`; true if that chain reaches `id` again. The DB
  // trigger forbids cycles, but a bad row should land at root, not vanish.
  const createsCycle = (id: string, parentId: string | null) => {
    const seen = new Set([id]);
    let cur = parentId;
    while (cur) {
      if (seen.has(cur)) return true;
      seen.add(cur);
      cur = nodes.get(cur)?.folder.parent_id ?? null;
    }
    return false;
  };

  const roots: FolderNode<D>[] = [];
  for (const node of nodes.values()) {
    const parentId = node.folder.parent_id ?? null;
    const parent = parentId ? nodes.get(parentId) : undefined;
    if (!parent || createsCycle(node.folder.id, parentId)) roots.push(node);
    else parent.children.push(node);
  }

  const unfiled: D[] = [];
  for (const d of decks) {
    const node = d.folder_id ? nodes.get(d.folder_id) : undefined;
    if (node) node.decks.push(d);
    else unfiled.push(d);
  }

  return { roots, unfiled };
}

/** `folderId` and every folder beneath it — where it can't be moved to. */
export function subtreeIds(folders: Folder[], folderId: string): Set<string> {
  const byParent = new Map<string, string[]>();
  for (const f of folders) {
    if (!f.parent_id) continue;
    byParent.set(f.parent_id, [...(byParent.get(f.parent_id) ?? []), f.id]);
  }
  const out = new Set<string>();
  const stack = [folderId];
  while (stack.length) {
    const id = stack.pop()!;
    if (out.has(id)) continue;
    out.add(id);
    stack.push(...(byParent.get(id) ?? []));
  }
  return out;
}

/** Folders depth-first with their depth, for indented pickers. */
export function flattenTree<D>(roots: FolderNode<D>[]): { folder: Folder; depth: number }[] {
  const out: { folder: Folder; depth: number }[] = [];
  const walk = (n: FolderNode<D>, depth: number) => {
    out.push({ folder: n.folder, depth });
    n.children.forEach((c) => walk(c, depth + 1));
  };
  roots.forEach((r) => walk(r, 0));
  return out;
}

/** Decks in a node and everything below it. */
export function totalDecks<D>(node: FolderNode<D>): number {
  return node.decks.length + node.children.reduce((n, c) => n + totalDecks(c), 0);
}
