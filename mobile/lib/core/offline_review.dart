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

/// Decks downloaded for offline review, by id. Invalidate after a download
/// or removal.
final offlineDecksProvider = FutureProvider<Map<String, OfflineDeck>>((ref) async {
  final list = await ref.watch(localDbProvider).offlineDeckList();
  return {for (final d in list) d.deckId: d};
});

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
  OfflineReview(this._repo, this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Repository _repo;
  final LocalDb _db;
  final DateTime Function() _now;

  /// Every card of a deck in one call — practice_cards has no cap of its own.
  static const _wholeDeck = 5000;

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
      // A deck downloaded for offline review beats the last-fetched queue:
      // it holds the whole deck, not just whatever was asked for last time.
      if (deckId != null && await _db.offlineDeck(deckId) != null) {
        return (cards: await offlineQueue(deckId), fromCache: true);
      }
      final cached = await _db.cachedQueue();
      if (cached.isEmpty) rethrow; // nothing to show and no reason to hide why
      return (cards: cached.map(_fromCached).toList(), fromCache: true);
    }
  }

  /// Downloads [deckId] for offline review: every card (practice_cards), which
  /// of them review_queue() serves right now, and the word list Monster Hunt
  /// builds its options from. Returns how many cards were saved. Throws when
  /// offline — there's nothing to download from.
  Future<int> download(String deckId, String deckName) async {
    final all = await _repo.practiceCards(deckId: deckId, limit: _wholeDeck);
    final queued = {for (final c in await _repo.reviewQueue(deckId: deckId, limit: 500)) c.cardId};
    await _db.saveOfflineDeck(
      OfflineDecksCompanion.insert(deckId: deckId, name: deckName, downloadedAt: _now(), cardCount: all.length),
      [for (final c in all) _toOffline(c, queued.contains(c.cardId))],
    );
    try {
      await quizWords(); // refreshes the offline word list for the hunt
    } catch (_) {}
    return all.length;
  }

  Future<void> removeDownload(String deckId) => _db.removeOfflineDeck(deckId);

  /// A downloaded deck's review queue, decided only from what the server last
  /// said: cards already in review/learning whose server-set due date has
  /// come, plus the new cards review_queue() itself was serving at download
  /// (so the daily new-card cap holds). Answers waiting in the outbox are left
  /// out — they're done until the server has scheduled them.
  Future<List<QueueCard>> offlineQueue(String deckId) async {
    final now = _now();
    final answered = {for (final p in await _db.pending()) p.cardId};
    final cards = (await _db.offlineDeckCardList(deckId))
        .where((c) => !answered.contains(c.cardId))
        .where((c) => c.inQueue || (c.state != 'new' && !c.dueAt.isAfter(now)))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return cards.map(_fromOffline).toList();
  }

  /// Sends an answer, or queues it for replay if the send fails.
  ///
  /// Returns the server's updated card when it went through, and null when it
  /// was queued — the caller uses that to decide whether it can trust the
  /// returned scheduling state.
  ///
  /// [source] is sent as-is and kept through the outbox: 'review' for classic
  /// review, 'quiz' for Monster Hunt (schedules, but labelled), 'drill' for
  /// free practice (logged, never schedules).
  Future<Map<String, dynamic>?> answer({
    required String cardId,
    required String rating,
    required String logId,
    int? durationMs,
    String source = 'review',
  }) async {
    try {
      return await _repo.reviewCard(
        cardId: cardId,
        rating: rating,
        logId: logId,
        durationMs: durationMs,
        source: source,
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
          source: Value(source),
        ),
      );
      return null;
    }
  }

  /// Every word's quiz fields for Monster Hunt's options, refreshing the local
  /// copy; falls back to that copy offline. Rethrows only when there's neither.
  Future<List<QuizWordRow>> quizWords() async {
    try {
      final words = await _repo.quizWords();
      await _db.cacheQuizWords([
        for (final w in words)
          CachedQuizWordsCompanion.insert(
            id: w.id,
            term: w.term,
            reading: Value(w.reading),
            meaning: Value(w.meaning),
            meaningMn: Value(w.meaningMn),
          ),
      ]);
      return words;
    } catch (e) {
      final cached = await _db.cachedQuizWordList();
      if (cached.isEmpty) rethrow;
      return [
        for (final c in cached)
          (id: c.id, term: c.term, reading: c.reading, meaning: c.meaning, meaningMn: c.meaningMn),
      ];
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
          source: answer.source,
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

  static OfflineDeckCardsCompanion _toOffline(QueueCard c, bool inQueue) => OfflineDeckCardsCompanion.insert(
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
        inQueue: Value(inQueue),
      );

  static QueueCard _fromOffline(OfflineDeckCard c) => QueueCard(
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
