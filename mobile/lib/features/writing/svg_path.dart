import 'dart:ui';

/// A minimal SVG path-data parser — enough for KanjiVG's strokes, which use
/// M, C/c, S/s and occasionally L/l and Z. The other line and curve commands
/// are handled too, so an unusual stroke doesn't silently vanish. Arcs (A/a)
/// never appear in KanjiVG and are skipped.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(
    r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = '';
  var cur = Offset.zero;
  var start = Offset.zero;
  Offset? lastCtrl; // for S/s and T/t reflection
  var lastCmd = '';

  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);
  Offset pt(bool rel) {
    final p = Offset(next(), next());
    return rel ? cur + p : p;
  }

  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd.isEmpty) {
      break;
    }
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        cur = pt(rel);
        start = cur;
        path.moveTo(cur.dx, cur.dy);
        // Further pairs after a moveto are implicit linetos.
        cmd = rel ? 'l' : 'L';
        lastCtrl = null;
      case 'L':
        cur = pt(rel);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'H':
        final x = next();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'V':
        final y = next();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'C':
        final c1 = pt(rel), c2 = pt(rel), end = pt(rel);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastCtrl = c2;
        cur = end;
      case 'S':
        final c1 = (lastCtrl != null && 'CS'.contains(lastCmd.toUpperCase()))
            ? cur * 2 - lastCtrl
            : cur;
        final c2 = pt(rel), end = pt(rel);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastCtrl = c2;
        cur = end;
      case 'Q':
        final c = pt(rel), end = pt(rel);
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        lastCtrl = c;
        cur = end;
      case 'T':
        final c = (lastCtrl != null && 'QT'.contains(lastCmd.toUpperCase()))
            ? cur * 2 - lastCtrl
            : cur;
        final end = pt(rel);
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        lastCtrl = c;
        cur = end;
      case 'Z':
        path.close();
        cur = start;
        lastCtrl = null;
      case 'A':
        // rx ry rotation large-arc sweep x y — drawn as a straight line.
        i += 5;
        cur = pt(rel);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      default:
        i++;
    }
    lastCmd = cmd;
  }
  return path;
}

/// The first point of a path-data string — where a stroke starts, for its
/// stroke-order number.
Offset? svgPathStart(String d) {
  final m = RegExp(r'[Mm]\s*(-?[\d.]+)[\s,]*(-?[\d.]+)').firstMatch(d);
  if (m == null) return null;
  return Offset(double.parse(m.group(1)!), double.parse(m.group(2)!));
}
