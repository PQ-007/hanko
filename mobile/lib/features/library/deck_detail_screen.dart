import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../decks/word_actions.dart';
import '../decks/word_editor.dart';
import '../shell/action_sheet.dart';
import '../stats/grade_bars.dart';
import 'deck_actions.dart';

/// One deck: its words, the grade chart doubling as a filter, and the deck's
/// actions (web DeckHeader.tsx + DeckDetail.tsx).
class DeckDetailScreen extends ConsumerStatefulWidget {
  const DeckDetailScreen({super.key, required this.deckId});
  final String deckId;

  @override
  ConsumerState<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends ConsumerState<DeckDetailScreen> {
  Grade? _filter;
  bool _grid = false;

  Future<void> _add(Deck deck) async {
    final draft = await showWordEditor(context);
    if (draft == null || !mounted) return;
    await addWordChecked(context, ref, deckId: deck.id, draft: draft);
  }

  Future<void> _edit(Word word) async {
    final draft = await showWordEditor(context, existing: word);
    if (draft == null || !mounted) return;
    try {
      await ref.read(repositoryProvider).updateWord(word.id, draft);
      ref.refreshLibrary(deckId: word.deckId);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final words = ref.watch(deckWordsProvider(widget.deckId));
    final hero = ref.watch(heroProvider);
    final deck = decks.value?.where((d) => d.id == widget.deckId).firstOrNull;

    if (deck == null) {
      return Scaffold(
        appBar: AppBar(),
        body: decks.isLoading ? const LoadingScene() : const Center(child: Text(T.noResults)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(deck.name),
        actions: [
          IconButton(
            tooltip: _grid ? T.listView : T.gridView,
            icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          IconButton(
            tooltip: T.practice,
            icon: const Icon(Icons.play_arrow),
            onPressed: () => startReviewFlow(context, ref, deckId: deck.id),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'rename':
                  await renameDeck(context, ref, deck);
                case 'move':
                  await moveDeck(context, ref, deck);
                case 'txt':
                  await exportDeckTxt(context, ref, deck);
                case 'delete':
                  if (await deleteDeck(context, ref, deck) && context.mounted) context.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text(T.rename)),
              PopupMenuItem(value: 'move', child: Text(T.moveTo)),
              PopupMenuItem(value: 'txt', child: Text(T.exportTxt)),
              PopupMenuItem(value: 'delete', child: Text(T.delete)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(deck),
        tooltip: T.addWord,
        child: const Icon(Icons.add),
      ),
      body: words.when(
        loading: () => const LoadingScene(label: T.loading),
        error: (e, _) => Center(child: Text('${T.loadFailed}\n$e')),
        data: (all) {
          if (all.isEmpty) {
            return HeroEmptyState(
              hero: hero,
              title: T.noWords,
              action: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text(T.addWord),
                onPressed: () => _add(deck),
              ),
            );
          }
          final visible =
              _filter == null ? all : all.where((w) => gradeOfWord(w) == _filter).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.refreshLibrary(deckId: deck.id),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  sliver: SliverToBoxAdapter(
                    child: GradeBars(
                      words: all,
                      selected: _filter,
                      onSelect: (g) => setState(() => _filter = g),
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(T.gradeFilterEmpty)),
                  )
                else if (_grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.95,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => _WordCard(
                        word: visible[i],
                        onEdit: () => _edit(visible[i]),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 88),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _WordTile(
                        word: visible[i],
                        onEdit: () => _edit(visible[i]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WordTile extends ConsumerWidget {
  const _WordTile({required this.word, required this.onEdit});
  final Word word;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = [word.reading, word.meaningMn, word.meaning]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');
    return ListTile(
      leading: IconButton(
        tooltip: T.playAudio,
        icon: const Icon(Icons.volume_up_outlined, color: HankoColors.seal),
        onPressed: () => playWord(context, ref, word),
      ),
      title: Row(
        children: [
          Flexible(child: Text(word.term, style: const TextStyle(fontSize: 17))),
          const SizedBox(width: 6),
          GradeBadge(gradeOfWord(word)),
        ],
      ),
      subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onEdit,
      trailing: IconButton(
        tooltip: T.removeWord,
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => confirmDeleteWord(context, ref, word),
      ),
    );
  }
}

/// Grid card: tap flips between the word and its meaning (the web's hover
/// flip, as a tap). Long-press edits.
class _WordCard extends ConsumerStatefulWidget {
  const _WordCard({required this.word, required this.onEdit});
  final Word word;
  final VoidCallback onEdit;

  @override
  ConsumerState<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends ConsumerState<_WordCard> {
  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _back = !_back),
        onLongPress: widget.onEdit,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Padding(
            key: ValueKey(_back),
            padding: const EdgeInsets.all(12),
            child: _back
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (w.meaningMn != null && w.meaningMn!.isNotEmpty)
                                Text(w.meaningMn!,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (w.meaning != null && w.meaning!.isNotEmpty)
                                Text(w.meaning!,
                                    style: TextStyle(fontSize: 12, color: context.hk.inkSoft)),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.volume_up_outlined, size: 20),
                            onPressed: () => playWord(context, ref, w),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: widget.onEdit,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => confirmDeleteWord(context, ref, w),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Align(alignment: Alignment.topRight, child: GradeBadge(gradeOfWord(w))),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(w.term,
                                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      if (w.reading != null && w.reading != w.term)
                        Text(w.reading!,
                            style: TextStyle(fontSize: 12, color: context.hk.inkSoft)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
