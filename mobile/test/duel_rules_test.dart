import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/duel/duel_rules.dart';

/// The golden fixture shared with the web (duel.test.ts) and Postgres
/// (supabase/tests/duel_damage_fixture.sql). Regenerating it to make a
/// failure go away would launder a real behaviour change into a green test.
const _fixture = '../web/src/app/decks/review/duel/_lib/duel.fixture.json';

void main() {
  test('roundDamage agrees with the shared golden fixture (TS, SQL, Dart)', () {
    final cases = jsonDecode(File(_fixture).readAsStringSync()) as List;
    expect(cases.length, greaterThan(400));
    for (final c in cases.cast<Map<String, dynamic>>()) {
      // correct: null is a round the player let expire (no answer at all),
      // read exactly as duel.test.ts reads it.
      final answer = c['correct'] == null
          ? null
          : DuelAnswer(correct: c['correct'] as bool, elapsedMs: (c['elapsedMs'] as num).toInt());
      final got = roundDamage(
        answer,
        (c['baselineMs'] as num?)?.toInt(),
        (c['streak'] as num).toInt(),
      );
      expect(got, c['damage'], reason: '$c');
    }
  });

  test('round timer: 10 s, tightening 0.5 s a round, floored at 6 s', () {
    expect(roundDurationMs(1), 10000);
    expect(roundDurationMs(2), 9500);
    expect(roundDurationMs(9), 6000);
    expect(roundDurationMs(12), 6000);
  });

  test('a timeout or a wrong answer deals nothing', () {
    expect(roundDamage(null, 4000, 5), 0);
    expect(roundDamage(const DuelAnswer(correct: false, elapsedMs: 500), 4000, 5), 0);
  });

  test('both knocked out in one round is a draw; level after the last round too', () {
    const hit = DuelAnswer(correct: true, elapsedMs: 1000);
    var rounds = <ResolvedRound>[];
    for (var r = 1; r <= 12; r++) {
      rounds = [...rounds, resolveRound(r, hit, hit, 4000, 4000, deriveDuelState(rounds))];
    }
    expect(duelOutcome(deriveDuelState(rounds)), DuelOutcome.draw);
  });

  test('fewer HP after the last round loses', () {
    final rounds = [
      for (var r = 1; r <= 12; r++)
        ResolvedRound(roundNo: r, you: null, them: null, yourDamage: 0, theirDamage: r == 1 ? 5 : 0),
    ];
    expect(duelOutcome(deriveDuelState(rounds)), DuelOutcome.lost);
  });

  group('bot', () {
    test('reaction first, then correctness, from the injected generator', () {
      final seq = [0.5, 0.1];
      var i = 0;
      final a = botAnswer(botProfiles[BotDifficulty.rival]!, () => seq[i++], 10000)!;
      expect(a.elapsedMs, 5200, reason: 'jitter 0 at rng 0.5');
      expect(a.correct, isTrue, reason: '0.1 < 0.75 accuracy');
    });

    test('a bot slower than the timer answers nothing', () {
      expect(botAnswer(botProfiles[BotDifficulty.rookie]!, () => 0.99, 6000), isNull);
    });
  });

  test("the server's round deadlines match the client's clock (latest migration)", () {
    // begin_round() issues each PvP round's deadline from duel_round_duration_ms.
    // It drifted once: the clients went to 10 s -> 6 s while the SQL stayed at
    // 5 s -> 3 s, so the server closed rounds with time still on the clock.
    final files = Directory('../supabase/migrations').listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final latest = files.lastWhere((f) => f.readAsStringSync().contains('function public.duel_round_duration_ms'));
    final sql = latest.readAsStringSync();
    final m = RegExp(r'greatest\((\d+),\s*(\d+)\s*-\s*\(greatest\(1, p_round_no\) - 1\)\s*\*\s*(\d+)\)').firstMatch(sql)!;
    int sqlDuration(int round) => max(int.parse(m[1]!), int.parse(m[2]!) - (max(1, round) - 1) * int.parse(m[3]!));
    for (var r = 1; r <= duelRoundCount; r++) {
      expect(sqlDuration(r), roundDurationMs(r), reason: 'round $r, from ${latest.path}');
    }
  });
}
