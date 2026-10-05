import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/repository.dart';
import '../../models/queue_card.dart';
import '../battle/rules.dart';
import '../battle/sprites.dart' show attackPose, maxAttackTier;
import 'duel_rules.dart';
import 'opponent.dart';

const _uuid = Uuid();

/// After a round: whoever hit swings, then the flinch, then the next round.
const _flinchBeatMs = 600;
const resolveHoldMs = 1500;
const _tickMs = 100;

enum DuelPhase { question, resolving }

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

/// The duel's round loop — DuelArena.tsx's, against an [OpponentDriver] that
/// is either a bot or a real player (PVP.md).
///
/// Cards come from `practice_cards()` (not the capped review queue, which is
/// empty on exactly the day you've finished your reviews and want to play),
/// fetched once. Each answer is logged with `source: 'battle'`, which
/// `review_card()` never schedules on — enforced in Postgres, not here.
/// Damage is decided once per round and folded purely ([deriveDuelState]);
/// in PvP the server decides the opponent's half and this only renders it.
class DuelController extends ChangeNotifier {
  DuelController({
    required this.repo,
    required this.opponent,
    required this.hero,
    required this.yourBaselineMs,
    this.deckId,
    this.rand = defaultRand,
    int Function() now = _wallClockMs,
    // ignore: prefer_initializing_formals
  }) : _now = now;

  final Repository repo;
  final OpponentDriver opponent;
  final String hero;
  final String? deckId;
  final Rand rand;
  final int? yourBaselineMs;
  final int Function() _now;

  List<QueueCard>? cards;
  List<QuizWord>? words;
  String? loadError;

  final rounds = <ResolvedRound>[];
  int roundNo = 1;
  DuelPhase phase = DuelPhase.question;
  List<QuizOption>? quiz;

  /// Your pick this round: null before picking; [timedOut] when the clock won.
  QuizOption? yourPick;
  bool timedOut = false;
  bool opponentAnswered = false;
  ResolvedRound? lastRound;

  String heroPose = 'idle';
  String foePose = 'idle';
  int heroPoseKey = 0, foePoseKey = 0;

  int remainingMs = roundDurationMs(1);
  int _startedAt = 0;
  bool _answered = false;
  Completer<DuelAnswer?>? _yours;
  RoundCancel? _cancel;
  Timer? _tick, _flinch, _next;
  bool _disposed = false;

  DuelState get state => deriveDuelState(rounds);
  DuelOutcome get outcome => duelOutcome(state);
  int get durationMs => roundDurationMs(roundNo);
  QueueCard? get card => (cards?.isNotEmpty ?? false) ? cards![(roundNo - 1) % cards!.length] : null;
  bool get notEnoughWords => words != null && words!.length < minWordsForBattle;
  bool get ready => quiz != null;

  Future<void> load() async {
    try {
      final rows = await repo.quizWords();
      words = [
        for (final w in rows)
          QuizWord(id: w.id, term: w.term, reading: w.reading, meaning: w.meaning, meaningMn: w.meaningMn),
      ];
      cards = await repo.practiceCards(deckId: deckId, limit: 60);
    } catch (e) {
      loadError = '$e';
      words ??= const [];
      cards ??= const [];
    }
    if (_disposed) return;
    if (!notEnoughWords && card != null) _startRound();
    _notify();
  }

  void _startRound() {
    final c = card;
    if (c == null || words == null) return;
    _answered = false;
    yourPick = null;
    timedOut = false;
    opponentAnswered = false;
    phase = DuelPhase.question;
    quiz = buildQuiz(
      wordId: c.wordId,
      term: c.term,
      reading: c.reading,
      meaning: c.meaning,
      meaningMn: c.meaningMn,
      allWords: words!,
      rand: rand,
    );
    _startedAt = _now();
    remainingMs = durationMs;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _onTick());

    final yours = _yours = Completer<DuelAnswer?>();
    final cancel = _cancel = RoundCancel();
    final round = roundNo;
    final theirs = opponent.answerFor(round, durationMs, cancel).then((a) {
      if (!cancel.cancelled) {
        opponentAnswered = true;
        _notify();
      }
      return a;
    });
    Future.wait([yours.future, theirs]).then((both) {
      if (cancel.cancelled || _disposed || round != roundNo) return;
      _closeRound(both[0], both[1]);
    });
  }

  int get _elapsed => _now() - _startedAt;

  void _onTick() {
    remainingMs = max(0, durationMs - _elapsed);
    if (remainingMs <= 0 && !_answered && phase == DuelPhase.question) {
      // The clock beat you: a timeout is submitted too, so the other side can
      // stop waiting at the buzzer.
      _answered = true;
      timedOut = true;
      _yours?.complete(null);
      final c = card;
      unawaited(opponent.submit(roundNo, null, c?.cardId).catchError((_) {}));
    }
    _notify();
  }

  void pick(QuizOption option) {
    if (_answered || phase != DuelPhase.question || outcome != DuelOutcome.ongoing) return;
    _answered = true;
    yourPick = option;
    final answer = DuelAnswer(correct: option.correct, elapsedMs: _elapsed);
    _yours?.complete(answer);
    final played = card;
    if (played != null) {
      // Logged, never scheduled — 'battle' is review_card()'s log-only branch.
      // Not awaited: a slow insert must not stall a real-time round.
      unawaited(repo
          .reviewCard(
            cardId: played.cardId,
            rating: option.correct ? 'good' : 'again',
            logId: _uuid.v4(),
            durationMs: answer.elapsedMs,
            source: 'battle',
          )
          .then((_) {}, onError: (_) {}));
      unawaited(opponent.submit(roundNo, answer, played.cardId).catchError((_) {}));
    }
    HapticFeedback.selectionClick();
    _notify();
  }

  void _closeRound(DuelAnswer? you, DuelAnswer? them) {
    _tick?.cancel();
    final before = state;
    final resolved = resolveRound(roundNo, you, them, yourBaselineMs, opponent.baselineMs, before);
    rounds.add(resolved);
    lastRound = resolved;
    phase = DuelPhase.resolving;

    // Beat one: whoever landed a hit swings.
    if (resolved.yourDamage > 0) {
      heroPose = attackPose(hero, min(maxAttackTier, duelStreakTier(before.yourStreak)));
      heroPoseKey++;
      duelStreakTier(before.yourStreak) > 0 ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    } else if (resolved.theirDamage > 0) {
      HapticFeedback.heavyImpact();
    }
    if (resolved.theirDamage > 0) {
      foePose = attackPose(opponent.slug, 0);
      foePoseKey++;
    }
    // Beat two: the flinch.
    _flinch = Timer(const Duration(milliseconds: _flinchBeatMs), () {
      if (resolved.yourDamage > 0) {
        foePose = 'hurt';
        foePoseKey++;
      }
      if (resolved.theirDamage > 0) {
        heroPose = 'hurt';
        heroPoseKey++;
      }
      _notify();
    });
    // ...then the next round, unless the match is over.
    if (outcome == DuelOutcome.ongoing) {
      _next = Timer(const Duration(milliseconds: resolveHoldMs), () {
        roundNo++;
        heroPose = 'idle';
        foePose = 'idle';
        heroPoseKey++;
        foePoseKey++;
        _startRound();
        _notify();
      });
    } else {
      if (outcome == DuelOutcome.won) {
        HapticFeedback.heavyImpact();
        Timer(const Duration(milliseconds: 120), HapticFeedback.heavyImpact);
      }
      opponent.dispose();
    }
    _notify();
  }

  void heroPoseEnded() {
    if (heroPose == 'idle') return;
    heroPose = 'idle';
    _notify();
  }

  void foePoseEnded() {
    if (foePose == 'idle') return;
    foePose = 'idle';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    for (final t in [_tick, _flinch, _next]) {
      t?.cancel();
    }
    opponent.dispose();
    super.dispose();
  }
}
