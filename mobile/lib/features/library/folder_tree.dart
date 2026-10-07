import '../../models/library.dart';

class FolderNode {
  FolderNode(this.folder);
  final Folder folder;
  final List<FolderNode> children = [];
  final List<Deck> decks = [];

  /// Decks in this folder and everything below it.
  int get totalDecks =>
      decks.length + children.fold<int>(0, (a, c) => a + c.totalDecks);
}

class LibraryTree {
  const LibraryTree({required this.roots, required this.unfiled});
  final List<FolderNode> roots;

  /// Decks with no folder, or whose folder no longer exists.
  final List<Deck> unfiled;
}

/// Arranges flat rows into a tree. A parent or folder that can't be found —
/// tombstoned, or simply not loaded — counts as root / unfiled, the same rule
/// the web sidebar uses for a deck whose folder was deleted (0024 relies on
/// this instead of cascading writes on delete).
///
/// Defends against a cycle even though the database trigger forbids one: a
/// node is only attached under a parent if walking up from that parent never
/// reaches it, so a bad row degrades to "shown at root" rather than vanishing.
LibraryTree buildLibraryTree(List<Folder> folders, List<Deck> decks) {
  final nodes = {for (final f in folders) f.id: FolderNode(f)};
  final roots = <FolderNode>[];

  bool createsCycle(String id, String? parentId) {
    final seen = <String>{id};
    var cur = parentId;
    while (cur != null) {
      if (!seen.add(cur)) return true;
      cur = nodes[cur]?.folder.parentId;
    }
    return false;
  }

  for (final node in nodes.values) {
    final parentId = node.folder.parentId;
    final parent = parentId == null ? null : nodes[parentId];
    if (parent == null || createsCycle(node.folder.id, parentId)) {
      roots.add(node);
    } else {
      parent.children.add(node);
    }
  }

  final unfiled = <Deck>[];
  for (final d in decks) {
    final node = d.folderId == null ? null : nodes[d.folderId];
    if (node == null) {
      unfiled.add(d);
    } else {
      node.decks.add(d);
    }
  }

  return LibraryTree(roots: roots, unfiled: unfiled);
}

/// [folderId] and every folder under it — the ones a folder can't be moved
/// into.
Set<String> subtreeIds(List<Folder> folders, String folderId) {
  final byParent = <String, List<String>>{};
  for (final f in folders) {
    if (f.parentId != null) (byParent[f.parentId!] ??= []).add(f.id);
  }
  final out = <String>{};
  final stack = [folderId];
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    if (!out.add(id)) continue;
    stack.addAll(byParent[id] ?? const []);
  }
  return out;
}

/// Depth-first (folder, depth) list for indented pickers.
List<(Folder, int)> flattenTree(List<FolderNode> roots) {
  final out = <(Folder, int)>[];
  void walk(FolderNode n, int depth) {
    out.add((n.folder, depth));
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  for (final r in roots) {
    walk(r, 0);
  }
  return out;
}
