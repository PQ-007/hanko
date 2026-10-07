import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/battle/sprites.dart';

// The sprite table is generated from the web's shared fixture, which the web's
// own sprites.test.ts pins to sprites.ts. This side pins the Dart table to the
// same file, so a frame count can't differ between the two apps without one of
// the two suites going red.
const _fixture = '../web/src/app/decks/review/battle/_lib/fixtures/sprites.fixture.json';

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    fixture = jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
  });

  test('frame table matches the shared fixture', () {
    final sprites = fixture['sprites'] as Map<String, dynamic>;
    expect(spriteFrames.keys.toSet(), sprites.keys.toSet());
    for (final MapEntry(key: slug, value: states) in sprites.entries) {
      final expected = {
        for (final e in (states as Map<String, dynamic>).entries)
          e.key: (e.value as Map<String, dynamic>)['frames'] as int,
      };
      expect(spriteFrames[slug], expected, reason: slug);
    }
  });

  test('offsets, rosters and clip timings match the shared fixture', () {
    final offsets = fixture['offsets'] as Map<String, dynamic>;
    for (final MapEntry(key: slug, value: o) in offsets.entries) {
      final m = o as Map<String, dynamic>;
      expect(spriteOffsets[slug], (x: m['x'] as int, y: m['y'] as int), reason: slug);
    }
    expect(playerRoster, List<String>.from(fixture['playerRoster'] as List));
    expect(monsterRoster, List<String>.from(fixture['monsterRoster'] as List));
    expect(defaultPlayerCharacter, fixture['playerCharacter']);
    expect(oneShotMs, fixture['oneShotMs']);
    expect(loopMs, fixture['loopMs']);
  });

  test('every sprite sheet the table names is a real asset', () {
    for (final MapEntry(key: slug, value: states) in spriteFrames.entries) {
      for (final state in states.keys) {
        expect(File('assets/battle/characters/$slug/$state.png').existsSync(), isTrue,
            reason: '$slug/$state');
      }
    }
  });

  test('missing poses fall back to idle; attacks climb and clamp', () {
    expect(resolveState('priest', 'attack03'), 'idle');
    expect(attackChain('priest'), ['attack01']);
    expect(attackPose('priest', 2), 'attack01');
    expect(critPose('knight'), 'attack03');
    expect(attackPose('archer', 2), 'attack02');
    expect(attackPose('knight', -1), 'attack01');
  });

  test('monster bag deals every monster once before any repeats', () {
    final bag = MonsterBag(random: Random(1).nextDouble);
    final first = [for (var i = 0; i < monsterRoster.length; i++) bag.pick()];
    expect(first.toSet().length, monsterRoster.length);
  });

  test('monster bag never deals the excluded character or a back-to-back repeat', () {
    final bag = MonsterBag(random: Random(7).nextDouble);
    String? last;
    for (var i = 0; i < monsterRoster.length * 5; i++) {
      final m = bag.pick(exclude: 'black-knight-a');
      expect(m, isNot('black-knight-a'));
      expect(m, isNot(last));
      last = m;
    }
  });
}
