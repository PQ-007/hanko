import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import '../../app_router.dart';
import '../../core/offline_review.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../writing/kanji_checker.dart';
import '../writing/kanji_strokes.dart';
import '../writing/lesson.dart';
import '../writing/writing_pad.dart';
import 'battle_controller.dart';
import 'battle_result.dart';
import 'fight_scene.dart';
import 'hero.dart';
import 'question_kinds.dart';
import 'rules.dart';
import 'sprite_view.dart';

// Text on the dark stage (globals.css `text-paper` at various opacities).
const _paper = Color(0xFFFAF7F0);

/// Monster Hunt (web /decks/review/battle). The session and the fight live in
/// [BattleController]; this only draws them.
class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key, this.deckId, this.free = false, this.kinds});

  final String? deckId;

  /// Free practice: any card, answers logged as drills, nothing rescheduled.
  final bool free;

  /// Pins the question kinds (tests and screenshots); null asks all.
  @visibleForTesting
  final Set<QuestionKind>? kinds;

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  late final BattleController c = BattleController(
    offline: ref.read(offlineReviewProvider),
    repo: ref.read(repositoryProvider),
    hero: ref.read(heroProvider),
    deckId: widget.deckId,
    free: widget.free,
    kinds: widget.kinds,
  )..load();

  /// Handwriting checks for writing questions; made on first use.
  KanjiChecker? _checker;
  bool _prefetched = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_prefetchStrokes);
  }

  /// Fetches stroke data for every kanji in the queue as soon as it's
  /// loaded, so a writing question can grade strokes (and draw its
  /// correction) without waiting on the network mid-fight.
  void _prefetchStrokes() {
    final queue = c.queue;
    if (_prefetched || queue == null || !c.canWrite) return;
    _prefetched = true;
    ref.read(kanjiStrokesProvider).prefetch({
      for (final card in queue) ...kanjiOf(card.term),
    });
  }

  @override
  void dispose() {
    c.removeListener(_prefetchStrokes);
    c.dispose();
    _checker?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171D25),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (c.queue == null || c.words == null) {
      return const DefaultTextStyle(
        style: TextStyle(color: _paper),
        child: LoadingScene(label: T.loadingWords),
      );
    }
    if (c.notEnoughWords) {
      return _Message(
        text: T.notEnoughWordsBattle,
        onBack: () => context.pop(),
      );
    }
    if (c.card == null && c.events.isEmpty) {
      if (c.loadError != null) {
        return _Message(
          text: T.queueLoadFailed,
          detail: c.loadError,
          onBack: () => context.pop(),
        );
      }
      return _Message(
        text: T.noWordsDueBattle,
        detail: T.noWordsDueBattleHint,
        onBack: () => context.pop(),
        // Not a dead end: wanting to practise on a quiet day is reasonable.
        action: widget.free
            ? null
            : FilledButton(
                onPressed: () => context.pushReplacement(
                  Routes.hunt(deckId: widget.deckId, free: true),
                ),
                child: const Text(T.freePracticeCta),
              ),
      );
    }
    if (c.outcome != BattleOutcome.ongoing) {
      return BattleResultView(
        outcome: c.outcome,
        reviewedCount: c.reviewedCount,
        defeatedMonsters: c.defeatedMonsters,
        events: c.events,
        monster: c.monster,
        hero: c.hero,
        monsterDown: c.state.monsterDefeated,
        onRetry: c.outcome == BattleOutcome.defeat ? c.retry : null,
        onStop: () => context.pop(),
      );
    }
    return Stack(
      children: [
        _Arena(
          c: c,
          free: widget.free,
          checker: () => _checker ??= KanjiChecker(),
        ),
        if (c.paused) _PauseOverlay(c: c),
      ],
    );
  }
}

class _Arena extends StatelessWidget {
  const _Arena({required this.c, required this.free, required this.checker});
  final KanjiChecker Function() checker;
  final BattleController c;
  final bool free;

  @override
  Widget build(BuildContext context) {
    final s = c.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          // Leave / pause on the left; kills, armour and undo on the right.
          Row(
            children: [
              _BarButton(
                icon: Icons.arrow_back,
                label: T.exitBattle,
                onTap: () => context.pop(),
              ),
              _BarButton(
                icon: Icons.pause,
                label: T.pauseBattle,
                onTap: c.togglePause,
              ),
              const Spacer(),
              if (c.defeatedMonsters.isNotEmpty)
                _Chip(text: '☠ ${T.killCount(c.defeatedMonsters.length)}'),
              if (s.armorCharges > 0) ...[
                const SizedBox(width: 6),
                const _Chip(
                  text: '🛡 ${T.armorGainedLabel}',
                  tint: Color(0xFF38BDF8),
                ),
              ],
              IconButton(
                tooltip: T.undoTitle,
                onPressed: c.canUndo ? c.undo : null,
                icon: const Icon(Icons.undo),
                color: _paper.withValues(alpha: 0.7),
                disabledColor: _paper.withValues(alpha: 0.25),
              ),
            ],
          ),
          if (c.saveError)
            const _Banner(text: T.saveFailed, color: Color(0xFFF87171)),
          // Stated plainly: free answers don't count toward scheduling.
          if (free)
            const _Banner(text: T.freePracticeBanner, color: Color(0xFF38BDF8)),
          if (c.fromCache || c.queuedOffline > 0)
            const _Banner(text: T.offlineQueued, color: Color(0xFFFBBF24)),
          const SizedBox(height: 6),
          _HpStrip(playerHp: s.playerHp, monsterHp: s.monsterHp),
          // Fixed height, always present, so nothing below jumps between
          // questions.
          SizedBox(
            height: 68,
            child: Center(child: _AnswerLine(c: c)),
          ),
          // Choice questions: the fighters take the space that's left and the
          // card sits in thumb reach. Writing needs the room more than the
          // fight does, so the fighters shrink to a strip and the card — the
          // pad — takes the rest.
          if (c.kind == QuestionKind.write && c.card != null) ...[
            SizedBox(
              height: 96,
              child: Center(child: _FighterRow(c: c)),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _QuestionCard(c: c, checker: checker),
            ),
          ] else ...[
            Expanded(
              child: Center(child: _FighterRow(c: c)),
            ),
            const SizedBox(height: 10),
            _QuestionCard(c: c, checker: checker),
          ],
          SizedBox(height: thumbZoneLift(context) * 0.5),
        ],
      ),
    );
  }
}

class _HpStrip extends StatelessWidget {
  const _HpStrip({required this.playerHp, required this.monsterHp});
  final int playerHp;
  final int monsterHp;

  @override
  Widget build(BuildContext context) {
    Widget bar(int hp, {required bool fromRight}) {
      final pct = (hp / playerMaxHp).clamp(0.0, 1.0);
      return Column(
        crossAxisAlignment: fromRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            '$hp/$playerMaxHp',
            style: TextStyle(
              color: _paper.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            // The player's bar drains from the left toward the VS badge,
            // mirroring the monster's.
            alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 300),
              widthFactor: pct,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDC2626), Color(0xFFF43F5E)],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: bar(playerHp, fromRight: true)),
        Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [context.hk.seal, context.hk.sealDark],
            ),
          ),
          child: const Text(
            'VS',
            style: TextStyle(
              color: _paper,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(child: bar(monsterHp, fromRight: false)),
      ],
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.c});
  final BattleController c;

  static const _flagText = {
    BattleFlag.victory: T.victoryFlag,
    BattleFlag.crit: T.critLabel,
    BattleFlag.evaded: T.evadedLabel,
    BattleFlag.armor: T.armorBlockedLabel,
    BattleFlag.timeout: T.timeUpLabel,
  };

  @override
  Widget build(BuildContext context) {
    final a = c.lastAnswer;
    final f = c.flag;
    final flag = f == null
        ? null
        : _FlagChip(
            text: _flagText[f]!,
            color: f == BattleFlag.victory
                ? const Color(0xFF34D399)
                : const Color(0xFFFBBF24),
          );
    if (a == null) return flag ?? const SizedBox.shrink();

    // The word just answered: term, reading and meaning, big enough to read
    // at a glance. Answering by meaning never shows how a word is pronounced,
    // and after a miss this is where the right answer is spelled out — shown
    // after, when it can't help.
    final tone = a.correct ? const Color(0xFF34D399) : const Color(0xFFF87171);
    final reading = a.reading != null && a.reading!.isNotEmpty && a.reading != a.term
        ? a.reading
        : null;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 16, 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            child: Icon(
              a.correct ? Icons.check_rounded : Icons.close_rounded,
              size: 20,
              color: const Color(0xFF1A1D22),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      a.term,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: _paper,
                      ),
                    ),
                    if (reading != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          reading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFBAE6FD),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (a.meaning.isNotEmpty)
                  Text(
                    a.meaning,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _paper.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return TweenAnimationBuilder<double>(
      // Re-keyed per answer so the pop-in replays even for the same word.
      key: ObjectKey(a),
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: ((v - 0.9) * 10).clamp(0.0, 1.0),
        child: Transform.scale(scale: v, child: child),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: card),
          if (flag != null) ...[const SizedBox(width: 8), flag],
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

class _FighterRow extends StatelessWidget {
  const _FighterRow({required this.c});
  final BattleController c;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        var size = min(150.0, box.maxWidth * 0.36);
        // In the writing strip the height is what's short.
        if (box.hasBoundedHeight) size = min(size, box.maxHeight - 20);
        final heroX = box.maxWidth * 0.27;
        final monsterX = box.maxWidth * 0.73;
        return SizedBox(
          height: size + 20,
          child: _Shake(
            shakeId: c.shakeId,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: heroX - size / 2,
                  bottom: 0,
                  child: SpriteView(
                    slug: c.hero,
                    state: c.playerDisplayPose,
                    replayKey: c.playerPoseKey,
                    size: size,
                    onOneShotEnd: c.playerPoseEnded,
                  ),
                ),
                Positioned(
                  left: monsterX - size / 2,
                  bottom: 0,
                  child: _Spawn(
                    key: ValueKey(c.monster),
                    child: SpriteView(
                      slug: c.monster,
                      state: c.monsterDisplayPose,
                      replayKey: c.monsterPoseKey,
                      size: size,
                      flip: true,
                      onOneShotEnd: c.monsterPoseEnded,
                    ),
                  ),
                ),
                if (c.shot case final shot?)
                  _Flight(
                    key: ValueKey(shot.id),
                    shot: shot,
                    fromX: shot.towardRight ? heroX : monsterX,
                    toX: shot.towardRight ? monsterX : heroX,
                    size: size,
                  ),
                if (c.popup case final p?)
                  _Popup(
                    key: ValueKey(p.id),
                    popup: p,
                    x: p.onMonster ? monsterX : heroX,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A shot crossing from thrower to target (ProjectileShot.tsx).
class _Flight extends StatelessWidget {
  const _Flight({
    super.key,
    required this.shot,
    required this.fromX,
    required this.toX,
    required this.size,
  });
  final Shot shot;
  final double fromX;
  final double toX;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: projectileFlightMs),
      builder: (context, t, child) => Positioned(
        left: fromX + (toX - fromX) * t - size / 2,
        bottom: 0,
        child: IgnorePointer(child: child!),
      ),
      child: ProjectileView(
        slug: shot.slug,
        pose: shot.pose,
        frames: shot.frames,
        fighterSize: size,
        flip: !shot.towardRight,
      ),
    );
  }
}

/// Floating damage number: rises and fades from above the target.
class _Popup extends StatelessWidget {
  const _Popup({super.key, required this.popup, required this.x});
  final DamagePopup popup;
  final double x;

  @override
  Widget build(BuildContext context) {
    final color = !popup.onMonster
        ? const Color(0xFFEF4444)
        : popup.crit
        ? const Color(0xFFFBBF24)
        : const Color(0xFF34D399);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOut,
      builder: (context, t, _) => Positioned(
        left: x - 40,
        top: 4 - 46 * t,
        width: 80,
        child: IgnorePointer(
          child: Opacity(
            opacity: 1 - t,
            child: Transform.scale(
              scale: 1 + 0.25 * t,
              child: Text(
                '-${popup.amount}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: popup.crit ? 30 : 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen shake on damage taken (globals.css `hanko-shake`): short and small.
class _Shake extends StatelessWidget {
  const _Shake({required this.shakeId, required this.child});
  final int shakeId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (shakeId == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(shakeId),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(sin(t * pi * 6) * 7 * (1 - t), 0),
        child: child,
      ),
      child: child,
    );
  }
}

/// A fresh monster pops into the arena instead of silently swapping in.
class _Spawn extends StatelessWidget {
  const _Spawn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -12 * (1 - t)),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        ),
      ),
      child: child,
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.c, required this.checker});
  final BattleController c;
  final KanjiChecker Function() checker;

  // Fixed colour per grid position, never per correctness (QuizOptions.tsx).
  static const _slots = [
    ('A', Color(0xFF10B981)),
    ('B', Color(0xFFEF4444)),
    ('C', Color(0xFF3B82F6)),
    ('D', Color(0xFFF59E0B)),
  ];

  @override
  Widget build(BuildContext context) {
    final quiz = c.quiz;
    final card = c.card;
    if (quiz == null || card == null) {
      return Center(
        child: Text(
          T.loadingQuiz,
          style: TextStyle(color: _paper.withValues(alpha: 0.5)),
        ),
      );
    }
    final timer = _Countdown(c: c);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: HankoColors.parchment,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: c.kind == QuestionKind.write
          // The card is parchment in both themes, so the pad and its
          // buttons take the light theme, whatever the app's mode.
          ? Theme(
              data: buildHankoTheme(Brightness.light),
              child: _WriteQuestion(
                key: ValueKey('${c.questionKey}:${c.writeSlot}'),
                c: c,
                checker: checker,
                timer: timer,
              ),
            )
          : Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    card.term,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2933),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                timer,
                const SizedBox(height: 14),
                // Every option the same fixed size, so the card never resizes
                // between questions (a meaning can be a ten-line synonym list).
                for (var row = 0; row < (quiz.length + 1) ~/ 2; row++) ...[
                  if (row > 0) const SizedBox(height: 10),
                  SizedBox(
                    height: 78,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (col > 0) const SizedBox(width: 10),
                          Expanded(
                            child: row * 2 + col < quiz.length
                                ? _Option(
                                    letter: _slots[(row * 2 + col) % 4].$1,
                                    color: _slots[(row * 2 + col) % 4].$2,
                                    text: quiz[row * 2 + col].answerText,
                                    onTap: () => c.pick(quiz[row * 2 + col]),
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The question's time left: a bar, and the seconds.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.c});
  final BattleController c;

  @override
  Widget build(BuildContext context) {
    final pct = c.remainingMs / c.timeLimitMs;
    final low = pct <= 1 / 3;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 9,
              backgroundColor: Colors.black.withValues(alpha: 0.08),
              color: low ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '${(c.remainingMs / 1000).ceil()}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: low ? const Color(0xFFDC2626) : const Color(0xFF666053),
            ),
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.letter,
    required this.color,
    required this.text,
    required this.onTap,
  });
  final String letter;
  final Color color;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  letter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _FitText(text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// An answer's text at the largest size (14 down to 9) where every word fits
/// whole on a line and the lot fits in the tile — a long Mongolian word is
/// shrunk rather than broken across two lines mid-word.
class _FitText extends StatelessWidget {
  const _FitText(this.text);
  final String text;

  static const _ink = Color(0xFF1F2933);

  /// Sizes already worked out, by text and box. The arena rebuilds on every
  /// clock tick (10 a second); re-measuring four answers at up to six sizes
  /// each time is visible jank on a slow phone with Dart on the main thread.
  static final _sizes = <String, double>{};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final key =
            '${box.maxWidth.round()}x${box.maxHeight.round()}x${MediaQuery.textScalerOf(context).scale(1)}|$text';
        final cached = _sizes[key];
        if (cached != null) {
          return Text(
            text,
            overflow: TextOverflow.ellipsis,
            maxLines: 4,
            style: TextStyle(fontSize: cached, height: 1.25, color: _ink),
          );
        }
        final scaler = MediaQuery.textScalerOf(context);
        final dir = Directionality.of(context);
        TextStyle styleAt(double size) =>
            TextStyle(fontSize: size, height: 1.25, color: _ink);
        bool fits(double size) {
          final style = styleAt(size);
          for (final word in text.split(RegExp(r'\s+'))) {
            final w = TextPainter(
              text: TextSpan(text: word, style: style),
              textDirection: dir,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (w.width > box.maxWidth) return false;
          }
          final all = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: dir,
            textScaler: scaler,
          )..layout(maxWidth: box.maxWidth);
          return all.height <= box.maxHeight;
        }

        var size = 14.0;
        while (size > 9 && !fits(size)) {
          size -= 1;
        }
        if (_sizes.length > 500) _sizes.clear();
        _sizes[key] = size;
        return Text(
          text,
          overflow: TextOverflow.ellipsis,
          maxLines: 4,
          style: styleAt(size),
        );
      },
    );
  }
}

/// A writing question: the word's reading and meaning, the word a box per
/// character, and a pad for the kanji being written — the largest thing on
/// screen. After a miss the correction is drawn on the pad itself (the right
/// kanji in red over the learner's strokes, the wrong stroke marked, what went
/// wrong above it) and the fight waits until the learner has seen it.
class _WriteQuestion extends ConsumerStatefulWidget {
  const _WriteQuestion({
    super.key,
    required this.c,
    required this.checker,
    required this.timer,
  });
  final BattleController c;
  final KanjiChecker Function() checker;
  final Widget timer;

  @override
  ConsumerState<_WriteQuestion> createState() => _WriteQuestionState();
}

class _WriteQuestionState extends ConsumerState<_WriteQuestion> {
  static const _ink = Color(0xFF1F2933);
  static const _muted = Color(0xFF666053);

  final _strokesDrawn = <List<mlkit.StrokePoint>>[];
  KanjiStrokes? _strokes;
  bool _checking = false;
  KanjiCheck? _miss;
  Size _area = Size.zero;

  BattleController get c => widget.c;

  List<String> get _chars =>
      c.card!.term.runes.map(String.fromCharCode).toList();
  List<int> get _positions => kanjiPositions(c.card!.term);
  int get _current => _positions[min(c.writeSlot, _positions.length - 1)];
  String get _target => _chars[_current];

  @override
  void initState() {
    super.initState();
    ref.read(kanjiStrokesProvider).load(_target).then((s) {
      if (mounted) setState(() => _strokes = s);
    });
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _check() async {
    if (_strokesDrawn.isEmpty || _checking || _miss != null) return;
    // The clock keeps running during the check. If it expires meanwhile the
    // question resolves and the next one appears — this result must not then
    // land on that next question.
    final question = '${c.questionKey}:${c.writeSlot}';
    setState(() => _checking = true);
    final result = await widget.checker().check(
      target: _target,
      ink: _strokesDrawn,
      area: _area,
      strokes: _strokes,
      preContext: _chars.take(_current).join(),
    );
    if (!mounted) return;
    setState(() => _checking = false);
    if ('${c.questionKey}:${c.writeSlot}' != question) return;
    if (result.ok) {
      c.writeResult(true);
      return;
    }
    // Hold the fight on the correction; the miss lands on "continue".
    setState(() => _miss = result);
    c.holdForCorrection();
  }

  @override
  Widget build(BuildContext context) {
    final card = c.card!;
    final meaning = answerTextOf(card.meaningMn, card.meaning);
    final miss = _miss;
    final strokes = _strokes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Prompt: reading big, meaning under it.
        Row(
          children: [
            Icon(Icons.draw_outlined, size: 18, color: context.hk.sealText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                card.reading ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
            // The word, a box per character: kana given, kanji filled in as
            // they're written (and revealed on a miss), the current one outlined.
            for (var i = 0; i < _chars.length; i++)
              Container(
                width: 34,
                height: 38,
                margin: const EdgeInsets.only(left: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: i == _current
                      ? context.hk.seal.withValues(alpha: 0.12)
                      : null,
                  border: Border.all(
                    color: i == _current
                        ? (miss != null ? writingRed : context.hk.seal)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Text(
                  !_positions.contains(i) ||
                          _positions.indexOf(i) < c.writeSlot ||
                          (i == _current && miss != null)
                      ? _chars[i]
                      : '?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: i == _current && miss != null ? writingRed : _ink,
                  ),
                ),
              ),
          ],
        ),
        if (meaning.isNotEmpty)
          Text(
            meaning,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        const SizedBox(height: 8),
        widget.timer,
        const SizedBox(height: 6),
        // What went wrong, right above the pad it's drawn on.
        SizedBox(
          height: 20,
          child: miss == null
              ? null
              : Text(
                  missMessage(miss),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: writingRed,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, box) {
                  _area = box.biggest;
                  return WritingPad(
                    strokes: strokes,
                    // The correction: every stroke of the right kanji, in red,
                    // numbered, under what was drawn.
                    guideCount: miss != null ? (strokes?.count ?? 0) : 0,
                    answer: miss != null,
                    demo: false,
                    ink: _strokesDrawn,
                    borderColor: miss != null ? writingRed : null,
                    badInk: miss?.grade?.stroke,
                    focusStroke: miss?.grade?.stroke,
                    onStart: (p) {
                      if (miss != null) return;
                      setState(
                        () => _strokesDrawn.add([
                          mlkit.StrokePoint(x: p.dx, y: p.dy, t: _now),
                        ]),
                      );
                    },
                    onUpdate: (p) {
                      if (miss != null || _strokesDrawn.isEmpty) return;
                      setState(
                        () => _strokesDrawn.last.add(
                          mlkit.StrokePoint(x: p.dx, y: p.dy, t: _now),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (miss != null)
          FilledButton(
            onPressed: () => c.writeResult(false),
            style: FilledButton.styleFrom(
              backgroundColor: writingRed,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(T.writingContinue),
          )
        else
          Row(
            children: [
              IconButton.outlined(
                tooltip: T.writingUndo,
                onPressed: _strokesDrawn.isEmpty
                    ? null
                    : () => setState(_strokesDrawn.removeLast),
                icon: const Icon(Icons.undo),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: T.writingClear,
                onPressed: _strokesDrawn.isEmpty
                    ? null
                    : () => setState(_strokesDrawn.clear),
                icon: const Icon(Icons.delete_outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _strokesDrawn.isEmpty || _checking ? null : _check,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _checking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(T.writingCheck),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Covers the whole stage: a paused question must not be readable, or the
/// pause becomes free thinking time.
class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.c});
  final BattleController c;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF171D25).withValues(alpha: 0.94),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pause,
                  size: 34,
                  color: _paper.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 10),
                const Text(
                  T.pausedTitle,
                  style: TextStyle(
                    color: _paper,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  T.pausedDesc,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _paper.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: c.togglePause,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(T.resumeBattle),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text(T.exitBattle),
                  style: TextButton.styleFrom(
                    foregroundColor: _paper.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: _paper.withValues(alpha: 0.65),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.tint});
  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? _paper;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 12),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.detail,
    required this.onBack,
    this.action,
  });
  final String text;
  final String? detail;
  final VoidCallback onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _paper,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _paper.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            ?action,
            TextButton(
              onPressed: onBack,
              style: TextButton.styleFrom(
                foregroundColor: _paper.withValues(alpha: 0.75),
              ),
              child: const Text(T.back),
            ),
          ],
        ),
      ),
    );
  }
}
