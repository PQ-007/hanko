import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/battle/rules.dart';
import 'package:mobile/features/battle/sprites.dart';

// The Monster Hunt rules against the fixture the web's TypeScript generated
// (web/src/app/decks/review/battle/_lib/fixtures/battle.fixture.json, pinned
// on that side by battle-fixture.test.ts). Same inputs, same scripted
// randomness, same outputs — or one of the two games has a different rule.

const _fixture = '../web/src/app/decks/review/battle/_lib/fixtures/battle.fixture.json';

/// A cycling list of [0, 1) values, consumed like the TS `withRandoms` helper.
Rand scripted(List<dynamic> values) {
  var i = 0;
  return () => (values[i++ % values.length] as num).toDouble();
}

void main() {
  late Map<String, dynamic> f;
  setUpAll(() => f = jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>);

  test('rollEvent matches every recorded roll', () {
    for (final c in (f['roll'] as List).cast<Map<String, dynamic>>()) {
      final out = rollEvent(
        c['rating'] as String,
        streak: c['streak'] as int,
        armorCharges: c['armorCharges'] as int,
        timedOut: c['timedOut'] as bool,
        rand: scripted([c['random']]),
      );
      expect(out.toJson(), c['out'], reason: jsonEncode(c));
    }
  });

  test('deriveBattleState and battleOutcome match every recorded fight', () {
    for (final c in (f['derive'] as List).cast<Map<String, dynamic>>()) {
      final events = [
        for (final e in (c['events'] as List).cast<Map<String, dynamic>>()) BattleEvent.fromJson(e),
      ];
      final out = deriveBattleState(events, c['monsterStartIndex'] as int);
      expect(out.toJson(), c['out']);
      expect(battleOutcome(out, queueIsEmpty: true).name, c['outcomeQueueEmpty']);
      expect(battleOutcome(out, queueIsEmpty: false).name, c['outcomeQueueLive']);
    }
  });

  test('streakTier matches', () {
    for (final c in (f['tiers'] as List).cast<Map<String, dynamic>>()) {
      expect(streakTier(c['streak'] as int), c['tier']);
    }
  });

  test('buildQuiz reproduces every recorded question under the same randoms', () {
    for (final c in (f['quiz'] as List).cast<Map<String, dynamic>>()) {
      final card = c['card'] as Map<String, dynamic>;
      final out = buildQuiz(
        wordId: card['word_id'] as String,
        term: card['term'] as String,
        reading: card['reading'] as String?,
        meaning: card['meaning'] as String?,
        meaningMn: card['meaning_mn'] as String?,
        allWords: [
          for (final w in (c['words'] as List).cast<Map<String, dynamic>>()) QuizWord.fromJson(w),
        ],
        rand: scripted(c['randoms'] as List),
      );
      expect([for (final o in out) o.toJson()], c['out']);
    }
  });

  test('the monster shuffle bag deals the recorded sequence', () {
    for (final c in (f['bag'] as List).cast<Map<String, dynamic>>()) {
      final bag = MonsterBag(random: scripted(c['randoms'] as List));
      for (final p in (c['picks'] as List).cast<Map<String, dynamic>>()) {
        expect(bag.pick(exclude: p['exclude'] as String?), p['out']);
      }
    }
  });

  group('rating helpers (BattleArena.tsx)', () {
    test('speed tiers split the 10s clock in thirds', () {
      expect(ratingForElapsed(0), 'easy');
      expect(ratingForElapsed(3333), 'easy');
      expect(ratingForElapsed(3334), 'good');
      expect(ratingForElapsed(6666), 'good');
      expect(ratingForElapsed(6667), 'hard');
      expect(ratingForElapsed(9999), 'hard');
    });

    test('the scheduler is never told easy', () {
      expect(scheduleRating('easy'), 'good');
      for (final r in ['again', 'hard', 'good']) {
        expect(scheduleRating(r), r);
      }
    });
  });
}
