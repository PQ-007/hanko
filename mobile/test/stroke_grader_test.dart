import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/writing/kanji_strokes.dart';
import 'package:mobile/features/writing/stroke_grader.dart';

void main() {
  // 食, 9 strokes, from a real KanjiVG file.
  final kanji = KanjiStrokes('食', parseKanjiVg(File('test/fixtures/kanjivg_098df.svg').readAsStringSync()));
  final expected = [for (final p in kanji.paths) pathPoints(p)];

  /// The kanji as a learner might draw it on a phone: three times the size,
  /// somewhere else on the pad, with a little wobble.
  List<List<Offset>> handwritten({int seed = 1, double wobble = 2}) {
    final rnd = Random(seed);
    return [
      for (final s in expected)
        [
          for (final p in s)
            Offset(40, 70) + p * 3 + Offset((rnd.nextDouble() - 0.5) * wobble * 3, (rnd.nextDouble() - 0.5) * wobble * 3),
        ],
    ];
  }

  test('a correct kanji passes, whatever its size and place on the pad', () {
    for (var seed = 0; seed < 5; seed++) {
      expect(gradeStrokes(handwritten(seed: seed), expected).ok, isTrue, reason: 'seed $seed');
    }
  });

  test('written small in a corner still passes', () {
    final small = [
      for (final s in expected) [for (final p in s) Offset(10, 10) + p * 0.8],
    ];
    expect(gradeStrokes(small, expected).ok, isTrue);
  });

  test('a missing stroke is a count error', () {
    final g = gradeStrokes(handwritten()..removeLast(), expected);
    expect(g.issue, StrokeIssue.count);
    expect((g.drawn, g.expected), (8, 9));
  });

  test('two strokes swapped is an order error, naming both', () {
    final h = handwritten();
    final swapped = [h[1], h[0], ...h.skip(2)];
    final g = gradeStrokes(swapped, expected);
    expect(g.issue, StrokeIssue.order);
    expect((g.stroke, g.expectedStroke), (0, 1));
  });

  test('a stroke drawn backwards is a direction error', () {
    final h = handwritten();
    h[3] = h[3].reversed.toList();
    final g = gradeStrokes(h, expected);
    expect(g.issue, StrokeIssue.direction);
    expect(g.stroke, 3);
  });

  test('a stroke in the wrong place is a shape error', () {
    final h = handwritten();
    // Stroke 5 (a horizontal inside 良) moved to the bottom-left corner.
    h[4] = [for (final p in h[4]) p + const Offset(-120, 150)];
    final g = gradeStrokes(h, expected);
    expect(g.ok, isFalse);
    expect(g.stroke, 4);
  });

  test('scribbles with the right stroke count fail', () {
    final rnd = Random(3);
    final scribble = [
      for (var i = 0; i < 9; i++)
        [for (var k = 0; k < 10; k++) Offset(rnd.nextDouble() * 300, rnd.nextDouble() * 300)],
    ];
    expect(gradeStrokes(scribble, expected).ok, isFalse);
  });

  test('sloppy but correct handwriting passes: stretched wide, shaky', () {
    final rnd = Random(7);
    final sloppy = [
      for (final s in expected)
        [
          for (final p in s)
            Offset(p.dx * 3.4, p.dy * 2.9) + Offset((rnd.nextDouble() - 0.5) * 18, (rnd.nextDouble() - 0.5) * 18),
        ],
    ];
    expect(gradeStrokes(sloppy, expected).ok, isTrue);
  });

  test('a degenerate expected stroke (no length) is graded, not a crash', () {
    expect(() => gradeStrokes([[const Offset(1, 1), const Offset(2, 2)]], [<Offset>[]]), returnsNormally);
  });
}
