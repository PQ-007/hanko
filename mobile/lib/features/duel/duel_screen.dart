import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../battle/sprite_view.dart';
import 'duel_api.dart';
import 'duel_controller.dart';
import 'duel_rules.dart';
import 'opponent.dart';

const _paper = Color(0xFFFAF7F0);
const _stage = Color(0xFF171D25);

/// A duel, start to finish: the arena, then the result. [makeOpponent] builds
/// a fresh opponent (a rematch is a new one); [matchId] is set for PvP, where
/// leaving counts as a forfeit.
class DuelScreen extends ConsumerStatefulWidget {
  const DuelScreen({super.key, required this.makeOpponent, this.matchId, this.deckId});

  final OpponentDriver Function() makeOpponent;
  final String? matchId;
  final String? deckId;

  @override
  ConsumerState<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends ConsumerState<DuelScreen> {
  DuelController? _c;
  int? _baseline;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _baseline ??= await ref.read(duelApiProvider).responseBaseline();
    if (!mounted) return;
    final old = _c;
    setState(() {
      _starting = false;
      _c = DuelController(
        repo: ref.read(repositoryProvider),
        opponent: widget.makeOpponent(),
        hero: ref.read(heroProvider),
        yourBaselineMs: _baseline,
        deckId: widget.deckId,
      )..load();
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Leaving a live PvP match forfeits it, so it asks first.
  Future<bool> _confirmLeave() async {
    final c = _c;
    if (widget.matchId == null || c == null || c.outcome != DuelOutcome.ongoing) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(T.duelLeaveTitle),
        content: const Text(T.duelLeaveDesc),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text(T.duelStay)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text(T.duelLeave)),
        ],
      ),
    );
    if (ok == true) {
      try {
        // concede, not forfeit: forfeit_match makes its caller the winner.
        await ref.read(duelApiProvider).concede(widget.matchId!);
      } catch (_) {}
    }
    return ok == true;
  }

  Future<void> _leave() async {
    if (await _confirmLeave() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: _stage,
        body: SafeArea(
          child: _starting || c == null
              ? const DefaultTextStyle(style: TextStyle(color: _paper), child: LoadingScene(label: T.duelLoading))
              : ListenableBuilder(listenable: c, builder: (context, _) => _body(c)),
        ),
      ),
    );
  }

  Widget _body(DuelController c) {
    if (c.cards == null) {
      return const DefaultTextStyle(style: TextStyle(color: _paper), child: LoadingScene(label: T.duelLoading));
    }
    if (c.loadError != null && (c.cards?.isEmpty ?? true)) {
      return _Message(text: T.duelLoadFailed, onBack: _leave);
    }
    if (c.notEnoughWords || c.card == null) {
      return _Message(text: T.notEnoughWordsBattle, onBack: _leave);
    }
    if (c.outcome != DuelOutcome.ongoing && c.phase == DuelPhase.resolving) {
      return _Result(
        c: c,
        hero: ref.read(heroProvider),
        onRematch: widget.matchId == null ? _start : null,
        onExit: () => Navigator.of(context).pop(),
      );
    }
    final s = c.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: _leave,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text(T.exitBattle),
                style: TextButton.styleFrom(foregroundColor: _paper.withValues(alpha: 0.7)),
              ),
              const Spacer(),
              Text(T.duelRoundOf(c.roundNo, duelRoundCount),
                  style: TextStyle(color: _paper.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
            ],
          ),
          _Bars(you: s.yourHp, them: s.theirHp, yourStreak: s.yourStreak, theirStreak: s.theirStreak, foe: c.opponent.name),
          SizedBox(height: 30, child: Center(child: _Status(c: c))),
          Expanded(child: Center(child: _Fighters(c: c))),
          const SizedBox(height: 8),
          _Question(c: c),
          SizedBox(height: thumbZoneLift(context) * 0.5),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.you, required this.them, required this.yourStreak, required this.theirStreak, required this.foe});
  final int you, them, yourStreak, theirStreak;
  final String foe;

  Widget _bar(String label, int hp, int streak, bool right) {
    return Expanded(
      child: Column(
        crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text('$label  $hp/$duelMaxHp${streak >= duelStreakTiers.first ? '  🔥${T.duelStreakLabel(streak)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _paper.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: hp / duelMaxHp,
              minHeight: 12,
              backgroundColor: Colors.black.withValues(alpha: 0.4),
              color: right ? const Color(0xFFF43F5E) : const Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _bar(T.duelYou, you, yourStreak, false),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('VS', style: TextStyle(color: _paper, fontWeight: FontWeight.w900)),
        ),
        _bar(foe, them, theirStreak, true),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.c});
  final DuelController c;

  @override
  Widget build(BuildContext context) {
    final r = c.lastRound;
    if (c.phase == DuelPhase.resolving && r != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (r.yourDamage > 0)
            Text('-${r.yourDamage} ⚔', style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w900, fontSize: 18)),
          if (r.yourDamage > 0 && r.theirDamage > 0) const SizedBox(width: 16),
          if (r.theirDamage > 0)
            Text('🛡 -${r.theirDamage}', style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w900, fontSize: 18)),
          if (r.yourDamage == 0 && r.theirDamage == 0)
            Text('—', style: TextStyle(color: _paper.withValues(alpha: 0.5), fontSize: 18)),
        ],
      );
    }
    return Text(
      c.timedOut ? T.duelTimedOut : (c.opponentAnswered ? T.duelOpponentAnswered : T.duelOpponentThinking),
      style: TextStyle(
        color: c.opponentAnswered ? const Color(0xFFFBBF24) : _paper.withValues(alpha: 0.55),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Fighters extends StatelessWidget {
  const _Fighters({required this.c});
  final DuelController c;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      var size = (box.maxWidth * 0.36).clamp(60.0, 150.0);
      if (box.hasBoundedHeight) size = size.clamp(40.0, box.maxHeight - 10);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          SpriteView(
            slug: c.hero,
            state: c.state.yourDefeated && c.phase == DuelPhase.resolving ? 'death' : c.heroPose,
            replayKey: c.heroPoseKey,
            size: size,
            onOneShotEnd: c.heroPoseEnded,
          ),
          SpriteView(
            slug: c.opponent.slug,
            state: c.state.theirDefeated && c.phase == DuelPhase.resolving ? 'death' : c.foePose,
            replayKey: c.foePoseKey,
            size: size,
            flip: true,
            onOneShotEnd: c.foePoseEnded,
          ),
        ],
      );
    });
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.c});
  final DuelController c;

  static const _ink = Color(0xFF1F2933);
  static const _slots = [Color(0xFF10B981), Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFFF59E0B)];

  @override
  Widget build(BuildContext context) {
    final quiz = c.quiz;
    final card = c.card;
    if (quiz == null || card == null) return const SizedBox(height: 260);
    final pct = (c.remainingMs / c.durationMs).clamp(0.0, 1.0);
    final picked = c.yourPick;
    final locked = picked != null || c.timedOut || c.phase == DuelPhase.resolving;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(color: HankoColors.parchment, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(card.term, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: _ink)),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.phase == DuelPhase.question ? pct : 0,
              minHeight: 8,
              backgroundColor: Colors.black.withValues(alpha: 0.08),
              color: pct <= 1 / 3 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 12),
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: 10),
            SizedBox(
              height: 70,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 10),
                    Expanded(
                      child: row * 2 + col < quiz.length
                          ? _Option(
                              color: _slots[row * 2 + col],
                              text: quiz[row * 2 + col].answerText,
                              // Your pick is outlined; the right answer is
                              // shown once the round has resolved.
                              state: c.phase == DuelPhase.resolving && quiz[row * 2 + col].correct
                                  ? _OptionState.right
                                  : identical(picked, quiz[row * 2 + col])
                                      ? _OptionState.picked
                                      : locked
                                          ? _OptionState.dim
                                          : _OptionState.open,
                              onTap: locked ? null : () => c.pick(quiz[row * 2 + col]),
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

enum _OptionState { open, picked, right, dim }

class _Option extends StatelessWidget {
  const _Option({required this.color, required this.text, required this.state, required this.onTap});
  final Color color;
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = switch (state) {
      _OptionState.right => const Color(0xFF16A34A),
      _OptionState.picked => HankoColors.seal,
      _ => Colors.transparent,
    };
    return Opacity(
      opacity: state == _OptionState.dim ? 0.45 : 1,
      child: Material(
        color: Colors.white.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border, width: 3)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.2, color: Color(0xFF1F2933))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.c, required this.hero, required this.onRematch, required this.onExit});
  final DuelController c;
  final String hero;
  final VoidCallback? onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final o = c.outcome;
    final correct = c.rounds.where((r) => r.you?.correct ?? false).length;
    var best = 0, run = 0;
    for (final r in c.rounds) {
      run = (r.you?.correct ?? false) ? run + 1 : 0;
      if (run > best) best = run;
    }
    final dealt = c.rounds.fold<int>(0, (s, r) => s + r.yourDamage);
    final (title, desc, color) = switch (o) {
      DuelOutcome.won => (T.duelWon, c.opponent.left ? T.duelOpponentLeft : T.duelWonDesc, const Color(0xFF34D399)),
      DuelOutcome.lost => (T.duelLost, T.duelLostDesc, const Color(0xFFF87171)),
      _ => (T.duelDraw, T.duelDrawDesc, const Color(0xFFFBBF24)),
    };
    Widget tile(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(value, style: const TextStyle(color: _paper, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, textAlign: TextAlign.center, style: TextStyle(color: _paper.withValues(alpha: 0.55), fontSize: 11)),
            ]),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(desc, textAlign: TextAlign.center, style: TextStyle(color: _paper.withValues(alpha: 0.6))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpriteView(slug: hero, state: o == DuelOutcome.lost ? 'death' : 'idle', size: 120),
              const SizedBox(width: 12),
              SpriteView(slug: c.opponent.slug, state: o == DuelOutcome.won ? 'death' : 'idle', size: 120, flip: true),
            ],
          ),
          const SizedBox(height: 20),
          Row(children: [
            tile(T.duelResultRounds, '${c.state.roundsPlayed}'),
            const SizedBox(width: 8),
            tile(T.duelResultCorrect, '$correct'),
            const SizedBox(width: 8),
            tile(T.duelResultBestStreak, '$best'),
            const SizedBox(width: 8),
            tile(T.duelResultDamage, '$dealt'),
          ]),
          const SizedBox(height: 10),
          Text(T.duelNotScheduled, textAlign: TextAlign.center, style: TextStyle(color: _paper.withValues(alpha: 0.4), fontSize: 11)),
          const SizedBox(height: 20),
          if (onRematch != null) ...[
            FilledButton.icon(
              onPressed: onRematch,
              icon: const Icon(Icons.replay),
              label: const Text(T.duelRematch),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: onExit,
            style: OutlinedButton.styleFrom(
              foregroundColor: _paper,
              side: BorderSide(color: _paper.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(T.stopBattle),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onBack});
  final String text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _paper)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onBack, child: const Text(T.exitBattle)),
        ]),
      ),
    );
  }
}
