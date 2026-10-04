import { test } from "node:test";
import assert from "node:assert/strict";
import type { Folder } from "@/lib/types";
import { buildLibraryTree, subtreeIds, totalDecks } from "./folderTree.ts";

// Same cases as mobile/test/library_test.dart — the two clients must file
// every deck in the same place.

function folder(id: string, parent: string | null = null): Folder {
  return {
    id,
    user_id: "u",
    name: id,
    parent_id: parent,
    created_at: "",
    updated_at: "",
    deleted: false,
  };
}

const deck = (id: string, folder_id: string | null = null) => ({ id, folder_id });

test("nests folders and files decks under them", () => {
  const tree = buildLibraryTree([folder("a"), folder("b", "a")], [deck("d1", "b"), deck("d2")]);
  assert.deepEqual(tree.roots.map((n) => n.folder.id), ["a"]);
  assert.equal(tree.roots[0].children[0].folder.id, "b");
  assert.equal(tree.roots[0].children[0].decks[0].id, "d1");
  assert.equal(totalDecks(tree.roots[0]), 1);
  assert.deepEqual(tree.unfiled.map((d) => d.id), ["d2"]);
});

test("a parent that is gone puts the child at root", () => {
  const tree = buildLibraryTree([folder("child", "deleted")], []);
  assert.equal(tree.roots[0].folder.id, "child");
});

test("a deck whose folder was deleted is unfiled, not lost", () => {
  // The flat sidebar only treated folder_id = null as unfiled, so decks in a
  // deleted folder disappeared from it altogether.
  const tree = buildLibraryTree([], [deck("d", "deleted")]);
  assert.deepEqual(tree.unfiled.map((d) => d.id), ["d"]);
});

test("a cycle degrades to root instead of vanishing", () => {
  const tree = buildLibraryTree([folder("x", "y"), folder("y", "x")], []);
  const ids = new Set<string>();
  const walk = (ns: typeof tree.roots) =>
    ns.forEach((n) => {
      ids.add(n.folder.id);
      walk(n.children);
    });
  walk(tree.roots);
  assert.deepEqual([...ids].sort(), ["x", "y"]);
});

test("subtreeIds covers the folder and everything beneath it", () => {
  const folders = [folder("a"), folder("b", "a"), folder("c", "b"), folder("z")];
  assert.deepEqual([...subtreeIds(folders, "a")].sort(), ["a", "b", "c"]);
  assert.deepEqual([...subtreeIds(folders, "z")], ["z"]);
});
