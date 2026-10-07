import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/writing/svg_path.dart';

void main() {
  test('a real KanjiVG stroke (食, first stroke) lands where it should', () {
    final p = parseSvgPath('M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93C45,25.34,31.75,41.19,14,51.5');
    final b = p.getBounds();
    // Starts top-middle, sweeps down-left to (14, 51.5).
    expect(b.left, closeTo(14, 0.5));
    expect(b.bottom, closeTo(51.5, 0.5));
    expect(b.top, closeTo(10.5, 0.5));
    expect(b.right, lessThan(53.5));
  });

  test('smooth curves reflect the previous control point', () {
    final p = parseSvgPath('M0,0c10,0,10,10,10,10s0,10,10,10');
    final m = p.computeMetrics().single;
    expect(m.getTangentForOffset(m.length)!.position, const Offset(20, 20));
  });

  test('lines, implicit linetos after a move, and close', () {
    final p = parseSvgPath('M10 10 20 10 l0 10 H10 z');
    expect(p.getBounds(), const Rect.fromLTRB(10, 10, 20, 20));
  });

  test('numbers packed without separators parse (KanjiVG writes 1.5-2.25)', () {
    final p = parseSvgPath('M0,0l1.5-2.25');
    expect(p.getBounds(), const Rect.fromLTRB(0, -2.25, 1.5, 0));
  });

  test('the start point is the first move', () {
    expect(svgPathStart('M52.75,10.5c0.11,0.98'), const Offset(52.75, 10.5));
    expect(svgPathStart('nothing'), isNull);
  });
}
