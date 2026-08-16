import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_db.dart';
import 'repository.dart';
import '../models/queue_card.dart';

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb();
  ref.onDispose(db.close);
  return db;
});

final offlineReviewProvider = Provider<OfflineReview>(
  (ref) => OfflineReview(ref.watch(repositoryProvider), ref.watch(localDbProvider)),
);

/// Online-first review with an offline fallback.
///
/// The design constraint from the project brief: do NOT port the extension's
/// last-write-wins sync into Dart. Two hand-written sync engines drift apart,
/// and review state is the one thing that must never be reconciled by guessing.
///
/// So this is not a sync engine. It is:
///   - a **cache** of the last queue the server handed us, replaced wholesale,
///     never merged, never used to decide what is due
///   - a **durable outbox** of answers, replayed in order
///
/// Replay is safe only because `review_card()` is idempotent on the device
/// generated log id: a reply lost to a dropped connection can be retried
/// without double-counting the review. That property was built in Phase 0
/// specifically so this layer could exist without inventing conflict rules.
class OfflineReview {
  const OfflineReview(this._repo, this._db);

  final Repository _repo;
  final LocalDb _db;

  /// Fetches from the server and refreshes the cache; falls back to the cached
  /// queue when the network is unavailable.
  Future<({List<QueueCard> cards, bool fromCache})> queue({String? deckId}) async {
    try {
      final cards = await _repo.reviewQueue(deckId: deckId);
      await _db.cacheQueue([
        for (var i = 0; i < cards.length; i++) _toCompanion(cards[i], i),
      ]);
      return (cards: cards, fromCache: false);
    } catch (e) {
      debugPrint('Queue fetch failed, falling back to cache: $e');
      final cached = await _db.cachedQueue();
      if (cached.isEmpty) rethrow; // nothing to show and no reason to hide why
      return (cards: cached.map(_fromCached).toList(), fromCache: true);
    }
  }

  /// Sends an answer, or queues it for replay if the send fails.
  ///
  /// Returns the server's updated card when it went through, and null when it
  /// was queued — the caller uses that to decide whether it can trust the
  /// returned scheduling state.
  Future<Map<String, dynamic>?> answer({
    required String cardId,
    required String rating,
    required String logId,
    int? durationMs,
  }) async {
    try {
      return await _repo.reviewCard(
        cardId: cardId,
        rating: rating,
        logId: logId,
        durationMs: durationMs,
      );
    } catch (e) {
      debugPrint('Answer queued for replay: $e');
      await _db.enqueueAnswer(
        PendingAnswersCompanion.insert(
          logId: logId,
          cardId: cardId,
          rating: rating,
          durationMs: Value(durationMs),
          answeredAt: DateTime.now(),
        ),
      );
      return null;
    }
  }

  Future<int> pendingCount() => _db.pendingCount();

  /// Undo, whichever side the answer currently lives on.
  ///
  /// If it never reached the server it is simply dropped from the outbox —
  /// calling undo_review() for it would fail, since there is no log row to
  /// undo. Returns the restored card when the server handled it, null when the
  /// answer was only ever local.
  Future<Map<String, dynamic>?> undo(String logId) async {
    final pending = await _db.pending();
    if (pending.any((a) => a.logId == logId)) {
      await _db.clearAnswer(logId);
      return null;
    }
    return await _repo.undoReview(logId);
  }

  /// Replays queued answers oldest-first. Stops at the first failure so the
  /// order is preserved and a still-offline device doesn't spin through the
  /// whole backlog. Returns how many were accepted.
  Future<int> flush() async {
    final pending = await _db.pending();
    var sent = 0;
    for (final answer in pending) {
      try {
        await _repo.reviewCard(
          cardId: answer.cardId,
          rating: answer.rating,
          logId: answer.logId,
          durationMs: answer.durationMs,
        );
        await _db.clearAnswer(answer.logId);
        sent++;
      } catch (e) {
        debugPrint('Replay stopped at ${answer.logId}: $e');
        break;
      }
    }
    return sent;
  }

  static CachedCardsCompanion _toCompanion(QueueCard c, int position) =>
      CachedCardsCompanion.insert(
        cardId: c.cardId,
        wordId: c.wordId,
        deckId: c.deckId,
        template: c.template,
        state: c.state,
        learningStep: c.learningStep,
        dueAt: c.dueAt,
        intervalDays: c.intervalDays,
        repetitions: c.repetitions,
        easeFactor: c.easeFactor,
        term: c.term,
        reading: Value(c.reading),
        meaning: Value(c.meaning),
        meaningMn: Value(c.meaningMn),
        audioPath: Value(c.audioPath),
        position: position,
      );

  static QueueCard _fromCached(CachedCard c) => QueueCard(
        cardId: c.cardId,
        wordId: c.wordId,
        deckId: c.deckId,
        template: c.template,
        state: c.state,
        learningStep: c.learningStep,
        dueAt: c.dueAt,
        intervalDays: c.intervalDays,
        repetitions: c.repetitions,
        easeFactor: c.easeFactor,
        term: c.term,
        reading: c.reading,
        meaning: c.meaning,
        meaningMn: c.meaningMn,
        audioPath: c.audioPath,
      );
}
