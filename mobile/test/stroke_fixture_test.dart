import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/writing/kanji_strokes.dart';
import 'package:mobile/features/writing/stroke_grader.dart';

/// The handwriting-grading fixture shared with the web
/// (web/src/app/decks/writing/_lib/fixtures/strokes.fixture.json, checked by
/// strokeGrader.test.ts). Each case is a drawing — the KanjiVG strokes of a
/// real kanji, transformed and sometimes broken on purpose — and the verdict
/// this grader gives it. The web parses the same SVGs with its own parser
/// and must reach the same verdicts, so the two apps judge handwriting alike.
///
/// Regenerate (only for an intended rule change, then fix both sides):
///   GEN_STROKE_FIXTURE=1 flutter test test/stroke_fixture_test.dart
const _fixture = '../web/src/app/decks/writing/_lib/fixtures/strokes.fixture.json';

const _kanji = {'食': 'test/fixtures/kanjivg_098df.svg', '連': 'test/fixtures/kanjivg_09023.svg'};

List<List<Offset>> _expected(String char) =>
    [for (final p in KanjiStrokes(char, parseKanjiVg(File(_kanji[char]!).readAsStringSync())).paths) pathPoints(p)];

/// Deterministic wobble (no RNG, so both languages could recompute it — though
/// the fixture stores the points anyway).
Offset _wobble(int i, double amp) => Offset(sin(i * 1.7) * amp, cos(i * 2.3) * amp);

List<Map<String, Object?>> _cases() {
  final out = <Map<String, Object?>>[];
  for (final char in _kanji.keys) {
    final exp = _expected(char);
    List<List<Offset>> drawn({double sx = 3, double sy = 3, Offset at = const Offset(40, 60), double amp = 2}) {
      var k = 0;
      return [
        for (final s in exp)
          [for (final p in s) at + Offset(p.dx * sx, p.dy * sy) + _wobble(k++, amp)],
      ];
    }

    final variants = <String, List<List<Offset>>>{
      'clean': drawn(),
      'small_corner': drawn(sx: 0.8, sy: 0.8, at: const Offset(5, 5), amp: 0.3),
      'stretched_shaky': drawn(sx: 3.4, sy: 2.9, amp: 8),
      'missing_last': drawn()..removeLast(),
      'extra_stroke': [...drawn(), [const Offset(10, 10), const Offset(60, 12)]],
      'swapped_first_two': (() {
        final d = drawn();
        return [d[1], d[0], ...d.skip(2)];
      })(),
      'reversed_third': (() {
        final d = drawn();
        d[2] = d[2].reversed.toList();
        return d;
      })(),
      'moved_fourth': (() {
        final d = drawn();
        d[3] = [for (final p in d[3]) p + const Offset(-140, 170)];
        return d;
      })(),
    };
    variants.forEach((name, d) {
      final g = gradeStrokes(d, exp);
      out.add({
        'kanji': char,
        'name': name,
        'drawn': [
          for (final s in d) [for (final p in s) [double.parse(p.dx.toStringAsFixed(2)), double.parse(p.dy.toStringAsFixed(2))]],
        ],
        'ok': g.ok,
        'issue': g.issue?.name,
        'stroke': g.stroke,
        'expectedStroke': g.expectedStroke,
      });
    });
  }
  return out;
}

void main() {
  test('the shared stroke fixture matches this grader', () {
    final cases = _cases();
    if (Platform.environment['GEN_STROKE_FIXTURE'] == '1') {
      File(_fixture).writeAsStringSync(const JsonEncoder.withIndent(null).convert(cases));
    }
    final stored = jsonDecode(File(_fixture).readAsStringSync()) as List;
    expect(stored.length, cases.length);
    for (final c in stored.cast<Map<String, dynamic>>()) {
      final drawn = [
        for (final s in c['drawn'] as List)
          [for (final p in s as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
      ];
      final g = gradeStrokes(drawn, _expected(c['kanji'] as String));
      expect((g.ok, g.issue?.name, g.stroke, g.expectedStroke), (c['ok'], c['issue'], c['stroke'], c['expectedStroke']),
          reason: '${c['kanji']} ${c['name']}');
    }
  });
}
