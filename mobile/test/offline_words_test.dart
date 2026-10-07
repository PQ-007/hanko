import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/local_db.dart';
import 'package:mobile/core/offline_words.dart';
import 'package:mobile/core/repository.dart';
import 'package:mobile/models/library.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the server: a set of word ids, with the same
/// ignore-a-conflicting-id insert as `Repository.addWords`.
class FakeRepo extends Repository {
  FakeRepo()
      : super(SupabaseClient('http://localhost', 'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final server = <String, (String deck, String term)>{};
  final failingDecks = <String>{};
  bool offline = false;
  int inserts = 0;

  @override
  Future<List<String>> addWords(String deckId, List<WordDraft> drafts, {List<String>? ids}) async {
    if (offline || failingDecks.contains(deckId)) throw Exception('offline');
    for (var i = 0; i < drafts.length; i++) {
      server.putIfAbsent(ids![i], () => (deckId, drafts[i].term));
      inserts++;
    }
    return ids!;
  }
}

void main() {
  late LocalDb db;
  late FakeRepo repo;
  late WordOutbox outbox;

  setUp(() {
    db = LocalDb.forTesting(NativeDatabase.memory());
    repo = FakeRepo();
    outbox = WordOutbox(repo, db);
  });
  tearDown(() => db.close());

  const words = [
    WordDraft(term: '猫', reading: 'ねこ', meaning: 'cat', meaningMn: 'муур'),
    WordDraft(term: 'コーヒー'),
  ];

  test('online, words go straight to the server and nothing is queued', () async {
    expect(await outbox.save('d', words), SaveOutcome.saved);
    expect(repo.server.values.map((w) => w.$2), ['猫', 'コーヒー']);
    expect(await outbox.pendingCount(), 0);
  });

  test('offline, words are kept on the phone with every field', () async {
    repo.offline = true;
    expect(await outbox.save('d', words), SaveOutcome.queued);
    final pending = await db.pendingWordList();
    expect(pending.map((w) => w.term), ['猫', 'コーヒー']);
    expect(pending.first.meaningMn, 'муур');
    expect(pending.first.deckId, 'd');
  });

  test('flush sends queued words once, with the ids they were queued under', () async {
    repo.offline = true;
    await outbox.save('d', words);
    final ids = (await db.pendingWordList()).map((w) => w.id).toList();
    repo.offline = false;
    expect(await outbox.flush(), 2);
    expect(repo.server.keys, ids);
    expect(await outbox.pendingCount(), 0);
    expect(await outbox.flush(), 0, reason: 'nothing left to send');
  });

  test('a replay after a lost reply cannot create the word twice', () async {
    repo.offline = true;
    await outbox.save('d', words);
    repo.offline = false;
    final first = (await db.pendingWordList()).first;
    // The insert reached the server, but the reply never came back.
    repo.server[first.id] = ('d', first.term);
    await outbox.flush();
    expect(repo.server.length, 2, reason: 'same id, so the replay was ignored');
  });

  test('a deck that still fails stays queued; the others go through', () async {
    repo.offline = true;
    await outbox.save('a', [words.first]);
    await outbox.save('b', [words.last]);
    repo.offline = false;
    repo.failingDecks.add('b');
    expect(await outbox.flush(), 1);
    expect((await db.pendingWordList()).single.deckId, 'b');
  });
}
