import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import 'duel_api.dart';
import 'duel_screen.dart';
import 'duel_shared.dart';
import 'opponent.dart';

/// Opens a live PvP match — by code, by invitation, or as a rematch — the same
/// way every time: who the opponent is and your record with them are loaded
/// first (a moment), then the duel screen opens on its intro.
///
/// [replace] swaps the current duel screen for the new one (a rematch from the
/// result screen), instead of stacking another on top.
Future<void> openRemoteDuel(BuildContext context, WidgetRef ref, MatchRow m, {bool replace = false}) async {
  final api = ref.read(duelApiProvider);
  final me = api.userId;
  if (me == null) return;
  final isHost = m.hostId == me;
  final opponentId = isHost ? m.guestId : m.hostId;
  if (opponentId == null) return;

  // Both are best effort: a missing name falls back to "Өрсөлдөгч" and a
  // missing record to "first fight" — neither may stop the match starting.
  final results = await Future.wait<Object?>([
    api.opponent(m.id).timeout(const Duration(seconds: 4)).catchError((_) => null),
    api.record(me, opponentId).timeout(const Duration(seconds: 4)).catchError((_) => const HeadToHead()),
  ]);
  if (!context.mounted) return;
  final info = results[0] as OpponentInfo?;
  final record = results[1] as HeadToHead;
  final name = info?.label ?? T.multiplayerTitle;

  final route = MaterialPageRoute<void>(
    builder: (_) => DuelScreen(
      matchId: m.id,
      makeOpponent: () => RemoteOpponent(
        api: api,
        matchId: m.id,
        opponentId: opponentId,
        name: name,
        slug: (isHost ? m.guestCharacter : m.hostCharacter) ?? 'knight',
        baselineMs: isHost ? m.guestBaselineMs : m.hostBaselineMs,
      ),
      online: DuelOnline(
        matchId: m.id,
        meId: me,
        opponentId: opponentId,
        foeName: name,
        foeSub: info?.sub,
        record: record,
        questions: m.questions,
      ),
    ),
  );
  final nav = Navigator.of(context, rootNavigator: true);
  if (replace) {
    unawaited(nav.pushReplacement(route));
  } else {
    unawaited(nav.push(route));
  }
}
