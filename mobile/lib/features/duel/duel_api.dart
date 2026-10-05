import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository.dart';

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

  Future<void> forfeit(String matchId) => db.rpc('forfeit_match', params: {'p_match_id': matchId});

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
