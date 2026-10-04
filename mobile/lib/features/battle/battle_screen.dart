import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/offline_review.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'battle_controller.dart';
import 'battle_result.dart';
import 'fight_scene.dart';
import 'hero.dart';
import 'rules.dart';
import 'sprite_view.dart';

// Text on the dark stage (globals.css `text-paper` at various opacities).
const _paper = Color(0xFFFAF7F0);

/// Monster Hunt (web /decks/review/battle). The session and the fight live in
/// [BattleController]; this only draws them.
class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key, this.deckId, this.free = false});

  final String? deckId;

  /// Free practice: any card, answers logged as drills, nothing rescheduled.
  final bool free;

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
  )..load();

  @override
  void dispose() {
    c.dispose();
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
      return _Message(text: T.notEnoughWordsBattle, onBack: () => context.pop());
    }
    if (c.card == null && c.events.isEmpty) {
      if (c.loadError != null) {
        return _Message(text: T.queueLoadFailed, detail: c.loadError, onBack: () => context.pop());
      }
      return _Message(
        text: T.noWordsDueBattle,
        detail: T.noWordsDueBattleHint,
        onBack: () => context.pop(),
        // Not a dead end: wanting to practise on a quiet day is reasonable.
        action: widget.free
            ? null
            : FilledButton(
                onPressed: () =>
                    context.pushReplacement(Routes.hunt(deckId: widget.deckId, free: true)),
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
        _Arena(c: c, free: widget.free),
        if (c.paused) _PauseOverlay(c: c),
      ],
    );
  }
}

class _Arena extends StatelessWidget {
  const _Arena({required this.c, required this.free});
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
              _BarButton(icon: Icons.arrow_back, label: T.exitBattle, onTap: () => context.pop()),
              _BarButton(icon: Icons.pause, label: T.pauseBattle, onTap: c.togglePause),
              const Spacer(),
              if (c.defeatedMonsters.isNotEmpty)
                _Chip(text: '☠ ${T.killCount(c.defeatedMonsters.length)}'),
              if (s.armorCharges > 0) ...[
                const SizedBox(width: 6),
                const _Chip(text: '🛡 ${T.armorGainedLabel}', tint: Color(0xFF38BDF8)),
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
          if (c.saveError) const _Banner(text: T.saveFailed, color: Color(0xFFF87171)),
          // Stated plainly: free answers don't count toward scheduling.
          if (free) const _Banner(text: T.freePracticeBanner, color: Color(0xFF38BDF8)),
          if (c.fromCache || c.queuedOffline > 0)
            const _Banner(text: T.offlineQueued, color: Color(0xFFFBBF24)),
          const SizedBox(height: 6),
          _HpStrip(playerHp: s.playerHp, monsterHp: s.monsterHp),
          // Fixed height, always present, so nothing below jumps between
          // questions.
          SizedBox(height: 34, child: Center(child: _AnswerLine(c: c))),
          // The fighters take the space that's left; the question card is
          // sized to its content and sits in thumb reach rather than being
          // stretched down to the bottom edge.
          Expanded(child: Center(child: _FighterRow(c: c))),
          const SizedBox(height: 10),
          _QuestionCard(c: c),
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
        crossAxisAlignment: fromRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text('$hp/$playerMaxHp',
              style: TextStyle(
                  color: _paper.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w700)),
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
                  gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFF43F5E)]),
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
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [HankoColors.seal, HankoColors.sealDark],
            ),
          ),
          child: const Text('VS',
              style: TextStyle(color: _paper, fontSize: 11, fontWeight: FontWeight.w800)),
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
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        // The word just answered, with its reading — answering by meaning never
        // shows how it's pronounced, so it's shown after, when it can't help.
        if (a != null)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: a.term),
              if (a.reading != null && a.reading!.isNotEmpty && a.reading != a.term)
                TextSpan(text: '  ${a.reading}', style: const TextStyle(fontWeight: FontWeight.w400)),
            ]),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: a.correct ? const Color(0xFF34D399) : const Color(0xFFF87171),
            ),
          ),
        if (f != null)
          Text(
            _flagText[f]!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: f == BattleFlag.victory ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
            ),
          ),
      ],
    );
  }
}

class _FighterRow extends StatelessWidget {
  const _FighterRow({required this.c});
  final BattleController c;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = min(150.0, box.maxWidth * 0.36);
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
    });
  }
}

/// A shot crossing from thrower to target (ProjectileShot.tsx).
class _Flight extends StatelessWidget {
  const _Flight({super.key, required this.shot, required this.fromX, required this.toX, required this.size});
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
      builder: (context, t, child) =>
          Transform.translate(offset: Offset(sin(t * pi * 6) * 7 * (1 - t), 0), child: child),
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
  const _QuestionCard({required this.c});
  final BattleController c;

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
        child: Text(T.loadingQuiz, style: TextStyle(color: _paper.withValues(alpha: 0.5))),
      );
    }
    final pct = c.remainingMs / questionTimeLimitMs;
    final low = pct <= 1 / 3;
    const ink = Color(0xFF1F2933);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: HankoColors.parchment,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(card.term,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: ink)),
          ),
          const SizedBox(height: 12),
          Row(
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
                width: 26,
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
          ),
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

class _Option extends StatelessWidget {
  const _Option({required this.letter, required this.color, required this.text, required this.onTap});
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
                child: Text(letter,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.25, color: Color(0xFF1F2933)),
                ),
              ),
            ],
          ),
        ),
      ),
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
                Icon(Icons.pause, size: 34, color: _paper.withValues(alpha: 0.7)),
                const SizedBox(height: 10),
                const Text(T.pausedTitle,
                    style: TextStyle(color: _paper, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(T.pausedDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _paper.withValues(alpha: 0.6))),
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
                  style: TextButton.styleFrom(foregroundColor: _paper.withValues(alpha: 0.75)),
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
  const _BarButton({required this.icon, required this.label, required this.onTap});
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
      child: Text(text, style: TextStyle(color: c.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
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
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 12)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.detail, required this.onBack, this.action});
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
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _paper, fontSize: 16, fontWeight: FontWeight.w600)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _paper.withValues(alpha: 0.6), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            ?action,
            TextButton(
              onPressed: onBack,
              style: TextButton.styleFrom(foregroundColor: _paper.withValues(alpha: 0.75)),
              child: const Text(T.back),
            ),
          ],
        ),
      ),
    );
  }
}
