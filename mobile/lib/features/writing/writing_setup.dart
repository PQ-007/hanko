import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../social/social_api.dart';
import 'kanji_progress.dart';
import 'lesson.dart';
import 'writing_rules.dart';

enum _View { words, kanji }

/// Choosing what to practise before a writing lesson: a deck, then either
/// words or the deck's kanji (each taught through the first word that has
/// it). Learned kanji are marked, and "new kanji" picks everything that still
/// has something to teach.
class WritingSetup extends ConsumerStatefulWidget {
  const WritingSetup({super.key, this.deckId, required this.onStart});
  final String? deckId;

  /// Called with the chosen words, in the order lessons should take them.
  final ValueChanged<List<Word>> onStart;

  @override
  ConsumerState<WritingSetup> createState() => _WritingSetupState();
}

class _WritingSetupState extends ConsumerState<WritingSetup> {
  late String? _deckId = widget.deckId;
  _View _view = _View.words;
  Set<String> _learned = {};
  final _words = <String>{}; // selected word ids
  final _kanji = <String>[]; // selected kanji, in tap order

  @override
  void initState() {
    super.initState();
    syncLearnedKanji(ref.read(socialApiProvider)).then((l) {
      if (mounted) setState(() => _learned = l);
    });
  }

  /// The deck's words that have a kanji, newest first (deck order on the web).
  List<Word> _candidates(List<Word> words) {
    final list = words.where((w) => hasKanji(w.term)).toList();
    if (_deckId == null) {
      list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
    return list;
  }

  bool _hasNew(Word w) => kanjiOf(w.term).any((k) => !_learned.contains(k));

  /// New kanji (not learned yet) across [words], each counted once.
  int _newIn(List<Word> words) => {
        for (final w in words)
          for (final k in kanjiOf(w.term))
            if (!_learned.contains(k)) k,
      }.length;

  List<Word> _chosen(List<Word> words) => _view == _View.words
      ? words.where((w) => _words.contains(w.id)).toList()
      : wordsForKanji(_kanji, words, (w) => w.term);

  void _pick(List<Word> words, {required bool onlyNew}) => setState(() {
    if (_view == _View.words) {
      _words
        ..clear()
        ..addAll(words.where((w) => !onlyNew || _hasNew(w)).map((w) => w.id));
    } else {
      _kanji
        ..clear()
        ..addAll(
          kanjiInOrder(
            words.map((w) => w.term),
          ).where((k) => !onlyNew || !_learned.contains(k)),
        );
    }
  });

  void _clear() => setState(() {
    _words.clear();
    _kanji.clear();
  });

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final source = _deckId == null
        ? ref.watch(allWordsProvider)
        : ref.watch(deckWordsProvider(_deckId!));
    final hero = ref.watch(heroProvider);

    return source.when(
      loading: () => const LoadingScene(label: T.loading),
      error: (e, _) => HeroEmptyState(
        hero: hero,
        state: 'hurt',
        title: T.loadFailed,
        subtitle: '$e',
      ),
      data: (all) {
        final words = _candidates(all);
        final chosen = _chosen(words);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: DropdownButtonFormField<String?>(
                initialValue: decks.any((d) => d.id == _deckId)
                    ? _deckId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: T.writingSetupDeck,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text(T.writingAllDecks),
                  ),
                  for (final d in decks)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() {
                  _deckId = v;
                  _clear();
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_View>(
                segments: const [
                  ButtonSegment(
                    value: _View.words,
                    icon: Icon(Icons.list),
                    label: Text(T.writingByWord),
                  ),
                  ButtonSegment(
                    value: _View.kanji,
                    icon: Icon(Icons.grid_view),
                    label: Text(T.writingByKanji),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() {
                  _view = s.single;
                  _clear();
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _pick(words, onlyNew: true),
                    child: const Text(T.writingPickNew),
                  ),
                  TextButton(
                    onPressed: () => _pick(words, onlyNew: false),
                    child: const Text(T.writingPickAll),
                  ),
                  TextButton(
                    onPressed: _clear,
                    child: const Text(T.writingPickNone),
                  ),
                  Text(
                    T.writingLearnedLegend,
                    style: TextStyle(fontSize: 11, color: context.hk.inkMute),
                  ),
                ],
              ),
            ),
            Expanded(
              child: words.isEmpty
                  ? HeroEmptyState(hero: hero, title: T.writingNoKanji)
                  : _view == _View.words
                  ? _WordList(
                      words: words,
                      selected: _words,
                      learned: _learned,
                      onToggle: (id) => setState(
                        () => _words.contains(id)
                            ? _words.remove(id)
                            : _words.add(id),
                      ),
                    )
                  : _KanjiGrid(
                      kanji: kanjiInOrder(words.map((w) => w.term)),
                      selected: _kanji,
                      learned: _learned,
                      onToggle: (k) => setState(
                        () => _kanji.contains(k)
                            ? _kanji.remove(k)
                            : _kanji.add(k),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Lessons teach at most 10 new kanji each (lessonSize).
                    if (_newIn(chosen) > newKanjiPerLesson)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          T.writingSplitHint(_newIn(chosen), newKanjiPerLesson),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: context.hk.inkMute),
                        ),
                      ),
                    if (_view == _View.kanji && _kanji.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          T.writingKanjiSelected(_kanji.length, chosen.length),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.hk.inkMute,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: chosen.isEmpty
                          ? null
                          : () => widget.onStart(chosen),
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(T.writingStartLesson(chosen.length)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WordList extends StatelessWidget {
  const _WordList({
    required this.words,
    required this.selected,
    required this.learned,
    required this.onToggle,
  });
  final List<Word> words;
  final Set<String> selected;
  final Set<String> learned;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      itemCount: words.length,
      itemBuilder: (context, i) {
        final w = words[i];
        final meaning = w.meaningMn?.isNotEmpty == true
            ? w.meaningMn!
            : (w.meaning ?? '');
        return CheckboxListTile(
          value: selected.contains(w.id),
          onChanged: (_) => onToggle(w.id),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text.rich(
            TextSpan(
              children: [
                for (final ch in w.term.runes.map(String.fromCharCode))
                  TextSpan(
                    text: ch,
                    // Learned kanji in green, so a word's remaining work shows.
                    style: TextStyle(
                      color: learned.contains(ch)
                          ? const Color(0xFF16A34A)
                          : null,
                    ),
                  ),
                if (w.reading != null && w.reading != w.term)
                  TextSpan(
                    text: '  ${w.reading}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: context.hk.inkMute,
                    ),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          subtitle: meaning.isEmpty
              ? null
              : Text(meaning, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}

class _KanjiGrid extends StatelessWidget {
  const _KanjiGrid({
    required this.kanji,
    required this.selected,
    required this.learned,
    required this.onToggle,
  });
  final List<String> kanji;
  final List<String> selected;
  final Set<String> learned;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 64,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: kanji.length,
      itemBuilder: (context, i) {
        final k = kanji[i];
        final on = selected.contains(k);
        final done = learned.contains(k);
        return Material(
          color: on ? context.hk.sealTint : context.hk.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: on ? context.hk.seal : context.hk.lineSoft,
              width: on ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onToggle(k),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    k,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (done)
                  const Positioned(
                    right: 4,
                    top: 2,
                    child: Text(
                      '✓',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
