import 'dart:math';
import 'dart:typed_data';

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

/// The everyone board (0027), by 'week' | 'total' | 'elo'.
final globalBoardProvider = FutureProvider.family<List<GlobalRow>, String>(
  (ref, by) => ref.watch(socialApiProvider).globalBoard(by),
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
    this.image,
    this.email,
  });
  final String? handle;
  final bool shareActivity;
  final String? name;
  /// Uploaded (avatars bucket, 0029) or Google photo; null = initial only.
  final String? image;
  final String? email;

  String get displayName => (name?.trim().isNotEmpty ?? false) ? name!.trim() : (handle ?? email ?? '?');
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

/// One row of global_leaderboard() (0027): a handle and scores only — a
/// stranger's name, picture and activity are never sent.
class GlobalRow {
  const GlobalRow({
    required this.rank,
    required this.handle,
    required this.isMe,
    required this.isFriend,
    required this.xpTotal,
    required this.xpWeek,
    required this.elo,
  });
  final int rank;
  final String handle;
  final bool isMe, isFriend;
  final int xpTotal, xpWeek, elo;

  factory GlobalRow.fromJson(Map<String, dynamic> j) => GlobalRow(
    rank: (j['rank'] as num).toInt(),
    handle: j['handle'] as String,
    isMe: j['is_me'] as bool? ?? false,
    isFriend: j['is_friend'] as bool? ?? false,
    xpTotal: (j['xp_total'] as num?)?.toInt() ?? 0,
    xpWeek: (j['xp_week'] as num?)?.toInt() ?? 0,
    elo: (j['elo'] as num?)?.toInt() ?? 1000,
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

  /// Uploads a new profile picture (already shrunk by the picker) to the
  /// public `avatars` bucket under your own folder (0029), points
  /// profiles.image at it, and clears out the previous ones.
  Future<void> setAvatar(Uint8List jpeg) async {
    final uid = _uid!;
    final bucket = db.storage.from('avatars');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await bucket.uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    await db.from('profiles').update({'image': bucket.getPublicUrl(path)}).eq('id', uid);
    try {
      final old = await bucket.list(path: uid);
      final stale = [for (final o in old) '$uid/${o.name}'].where((p) => p != path).toList();
      if (stale.isNotEmpty) await bucket.remove(stale);
    } catch (_) {}
  }

  /// Back to the initial-letter avatar; the uploaded files go too.
  Future<void> removeAvatar() async {
    final uid = _uid!;
    await db.from('profiles').update({'image': null}).eq('id', uid);
    try {
      final bucket = db.storage.from('avatars');
      final old = await bucket.list(path: uid);
      if (old.isNotEmpty) await bucket.remove([for (final o in old) '$uid/${o.name}']);
    } catch (_) {}
  }

  Future<MyProfile> me() async {
    final row = await db
        .from('profiles')
        .select('handle, share_activity, name, image')
        .eq('id', _uid!)
        .maybeSingle();
    return MyProfile(
      handle: row?['handle'] as String?,
      shareActivity: row?['share_activity'] as bool? ?? true,
      name: row?['name'] as String?,
      image: row?['image'] as String?,
      email: db.auth.currentUser?.email,
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

  Future<List<GlobalRow>> globalBoard(String by) async {
    final rows =
        await db.rpc('global_leaderboard', params: {'p_by': by, 'p_limit': 50})
            as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>()) GlobalRow.fromJson(r),
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
