import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository.dart';
import 'duel_shared.dart';

final duelApiProvider = Provider<DuelApi>((ref) => DuelApi(ref.watch(supabaseProvider)));

/// One match row (0020_pvp.sql `matches`), as the client needs it.
class MatchRow {
  const MatchRow({
    required this.id,
    required this.joinCode,
    required this.hostId,
    required this.guestId,
    required this.hostCharacter,
    required this.guestCharacter,
    required this.hostBaselineMs,
    required this.guestBaselineMs,
    required this.status,
    required this.winnerId,
    this.invitedId,
    this.rematchOf,
    this.questions,
  });

  final String id;
  final String? joinCode;
  final String hostId;
  final String? guestId;
  final String hostCharacter;
  final String? guestCharacter;
  final int? hostBaselineMs;
  final int? guestBaselineMs;

  /// lobby | active | finished | abandoned
  final String status;
  final String? winnerId;

  /// A friend's invitation or a rematch is for this one person (0030).
  final String? invitedId;
  final String? rematchOf;

  /// The question set both players answer (0030); null on older matches.
  final List<SharedQuestion>? questions;

  factory MatchRow.fromJson(Map<String, dynamic> j) => MatchRow(
        id: j['id'] as String,
        joinCode: j['join_code'] as String?,
        hostId: j['host_id'] as String,
        guestId: j['guest_id'] as String?,
        hostCharacter: j['host_character'] as String? ?? 'knight',
        guestCharacter: j['guest_character'] as String?,
        hostBaselineMs: (j['host_baseline_ms'] as num?)?.toInt(),
        guestBaselineMs: (j['guest_baseline_ms'] as num?)?.toInt(),
        status: j['status'] as String? ?? 'lobby',
        winnerId: j['winner_id'] as String?,
        invitedId: j['invited_id'] as String?,
        rematchOf: j['rematch_of'] as String?,
        questions: parseQuestions(j['questions']),
      );
}

/// The PvP server calls (0020_pvp.sql), the same ones the web's DuelLobby and
/// remoteOpponent.ts make. Damage, timing and HP are decided by these
/// functions in Postgres — the client only renders them.
class DuelApi {
  const DuelApi(this.db);
  final SupabaseClient db;

  String? get userId => db.auth.currentUser?.id;

  /// This player's median answer time (null under ~20 reviews, or if the
  /// migration isn't applied — damage then uses the constant fallback).
  Future<int?> responseBaseline() async {
    try {
      final v = await db.rpc('response_baseline');
      return (v as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<MatchRow> createMatch(String character) async =>
      MatchRow.fromJson(Map<String, dynamic>.from(await db.rpc('create_match', params: {'p_character': character}) as Map));

  Future<MatchRow> joinMatch(String code, String character) async => MatchRow.fromJson(Map<String, dynamic>.from(
      await db.rpc('join_match', params: {'p_code': code.trim().toUpperCase(), 'p_character': character}) as Map));

  Future<MatchRow?> match(String id) async {
    final row = await db.from('matches').select().eq('id', id).maybeSingle();
    return row == null ? null : MatchRow.fromJson(row);
  }

  /// "My opponent has gone": the caller — the one still here — wins (0020).
  /// Never call this to leave; that's [concede].
  Future<void> forfeit(String matchId) => db.rpc('forfeit_match', params: {'p_match_id': matchId});

  /// Leaving a match: the caller loses (0026). Falls back to cancelling the
  /// lobby with forfeit_match only when nobody has joined, where there's no
  /// winner to name either way.
  Future<void> concede(String matchId) => db.rpc('concede_match', params: {'p_match_id': matchId});

  /// Idempotent; whichever client calls first fixes the round's server start.
  Future<Map<String, dynamic>?> beginRound(String matchId, int roundNo) async {
    final v = await db.rpc('begin_round', params: {'p_match_id': matchId, 'p_round_no': roundNo});
    return v == null ? null : Map<String, dynamic>.from(v as Map);
  }

  /// A timeout is submitted as a wrong answer, so the opponent's client can
  /// stop waiting at the buzzer rather than poll an absence.
  Future<void> submitAnswer(String matchId, int roundNo, bool correct, int? elapsedMs, String? cardId) =>
      db.rpc('submit_round_answer', params: {
        'p_match_id': matchId,
        'p_round_no': roundNo,
        'p_correct': correct,
        'p_client_elapsed_ms': elapsedMs,
        'p_card_id': cardId,
      });

  Future<void> resolveRound(String matchId, int roundNo) =>
      db.rpc('resolve_round', params: {'p_match_id': matchId, 'p_round_no': roundNo});

  // ---- Friends: invites, rematch, who's across the table (0030) --------------

  Future<MatchRow> _row(Object? v) async => MatchRow.fromJson(Map<String, dynamic>.from(v as Map));

  Future<MatchRow> inviteFriend(String friendId, String character) async =>
      _row(await db.rpc('invite_to_duel', params: {'p_friend': friendId, 'p_character': character}));

  Future<MatchRow> acceptInvite(String matchId, String character) async =>
      _row(await db.rpc('accept_duel_invite', params: {'p_match_id': matchId, 'p_character': character}));

  Future<void> declineInvite(String matchId) => db.rpc('decline_duel_invite', params: {'p_match_id': matchId});

  /// Pressing "again": creates the request, or accepts theirs (then active).
  Future<MatchRow> rematch(String matchId, String character) async =>
      _row(await db.rpc('duel_rematch', params: {'p_match_id': matchId, 'p_character': character}));

  /// The live rematch of [matchId], if either player has asked for one.
  Future<MatchRow?> rematchOf(String matchId) async {
    final row = await db
        .from('matches')
        .select()
        .eq('rematch_of', matchId)
        .inFilter('status', ['lobby', 'active'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : MatchRow.fromJson(row);
  }

  Future<List<DuelInvite>> invites() async {
    final rows = await db.rpc('duel_invites') as List;
    return [for (final r in rows) DuelInvite.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<List<FriendLite>> friends() async {
    final rows = await db.rpc('my_friends') as List;
    return [for (final r in rows) FriendLite.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<OpponentInfo?> opponent(String matchId) async {
    final rows = await db.rpc('duel_opponent', params: {'p_match_id': matchId}) as List;
    return rows.isEmpty ? null : OpponentInfo.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Your face-to-face record with [other] (RLS: your own matches only).
  Future<HeadToHead> record(String me, String other) async {
    try {
      final rows = await db
          .from('matches')
          .select('id, host_id, guest_id, status, winner_id, host_hp, guest_hp, created_at, finished_at')
          .or('and(host_id.eq.$me,guest_id.eq.$other),and(host_id.eq.$other,guest_id.eq.$me)')
          .order('created_at', ascending: false)
          .limit(200);
      return headToHead(List<Map<String, dynamic>>.from(rows), me)[other] ?? const HeadToHead();
    } catch (_) {
      return const HeadToHead();
    }
  }

  /// Your own recognition card for a word, by term — what a shared question's
  /// answer is logged against (never scheduled: source 'battle').
  Future<String?> cardIdForTerm(String term) async {
    final w = await db.from('words').select('id').eq('term', term).eq('deleted', false).limit(1).maybeSingle();
    if (w == null) return null;
    final c = await db
        .from('cards')
        .select('id')
        .eq('word_id', w['id'] as String)
        .eq('template', 'recognition')
        .limit(1)
        .maybeSingle();
    return c?['id'] as String?;
  }

  /// The opponent's answer row for a round, as the server decided it.
  Future<({bool correct, int effectiveMs})?> answer(String matchId, int roundNo, String userId) async {
    final row = await db
        .from('match_answers')
        .select('correct, effective_ms')
        .eq('match_id', matchId)
        .eq('round_no', roundNo)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return (correct: row['correct'] as bool, effectiveMs: (row['effective_ms'] as num).toInt());
  }
}

/// A challenge waiting for me — duel_invites() (0030).
class DuelInvite {
  const DuelInvite({required this.matchId, required this.hostId, this.hostName, this.hostHandle, required this.rematch});
  final String matchId, hostId;
  final String? hostName, hostHandle;
  final bool rematch;

  String get label => opponentLabel(hostName, hostHandle);

  factory DuelInvite.fromJson(Map<String, dynamic> j) => DuelInvite(
        matchId: j['match_id'] as String,
        hostId: j['host_id'] as String,
        hostName: j['host_name'] as String?,
        hostHandle: j['host_handle'] as String?,
        rematch: j['rematch'] as bool? ?? false,
      );
}

class FriendLite {
  const FriendLite({required this.userId, this.handle, this.name, this.image});
  final String userId;
  final String? handle, name, image;

  String get label => opponentLabel(name, handle);

  factory FriendLite.fromJson(Map<String, dynamic> j) => FriendLite(
        userId: j['user_id'] as String,
        handle: j['handle'] as String?,
        name: j['name'] as String?,
        image: j['image'] as String?,
      );
}

/// duel_opponent() (0030): handle always; name and picture for friends only.
class OpponentInfo {
  const OpponentInfo({required this.id, this.handle, this.name, required this.isFriend, required this.elo});
  final String id;
  final String? handle, name;
  final bool isFriend;
  final int elo;

  String get label => opponentLabel(name, handle);

  /// "@handle · 1032 ELO" under the name.
  String get sub => [if (name != null && name!.trim().isNotEmpty && handle != null) '@$handle', '$elo ELO'].join(' · ');

  factory OpponentInfo.fromJson(Map<String, dynamic> j) => OpponentInfo(
        id: j['opponent_id'] as String,
        handle: j['handle'] as String?,
        name: j['name'] as String?,
        isFriend: j['is_friend'] as bool? ?? false,
        elo: (j['elo'] as num?)?.toInt() ?? 1000,
      );
}

String opponentLabel(String? name, String? handle, [String fallback = 'Өрсөлдөгч']) {
  if (name != null && name.trim().isNotEmpty) return name.trim();
  if (handle != null && handle.isNotEmpty) return '@$handle';
  return fallback;
}
