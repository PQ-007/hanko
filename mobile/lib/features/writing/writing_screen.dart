import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;
import 'package:uuid/uuid.dart';

import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/library.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../battle/sprite_view.dart';
import 'kanji_checker.dart';
import 'kanji_progress.dart';
import 'kanji_strokes.dart';
import 'lesson.dart';
import 'stroke_grader.dart';
import 'writing_pad.dart';
import 'writing_rules.dart';
import 'writing_setup.dart';

/// Kanji writing lessons, one kanji per box.
///
/// Each new kanji climbs a ladder of help — trace it over its outline after
/// watching the stroke order, write it with half the strokes shown, write it
/// from memory — and then the whole word is asked for, a kanji at a time with
/// its kana given. Kanji passed from memory are remembered on the phone and
/// skip straight to their words in later lessons.
///
/// Opens on [WritingSetup] to pick a deck and words or kanji; lessons then
/// work through that selection in order.
///
/// Practice only: answers logged against each word's card with
/// `source: 'drill'`, nothing rescheduled. Recognition is ML Kit's on-device
/// handwriting model (downloaded once); stroke order is KanjiVG, fetched per
/// kanji and cached.
class WritingScreen extends ConsumerStatefulWidget {
  const WritingScreen({super.key, this.deckId});
  final String? deckId;

  @override
  ConsumerState<WritingScreen> createState() => _WritingScreenState();
}

enum _Phase { writing, correct, wrong }


class _WritingScreenState extends ConsumerState<WritingScreen> {
  static const _uuid = Uuid();

  final _checker = KanjiChecker();

  String? _status;
  String? _error;

  /// Every practisable word; lessons take [wordsPerLesson] at a time.
  List<Word> _pool = const [];
  Map<String, String> _cardIds = const {};

  /// The setup screen is showing (what to practise isn't chosen yet).
  bool _picking = true;
  int _offset = 0;

  List<Word> _words = const [];
  List<LessonStep> _steps = const [];
  int _stepIndex = 0;
  final _strokeData = <String, KanjiStrokes?>{};
  Set<String> _learned = {};

  // Current step.
  _Phase _phase = _Phase.writing;
  final _ink = <List<mlkit.StrokePoint>>[];
  List<String> _guesses = const [];
  StrokeGrade? _grade;
  bool _checking = false;
  bool _showAnswer = false;
  int _slot = 0; // word step: which kanji of the word is being written
  int _demoKey = 0; // bumps to replay the stroke-order demo

  // Lesson results.
  final _missedWords = <int>{};
  int _newKanji = 0;
  int _checks = 0;
  int _firstTry = 0;
  bool _missedThisStep = false;
  Size _padSize = Size.zero;

  LessonStep? get _step =>
      _stepIndex < _steps.length ? _steps[_stepIndex] : null;
  bool get _done => _steps.isNotEmpty && _step == null;

  @override
  void dispose() {
    _checker.close();
    super.dispose();
  }

  // ---- Setup -----------------------------------------------------------------

  /// Starts lessons over [words], in order, [wordsPerLesson] at a time.
  Future<void> _begin(List<Word> words) async {
    setState(() {
      _picking = false;
      _status = T.loading;
      _error = null;
    });
    try {
      if (!await handwritingReady()) {
        if (mounted) setState(() => _status = T.writingModelDownloading);
        if (!await handwritingReady(download: true)) {
          throw const _Failure(T.writingModelFailed);
        }
      }
      _learned = await loadLearnedKanji();
      try {
        _cardIds = await ref.read(repositoryProvider).recognitionCardIds([
          for (final w in words) w.id,
        ]);
      } catch (_) {
        // Offline: the lesson still runs; its drill rows just aren't logged.
        _cardIds = const {};
      }
      _pool = words;
      _offset = 0;
      await _startLesson();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = e is _Failure ? e.message : '$e';
        });
      }
    }
  }

  Future<void> _startLesson() async {
    final words = _pool.skip(_offset).take(wordsPerLesson).toList();
    _offset += words.length;
    if (mounted) setState(() => _status = T.writingPreparing);
    final kanji = {for (final w in words) ...kanjiOf(w.term)};
    final store = ref.read(kanjiStrokesProvider);
    await store.prefetch(kanji);
    for (final k in kanji) {
      _strokeData[k] = await store.load(k);
    }
    if (!mounted) return;
    setState(() {
      _status = null;
      _words = words;
      _steps = planLesson([for (final w in words) w.term], learned: _learned);
      _stepIndex = 0;
      _missedWords.clear();
      _newKanji = 0;
      _checks = 0;
      _firstTry = 0;
      _resetStep();
    });
  }

  void _resetStep() {
    _phase = _Phase.writing;
    _ink.clear();
    _guesses = const [];
    _grade = null;
    _showAnswer = false;
    _missedThisStep = false;
    _slot = 0;
    _demoKey++;
  }

  // ---- Targets ---------------------------------------------------------------

  Word get _word => _words[_step!.wordIndex];

  /// The kanji being written right now.
  String get _target {
    final step = _step!;
    if (step.kind != StepKind.word) return step.char!;
    final chars = _word.term.runes.map(String.fromCharCode).toList();
    return chars[kanjiPositions(_word.term)[_slot]];
  }

  KanjiStrokes? get _strokes => _strokeData[_target];

  /// How many of the target's strokes are drawn as a guide on the pad.
  int get _guideCount {
    final s = _strokes;
    if (s == null) return 0;
    if (_showAnswer) return s.count;
    return switch (_step!.kind) {
      StepKind.trace => s.count,
      StepKind.partial => partialStrokes(s.count),
      _ => 0,
    };
  }

  // ---- Pad -----------------------------------------------------------------

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _strokeStart(Offset p) {
    if (_phase == _Phase.correct) return;
    setState(() {
      // Writing again after a miss starts on a clean pad (the answer stays
      // shown as a guide for this try).
      if (_phase == _Phase.wrong) {
        _phase = _Phase.writing;
        _ink.clear();
      }
      _ink.add([mlkit.StrokePoint(x: p.dx, y: p.dy, t: _now)]);
    });
  }

  void _strokeUpdate(Offset p) {
    if (_ink.isEmpty || _phase != _Phase.writing) return;
    setState(() => _ink.last.add(mlkit.StrokePoint(x: p.dx, y: p.dy, t: _now)));
  }

  // ---- Answers ---------------------------------------------------------------

  Future<void> _check() async {
    if (_ink.isEmpty || _checking || _step == null) return;
    setState(() => _checking = true);
    final step = _step!;
    final target = _target;
    final chars = _word.term.runes.map(String.fromCharCode).toList();
    final before = step.kind == StepKind.word
        ? chars.take(kanjiPositions(_word.term)[_slot]).join()
        : '';
    final result = await _checker.check(
      target: target,
      ink: _ink,
      area: _padSize,
      strokes: _strokes,
      preContext: before,
    );
    if (!mounted) return;
    final ok = result.ok;
    final guesses = result.guesses;
    final grade = result.grade;
    _checks++;
    setState(() {
      _checking = false;
      _grade = grade;
      _guesses = guesses.take(shownGuesses).toList();
      if (ok) {
        if (!_missedThisStep) _firstTry++;
        _phase = _Phase.correct;
      } else {
        _phase = _Phase.wrong;
        _missedThisStep = true;
        _showAnswer = true;
        _missedWords.add(step.wordIndex);
      }
    });
    ok ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    if (ok && step.kind == StepKind.blank && !_learned.contains(target)) {
      _learned.add(target);
      _newKanji++;
      await saveLearnedKanji(_learned);
    }
  }

  /// Moves on: to the word's next kanji, or the next step.
  void _continue() {
    final step = _step;
    if (step == null) return;
    if (step.kind == StepKind.word &&
        _slot + 1 < kanjiPositions(_word.term).length) {
      setState(() {
        _slot++;
        _phase = _Phase.writing;
        _ink.clear();
        _guesses = const [];
        _grade = null;
        _showAnswer = false;
        _missedThisStep = false;
        _demoKey++;
      });
      return;
    }
    final lastOfWord =
        _stepIndex + 1 >= _steps.length ||
        _steps[_stepIndex + 1].wordIndex != step.wordIndex;
    if (lastOfWord) _logWord(step.wordIndex);
    setState(() {
      _stepIndex++;
      _resetStep();
    });
  }

  void _retry() => setState(() {
    _phase = _Phase.writing;
    _ink.clear();
  });

  /// Fire-and-forget, like the speed round: a lost drill row costs nothing
  /// scheduling depends on.
  void _logWord(int wordIndex) {
    final cardId = _cardIds[_words[wordIndex].id];
    if (cardId == null) return;
    unawaited(
      ref
          .read(repositoryProvider)
          .reviewCard(
            cardId: cardId,
            rating: _missedWords.contains(wordIndex) ? 'again' : 'good',
            logId: _uuid.v4(),
            source: 'drill',
          )
          .then((_) {}, onError: (_) {}),
    );
  }

  // ---- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hero = ref.watch(heroProvider);
    final step = _step;
    return Scaffold(
      appBar: AppBar(
        title: _picking || step == null || _status != null
            ? const Text(T.writingTitle)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _stepIndex / _steps.length,
                  minHeight: 12,
                  backgroundColor: context.hk.lineSoft,
                  color: writingGreen,
                ),
              ),
      ),
      body: _picking
          ? WritingSetup(deckId: widget.deckId, onStart: _begin)
          : _status != null
          ? LoadingScene(label: _status)
          : _error != null
          ? HeroEmptyState(
              hero: hero,
              state: 'hurt',
              title: T.loadFailed,
              subtitle: _error,
              action: FilledButton(
                onPressed: () => setState(() => _picking = true),
                child: const Text(T.writingBackToPick),
              ),
            )
          : _steps.isEmpty
          ? HeroEmptyState(hero: hero, title: T.writingNoKanji)
          : _done
          ? _Finished(
              hero: hero,
              words: _words.length,
              newKanji: _newKanji,
              firstTry: _firstTry,
              checks: _checks,
              onNext: _offset < _pool.length ? _startLesson : null,
              onPick: () => setState(() => _picking = true),
              onClose: () => Navigator.of(context).pop(),
            )
          : _lesson(step!),
    );
  }

  Widget _lesson(LessonStep step) {
    final strokes = _strokes;
    final term = _word.term;
    final positions = kanjiPositions(term);
    final highlight = step.kind == StepKind.word
        ? positions[_slot]
        : term.runes.map(String.fromCharCode).toList().indexOf(step.char!);
    final meaning = [
      _word.meaningMn,
      _word.meaning,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _instruction(step),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _WordRow(
              term: term,
              highlight: highlight,
              // Kanji not yet written stay hidden, except while tracing (the
              // outline shows it anyway), ones already written in this word,
              // and the answer after a miss.
              revealed: {
                for (var i = 0; i < term.runes.length; i++)
                  if (!positions.contains(i) ||
                      (step.kind == StepKind.trace && i == highlight) ||
                      (step.kind == StepKind.word &&
                          positions.indexOf(i) < _slot) ||
                      (i == highlight &&
                          (_phase == _Phase.correct || _showAnswer)))
                    i,
              },
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (_word.reading != null) _word.reading!,
                if (meaning.isNotEmpty) meaning,
              ].join('  ·  '),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.hk.inkMute),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      _padSize = box.biggest;
                      return WritingPad(
                        key: ValueKey(_demoKey),
                        strokes: strokes,
                        guideCount: _guideCount,
                        answer: _showAnswer,
                        demo:
                            step.kind == StepKind.trace &&
                            !_showAnswer &&
                            strokes != null,
                        ink: _ink,
                        borderColor: switch (_phase) {
                          _Phase.correct => writingGreen,
                          _Phase.wrong => writingRed,
                          _Phase.writing => null,
                        },
                        // On a miss: the drawn stroke that went wrong, and the
                        // stroke it should have been.
                        badInk: _phase == _Phase.wrong ? _grade?.stroke : null,
                        focusStroke: _phase == _Phase.wrong
                            ? _grade?.stroke
                            : null,
                        onStart: _strokeStart,
                        onUpdate: _strokeUpdate,
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _bottom(step, strokes),
            SizedBox(height: thumbZoneLift(context) * 0.4),
          ],
        ),
      ),
    );
  }

  String _missMessage() => missMessage(KanjiCheck(ok: false, guesses: _guesses, grade: _grade));

  String _instruction(LessonStep step) => switch (step.kind) {
    StepKind.trace => T.writingStepTrace,
    StepKind.partial => T.writingStepPartial,
    StepKind.blank => T.writingStepBlank,
    StepKind.word => T.writingStepWord,
  };

  Widget _bottom(LessonStep step, KanjiStrokes? strokes) {
    const pad = EdgeInsets.symmetric(vertical: 14);
    switch (_phase) {
      case _Phase.correct:
        return _Banner(
          color: writingGreen,
          title: T.writingCorrect,
          button: FilledButton(
            onPressed: _continue,
            style: FilledButton.styleFrom(
              backgroundColor: writingGreen,
              padding: pad,
            ),
            child: const Text(T.writingContinue),
          ),
        );
      case _Phase.wrong:
        return _Banner(
          color: writingRed,
          title: T.writingWrong,
          subtitle: _missMessage(),
          button: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _continue,
                  style: OutlinedButton.styleFrom(padding: pad),
                  child: const Text(T.writingSkip),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _retry,
                  style: FilledButton.styleFrom(
                    backgroundColor: writingRed,
                    padding: pad,
                  ),
                  child: const Text(T.writingRetry),
                ),
              ),
            ],
          ),
        );
      case _Phase.writing:
        return Row(
          children: [
            IconButton.outlined(
              tooltip: T.writingUndo,
              onPressed: _ink.isEmpty ? null : () => setState(_ink.removeLast),
              icon: const Icon(Icons.undo),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: T.writingClear,
              onPressed: _ink.isEmpty ? null : () => setState(_ink.clear),
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 6),
            if (strokes != null && step.kind == StepKind.trace)
              IconButton.outlined(
                tooltip: T.writingReplay,
                onPressed: () => setState(() => _demoKey++),
                icon: const Icon(Icons.replay),
              )
            else
              IconButton.outlined(
                tooltip: T.writingReveal,
                onPressed: _showAnswer || strokes == null
                    ? null
                    : () => setState(() => _showAnswer = true),
                icon: const Icon(Icons.lightbulb_outline),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _ink.isEmpty || _checking ? null : _check,
                style: FilledButton.styleFrom(padding: pad),
                child: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(T.writingCheck),
              ),
            ),
          ],
        );
    }
  }
}

class _Failure implements Exception {
  const _Failure(this.message);
  final String message;
}

/// The word, a box per character: kana shown, kanji hidden until written, the
/// one being written outlined.
class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.term,
    required this.highlight,
    required this.revealed,
  });
  final String term;
  final int highlight;
  final Set<int> revealed;

  @override
  Widget build(BuildContext context) {
    final chars = term.runes.map(String.fromCharCode).toList();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i++)
            Container(
              width: 48,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: i == highlight ? context.hk.sealTint : null,
                border: Border.all(
                  color: i == highlight ? HankoColors.seal : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                revealed.contains(i) ? chars[i] : '?',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: revealed.contains(i)
                      ? context.hk.ink
                      : context.hk.inkMute.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.title,
    this.subtitle,
    required this.button,
  });
  final Color color;
  final String title;
  final String? subtitle;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color),
            ),
          const SizedBox(height: 8),
          button,
        ],
      ),
    );
  }
}

/// The end of a lesson: the hero celebrating, and what was done.
class _Finished extends StatelessWidget {
  const _Finished({
    required this.hero,
    required this.words,
    required this.newKanji,
    required this.firstTry,
    required this.checks,
    required this.onNext,
    required this.onPick,
    required this.onClose,
  });

  final String hero;
  final int words, newKanji, firstTry, checks;
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accuracy = checks == 0 ? 100 : (firstTry * 100 / checks).round();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SpriteView(slug: hero, state: 'attack01', size: 150),
            ),
            const SizedBox(height: 8),
            const Text(
              T.writingLessonDone,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _Stat(value: '$words', label: T.writingStatWords),
                const SizedBox(width: 8),
                _Stat(value: '$newKanji', label: T.writingStatNewKanji),
                const SizedBox(width: 8),
                _Stat(value: '$accuracy%', label: T.writingStatAccuracy),
              ],
            ),
            const SizedBox(height: 24),
            if (onNext != null) ...[
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(T.writingNextLesson),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: onPick,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(T.writingBackToPick),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(T.writingFinish),
            ),
            const SizedBox(height: 16),
            Text(
              T.kanjiVgCredit,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.hk.inkMute),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.hk.inkMute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
