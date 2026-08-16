import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/local_db.dart';
import 'package:drift/drift.dart';

/// Exercises the durable outbox against a real in-memory SQLite database — the
/// same engine that runs on the device, so schema and column mapping are
/// genuinely covered rather than mocked away.
void main() {
  late LocalDb db;

  setUp(() => db = LocalDb.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  PendingAnswersCompanion answer(String logId, {DateTime? at}) =>
      PendingAnswersCompanion.insert(
        logId: logId,
        cardId: 'card-$logId',
        rating: 'good',
        durationMs: const Value(1200),
        answeredAt: at ?? DateTime(2026, 8, 17, 12),
      );

  test('an answer survives being written and read back', () async {
    await db.enqueueAnswer(answer('a'));
    final pending = await db.pending();
    expect(pending, hasLength(1));
    expect(pending.single.cardId, 'card-a');
    expect(pending.single.durationMs, 1200);
  });

  test('replay order is oldest first, so learning steps stay in sequence',
      () async {
    await db.enqueueAnswer(answer('late', at: DateTime(2026, 8, 17, 12, 5)));
    await db.enqueueAnswer(answer('early', at: DateTime(2026, 8, 17, 12, 1)));
    final pending = await db.pending();
    expect(pending.map((a) => a.logId), ['early', 'late']);
  });

  test('re-enqueuing the same log id replaces rather than duplicates', () async {
    // The log id is the idempotency key; two rows for one answer would mean
    // sending it twice and double-counting the review.
    await db.enqueueAnswer(answer('dup'));
    await db.enqueueAnswer(answer('dup'));
    expect(await db.pendingCount(), 1);
  });

  test('clearing one answer leaves the rest queued', () async {
    await db.enqueueAnswer(answer('a'));
    await db.enqueueAnswer(answer('b'));
    await db.clearAnswer('a');
    final pending = await db.pending();
    expect(pending.map((a) => a.logId), ['b']);
  });

  test('the cached queue is replaced wholesale, never merged', () async {
    CachedCardsCompanion card(String id, int pos) => CachedCardsCompanion.insert(
          cardId: id,
          wordId: 'w-$id',
          deckId: 'd',
          template: 'recognition',
          state: 'new',
          learningStep: 0,
          dueAt: DateTime(2026, 8, 17),
          intervalDays: 0,
          repetitions: 0,
          easeFactor: 2.5,
          term: 'x',
          position: pos,
        );

    await db.cacheQueue([card('1', 0), card('2', 1)]);
    expect(await db.cachedQueue(), hasLength(2));

    // A stale card must not linger: the server is the only authority on what
    // is due, so yesterday's queue can't survive into today's.
    await db.cacheQueue([card('3', 0)]);
    final cached = await db.cachedQueue();
    expect(cached.map((c) => c.cardId), ['3']);
  });

  test('cached queue preserves server order', () async {
    CachedCardsCompanion card(String id, int pos) => CachedCardsCompanion.insert(
          cardId: id,
          wordId: 'w-$id',
          deckId: 'd',
          template: 'recognition',
          state: 'review',
          learningStep: 0,
          dueAt: DateTime(2026, 8, 17),
          intervalDays: 3,
          repetitions: 2,
          easeFactor: 2.5,
          term: 'x',
          position: pos,
        );

    await db.cacheQueue([card('c', 2), card('a', 0), card('b', 1)]);
    final cached = await db.cachedQueue();
    expect(cached.map((c) => c.cardId), ['a', 'b', 'c']);
  });
}
