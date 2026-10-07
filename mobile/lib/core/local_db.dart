import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

/// Answers given while offline, waiting to be replayed to the server.
///
/// One of only two write paths allowed to be queued (the other is
/// [PendingWords]). Everything else (renaming decks, editing a word) simply
/// fails when offline, because those are deliberate actions a user will
/// retry — whereas losing a review means losing scheduling state you can't
/// reconstruct.
///
/// [logId] is generated at answer time and reused on every replay attempt.
/// `review_card()` treats it as an idempotency key, so replaying a queue after
/// a flaky connection can't double-count a review or inflate a streak. That
/// property is the whole reason offline replay is safe here.
class PendingAnswers extends Table {
  TextColumn get logId => text().named('log_id')();
  TextColumn get cardId => text().named('card_id')();
  TextColumn get rating => text()();
  IntColumn get durationMs => integer().named('duration_ms').nullable()();
  DateTimeColumn get answeredAt => dateTime().named('answered_at')();

  /// `review_card()`'s `p_source` (schema v2). Replayed exactly as answered:
  /// a Monster Hunt answer queued offline must still land as 'quiz', or the
  /// label 0018 added to compare it against classic review is silently lost.
  /// Rows queued before v2 were all classic review, hence the default.
  TextColumn get source => text().withDefault(const Constant('review'))();

  @override
  Set<Column> get primaryKey => {logId};
}

/// The last review queue fetched from the server, so a session can start with
/// no connection at all.
///
/// Deliberately a cache and not a source of truth: it is replaced wholesale on
/// every successful fetch. Nothing here is merged, and no scheduling decision
/// is ever made from it — the server still owns what is due.
class CachedCards extends Table {
  TextColumn get cardId => text().named('card_id')();
  TextColumn get wordId => text().named('word_id')();
  TextColumn get deckId => text().named('deck_id')();
  TextColumn get template => text()();
  TextColumn get state => text()();
  IntColumn get learningStep => integer().named('learning_step')();
  DateTimeColumn get dueAt => dateTime().named('due_at')();
  IntColumn get intervalDays => integer().named('interval_days')();
  IntColumn get repetitions => integer()();
  RealColumn get easeFactor => real().named('ease_factor')();
  TextColumn get term => text()();
  TextColumn get reading => text().nullable()();
  TextColumn get meaning => text().nullable()();
  TextColumn get meaningMn => text().named('meaning_mn').nullable()();
  TextColumn get audioPath => text().named('audio_path').nullable()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {cardId};
}

/// Every word's quiz fields, so Monster Hunt can build its four options with
/// no connection (schema v2). Same contract as [CachedCards]: replaced
/// wholesale on each successful fetch, never merged, never authoritative.
class CachedQuizWords extends Table {
  TextColumn get id => text()();
  TextColumn get term => text()();
  TextColumn get reading => text().nullable()();
  TextColumn get meaning => text().nullable()();
  TextColumn get meaningMn => text().named('meaning_mn').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Words saved from a camera capture with no connection (schema v3), waiting
/// to be inserted. A photographed page isn't something the user can simply
/// retry later — the page may be gone — so these are queued rather than
/// failed.
///
/// [id] is generated on the device and reused on every attempt, and the insert
/// ignores a conflicting id (`Repository.addWords`), so a save whose reply was
/// lost can be replayed without creating the word twice.
class PendingWords extends Table {
  TextColumn get id => text()();
  TextColumn get deckId => text().named('deck_id')();
  TextColumn get term => text()();
  TextColumn get reading => text().nullable()();
  TextColumn get meaning => text().nullable()();
  TextColumn get meaningMn => text().named('meaning_mn').nullable()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// Decks downloaded for offline review (schema v4): what was downloaded and
/// when. The cards themselves are in [OfflineDeckCards].
class OfflineDecks extends Table {
  TextColumn get deckId => text().named('deck_id')();
  TextColumn get name => text()();
  DateTimeColumn get downloadedAt => dateTime().named('downloaded_at')();
  IntColumn get cardCount => integer().named('card_count')();

  @override
  Set<Column> get primaryKey => {deckId};
}

/// Every card of a downloaded deck, as the server last described it. Like
/// [CachedCards] this is a snapshot, replaced wholesale on each download or
/// refresh and never merged: due dates and states come from the server, and
/// answers given offline still go through the outbox to review_card(), which
/// does the actual scheduling when the phone is back online.
///
/// [inQueue] marks the cards that review_queue() itself returned at download
/// time — the only *new* cards served offline, so the daily new-card cap the
/// server applied is respected without being re-implemented here.
class OfflineDeckCards extends Table {
  TextColumn get cardId => text().named('card_id')();
  TextColumn get wordId => text().named('word_id')();
  TextColumn get deckId => text().named('deck_id')();
  TextColumn get template => text()();
  TextColumn get state => text()();
  IntColumn get learningStep => integer().named('learning_step')();
  DateTimeColumn get dueAt => dateTime().named('due_at')();
  IntColumn get intervalDays => integer().named('interval_days')();
  IntColumn get repetitions => integer()();
  RealColumn get easeFactor => real().named('ease_factor')();
  TextColumn get term => text()();
  TextColumn get reading => text().nullable()();
  TextColumn get meaning => text().nullable()();
  TextColumn get meaningMn => text().named('meaning_mn').nullable()();
  TextColumn get audioPath => text().named('audio_path').nullable()();
  BoolColumn get inQueue => boolean().named('in_queue').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {cardId};
}

@DriftDatabase(tables: [PendingAnswers, CachedCards, CachedQuizWords, PendingWords, OfflineDecks, OfflineDeckCards])
class LocalDb extends _$LocalDb {
  LocalDb() : super(driftDatabase(name: 'hanko'));

  LocalDb.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v1 → v2: answers keep their source through the outbox, and the
          // word list is cached for offline Monster Hunt.
          if (from < 2) {
            await m.addColumn(pendingAnswers, pendingAnswers.source);
            await m.createTable(cachedQuizWords);
          }
          // v2 → v3: the camera capture's offline word outbox.
          if (from < 3) await m.createTable(pendingWords);
          // v3 → v4: decks downloaded for offline review.
          if (from < 4) {
            await m.createTable(offlineDecks);
            await m.createTable(offlineDeckCards);
          }
        },
      );

  Future<void> enqueueAnswer(PendingAnswersCompanion answer) =>
      into(pendingAnswers).insert(answer, mode: InsertMode.insertOrReplace);

  Future<List<PendingAnswer>> pending() =>
      (select(pendingAnswers)..orderBy([(t) => OrderingTerm(expression: t.answeredAt)]))
          .get();

  Future<void> clearAnswer(String logId) =>
      (delete(pendingAnswers)..where((t) => t.logId.equals(logId))).go();

  Future<int> pendingCount() async => (await pending()).length;

  Future<void> cacheQueue(List<CachedCardsCompanion> cards) async {
    await transaction(() async {
      await delete(cachedCards).go();
      await batch((b) => b.insertAll(cachedCards, cards));
    });
  }

  Future<List<CachedCard>> cachedQueue() =>
      (select(cachedCards)..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .get();

  Future<void> cacheQuizWords(List<CachedQuizWordsCompanion> words) async {
    await transaction(() async {
      await delete(cachedQuizWords).go();
      await batch((b) => b.insertAll(cachedQuizWords, words));
    });
  }

  Future<List<CachedQuizWord>> cachedQuizWordList() => select(cachedQuizWords).get();

  Future<void> enqueueWords(List<PendingWordsCompanion> words) =>
      batch((b) => b.insertAll(pendingWords, words, mode: InsertMode.insertOrReplace));

  Future<List<PendingWord>> pendingWordList() =>
      (select(pendingWords)..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  Future<void> clearWords(Iterable<String> ids) =>
      (delete(pendingWords)..where((t) => t.id.isIn(ids))).go();

  /// Replaces a downloaded deck's snapshot (cards and its header) in one go.
  Future<void> saveOfflineDeck(OfflineDecksCompanion deck, List<OfflineDeckCardsCompanion> cards) async {
    final id = deck.deckId.value;
    await transaction(() async {
      await (delete(offlineDeckCards)..where((t) => t.deckId.equals(id))).go();
      await batch((b) => b.insertAll(offlineDeckCards, cards, mode: InsertMode.insertOrReplace));
      await into(offlineDecks).insert(deck, mode: InsertMode.insertOrReplace);
    });
  }

  Future<List<OfflineDeck>> offlineDeckList() =>
      (select(offlineDecks)..orderBy([(t) => OrderingTerm(expression: t.name)])).get();

  Future<OfflineDeck?> offlineDeck(String deckId) =>
      (select(offlineDecks)..where((t) => t.deckId.equals(deckId))).getSingleOrNull();

  Future<List<OfflineDeckCard>> offlineDeckCardList(String deckId) =>
      (select(offlineDeckCards)..where((t) => t.deckId.equals(deckId))).get();

  Future<void> removeOfflineDeck(String deckId) async {
    await transaction(() async {
      await (delete(offlineDeckCards)..where((t) => t.deckId.equals(deckId))).go();
      await (delete(offlineDecks)..where((t) => t.deckId.equals(deckId))).go();
    });
  }
}
