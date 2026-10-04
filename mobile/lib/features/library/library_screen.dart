import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../decks/word_actions.dart';
import '../stats/grade_bars.dart';
import 'deck_actions.dart';
import 'folder_tree.dart';

/// Folders (nested) and decks, plus search across every deck.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<Word>>? _results;

  /// Collapsed folder ids. Expanded by default, like the web sidebar.
  final _collapsed = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    // Same 250ms debounce as the web's DeckDashboard search.
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = q.trim();
        _results = _query.isEmpty ? null : ref.read(repositoryProvider).searchWords(_query);
      });
    });
  }

  void _openDeck(String deckId) => context.push(Routes.deck(deckId));

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(foldersProvider);
    final decks = ref.watch(decksProvider);
    final counts = ref.watch(deckCountsProvider).value ?? const <String, int>{};
    final hero = ref.watch(heroProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(T.navLibrary),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            onSelected: (v) {
              if (v == 'folder') createFolder(context, ref);
              if (v == 'deck') createDeck(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'deck',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.style_outlined),
                    title: Text(T.newDeck)),
              ),
              PopupMenuItem(
                value: 'folder',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.create_new_folder_outlined),
                    title: Text(T.newFolderTitle)),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: _onQuery,
              decoration: InputDecoration(
                hintText: T.search,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _onQuery('');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: _query.isNotEmpty
          ? _SearchResults(future: _results, onOpenDeck: _openDeck)
          : (folders.isLoading && !folders.hasValue) || (decks.isLoading && !decks.hasValue)
              ? const LoadingScene(label: T.loading)
              : folders.hasError || decks.hasError
                  ? Center(child: Text('${T.loadFailed}\n${folders.error ?? decks.error}'))
                  : RefreshIndicator(
                      onRefresh: () async => ref.refreshLibrary(),
                      child: _tree(
                        buildLibraryTree(folders.value!, decks.value!),
                        counts,
                        hero,
                      ),
                    ),
    );
  }

  Widget _tree(LibraryTree tree, Map<String, int> counts, String hero) {
    if (tree.roots.isEmpty && tree.unfiled.isEmpty) {
      return ListView(
        children: [
          HeroEmptyState(
            hero: hero,
            title: T.noDecks,
            subtitle: T.createDeckToStart,
            action: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text(T.newDeck),
              onPressed: () => createDeck(context, ref),
            ),
          ),
        ],
      );
    }

    final rows = <Widget>[];
    void addFolder(FolderNode node, int depth) {
      final open = !_collapsed.contains(node.folder.id);
      rows.add(_FolderRow(
        node: node,
        depth: depth,
        open: open,
        onToggle: () => setState(() {
          open ? _collapsed.add(node.folder.id) : _collapsed.remove(node.folder.id);
        }),
      ));
      if (!open) return;
      for (final child in node.children) {
        addFolder(child, depth + 1);
      }
      for (final d in node.decks) {
        rows.add(_DeckRow(deck: d, depth: depth + 1, count: counts[d.id] ?? 0, onOpen: _openDeck));
      }
      if (node.children.isEmpty && node.decks.isEmpty) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: 56.0 + (depth + 1) * 18, bottom: 6),
          child: const Text(T.emptyFolder, style: TextStyle(color: HankoColors.inkMute, fontSize: 12)),
        ));
      }
    }

    for (final root in tree.roots) {
      addFolder(root, 0);
    }
    if (tree.unfiled.isNotEmpty) {
      if (tree.roots.isNotEmpty) {
        rows.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(T.noFolder,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HankoColors.inkMute)),
        ));
      }
      for (final d in tree.unfiled) {
        rows.add(_DeckRow(deck: d, depth: 0, count: counts[d.id] ?? 0, onOpen: _openDeck));
      }
    }

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({
    required this.node,
    required this.depth,
    required this.open,
    required this.onToggle,
  });

  final FolderNode node;
  final int depth;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = node.folder;
    return ListTile(
      contentPadding: EdgeInsets.only(left: 8.0 + depth * 18, right: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20, color: HankoColors.inkMute),
          const SizedBox(width: 2),
          Icon(open ? Icons.folder_open_outlined : Icons.folder_outlined, color: HankoColors.seal),
        ],
      ),
      title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${node.totalDecks} ${T.colDeck.toLowerCase()}',
          style: const TextStyle(fontSize: 11)),
      onTap: onToggle,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) {
          switch (v) {
            case 'deck':
              createDeck(context, ref, folder: f);
            case 'folder':
              createFolder(context, ref, parent: f);
            case 'rename':
              renameFolder(context, ref, f);
            case 'move':
              moveFolder(context, ref, f);
            case 'delete':
              deleteFolder(context, ref, f);
          }
        },
        itemBuilder: (_) => [
          _item('deck', Icons.style_outlined, T.newDeck),
          _item('folder', Icons.create_new_folder_outlined, T.newFolderInside),
          _item('rename', Icons.edit_outlined, T.rename),
          _item('move', Icons.drive_file_move_outlined, T.moveTo),
          _item('delete', Icons.delete_outline, T.delete, danger: true),
        ],
      ),
    );
  }
}

class _DeckRow extends ConsumerWidget {
  const _DeckRow({
    required this.deck,
    required this.depth,
    required this.count,
    required this.onOpen,
  });

  final Deck deck;
  final int depth;
  final int count;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 30.0 + depth * 18, right: 4),
      leading: const Icon(Icons.style_outlined, color: HankoColors.inkSoft),
      title: Text(deck.name),
      subtitle: Text(T.wordCount(count), style: const TextStyle(fontSize: 11)),
      onTap: () => onOpen(deck.id),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) {
          switch (v) {
            case 'rename':
              renameDeck(context, ref, deck);
            case 'move':
              moveDeck(context, ref, deck);
            case 'delete':
              deleteDeck(context, ref, deck);
          }
        },
        itemBuilder: (_) => [
          _item('rename', Icons.edit_outlined, T.rename),
          _item('move', Icons.drive_file_move_outlined, T.moveTo),
          _item('delete', Icons.delete_outline, T.delete, danger: true),
        ],
      ),
    );
  }
}

PopupMenuItem<String> _item(String value, IconData icon, String label, {bool danger = false}) {
  final color = danger ? Colors.red.shade700 : null;
  return PopupMenuItem(
    value: value,
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(color: color)),
    ),
  );
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.future, required this.onOpenDeck});
  final Future<List<Word>>? future;
  final ValueChanged<String> onOpenDeck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Word>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (snap.hasError) return Center(child: Text('${T.loadFailed}\n${snap.error}'));
        final words = snap.data ?? const [];
        if (words.isEmpty) return const Center(child: Text(T.noResults));
        return ListView.separated(
          itemCount: words.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final w = words[i];
            final sub = [w.reading, w.meaningMn, w.meaning]
                .where((s) => s != null && s.isNotEmpty)
                .join(' · ');
            return ListTile(
              title: Row(
                children: [
                  Flexible(child: Text(w.term, style: const TextStyle(fontSize: 17))),
                  const SizedBox(width: 6),
                  GradeBadge(gradeOfWord(w)),
                ],
              ),
              subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: w.deckName == null
                  ? null
                  : ActionChip(
                      label: Text(w.deckName!, style: const TextStyle(fontSize: 11)),
                      onPressed: () => onOpenDeck(w.deckId),
                    ),
              onTap: () => playWord(context, ref, w),
            );
          },
        );
      },
    );
  }
}
