import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repository.dart';
import '../../core/confirm_dialog.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../battle/sprite_view.dart';
import 'duel_api.dart';
import 'duel_controller.dart';
import 'duel_rules.dart';
import 'duel_shared.dart';
import 'opponent.dart';
import 'remote_launch.dart';

const _paper = Color(0xFFFAF7F0);
const _stage = Color(0xFF171D25);

/// Everything that exists only when the opponent is a person (0030).
class DuelOnline {
  const DuelOnline({
    required this.matchId,
    required this.meId,
    required this.opponentId,
    required this.foeName,
    this.foeSub,
    required this.record,
    this.questions,
  });
  final String matchId, meId, opponentId, foeName;
  final String? foeSub;

  /// Your record with them BEFORE this match.
  final HeadToHead record;

  /// The question set both players answer; null on matches from before 0030.
  final List<SharedQuestion>? questions;
}

/// How long the pre-fight screen holds (web: DuelIntro INTRO_MS).
const duelIntroMs = 4500;

/// A duel, start to finish: the arena, then the result. [makeOpponent] builds
/// a fresh opponent (a rematch is a new one); [matchId] is set for PvP, where
/// leaving counts as a forfeit, and [online] adds the intro, the shared
/// questions, the record and the rematch.
class DuelScreen extends ConsumerStatefulWidget {
  const DuelScreen({super.key, required this.makeOpponent, this.matchId, this.deckId, this.online});

  final OpponentDriver Function() makeOpponent;
  final String? matchId;
  final String? deckId;
  final DuelOnline? online;

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
        questions: widget.online?.questions,
        introDelay: widget.online == null ? Duration.zero : const Duration(milliseconds: duelIntroMs),
        cardForTerm: widget.online == null ? null : ref.read(duelApiProvider).cardIdForTerm,
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
    final ok = await askConfirm(
      context,
      title: T.duelLeaveTitle,
      body: T.duelLeaveDesc,
      confirmLabel: T.duelLeave,
      cancelLabel: T.duelStay,
      danger: true,
      icon: Icons.flag_outlined,
    );
    if (ok) {
      try {
        // concede, not forfeit: forfeit_match makes its caller the winner.
        await ref.read(duelApiProvider).concede(widget.matchId!);
      } catch (_) {}
    }
    return ok;
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
    final online = widget.online;
    if (online != null && !c.introDone) {
      return _Intro(hero: ref.read(heroProvider), foeSlug: c.opponent.slug, online: online);
    }
    if (c.cards == null) {
      return const DefaultTextStyle(style: TextStyle(color: _paper), child: LoadingScene(label: T.duelLoading));
    }
    if (c.loadError != null && (c.cards?.isEmpty ?? true)) {
      return _Message(text: T.duelLoadFailed, onBack: _leave);
    }
    if (!c.shared && (c.notEnoughWords || c.card == null)) {
      return _Message(text: T.notEnoughWordsBattle, onBack: _leave);
    }
    if (c.outcome != DuelOutcome.ongoing && c.phase == DuelPhase.resolving) {
      return _Result(
        c: c,
        hero: ref.read(heroProvider),
        onRematch: widget.matchId == null ? _start : null,
        onExit: () => Navigator.of(context).pop(),
        online: online == null
            ? null
            : _OnlineEnd(
                online: online,
                hero: ref.read(heroProvider),
                onExit: () => Navigator.of(context).pop(),
                onStarted: (m) => openRemoteDuel(context, ref, m, replace: true),
              ),
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
    final term = c.term;
    if (quiz == null || term == null) return const SizedBox(height: 260);
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
            child: Text(term, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: _ink)),
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
      _OptionState.picked => context.hk.seal,
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
  const _Result({required this.c, required this.hero, required this.onRematch, required this.onExit, this.online});
  final DuelController c;
  final String hero;
  final VoidCallback? onRematch;
  final VoidCallback onExit;

  /// The record and the rematch, for a match against a person.
  final Widget? online;

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
          if (online != null) online!
          else ...[
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

// ---- Person vs person: intro, record, rematch (0030) -------------------------

/// The screen before a PvP match: who's across, and your record so far.
class _Intro extends StatefulWidget {
  const _Intro({required this.hero, required this.foeSlug, required this.online});
  final String hero, foeSlug;
  final DuelOnline online;

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> {
  late final DateTime _start = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = ((duelIntroMs - DateTime.now().difference(_start).inMilliseconds) / 1000).ceil();
    final o = widget.online;
    Widget name(String text, [String? sub]) => Column(
          children: [
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _paper, fontWeight: FontWeight.w800, fontSize: 15)),
            if (sub != null)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _paper.withValues(alpha: 0.45), fontSize: 11)),
          ],
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(T.duelIntroKicker.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(color: _paper.withValues(alpha: 0.4), fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Two rows of a three-column table, so the names line up whatever
          // the opponent's extra "@handle · ELO" line does.
          Table(
            columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth(), 2: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                Center(child: SpriteView(slug: widget.hero, size: 120)),
                Text('VS', style: TextStyle(color: _paper.withValues(alpha: 0.3), fontSize: 24, fontWeight: FontWeight.w900)),
                Center(child: SpriteView(slug: widget.foeSlug, size: 120, flip: true)),
              ]),
              TableRow(children: [
                Align(alignment: Alignment.topCenter, child: name(T.duelYou)),
                const SizedBox(),
                Align(alignment: Alignment.topCenter, child: name(o.foeName, o.foeSub)),
              ]),
            ],
          ),
          const SizedBox(height: 20),
          DuelRecordCard(record: o.record, youName: T.duelYou, themName: o.foeName),
          const SizedBox(height: 18),
          Text(left > 0 ? T.duelIntroStarting(left) : T.duelIntroGo,
              textAlign: TextAlign.center,
              style: TextStyle(color: _paper.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Your face-to-face record: the score, a bar split by results, and the last
/// five fights as chips. Same card as the web's H2HRecord.
class DuelRecordCard extends StatelessWidget {
  const DuelRecordCard({super.key, required this.record, required this.youName, required this.themName, this.compact = false});
  final HeadToHead record;
  final String youName, themName;
  final bool compact;

  static const _win = Color(0xFF34D399), _loss = Color(0xFFF87171), _draw = Color(0xFFFCD34D);

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    );
    final kicker = TextStyle(color: _paper.withValues(alpha: 0.4), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700);
    if (record.total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: box,
        child: Column(children: [
          Text(T.duelRecTitle.toUpperCase(), style: kicker),
          const SizedBox(height: 6),
          const Text(T.duelRecFirst, style: TextStyle(color: _paper, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text(T.duelRecFirstDesc, textAlign: TextAlign.center, style: TextStyle(color: _paper.withValues(alpha: 0.5), fontSize: 12)),
        ]),
      );
    }
    final big = compact ? 36.0 : 46.0;
    Widget score(String who, int n, Color color, CrossAxisAlignment a) => Expanded(
          child: Column(crossAxisAlignment: a, children: [
            Text(who, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _paper.withValues(alpha: 0.55), fontSize: 12)),
            Text('$n', style: TextStyle(color: color, fontSize: big, fontWeight: FontWeight.w900, height: 1.05)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: box,
      child: Column(children: [
        Text('${T.duelRecTitle} · ${T.duelRecGames(record.total)}'.toUpperCase(), textAlign: TextAlign.center, style: kicker),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          score(youName, record.wins, _win, CrossAxisAlignment.end),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(':', style: TextStyle(color: _paper.withValues(alpha: 0.3), fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          score(themName, record.losses, _loss, CrossAxisAlignment.start),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              if (record.wins > 0) Expanded(flex: record.wins, child: const ColoredBox(color: _win)),
              if (record.draws > 0) Expanded(flex: record.draws, child: const ColoredBox(color: _draw)),
              if (record.losses > 0) Expanded(flex: record.losses, child: const ColoredBox(color: _loss)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(T.duelRecSummary(record.wins, record.losses, record.draws),
            style: TextStyle(color: _paper.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final m in record.last(5))
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (m.result) { MatchResult.win => _win, MatchResult.loss => _loss, MatchResult.draw => _draw }
                      .withValues(alpha: 0.2),
                  border: Border.all(
                      color: switch (m.result) { MatchResult.win => _win, MatchResult.loss => _loss, MatchResult.draw => _draw }
                          .withValues(alpha: 0.5)),
                ),
                child: Text(
                  switch (m.result) { MatchResult.win => '✓', MatchResult.loss => '✕', MatchResult.draw => '=' },
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: switch (m.result) { MatchResult.win => _win, MatchResult.loss => _loss, MatchResult.draw => _draw },
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

/// The ending of a match against a person: the record (this match included
/// once it's written) and the "again" button. duel_rematch() is symmetric —
/// whoever presses first asks, whoever presses second starts it — so this
/// only reflects the server's state: nobody asked, I'm waiting, or they asked.
class _OnlineEnd extends ConsumerStatefulWidget {
  const _OnlineEnd({required this.online, required this.hero, required this.onExit, required this.onStarted});
  final DuelOnline online;
  final String hero;
  final VoidCallback onExit;
  final void Function(MatchRow m) onStarted;

  @override
  ConsumerState<_OnlineEnd> createState() => _OnlineEndState();
}

class _OnlineEndState extends ConsumerState<_OnlineEnd> {
  late HeadToHead _record = widget.online.record;
  MatchRow? _rematch;
  bool _sending = false, _failed = false, _started = false;
  Timer? _poll;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    _loadRecord();
    _refresh();
    _poll = Timer.periodic(const Duration(milliseconds: 2500), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// The last round's resolve_round is what finishes the match, so the new
  /// result can lag a moment: retry until it's counted.
  Future<void> _loadRecord() async {
    final o = widget.online;
    final r = await ref.read(duelApiProvider).record(o.meId, o.opponentId);
    if (!mounted) return;
    if (r.total > o.record.total || _tries >= 6) {
      setState(() => _record = r);
    } else {
      _tries++;
      Timer(const Duration(milliseconds: 1200), _loadRecord);
    }
  }

  void _apply(MatchRow? m) {
    if (!mounted) return;
    setState(() => _rematch = m);
    if (m != null && m.status == 'active' && !_started) {
      _started = true;
      _poll?.cancel();
      widget.onStarted(m);
    }
  }

  Future<void> _refresh() async {
    try {
      _apply(await ref.read(duelApiProvider).rematchOf(widget.online.matchId));
    } catch (_) {}
  }

  Future<void> _request() async {
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      _apply(await ref.read(duelApiProvider).rematch(widget.online.matchId, widget.hero));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _cancel() async {
    final m = _rematch;
    if (m == null) return;
    final api = ref.read(duelApiProvider);
    try {
      if (m.hostId == widget.online.meId) {
        await api.concede(m.id);
      } else {
        await api.declineInvite(m.id);
      }
    } catch (_) {}
    if (mounted) setState(() => _rematch = null);
  }

  @override
  Widget build(BuildContext context) {
    final m = _rematch;
    final waiting = m != null && m.status == 'lobby' && m.hostId == widget.online.meId;
    final incoming = m != null && m.status == 'lobby' && m.hostId != widget.online.meId;
    final name = widget.online.foeName;
    final ghost = OutlinedButton.styleFrom(
      foregroundColor: _paper,
      side: BorderSide(color: _paper.withValues(alpha: 0.2)),
      padding: const EdgeInsets.symmetric(vertical: 14),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DuelRecordCard(record: _record, youName: T.duelYou, themName: name, compact: true),
        const SizedBox(height: 16),
        if (incoming) ...[
          Text(T.duelRematchIncoming(name),
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFCD34D), fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
        ],
        if (_failed) ...[
          const Text(T.duelRematchFailed, textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12)),
          const SizedBox(height: 8),
        ],
        if (waiting) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _paper)),
              const SizedBox(width: 10),
              Flexible(child: Text(T.duelRematchWaiting(name), style: const TextStyle(color: _paper, fontWeight: FontWeight.w700))),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _cancel, style: ghost, child: const Text(T.duelRematchCancel)),
        ] else ...[
          FilledButton.icon(
            onPressed: _sending ? null : _request,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.replay),
            label: Text(incoming ? T.duelInviteAccept : T.duelRematch),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (incoming) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _cancel, style: ghost, child: const Text(T.duelInviteDecline)),
          ],
        ],
        const SizedBox(height: 8),
        OutlinedButton(onPressed: widget.onExit, style: ghost, child: const Text(T.stopBattle)),
      ],
    );
  }
}
