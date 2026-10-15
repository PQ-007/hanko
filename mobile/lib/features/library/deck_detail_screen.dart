import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/offline_review.dart';
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
import '../shell/quick_add_sheet.dart';
import '../stats/grade_bars.dart';
import 'deck_actions.dart';
import 'deck_share_sheet.dart';
import 'word_batches.dart';
import 'word_bulk.dart';

/// One deck: its words, the grade chart doubling as a filter, and the deck's
/// actions (web DeckHeader.tsx + DeckDetail.tsx). Plus what a camera capture
/// needs: the last batch added, with undo; sort and an "added when" filter;
/// and a long-press selection to delete or move several words at once.
class DeckDetailScreen extends ConsumerStatefulWidget {
  const DeckDetailScreen({super.key, required this.deckId});
  final String deckId;

  @override
  ConsumerState<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends ConsumerState<DeckDetailScreen> {
  Grade? _filter;
  bool _grid = false;
  WordSort _sort = WordSort.newest;
  AddedWithin _within = AddedWithin.any;

  /// Long-press starts a selection; while it is non-empty, taps toggle.
  final _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Word w) => setState(() {
    if (!_selected.remove(w.id)) _selected.add(w.id);
  });

  Future<void> _deleteSelected(Deck deck) async {
    final ids = [..._selected];
    if (await deleteWordsWithUndo(context, ref, deckId: deck.id, ids: ids) && mounted) {
      setState(_selected.clear);
    }
  }

  Future<void> _moveSelected(Deck deck) async {
    final ids = [..._selected];
    if (await moveWordsWithUndo(context, ref, fromDeckId: deck.id, ids: ids) && mounted) {
      setState(_selected.clear);
    }
  }

  /// The same add sheet as quick add, with this deck fixed: lookups as you
  /// type, the handwriting pad, and it stays open for the next word.
  Future<void> _add(Deck deck) => showQuickAddSheet(context, ref, deckId: deck.id, lockDeck: true);

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
    // Kept loaded so the ⋯ menu knows whether this deck is downloaded.
    ref.watch(offlineDecksProvider);
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

    final visibleIds = _visible(words.value ?? const []).map((w) => w.id).toList();

    return PopScope(
      // Back leaves the selection first, then the deck.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: T.cancel,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text(T.selectedCount(_selected.length)),
                actions: [
                  IconButton(
                    tooltip: T.selectAll,
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() => _selected.addAll(visibleIds)),
                  ),
                  IconButton(
                    tooltip: T.moveWordsTo,
                    icon: const Icon(Icons.drive_file_move_outline),
                    onPressed: () => _moveSelected(deck),
                  ),
                  IconButton(
                    tooltip: T.deleteSelected,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteSelected(deck),
                  ),
                ],
              )
            : AppBar(
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
                        case 'share':
                          await showDeckShareSheet(context, deck);
                        case 'offline':
                          await downloadDeckOffline(context, ref, deck);
                        case 'offlineRemove':
                          await removeDeckOffline(context, ref, deck);
                        case 'examples':
                          await fillDeckExamples(context, ref, deck);
                        case 'delete':
                          if (await deleteDeck(context, ref, deck) && context.mounted) {
                            context.pop();
                          }
                      }
                    },
                    itemBuilder: (_) {
                      final downloaded =
                          ref.read(offlineDecksProvider).value?.containsKey(deck.id) ?? false;
                      return [
                        const PopupMenuItem(value: 'share', child: Text(T.shareDeck)),
                        PopupMenuItem(
                          value: 'offline',
                          child: Text(downloaded ? T.offlineRefresh : T.offlineDownload),
                        ),
                        if (downloaded)
                          const PopupMenuItem(value: 'offlineRemove', child: Text(T.offlineRemove)),
                        const PopupMenuItem(value: 'examples', child: Text(T.fillExamples)),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'rename', child: Text(T.rename)),
                        const PopupMenuItem(value: 'move', child: Text(T.moveTo)),
                        const PopupMenuItem(value: 'txt', child: Text(T.exportTxt)),
                        const PopupMenuItem(value: 'delete', child: Text(T.delete)),
                      ];
                    },
                  ),
                ],
              ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
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
            final visible = _visible(all);
            final batch = _selecting ? null : latestBatch(all, DateTime.now());

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
                  if (batch != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      sliver: SliverToBoxAdapter(
                        child: _LastBatchCard(
                          batch: batch,
                          onSelect: () =>
                              setState(() => _selected.addAll(batch.words.map((w) => w.id))),
                          onUndo: () => deleteWordsWithUndo(
                            context,
                            ref,
                            deckId: deck.id,
                            ids: [for (final w in batch.words) w.id],
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _ListControls(
                      within: _within,
                      sort: _sort,
                      onWithin: (v) => setState(() => _within = v),
                      onSort: (v) => setState(() => _sort = v),
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _within != AddedWithin.any ? T.addedFilterEmpty : T.gradeFilterEmpty,
                        ),
                      ),
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
                          selecting: _selecting,
                          selected: _selected.contains(visible[i].id),
                          onToggle: () => _toggle(visible[i]),
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
                          selecting: _selecting,
                          selected: _selected.contains(visible[i].id),
                          onToggle: () => _toggle(visible[i]),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Grade filter, then the "added when" filter, then the chosen order.
  List<Word> _visible(List<Word> all) {
    final graded = _filter == null ? all : all.where((w) => gradeOfWord(w) == _filter).toList();
    return sortWords(addedWithin(graded, _within, DateTime.now()), _sort);
  }
}

class _WordTile extends ConsumerWidget {
  const _WordTile({
    required this.word,
    required this.onEdit,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });
  final Word word;
  final VoidCallback onEdit;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = [
      word.reading,
      word.meaningMn,
      word.meaning,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');
    return ListTile(
      selected: selected,
      selectedTileColor: context.hk.sealTint.withValues(alpha: 0.45),
      leading: selecting
          ? Checkbox(value: selected, onChanged: (_) => onToggle())
          : IconButton(
              tooltip: T.playAudio,
              icon: Icon(Icons.volume_up_outlined, color: context.hk.sealText),
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
      onTap: selecting ? onToggle : onEdit,
      onLongPress: onToggle,
      trailing: selecting
          ? null
          : IconButton(
              tooltip: T.removeWord,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => confirmDeleteWord(context, ref, word),
            ),
    );
  }
}

/// Grid card: tap flips between the word and its meaning (the web's hover
/// flip, as a tap); editing is on the back. Long-press selects, as in the
/// list, and while selecting a tap toggles instead of flipping.
class _WordCard extends ConsumerStatefulWidget {
  const _WordCard({
    required this.word,
    required this.onEdit,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });
  final Word word;
  final VoidCallback onEdit;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  @override
  ConsumerState<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends ConsumerState<_WordCard> {
  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    final hk = context.hk;
    return Card(
      margin: EdgeInsets.zero,
      color: widget.selected ? hk.sealTint : null,
      shape: widget.selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: hk.seal, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.selecting ? widget.onToggle : () => setState(() => _back = !_back),
        onLongPress: widget.onToggle,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Padding(
            key: ValueKey(_back),
            padding: const EdgeInsets.all(12),
            child: _back && !widget.selecting
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Centred on the card, like the word on the front;
                      // a meaning too long to fit still scrolls.
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (w.meaningMn != null && w.meaningMn!.isNotEmpty)
                                  Text(
                                    w.meaningMn!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                if (w.meaning != null && w.meaning!.isNotEmpty)
                                  Text(
                                    w.meaning!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: context.hk.inkSoft),
                                  ),
                              ],
                            ),
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
                      Row(
                        children: [
                          if (widget.selecting)
                            Icon(
                              widget.selected ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 20,
                              color: widget.selected ? hk.sealText : hk.inkMute,
                            ),
                          const Spacer(),
                          GradeBadge(gradeOfWord(w)),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              w.term,
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      if (w.reading != null && w.reading != w.term)
                        Text(w.reading!, style: TextStyle(fontSize: 12, color: context.hk.inkSoft)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The deck's most recent batch — a camera capture, usually — with the two
/// ways out of having pushed it into the wrong deck.
class _LastBatchCard extends StatelessWidget {
  const _LastBatchCard({required this.batch, required this.onSelect, required this.onUndo});
  final WordBatch batch;
  final VoidCallback onSelect;
  final VoidCallback onUndo;

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    return d.inHours >= 1 ? T.agoHours(d.inHours) : T.agoMinutes(d.inMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final n = batch.words.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: hk.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hk.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 18, color: hk.sealText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(T.lastBatch(n), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(_ago(batch.at), style: TextStyle(fontSize: 12, color: hk.inkMute)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in batch.words.take(8))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: hk.paper,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: hk.lineSoft),
                  ),
                  child: Text(w.term, style: const TextStyle(fontSize: 13)),
                ),
              if (n > 8) Text('+${n - 8}', style: TextStyle(fontSize: 12, color: hk.inkMute)),
            ],
          ),
          const SizedBox(height: 6),
          Text(T.lastBatchHint, style: TextStyle(fontSize: 12, color: hk.inkSoft)),
          const SizedBox(height: 4),
          // Wraps rather than overflows on a narrow phone or large text.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text(T.selectWords),
              ),
              TextButton.icon(
                onPressed: onUndo,
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                icon: const Icon(Icons.undo, size: 18),
                label: Text(T.lastBatchUndo(n)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Added when" filter chips and the sort menu, above the word list.
class _ListControls extends StatelessWidget {
  const _ListControls({
    required this.within,
    required this.sort,
    required this.onWithin,
    required this.onSort,
  });
  final AddedWithin within;
  final WordSort sort;
  final ValueChanged<AddedWithin> onWithin;
  final ValueChanged<WordSort> onSort;

  static const _withinLabels = {
    AddedWithin.any: T.addedAny,
    AddedWithin.today: T.addedToday,
    AddedWithin.week: T.addedWeek,
  };
  static const _sortLabels = {
    WordSort.newest: T.sortNewest,
    WordSort.oldest: T.sortOldest,
    WordSort.alphabetical: T.sortAlphabetical,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in _withinLabels.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: within == e.key,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onWithin(e.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
          PopupMenuButton<WordSort>(
            tooltip: _sortLabels[sort],
            icon: const Icon(Icons.sort),
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (_) => [
              for (final e in _sortLabels.entries)
                CheckedPopupMenuItem(value: e.key, checked: sort == e.key, child: Text(e.value)),
            ],
          ),
        ],
      ),
    );
  }
}
