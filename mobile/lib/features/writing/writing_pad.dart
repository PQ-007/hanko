import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../../core/theme.dart';
import 'kanji_strokes.dart';

const writingGreen = Color(0xFF16A34A);
const writingRed = Color(0xFFDC2626);

/// The writing square: practice-paper cross, a guide of the kanji's strokes
/// (all, some or none), an animated stroke-order demo on the trace step, the
/// answer in red after a miss, and the learner's own strokes on top.
class WritingPad extends StatefulWidget {
  const WritingPad({
    super.key,
    required this.strokes,
    required this.guideCount,
    required this.answer,
    required this.demo,
    required this.ink,
    this.borderColor,
    required this.onStart,
    required this.onUpdate,
    this.badInk,
    this.focusStroke,
  });

  final int? badInk;
  final int? focusStroke;
  final KanjiStrokes? strokes;
  final int guideCount;
  final bool answer;
  final bool demo;
  final List<List<mlkit.StrokePoint>> ink;
  /// Green after a right answer, red after a wrong one; the theme's line
  /// colour otherwise.
  final Color? borderColor;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;

  @override
  State<WritingPad> createState() => _WritingPadState();
}

class _WritingPadState extends State<WritingPad> with SingleTickerProviderStateMixin {
  AnimationController? _demo;

  @override
  void initState() {
    super.initState();
    final s = widget.strokes;
    if (widget.demo && s != null) {
      // About half a second per stroke, the pace of a teacher's brush demo.
      _demo =
          AnimationController(
              vsync: this,
              duration: Duration(milliseconds: 500 * s.count),
            )
            ..addListener(() => setState(() {}))
            ..forward();
    }
  }

  @override
  void dispose() {
    _demo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.borderColor ?? context.hk.line;
    final demo = _demo;
    return GestureDetector(
      onPanStart: (d) => widget.onStart(d.localPosition),
      onPanUpdate: (d) => widget.onUpdate(d.localPosition),
      child: Container(
        decoration: BoxDecoration(
          color: context.hk.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _PadPainter(
                  badInk: widget.badInk,
                  focusStroke: widget.focusStroke,
                  strokes: widget.strokes,
                  guideCount: widget.guideCount,
                  answer: widget.answer,
                  demoProgress: demo != null && demo.isAnimating
                      ? demo.value * widget.strokes!.count
                      : null,
                  ink: widget.ink,
                  guideColor: context.hk.ink.withValues(alpha: 0.13),
                  crossColor: context.hk.lineSoft,
                  inkColor: context.hk.ink,
                  numberColor: context.hk.inkMute,
                ),
              ),
              // Live stroke count, so a missing or extra stroke is visible
              // before checking.
              if (widget.strokes != null)
                Positioned(
                  right: 10,
                  bottom: 8,
                  child: Text(
                    '${widget.ink.length} / ${widget.strokes!.count}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.ink.length > widget.strokes!.count
                          ? writingRed
                          : context.hk.inkMute,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    this.badInk,
    this.focusStroke,
    required this.strokes,
    required this.guideCount,
    required this.answer,
    required this.demoProgress,
    required this.ink,
    required this.guideColor,
    required this.crossColor,
    required this.inkColor,
    required this.numberColor,
  });

  final int? badInk;
  final int? focusStroke;
  final KanjiStrokes? strokes;
  final int guideCount;
  final bool answer;

  /// Strokes drawn so far in the demo, fractional (2.5 = two and a half).
  final double? demoProgress;
  final List<List<mlkit.StrokePoint>> ink;
  final Color guideColor, crossColor, inkColor, numberColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Practice-paper cross (十字), dashed.
    final cross = Paint()
      ..color = crossColor
      ..strokeWidth = 1;
    const dash = 8.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(x + dash, size.height / 2),
        cross,
      );
    }
    for (var y = 0.0; y < size.height; y += dash * 2) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + dash),
        cross,
      );
    }

    final s = strokes;
    final scale = size.width / KanjiStrokes.box;
    final width = size.width * 0.045;
    if (s != null) {
      canvas.save();
      canvas.scale(scale);
      final guide = Paint()
        ..color = answer ? writingRed.withValues(alpha: 0.3) : guideColor
        ..strokeWidth = width / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < guideCount && i < s.count; i++) {
        canvas.drawPath(s.paths[i], guide);
      }
      // The stroke the learner got wrong, in full red on the answer.
      final f = focusStroke;
      if (answer && f != null && f < s.count) {
        canvas.drawPath(
          s.paths[f],
          Paint()
            ..color = writingRed.withValues(alpha: 0.85)
            ..strokeWidth = width / scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
      }
      // The demo: strokes drawn one after another in the accent colour.
      final p = demoProgress;
      if (p != null) {
        final demo = Paint()
          ..color = HankoColors.seal
          ..strokeWidth = width / scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        for (var i = 0; i < s.count && i < p; i++) {
          final fraction = (p - i).clamp(0.0, 1.0);
          if (fraction >= 1) {
            canvas.drawPath(s.paths[i], demo);
          } else {
            for (final m in s.paths[i].computeMetrics()) {
              canvas.drawPath(m.extractPath(0, m.length * fraction), demo);
            }
          }
        }
      }
      canvas.restore();
      // Stroke numbers at each guide stroke's start.
      for (var i = 0; i < guideCount && i < s.count; i++) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              fontSize: size.width * 0.035,
              color: answer ? writingRed : numberColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final at = s.starts[i] * scale;
        tp.paint(canvas, at + Offset(-tp.width - 4, -tp.height / 2));
      }
    }

    final pen = Paint()
      ..color = inkColor
      ..strokeWidth = width * 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final badPen = Paint()
      ..color = writingRed
      ..strokeWidth = pen.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < ink.length; i++) {
      final stroke = ink[i];
      final p = i == badInk ? badPen : pen;
      if (stroke.length == 1) {
        canvas.drawCircle(
          Offset(stroke.first.x, stroke.first.y),
          pen.strokeWidth / 2,
          Paint()..color = p.color,
        );
        continue;
      }
      final path = Path()..moveTo(stroke.first.x, stroke.first.y);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.x, pt.y);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

