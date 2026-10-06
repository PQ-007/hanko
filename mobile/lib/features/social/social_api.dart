import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository.dart';

final socialApiProvider = Provider<SocialApi>(
  (ref) => SocialApi(ref.watch(supabaseProvider)),
);

final myProfileProvider = FutureProvider<MyProfile>(
  (ref) => ref.watch(socialApiProvider).me(),
);
final friendOverviewProvider = FutureProvider<List<FriendRow>>(
  (ref) => ref.watch(socialApiProvider).overview(),
);
final friendRequestsProvider = FutureProvider<List<FriendRequest>>(
  (ref) => ref.watch(socialApiProvider).requests(),
);

/// Levels grow with the square root of XP: each level costs a little more
/// than the last (level 2 at 100 XP, 5 at 1,600, 10 at 8,100).
int levelFor(int xp) => sqrt(max(0, xp) / 100).floor() + 1;

/// XP where [level] starts, for the progress bar to the next one.
int xpForLevel(int level) => 100 * (level - 1) * (level - 1);

class MyProfile {
  const MyProfile({
    required this.handle,
    required this.shareActivity,
    this.name,
  });
  final String? handle;
  final bool shareActivity;
  final String? name;
}

/// One row of friend_overview() (0026): you or an accepted friend. Numbers
/// are null for a friend who turned sharing off.
class FriendRow {
  const FriendRow({
    required this.userId,
    required this.handle,
    required this.name,
    required this.image,
    required this.isMe,
    required this.shares,
    this.elo,
    this.pvpGames,
    this.xpTotal,
    this.xpWeek,
    this.addedToday,
    this.reviewedToday,
    this.wordsLearned,
    this.kanjiLearned,
    this.recentKanji = const [],
    this.activeDaysWeek,
  });

  final String userId;
  final String? handle;
  final String? name;
  final String? image;
  final bool isMe;
  final bool shares;
  final int? elo,
      pvpGames,
      xpTotal,
      xpWeek,
      addedToday,
      reviewedToday,
      wordsLearned,
      kanjiLearned,
      activeDaysWeek;
  final List<String> recentKanji;

  String get displayName =>
      (name?.trim().isNotEmpty ?? false) ? name!.trim() : (handle ?? '—');

  static int? _i(Object? v) => (v as num?)?.toInt();

  factory FriendRow.fromJson(Map<String, dynamic> j) => FriendRow(
    userId: j['user_id'] as String,
    handle: j['handle'] as String?,
    name: j['name'] as String?,
    image: j['image'] as String?,
    isMe: j['is_me'] as bool? ?? false,
    shares: j['shares'] as bool? ?? false,
    elo: _i(j['elo']),
    pvpGames: _i(j['pvp_games']),
    xpTotal: _i(j['xp_total']),
    xpWeek: _i(j['xp_week']),
    addedToday: _i(j['added_today']),
    reviewedToday: _i(j['reviewed_today']),
    wordsLearned: _i(j['words_learned']),
    kanjiLearned: _i(j['kanji_learned']),
    recentKanji: [
      for (final k in (j['recent_kanji'] as List?) ?? const []) k as String,
    ],
    activeDaysWeek: _i(j['active_days_week']),
  );
}

class FriendRequest {
  const FriendRequest({
    required this.otherId,
    required this.handle,
    required this.name,
    required this.incoming,
  });
  final String otherId;
  final String? handle;
  final String? name;
  final bool incoming;
}

enum HandleError { format, taken, other }

/// The social calls (0026_social.sql). Everything another person's numbers
/// come from goes through friend_overview(), which decides on the server
/// whose numbers you may see — this never queries anyone else's tables.
class SocialApi {
  const SocialApi(this.db);
  final SupabaseClient db;

  String? get _uid => db.auth.currentUser?.id;

  Future<MyProfile> me() async {
    final row = await db
        .from('profiles')
        .select('handle, share_activity, name')
        .eq('id', _uid!)
        .maybeSingle();
    return MyProfile(
      handle: row?['handle'] as String?,
      shareActivity: row?['share_activity'] as bool? ?? true,
      name: row?['name'] as String?,
    );
  }

  /// Normalised to lowercase. Returns null on success.
  Future<HandleError?> setHandle(String handle) async {
    final h = handle.trim().replaceFirst(RegExp('^@'), '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(h)) return HandleError.format;
    try {
      await db.from('profiles').update({'handle': h}).eq('id', _uid!);
      return null;
    } on PostgrestException catch (e) {
      return e.code == '23505'
          ? HandleError.taken
          : (e.code == '23514' ? HandleError.format : HandleError.other);
    } catch (_) {
      return HandleError.other;
    }
  }

  Future<void> setShare(bool share) =>
      db.from('profiles').update({'share_activity': share}).eq('id', _uid!);

  /// sent | accepted | already | not_found | self
  Future<String> sendRequest(String handle) async =>
      await db.rpc(
            'send_friend_request',
            params: {'p_handle': handle.trim().replaceFirst(RegExp('^@'), '')},
          )
          as String;

  Future<void> respond(String fromId, bool accept) => db.rpc(
    'respond_friend_request',
    params: {'p_from': fromId, 'p_accept': accept},
  );

  Future<void> remove(String otherId) =>
      db.rpc('remove_friend', params: {'p_other': otherId});

  Future<List<FriendRequest>> requests() async {
    final rows = await db.rpc('friend_requests') as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        FriendRequest(
          otherId: r['other_id'] as String,
          handle: r['handle'] as String?,
          name: r['name'] as String?,
          incoming: r['incoming'] as bool? ?? false,
        ),
    ];
  }

  Future<List<FriendRow>> overview() async {
    final rows = await db.rpc('friend_overview') as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>()) FriendRow.fromJson(r),
    ];
  }

  // ---- Learned kanji ---------------------------------------------------------

  Future<Set<String>> learnedKanji() async {
    final rows = await db.from('learned_kanji').select('kanji');
    return {for (final r in rows) r['kanji'] as String};
  }

  /// Ignores ones already there, so it's safe to send the whole local set.
  Future<void> addLearnedKanji(Iterable<String> kanji) async {
    final uid = _uid;
    final list = kanji.toSet().toList();
    if (uid == null || list.isEmpty) return;
    await db
        .from('learned_kanji')
        .upsert(
          [
            for (final k in list) {'user_id': uid, 'kanji': k},
          ],
          onConflict: 'user_id,kanji',
          ignoreDuplicates: true,
        );
  }
}
