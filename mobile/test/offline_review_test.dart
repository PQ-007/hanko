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

  test('a Monster Hunt answer keeps its quiz source through the outbox', () async {
    // Lost here, an offline quiz answer would replay as plain 'review' and
    // vanish from the comparison 0018 added the label for.
    await db.enqueueAnswer(PendingAnswersCompanion.insert(
      logId: 'q',
      cardId: 'c',
      rating: 'good',
      answeredAt: DateTime(2026, 10, 5),
      source: const Value('quiz'),
    ));
    expect((await db.pending()).single.source, 'quiz');
  });

  test('an answer queued without a source is classic review', () async {
    await db.enqueueAnswer(answer('plain'));
    expect((await db.pending()).single.source, 'review');
  });

  test('the quiz word cache is replaced wholesale', () async {
    CachedQuizWordsCompanion w(String id) =>
        CachedQuizWordsCompanion.insert(id: id, term: 't$id', meaningMn: const Value('мн'));
    await db.cacheQuizWords([w('1'), w('2')]);
    await db.cacheQuizWords([w('3')]);
    expect((await db.cachedQuizWordList()).map((x) => x.id), ['3']);
  });

  test('a v1 database on the phone upgrades without losing queued answers', () async {
    // Built by hand in the v1 shape, the way an installed app has it today.
    final upgraded = LocalDb.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE pending_answers (log_id TEXT NOT NULL, card_id TEXT NOT NULL, '
          'rating TEXT NOT NULL, duration_ms INTEGER NULL, answered_at INTEGER NOT NULL, '
          'PRIMARY KEY (log_id))');
      raw.execute('CREATE TABLE cached_cards (card_id TEXT NOT NULL, word_id TEXT NOT NULL, '
          'deck_id TEXT NOT NULL, template TEXT NOT NULL, state TEXT NOT NULL, '
          'learning_step INTEGER NOT NULL, due_at INTEGER NOT NULL, interval_days INTEGER NOT NULL, '
          'repetitions INTEGER NOT NULL, ease_factor REAL NOT NULL, term TEXT NOT NULL, '
          'reading TEXT NULL, meaning TEXT NULL, meaning_mn TEXT NULL, audio_path TEXT NULL, '
          'position INTEGER NOT NULL, PRIMARY KEY (card_id))');
      raw.execute("INSERT INTO pending_answers VALUES ('old', 'c1', 'again', NULL, 1780000000)");
      raw.execute('PRAGMA user_version = 1');
    }));
    addTearDown(upgraded.close);

    final pending = await upgraded.pending();
    expect(pending.single.logId, 'old', reason: 'the queued answer survived');
    expect(pending.single.source, 'review', reason: 'pre-v2 answers were classic review');
    await upgraded.cacheQuizWords([CachedQuizWordsCompanion.insert(id: 'w', term: 't')]);
    expect(await upgraded.cachedQuizWordList(), hasLength(1), reason: 'new table exists');
    expect(await upgraded.pendingWordList(), isEmpty, reason: 'v3 word outbox exists too');
  });
}
