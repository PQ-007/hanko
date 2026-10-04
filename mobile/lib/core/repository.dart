import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/library.dart';
import '../models/queue_card.dart';
import 'reminders.dart';

const _uuid = Uuid();

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Emits on every sign-in / sign-out so the UI can follow the session.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final repositoryProvider = Provider<Repository>(
  (ref) => Repository(ref.watch(supabaseProvider)),
);

/// Built once and reused; initialising the notification plugin twice is
/// wasteful and the timezone database only needs loading once.
final remindersProvider = FutureProvider<Reminders>(
  (ref) => Reminders.create(ref.watch(repositoryProvider)),
);

/// Everything this app knows how to ask the backend.
///
/// Scheduling is deliberately absent: `review_card()` on the server is the only
/// scheduler (FSRS-5 since 0021_fsrs.sql), so there is nothing here to drift
/// out of step with the web app. This class just calls it.
class Repository {
  const Repository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('not signed in');
    return user.id;
  }

  // ---- Folders -------------------------------------------------------------

  /// Oldest first, matching the web sidebar's order.
  Future<List<Folder>> folders() async {
    final rows = await _db
        .from('folders')
        .select()
        .eq('deleted', false)
        .order('created_at');
    return rows.map((r) => Folder.fromJson(r)).toList();
  }

  Future<void> createFolder(String name, {String? parentId}) async {
    await _db.from('folders').insert({
      'user_id': _uid,
      'name': name,
      'parent_id': ?parentId,
    });
  }

  Future<void> renameFolder(String folderId, String name) async {
    await _db.from('folders').update({'name': name}).eq('id', folderId);
  }

  /// Cycles are rejected server-side by the `folders_check_parent` trigger
  /// (0024), so a bad move surfaces as an error rather than corrupting the tree.
  Future<void> moveFolder(String folderId, String? parentId) async {
    await _db.from('folders').update({'parent_id': parentId}).eq('id', folderId);
  }

  /// Tombstone only, like the web sidebar. Its decks and sub-folders keep
  /// pointing at it; every client treats a parent it can't see as root, so
  /// nothing is lost and nothing needs a cascade of writes.
  Future<void> deleteFolder(String folderId) async {
    await _db.from('folders').update({'deleted': true}).eq('id', folderId);
  }

  // ---- Decks ---------------------------------------------------------------

  Future<List<Deck>> decks() async {
    final rows = await _db
        .from('decks')
        .select()
        .eq('deleted', false)
        .order('name');
    return rows.map((r) => Deck.fromJson(r)).toList();
  }

  Future<void> createDeck(String name, {String? folderId}) async {
    await _db.from('decks').insert({
      'user_id': _uid,
      'name': name,
      'folder_id': ?folderId,
    });
  }

  Future<void> moveDeck(String deckId, String? folderId) async {
    await _db.from('decks').update({'folder_id': folderId}).eq('id', deckId);
  }

  // ---- Words ---------------------------------------------------------------

  /// Non-deleted words in a deck, newest first.
  Future<List<Word>> words(String deckId) async {
    final rows = await _db
        .from('words')
        .select()
        .eq('deck_id', deckId)
        .eq('deleted', false)
        .order('date_added', ascending: false);
    return rows.map((r) => Word.fromJson(r)).toList();
  }

  /// Every live word. The stats page and the per-deck counts both derive from
  /// this one read, the same way the web dashboard does.
  ///
  /// Ordered by id, as on the web dashboard: the word spotlight indexes into
  /// this list by a day seed, so both clients need the same order to show the
  /// same "word of the day".
  Future<List<Word>> allWords() async {
    final rows = await _db.from('words').select().eq('deleted', false).order('id');
    return rows.map((r) => Word.fromJson(r)).toList();
  }

  /// Search across every deck — same query and the same character stripping
  /// as web/src/app/decks/DeckDashboard.tsx, so the two find the same words.
  Future<List<Word>> searchWords(String query) async {
    final q = query.replaceAll(RegExp(r'[,()%*]'), '').trim();
    if (q.isEmpty) return const [];
    final like = '%$q%';
    final rows = await _db
        .from('words')
        .select('*, deck:decks(name)')
        .eq('deleted', false)
        .or('term.ilike.$like,reading.ilike.$like,meaning.ilike.$like,meaning_mn.ilike.$like')
        .order('date_added', ascending: false)
        .limit(100);
    return rows.map((r) => Word.fromJson(r)).toList();
  }

  /// Terms from [terms] that already exist (live) in [deckId]. One query for
  /// any number of candidates — the camera's batch add asks about a whole page
  /// of words at once.
  Future<Set<String>> existingTerms(String deckId, Iterable<String> terms) async {
    final list = terms.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await _db
        .from('words')
        .select('term')
        .eq('deck_id', deckId)
        .eq('deleted', false)
        .inFilter('term', list);
    return {for (final r in rows) r['term'] as String};
  }

  /// The one way words get created on mobile — manual add, quick add and the
  /// camera's batch add all come through here.
  ///
  /// Ids are generated on the device and the insert ignores a conflicting id,
  /// so replaying a save after a dropped connection can't create a word twice.
  /// Cards are never written here: the `words_create_default_card` trigger
  /// (0006_cards.sql) gives each new word a `state='new'` recognition card,
  /// exactly as it does for words from the extension and the web.
  Future<List<String>> addWords(
    String deckId,
    List<WordDraft> drafts, {
    List<String>? ids,
  }) async {
    final uid = _uid;
    final rowIds = ids ?? [for (final _ in drafts) _uuid.v4()];
    final rows = [
      for (var i = 0; i < drafts.length; i++)
        {
          'id': rowIds[i],
          'deck_id': deckId,
          'user_id': uid,
          'term': drafts[i].term,
          'reading': drafts[i].reading,
          'meaning': drafts[i].meaning,
          'meaning_mn': drafts[i].meaningMn,
        },
    ];
    if (rows.isEmpty) return const [];
    await _db.from('words').upsert(rows, onConflict: 'id', ignoreDuplicates: true);
    return rowIds;
  }

  // ---- Profile -------------------------------------------------------------

  /// Bounds match `profiles_new_per_day_check` (0023): 0–999.
  Future<void> setNewPerDay(int value) async {
    await _db.from('profiles').update({'new_per_day': value}).eq('id', _uid);
  }

  // ---- Stats ---------------------------------------------------------------

  /// Retention and accuracy over the last [days] (`review_stats`, 0024).
  /// Returns null if the migration isn't applied, so the stats page can hide
  /// the section instead of failing whole.
  Future<ReviewStats?> reviewStats({int days = 30}) async {
    try {
      final rows = await _db.rpc<List<dynamic>>(
        'review_stats',
        params: {'p_days': days},
      );
      if (rows.isEmpty) return null;
      return ReviewStats.fromJson(Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return null;
    }
  }


  /// Renames a deck. `updated_at` is bumped by a trigger, so the extension's
  /// next sync pulls the new name without anything here having to stamp it —
  /// and last-write-wins on that column means a rename can't be clobbered by a
  /// stale cached copy on another device.
  Future<void> renameDeck(String deckId, String name) async {
    await _db.from('decks').update({'name': name}).eq('id', deckId);
  }

  /// Deletes a deck, matching the web app's behaviour exactly
  /// (web/src/app/decks/_components/DeckHeader.tsx): tombstone the words, then
  /// the deck.
  ///
  /// Order matters. Words first means a failure part-way leaves a live deck
  /// holding deleted words — visibly odd but harmless. The reverse order would
  /// leave live words stranded in a deleted deck, reachable by nothing.
  ///
  /// Cards are deliberately left alone. `review_queue()` joins through `words`
  /// and filters `deleted = false`, so the cards drop out of the queue on their
  /// own, while review_log keeps the history — which means restoring a deck
  /// would restore its schedules intact rather than resetting every card.
  Future<void> deleteDeck(String deckId) async {
    await _db.from('words').update({'deleted': true}).eq('deck_id', deckId);
    await _db.from('decks').update({'deleted': true}).eq('id', deckId);
  }

  Future<void> updateWord(String wordId, WordDraft draft) async {
    await _db.from('words').update({
      'term': draft.term,
      'reading': draft.reading,
      'meaning': draft.meaning,
      'meaning_mn': draft.meaningMn,
    }).eq('id', wordId);
  }

  /// Tombstone rather than a hard delete: the extension syncs by last-write-wins
  /// over `updated_at`, and a row that simply vanishes would be re-uploaded from
  /// whichever client still has it cached.
  Future<void> deleteWord(String wordId) async {
    await _db.from('words').update({'deleted': true}).eq('id', wordId);
  }

  /// What's due, under the server's day cutoff and daily caps.
  ///
  /// [at] asks for a future moment instead of now — the daily reminder needs
  /// the count as it will be when it fires, not as it is when the app happens
  /// to be open.
  Future<DueSummary> dueSummary({String? deckId, DateTime? at}) async {
    final rows = await _db.rpc<List<dynamic>>(
      'due_summary',
      params: {
        'p_deck_id': deckId,
        if (at != null) 'p_at': at.toUtc().toIso8601String(),
      },
    );
    if (rows.isEmpty) return DueSummary.empty;
    return DueSummary.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<QueueCard>> reviewQueue({String? deckId, int limit = 60}) async {
    final rows = await _db.rpc<List<dynamic>>(
      'review_queue',
      params: {'p_deck_id': deckId, 'p_limit': limit},
    );
    return rows
        .map((r) => QueueCard.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Answer a card. [logId] is generated on the device and reused when
  /// retrying, which is what makes the write idempotent — an answer replayed
  /// after an offline gap is applied exactly once instead of double-counting
  /// the review and inflating the streak.
  Future<Map<String, dynamic>> reviewCard({
    required String cardId,
    required String rating,
    required String logId,
    int? durationMs,
    // 'review' (the default) and 'quiz' (Monster Hunt) are real scheduling
    // answers. 'drill' and 'battle' are logged but the server returns the card
    // untouched (the non-scheduling branch of review_card() in 0021_fsrs.sql),
    // which is what makes the speed round safe to answer.
    String source = 'review',
  }) async {
    final row = await _db.rpc<Map<String, dynamic>>(
      'review_card',
      params: {
        'p_card_id': cardId,
        'p_rating': rating,
        'p_duration_ms': durationMs,
        'p_log_id': logId,
        'p_source': source,
      },
    );
    return row;
  }

  /// Mature review cards, for the speed round drill. Unlike `review_queue()`
  /// this ignores `due_at` and the daily caps on purpose — a drill is extra,
  /// opt-in practice, not part of today's scheduled workload, so it must not
  /// compete with it for the cap.
  Future<List<QueueCard>> matureCards({String? deckId, int limit = 30}) async {
    final rows = await _db.rpc<List<dynamic>>(
      'mature_cards',
      params: {'p_deck_id': deckId, 'p_limit': limit},
    );
    return rows
        .map((r) => QueueCard.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Cards with a high lapse count, for a focused rescue session. Also ignores
  /// `due_at` — the point is to reach a leech *before* the scheduler would, and
  /// unlike the drill queue these answers use the default `source: 'review'`,
  /// so a successful rescue is a real review that reschedules the card.
  Future<List<QueueCard>> leechCards({String? deckId, int limit = 30}) async {
    final rows = await _db.rpc<List<dynamic>>(
      'leech_cards',
      params: {'p_deck_id': deckId, 'p_limit': limit},
    );
    return rows
        .map((r) => QueueCard.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Reviews per SRS day, newest last. The server buckets by the same day
  /// cutoff the scheduler uses, so a streak can never claim a day the review
  /// queue disagrees about.
  Future<Map<DateTime, int>> reviewActivity({int days = 400}) async {
    final rows = await _db.rpc<List<dynamic>>(
      'review_activity',
      params: {'p_days': days},
    );
    return {
      for (final r in rows)
        DateTime.parse((r as Map)['day'] as String):
            ((r)['reviews'] as num).toInt(),
    };
  }

  /// The scheduler's current day (`current_srs_day()`, 0019).
  ///
  /// The streak walk has to start on the same day boundary `review_activity()`
  /// buckets by — which rolls over at `profiles.day_cutoff_hour`, not at local
  /// midnight. Between the two, `DateTime.now()` is a day ahead of the server,
  /// and on a device whose clock or timezone disagrees with the profile it can
  /// be wrong at any hour.
  ///
  /// Returns null rather than throwing if the migration isn't applied yet; the
  /// caller then falls back to the device's date, which is what it used to do
  /// unconditionally.
  Future<DateTime?> currentSrsDay() async {
    try {
      final day = await _db.rpc<String?>('current_srs_day');
      return day == null ? null : DateTime.parse(day);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> undoReview(String logId) async {
    return await _db.rpc<Map<String, dynamic>>(
      'undo_review',
      params: {'p_log_id': logId},
    );
  }

  /// Available streak-freeze grace days (`profiles.streak_freezes`,
  /// 0014_gamification.sql). Falls back to 0 rather than throwing — a stats
  /// screen should never break because one extra column couldn't be read.
  Future<int> streakFreezes() async {
    final user = _db.auth.currentUser;
    if (user == null) return 0;
    try {
      final row = await _db
          .from('profiles')
          .select('streak_freezes')
          .eq('id', user.id)
          .maybeSingle();
      return (row?['streak_freezes'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The SRS day boundary is evaluated server-side in the user's timezone, and
  /// nothing else writes it — left null it silently falls back to UTC, which
  /// for UTC+8 rolls the day over at noon. The web app does the same thing.
  Future<void> syncTimezone(String ianaName) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('profiles').update({'timezone': ianaName}).eq('id', user.id);
  }
}
