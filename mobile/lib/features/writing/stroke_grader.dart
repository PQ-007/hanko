import 'dart:math';
import 'dart:ui';

/// What's wrong with a handwritten kanji, stroke by stroke, against its
/// KanjiVG strokes — the check a teacher makes and a character recogniser
/// doesn't: a recogniser reads the finished shape, so it happily accepts a
/// kanji drawn with strokes missing, in the wrong order or backwards.
enum StrokeIssue { count, order, direction, shape }

class StrokeGrade {
  const StrokeGrade.ok(this.drawn, this.expected)
    : issue = null,
      stroke = null,
      expectedStroke = null;
  const StrokeGrade.fail(
    this.issue,
    this.drawn,
    this.expected, {
    this.stroke,
    this.expectedStroke,
  });

  final StrokeIssue? issue;
  final int drawn;
  final int expected;

  /// Index of the first drawn stroke that's wrong.
  final int? stroke;

  /// For [StrokeIssue.order]: which expected stroke the drawn one actually is.
  final int? expectedStroke;

  bool get ok => issue == null;
}

/// Points per stroke after resampling: enough to follow a hooked or curved
/// stroke, few enough to stay cheap.
const _samples = 16;

/// Tolerances in KanjiVG's 109-unit box, after the drawing is scaled onto the
/// kanji's own bounds. Generous on purpose: this is handwriting with a finger
/// on glass, and the recogniser still has to agree on the overall shape.
const _meanTolerance = 17.0;
const _endTolerance = 26.0;

/// Strokes shorter than this (dots, ticks) are compared by position only —
/// their direction is too small to judge reliably.
const _shortStroke = 12.0;

/// Grades [drawn] (pad coordinates, one point list per stroke) against
/// [expected] (KanjiVG coordinates, one polyline per stroke, in order).
///
/// The drawing is first scaled and centred onto the kanji's bounds, so a kanji
/// written small in a corner is judged on its strokes, not where it sits.
StrokeGrade gradeStrokes(
  List<List<Offset>> drawn,
  List<List<Offset>> expected,
) {
  final d = drawn.where((s) => s.isNotEmpty).toList();
  if (d.length != expected.length) {
    return StrokeGrade.fail(StrokeIssue.count, d.length, expected.length);
  }
  final user = _normalize(d, expected);
  final exp = [for (final s in expected) _resample(s)];
  for (var i = 0; i < user.length; i++) {
    if (_matches(user[i], exp[i])) continue;
    for (var j = 0; j < exp.length; j++) {
      if (j != i && _matches(user[i], exp[j])) {
        return StrokeGrade.fail(
          StrokeIssue.order,
          d.length,
          expected.length,
          stroke: i,
          expectedStroke: j,
        );
      }
    }
    final issue = _matches(user[i].reversed.toList(), exp[i])
        ? StrokeIssue.direction
        : StrokeIssue.shape;
    return StrokeGrade.fail(issue, d.length, expected.length, stroke: i);
  }
  return StrokeGrade.ok(d.length, expected.length);
}

/// A KanjiVG stroke path as a polyline in its own coordinates.
List<Offset> pathPoints(Path path, {int count = 32}) {
  final out = <Offset>[];
  for (final m in path.computeMetrics()) {
    for (var k = 0; k <= count; k++) {
      final t = m.getTangentForOffset(m.length * k / count);
      if (t != null) out.add(t.position);
    }
  }
  return out;
}

bool _matches(List<Offset> u, List<Offset> e) {
  final eLen = _length(e);
  final uLen = _length(u);
  if (eLen < _shortStroke && uLen < _shortStroke * 1.6) {
    return (_centre(u) - _centre(e)).distance < _endTolerance;
  }
  var sum = 0.0;
  for (var k = 0; k < _samples; k++) {
    sum += (u[k] - e[k]).distance;
  }
  return sum / _samples < _meanTolerance &&
      (u.first - e.first).distance < _endTolerance &&
      (u.last - e.last).distance < _endTolerance;
}

/// Scales and centres the drawing onto the expected strokes' bounds, keeping
/// its proportions, then resamples each stroke.
List<List<Offset>> _normalize(
  List<List<Offset>> drawn,
  List<List<Offset>> expected,
) {
  final ru = _bounds(drawn.expand((s) => s));
  final re = _bounds(expected.expand((s) => s));
  final userSize = max(max(ru.width, ru.height), 1.0);
  final scale = max(re.width, re.height) / userSize;
  return [
    for (final s in drawn)
      _resample([for (final p in s) re.center + (p - ru.center) * scale]),
  ];
}

Rect _bounds(Iterable<Offset> pts) {
  var l = double.infinity,
      t = double.infinity,
      r = -double.infinity,
      b = -double.infinity;
  for (final p in pts) {
    l = min(l, p.dx);
    t = min(t, p.dy);
    r = max(r, p.dx);
    b = max(b, p.dy);
  }
  return l.isFinite ? Rect.fromLTRB(l, t, r, b) : Rect.zero;
}

double _length(List<Offset> pts) {
  var len = 0.0;
  for (var k = 1; k < pts.length; k++) {
    len += (pts[k] - pts[k - 1]).distance;
  }
  return len;
}

Offset _centre(List<Offset> pts) =>
    pts.fold(Offset.zero, (a, p) => a + p) / pts.length.toDouble();

/// [_samples] points evenly spaced along the stroke.
List<Offset> _resample(List<Offset> pts) {
  if (pts.isEmpty) return List.filled(_samples, Offset.zero);
  if (pts.length == 1) return List.filled(_samples, pts.first);
  final total = _length(pts);
  if (total == 0) return List.filled(_samples, pts.first);
  final out = <Offset>[pts.first];
  final step = total / (_samples - 1);
  var walked = 0.0;
  var target = step;
  for (var k = 1; k < pts.length && out.length < _samples; k++) {
    final a = pts[k - 1], b = pts[k];
    final seg = (b - a).distance;
    while (seg > 0 && walked + seg >= target && out.length < _samples - 1) {
      out.add(Offset.lerp(a, b, (target - walked) / seg)!);
      target += step;
    }
    walked += seg;
  }
  while (out.length < _samples) {
    out.add(pts.last);
  }
  return out;
}
