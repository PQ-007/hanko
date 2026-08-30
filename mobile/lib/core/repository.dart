import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/queue_card.dart';
import 'reminders.dart';

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
/// implementation of SM-2, so there is nothing here to drift out of step with
/// the web app. This class just calls it.
class Repository {
  const Repository(this._db);

  final SupabaseClient _db;

  Future<List<Map<String, dynamic>>> decks() async {
    final rows = await _db
        .from('decks')
        .select()
        .eq('deleted', false)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Non-deleted words in a deck, newest first.
  Future<List<Map<String, dynamic>>> words(String deckId) async {
    final rows = await _db
        .from('words')
        .select()
        .eq('deck_id', deckId)
        .eq('deleted', false)
        .order('date_added', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> createDeck(String name) async {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('not signed in');
    await _db.from('decks').insert({'user_id': user.id, 'name': name});
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

  /// The recognition card is created server-side by a trigger on `words`
  /// (0006_cards.sql), so nothing here has to know about the cards table —
  /// same as the extension, which predates it entirely.
  Future<void> addWord({
    required String deckId,
    required String term,
    String? reading,
    String? meaning,
    String? meaningMn,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('not signed in');
    await _db.from('words').insert({
      'deck_id': deckId,
      'user_id': user.id,
      'term': term,
      'reading': reading,
      'meaning': meaning,
      'meaning_mn': meaningMn,
    });
  }

  Future<void> updateWord({
    required String wordId,
    required String term,
    String? reading,
    String? meaning,
    String? meaningMn,
  }) async {
    await _db.from('words').update({
      'term': term,
      'reading': reading,
      'meaning': meaning,
      'meaning_mn': meaningMn,
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
    if (rows.isEmpty) {
      return const DueSummary(
        dueNow: 0,
        reviewDue: 0,
        newDue: 0,
        reviewRemaining: 0,
        newRemaining: 0,
      );
    }
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
    // 'review' (the default) is a real scheduling answer. 'drill' logs the
    // answer but the server returns the card completely untouched — see the
    // `p_source <> 'review'` branch in 0009_review_card.sql — which is what
    // makes the speed round safe to answer without disturbing SM-2 state.
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
