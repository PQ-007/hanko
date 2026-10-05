import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/library.dart';
import 'local_db.dart';
import 'offline_review.dart';
import 'repository.dart';

final wordOutboxProvider = Provider<WordOutbox>(
  (ref) => WordOutbox(ref.watch(repositoryProvider), ref.watch(localDbProvider)),
);

/// What happened to a batch save.
enum SaveOutcome { saved, queued }

/// Saves a camera capture's words, queueing them on the device when there is
/// no connection — the same shape as [OfflineReview]'s answer outbox, and safe
/// for the same reason: ids are generated here once, and `addWords` ignores a
/// conflicting id, so a replay can't create a word twice.
class WordOutbox {
  WordOutbox(this._repo, this._db);

  final Repository _repo;
  final LocalDb _db;
  static const _uuid = Uuid();

  Future<SaveOutcome> save(String deckId, List<WordDraft> drafts) async {
    final ids = [for (final _ in drafts) _uuid.v4()];
    try {
      await _repo.addWords(deckId, drafts, ids: ids);
      return SaveOutcome.saved;
    } catch (e) {
      debugPrint('Words queued for later: $e');
      final now = DateTime.now();
      await _db.enqueueWords([
        for (var i = 0; i < drafts.length; i++)
          PendingWordsCompanion.insert(
            id: ids[i],
            deckId: deckId,
            term: drafts[i].term,
            reading: Value(drafts[i].reading),
            meaning: Value(drafts[i].meaning),
            meaningMn: Value(drafts[i].meaningMn),
            createdAt: now,
          ),
      ]);
      return SaveOutcome.queued;
    }
  }

  Future<int> pendingCount() async => (await _db.pendingWordList()).length;

  /// Sends everything queued, one deck at a time. A deck that fails stays
  /// queued for the next attempt; returns how many words went through.
  Future<int> flush() async {
    final pending = await _db.pendingWordList();
    final byDeck = <String, List<PendingWord>>{};
    for (final w in pending) {
      (byDeck[w.deckId] ??= []).add(w);
    }
    var sent = 0;
    for (final entry in byDeck.entries) {
      final words = entry.value;
      try {
        await _repo.addWords(
          entry.key,
          [
            for (final w in words)
              WordDraft(term: w.term, reading: w.reading, meaning: w.meaning, meaningMn: w.meaningMn),
          ],
          ids: [for (final w in words) w.id],
        );
        await _db.clearWords(words.map((w) => w.id));
        sent += words.length;
      } catch (e) {
        debugPrint('Queued words still offline: $e');
      }
    }
    return sent;
  }
}
