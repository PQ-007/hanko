import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/local_db.dart';
import 'package:mobile/core/offline_review.dart';
import 'package:mobile/core/repository.dart';
import 'package:mobile/models/queue_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A deck downloaded for offline review: what's saved, and what the offline
/// queue serves — decided only from what the server said, never by
/// re-implementing scheduling on the phone.
class _Repo extends Repository {
  _Repo(this.all, this.queued)
      : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final List<QueueCard> all;
  final List<QueueCard> queued;
  bool offline = false;

  @override
  Future<List<QueueCard>> practiceCards({String? deckId, int limit = 60}) async {
    if (offline) throw Exception('offline');
    return all;
  }

  @override
  Future<List<QueueCard>> reviewQueue({String? deckId, int limit = 60}) async {
    if (offline) throw Exception('offline');
    return queued;
  }

  @override
  Future<List<QuizWordRow>> quizWords() async {
    if (offline) throw Exception('offline');
    return const [];
  }

  @override
  Future<Map<String, dynamic>> reviewCard({
    required String cardId,
    required String rating,
    required String logId,
    int? durationMs,
    String source = 'review',
  }) async =>
      throw Exception('offline');
}

final now = DateTime(2026, 10, 7, 12);

QueueCard card(String id, {String state = 'review', required DateTime due}) => QueueCard(
      cardId: id,
      wordId: 'w-$id',
      deckId: 'd1',
      template: 'recognition',
      state: state,
      learningStep: 0,
      dueAt: due,
      intervalDays: 3,
      repetitions: 2,
      easeFactor: 2.5,
      term: '語$id',
    );

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final dueReview = card('due', due: now.subtract(const Duration(hours: 1)));
  final laterReview = card('later', due: now.add(const Duration(days: 2)));
  final newQueued = card('new-in', state: 'new', due: now);
  final newCapped = card('new-out', state: 'new', due: now); // over the daily cap
  final all = [dueReview, laterReview, newQueued, newCapped];

  test('download saves every card and remembers which the server was serving', () async {
    final repo = _Repo(all, [dueReview, newQueued]);
    final offline = OfflineReview(repo, db, now: () => now);
    expect(await offline.download('d1', 'N5'), 4);
    final deck = await db.offlineDeck('d1');
    expect(deck?.name, 'N5');
    expect(deck?.cardCount, 4);
    expect((await db.offlineDeckCardList('d1')).where((c) => c.inQueue).map((c) => c.cardId).toSet(), {'due', 'new-in'});
  });

  test('offline queue: due reviews + the new cards the server allowed, nothing else', () async {
    final repo = _Repo(all, [dueReview, newQueued]);
    final offline = OfflineReview(repo, db, now: () => now);
    await offline.download('d1', 'N5');
    expect((await offline.offlineQueue('d1')).map((c) => c.cardId).toSet(), {'due', 'new-in'});
  });

  test('a review that comes due later while offline is served then', () async {
    final repo = _Repo(all, [dueReview, newQueued]);
    var clock = now;
    final offline = OfflineReview(repo, db, now: () => clock);
    await offline.download('d1', 'N5');
    clock = now.add(const Duration(days: 3));
    expect((await offline.offlineQueue('d1')).map((c) => c.cardId).toSet(), {'due', 'later', 'new-in'});
  });

  test('when the fetch fails, review uses the downloaded deck; answered cards drop out', () async {
    final repo = _Repo(all, [dueReview, newQueued]);
    final offline = OfflineReview(repo, db, now: () => now);
    await offline.download('d1', 'N5');
    repo.offline = true;
    final q = await offline.queue(deckId: 'd1');
    expect(q.fromCache, isTrue);
    expect(q.cards.map((c) => c.cardId).toSet(), {'due', 'new-in'});

    // Answered offline → in the outbox → not served again before it's scheduled.
    expect(await offline.answer(cardId: 'due', rating: 'good', logId: 'log-1'), isNull);
    expect((await offline.queue(deckId: 'd1')).cards.map((c) => c.cardId), ['new-in']);
  });

  test('downloading again replaces the copy; removing forgets it', () async {
    final repo = _Repo(all, [dueReview]);
    final offline = OfflineReview(repo, db, now: () => now);
    await offline.download('d1', 'N5');
    final smaller = _Repo([dueReview], [dueReview]);
    await OfflineReview(smaller, db, now: () => now).download('d1', 'N5');
    expect((await db.offlineDeckCardList('d1')).map((c) => c.cardId), ['due']);
    await offline.removeDownload('d1');
    expect(await db.offlineDeck('d1'), isNull);
    expect(await db.offlineDeckCardList('d1'), isEmpty);
  });
}
