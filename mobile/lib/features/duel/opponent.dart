import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../battle/rules.dart' show Rand, defaultRand;
import 'duel_api.dart';
import 'duel_rules.dart';

/// Cancels a round's wait (the screen closed, the match ended).
class RoundCancel {
  final _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// The seam between the duel and whoever it is fighting (opponent.ts): the
/// round loop must not know whether the other side is a bot or a person on
/// another phone. Every [answerFor] must settle within the round's duration,
/// or the round — and the match — would hang.
abstract class OpponentDriver {
  String get name;
  String get slug;

  /// The opponent's own median answer time, for damage scaling.
  int? get baselineMs;

  Future<DuelAnswer?> answerFor(int roundNo, int durationMs, RoundCancel cancel);

  /// True once the opponent has gone (a real player who stopped answering).
  bool get left => false;

  /// Publishes the local player's answer. A bot has nobody to tell.
  Future<void> submit(int roundNo, DuelAnswer? answer, String? cardId) async {}

  void dispose() {}
}

/// A bot that answers in its own time: the answer is sampled at the top of
/// the round but only revealed when its reaction time elapses (a miss at the
/// buzzer), so it feels like someone thinking rather than a number appearing.
class BotOpponent extends OpponentDriver {
  BotOpponent({required this.name, required this.slug, required this.profile, Rand? rng}) : _rng = rng ?? defaultRand;

  @override
  final String name;
  @override
  final String slug;
  final BotProfile profile;
  final Rand _rng;

  @override
  int? get baselineMs => botBaselineMs(profile);

  @override
  Future<DuelAnswer?> answerFor(int roundNo, int durationMs, RoundCancel cancel) {
    final answer = botAnswer(profile, _rng, durationMs);
    final revealAt = answer?.elapsedMs ?? durationMs;
    final result = Completer<DuelAnswer?>();
    final timer = Timer(Duration(milliseconds: revealAt), () {
      if (!result.isCompleted) result.complete(answer);
    });
    cancel.whenCancelled.then((_) {
      timer.cancel();
      if (!result.isCompleted) result.complete(null);
    });
    return result.future;
  }
}

/// A real person on another phone (remoteOpponent.ts). Realtime is an
/// optimisation, not the mechanism: every round ends with a direct read of
/// the opponent's answer row and is bounded by its own deadline, so a channel
/// that never connects costs latency, not correctness.
class RemoteOpponent extends OpponentDriver {
  RemoteOpponent({
    required this.api,
    required this.matchId,
    required this.opponentId,
    required this.name,
    required this.slug,
    required this.baselineMs,
  });

  final DuelApi api;
  final String matchId;
  final String opponentId;
  @override
  final String name;
  @override
  final String slug;
  @override
  final int? baselineMs;

  RealtimeChannel? _channel;

  /// Rounds in a row with no answer row from the opponent. A timeout still
  /// writes a row (submit sends it as wrong), so a missing one means their
  /// app isn't there: three in a row and they've left (PVP.md 3.4).
  int _missing = 0;
  bool _left = false;
  static const _absentRounds = 3;

  @override
  bool get left => _left;

  @override
  Future<DuelAnswer?> answerFor(int roundNo, int durationMs, RoundCancel cancel) async {
    Map<String, dynamic>? round;
    try {
      round = await api.beginRound(matchId, roundNo);
    } catch (_) {}
    // What's left of the round by the server's clock — a slow loader gets a
    // shorter round rather than a different deadline from its opponent.
    final startsAt = DateTime.tryParse(round?['starts_at'] as String? ?? '');
    final duration = (round?['duration_ms'] as num?)?.toInt() ?? durationMs;
    final remaining = startsAt == null
        ? duration
        : (duration - DateTime.now().difference(startsAt).inMilliseconds).clamp(0, duration);

    final arrived = Completer<void>();
    void done() {
      if (!arrived.isCompleted) arrived.complete();
    }

    final timer = Timer(Duration(milliseconds: remaining), done);
    cancel.whenCancelled.then((_) => done());
    _channel = api.db
        .channel('match:$matchId:round:$roundNo')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'match_answers',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'match_id', value: matchId),
          callback: (payload) {
            final row = payload.newRecord;
            if (row['round_no'] == roundNo && row['user_id'] == opponentId) done();
          },
        )
        .subscribe();

    await arrived.future;
    timer.cancel();
    _dropChannel();
    if (cancel.cancelled) return null;

    // Applies the round's damage server-side; idempotent, and needed even when
    // nobody answered, or a round both let expire would never advance.
    try {
      await api.resolveRound(matchId, roundNo);
    } catch (_) {}
    try {
      final row = await api.answer(matchId, roundNo, opponentId);
      _missing = row == null ? _missing + 1 : 0;
      if (_missing >= _absentRounds && !_left) {
        _left = true;
        // The one still here claims the match (forfeit_match's meaning).
        try {
          await api.forfeit(matchId);
        } catch (_) {}
      }
      return row == null ? null : DuelAnswer(correct: row.correct, elapsedMs: row.effectiveMs);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> submit(int roundNo, DuelAnswer? answer, String? cardId) =>
      api.submitAnswer(matchId, roundNo, answer?.correct ?? false, answer?.elapsedMs, cardId);

  void _dropChannel() {
    final c = _channel;
    _channel = null;
    if (c != null) api.db.removeChannel(c);
  }

  @override
  void dispose() => _dropChannel();
}
